use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime};

use crate::plugin::update_apply::{UpdateOutcome, UpdateResult};
use crate::support::{replace_atomically_with, FileMutator, StdFileMutator};

/// How long a running marker counts as live. It equals the unit's
/// `RuntimeMaxSec`, after which systemd has stopped the run.
pub const UPDATE_RUN_WINDOW: Duration = Duration::seconds(180);

/// Rounds of link-then-inspect before a launcher that keeps losing the race
/// reports the slot as taken.
const LINK_ATTEMPTS: usize = 3;

/// Running marker written by `update apply` before it starts the unit.
pub const UPDATE_RUNNING_FILE: &str = "update-running.json";

/// Result document written by `update run` when the unit finishes.
pub const UPDATE_RESULT_FILE: &str = "update-result.json";

/// `{"schemaVersion":1,"operation":"update", ...body}`: the frame every
/// update state file and update stdout document shares.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateDocument<T> {
    pub schema_version: u32,
    pub operation: String,
    #[serde(flatten)]
    pub body: T,
}

impl<T: Serialize> UpdateDocument<T> {
    pub fn new(body: T) -> Self {
        Self {
            schema_version: 1,
            operation: "update".to_owned(),
            body,
        }
    }

    pub fn to_json_line(&self) -> Result<String, serde_json::Error> {
        let mut line = serde_json::to_string(self)?;
        line.push('\n');
        Ok(line)
    }
}

/// Body of `update-running.json` (CLI-029A). `targetVersion` is `null` when
/// the confirmation came from the TTY phrase, which names no version.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateRunning {
    pub txid: String,
    #[serde(with = "time::serde::rfc3339")]
    pub started_at: OffsetDateTime,
    pub target_version: Option<String>,
}

impl UpdateRunning {
    pub fn is_live(&self, now: OffsetDateTime) -> bool {
        let age = now - self.started_at;
        age >= Duration::ZERO && age < UPDATE_RUN_WINDOW
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Begin {
    Started,
    AlreadyRunning,
}

/// `update status` body (CLI-029B).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum UpdateStatus {
    None,
    #[serde(rename_all = "camelCase")]
    Running {
        #[serde(with = "time::serde::rfc3339")]
        started_at: OffsetDateTime,
        target_version: Option<String>,
    },
    Finished(UpdateOutcome),
}

/// The two update state files under `$XDG_STATE_HOME/agent-bar/`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateStateFiles {
    pub running: PathBuf,
    pub result: PathBuf,
}

impl UpdateStateFiles {
    pub fn in_state_dir(dir: &Path) -> Self {
        Self {
            running: dir.join(UPDATE_RUNNING_FILE),
            result: dir.join(UPDATE_RESULT_FILE),
        }
    }

    /// Claim the update slot (CLI-029A). The marker appears by hard link,
    /// which fails when any marker exists, so of two racing launchers only
    /// one sees `Started`. A marker that is no longer live is taken over
    /// only while it still holds the bytes this launcher judged; any unread
    /// result from an earlier run is cleared once the slot is ours.
    pub fn begin(&self, marker: &UpdateRunning, now: OffsetDateTime) -> io::Result<Begin> {
        self.begin_racing(marker, now, || {})
    }

    fn begin_racing(
        &self,
        marker: &UpdateRunning,
        now: OffsetDateTime,
        mut before_write: impl FnMut(),
    ) -> io::Result<Begin> {
        let line = UpdateDocument::new(marker)
            .to_json_line()
            .map_err(io::Error::other)?;
        let staged = self
            .running
            .with_file_name(format!(".update-running-{}.tmp", marker.txid));
        replace_atomically_with(&StdFileMutator, &staged, line.as_bytes(), 0o600)?;
        let begun = self.link_marker(&staged, now, &mut before_write);
        remove_if_present(&staged)?;
        if begun? == Begin::AlreadyRunning {
            return Ok(Begin::AlreadyRunning);
        }
        remove_if_present(&self.result)?;
        Ok(Begin::Started)
    }

    fn link_marker(
        &self,
        staged: &Path,
        now: OffsetDateTime,
        before_write: &mut impl FnMut(),
    ) -> io::Result<Begin> {
        for _ in 0..LINK_ATTEMPTS {
            before_write();
            match std::fs::hard_link(staged, &self.running) {
                Ok(()) => return Ok(Begin::Started),
                Err(err) if err.kind() == io::ErrorKind::AlreadyExists => {}
                Err(err) => return Err(err),
            }
            let Some(existing) = read_bytes(&self.running)? else {
                continue;
            };
            if self.is_live(&existing, now) {
                return Ok(Begin::AlreadyRunning);
            }
            remove_if_unchanged(&self.running, &existing)?;
        }
        Ok(Begin::AlreadyRunning)
    }

    fn is_live(&self, marker: &[u8], now: OffsetDateTime) -> bool {
        parse_document::<UpdateRunning>(marker).is_some_and(|doc| doc.body.is_live(now))
    }

    /// Drop the marker of a run whose unit never started.
    pub fn abandon(&self) -> io::Result<()> {
        remove_if_present(&self.running)
    }

    /// What the last update is doing (CLI-029B). A result is consumed by the
    /// read that reports it, and so is a marker whose unit can no longer be
    /// alive: each finished run is reported exactly once. `tree_version`
    /// supplies `installedVersion` for a run that never wrote a result.
    pub fn read_status(
        &self,
        now: OffsetDateTime,
        tree_version: impl FnOnce() -> Option<String>,
    ) -> io::Result<UpdateStatus> {
        if let Some(bytes) = claim(&self.result)? {
            let _ = self.abandon();
            let outcome = parse_document::<UpdateOutcome>(&bytes)
                .map(|doc| doc.body)
                .unwrap_or_else(|| {
                    UpdateOutcome::new(UpdateResult::Failed, None, tree_version(), now)
                });
            return Ok(UpdateStatus::Finished(outcome));
        }
        if let Some(marker) = self.read_marker()? {
            if marker.is_live(now) {
                return Ok(UpdateStatus::Running {
                    started_at: marker.started_at,
                    target_version: marker.target_version,
                });
            }
        }
        if claim(&self.running)?.is_some() {
            return Ok(UpdateStatus::Finished(UpdateOutcome::new(
                UpdateResult::Failed,
                None,
                tree_version(),
                now,
            )));
        }
        Ok(UpdateStatus::None)
    }

    fn read_marker(&self) -> io::Result<Option<UpdateRunning>> {
        Ok(read_document(&self.running)?.map(|doc| doc.body))
    }

    /// Publish the run's outcome, then drop the running marker (CLI-029C).
    pub fn finish(&self, outcome: &UpdateOutcome) -> io::Result<()> {
        self.finish_with(&StdFileMutator, outcome)
    }

    pub fn finish_with<M: FileMutator + ?Sized>(
        &self,
        mutator: &M,
        outcome: &UpdateOutcome,
    ) -> io::Result<()> {
        let line = UpdateDocument::new(outcome)
            .to_json_line()
            .map_err(io::Error::other)?;
        replace_atomically_with(mutator, &self.result, line.as_bytes(), 0o600)?;
        remove_if_present(&self.running)
    }
}

/// `Ok(None)` for a missing file and for one that is not a valid update
/// document; callers treat both as absent.
fn read_document<T: for<'de> Deserialize<'de>>(
    path: &Path,
) -> io::Result<Option<UpdateDocument<T>>> {
    match std::fs::read(path) {
        Ok(bytes) => Ok(parse_document(&bytes)),
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(err) => Err(err),
    }
}

fn parse_document<T: for<'de> Deserialize<'de>>(bytes: &[u8]) -> Option<UpdateDocument<T>> {
    serde_json::from_slice::<UpdateDocument<T>>(bytes)
        .ok()
        .filter(|doc| doc.schema_version == 1 && doc.operation == "update")
}

fn read_bytes(path: &Path) -> io::Result<Option<Vec<u8>>> {
    match std::fs::read(path) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(err) => Err(err),
    }
}

/// Move `path` to a name private to this call. The rename is atomic, so of
/// several concurrent callers exactly one receives the file.
fn take(path: &Path) -> io::Result<Option<PathBuf>> {
    static SEQUENCE: AtomicU64 = AtomicU64::new(0);
    let taken = path.with_file_name(format!(
        ".{}.{}-{}.taken",
        path.file_name()
            .map(|n| n.to_string_lossy())
            .unwrap_or_default(),
        std::process::id(),
        SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    match std::fs::rename(path, &taken) {
        Ok(()) => Ok(Some(taken)),
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(err) => Err(err),
    }
}

/// Take `path` out of the shared directory and return its bytes, so two
/// concurrent readers never both report it.
fn claim(path: &Path) -> io::Result<Option<Vec<u8>>> {
    let Some(taken) = take(path)? else {
        return Ok(None);
    };
    let bytes = std::fs::read(&taken);
    remove_if_present(&taken)?;
    bytes.map(Some)
}

/// Remove `path` only while it still holds `expected`. A file that changed
/// after the caller read it belongs to another launcher and is put back.
fn remove_if_unchanged(path: &Path, expected: &[u8]) -> io::Result<bool> {
    let Some(taken) = take(path)? else {
        return Ok(false);
    };
    let unchanged = std::fs::read(&taken).map(|bytes| bytes == expected);
    if !matches!(unchanged, Ok(true)) {
        match std::fs::hard_link(&taken, path) {
            Err(err) if err.kind() != io::ErrorKind::AlreadyExists => {
                let _ = remove_if_present(&taken);
                return Err(err);
            }
            _ => {}
        }
    }
    remove_if_present(&taken)?;
    unchanged
}

fn remove_if_present(path: &Path) -> io::Result<()> {
    match std::fs::remove_file(path) {
        Err(err) if err.kind() != io::ErrorKind::NotFound => Err(err),
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::support::{AtomicFailPoint, FailingMutator};
    use time::macros::datetime;

    fn outcome() -> UpdateOutcome {
        UpdateOutcome::new(
            UpdateResult::Updated,
            Some("10.6.1".to_owned()),
            Some("10.6.2".to_owned()),
            datetime!(2026-09-22 16:40:05 UTC),
        )
    }

    fn entries(dir: &Path) -> Vec<String> {
        let mut names: Vec<String> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }

    fn marker(started_at: OffsetDateTime) -> UpdateRunning {
        UpdateRunning {
            txid: "0123456789abcdef0123456789abcdef".to_owned(),
            started_at,
            target_version: Some("10.6.2".to_owned()),
        }
    }

    const NOW: OffsetDateTime = datetime!(2026-09-22 16:40:05 UTC);

    fn status_line(files: &UpdateStateFiles, now: OffsetDateTime) -> String {
        let status = files
            .read_status(now, || Some("10.6.2".to_owned()))
            .unwrap();
        UpdateDocument::new(status).to_json_line().unwrap()
    }

    const NONE: &str = "{\"schemaVersion\":1,\"operation\":\"update\",\"status\":\"none\"}\n";

    #[test]
    fn status_is_none_without_state_files() {
        let dir = tempfile::tempdir().unwrap();
        let files = UpdateStateFiles::in_state_dir(&dir.path().join("agent-bar"));
        assert_eq!(status_line(&files, NOW), NONE);
    }

    #[test]
    fn status_is_running_while_the_marker_is_live() {
        let dir = tempfile::tempdir().unwrap();
        let files = UpdateStateFiles::in_state_dir(dir.path());
        files.begin(&marker(NOW), NOW).unwrap();
        let later = NOW + Duration::seconds(179);
        for _ in 0..2 {
            assert_eq!(
                status_line(&files, later),
                "{\"schemaVersion\":1,\"operation\":\"update\",\"status\":\"running\",\"startedAt\":\"2026-09-22T16:40:05Z\",\"targetVersion\":\"10.6.2\"}\n"
            );
        }
    }

    #[test]
    fn status_reports_a_finished_result_once() {
        let dir = tempfile::tempdir().unwrap();
        let files = UpdateStateFiles::in_state_dir(dir.path());
        files.begin(&marker(NOW), NOW).unwrap();
        files.finish(&outcome()).unwrap();
        assert_eq!(
            status_line(&files, NOW),
            "{\"schemaVersion\":1,\"operation\":\"update\",\"status\":\"finished\",\"result\":\"updated\",\"fromVersion\":\"10.6.1\",\"installedVersion\":\"10.6.2\",\"restartRequired\":true,\"finishedAt\":\"2026-09-22T16:40:05Z\"}\n"
        );
        assert_eq!(status_line(&files, NOW), NONE);
        assert!(entries(dir.path()).is_empty());
    }

    #[test]
    fn status_reports_a_stale_or_unreadable_marker_once_as_failed() {
        let dir = tempfile::tempdir().unwrap();
        let files = UpdateStateFiles::in_state_dir(dir.path());
        for stale in [
            UpdateDocument::new(marker(NOW)).to_json_line().unwrap(),
            "{not json".to_owned(),
        ] {
            std::fs::write(&files.running, &stale).unwrap();
            let checked_at = NOW + Duration::seconds(180);
            assert_eq!(
                status_line(&files, checked_at),
                "{\"schemaVersion\":1,\"operation\":\"update\",\"status\":\"finished\",\"result\":\"failed\",\"fromVersion\":null,\"installedVersion\":\"10.6.2\",\"restartRequired\":false,\"finishedAt\":\"2026-09-22T16:43:05Z\"}\n",
                "{stale}"
            );
            assert_eq!(status_line(&files, checked_at), NONE);
            assert!(entries(dir.path()).is_empty());
        }
    }

    #[test]
    fn begin_writes_the_marker_document_and_clears_an_old_result() {
        let dir = tempfile::tempdir().unwrap();
        let files = UpdateStateFiles::in_state_dir(&dir.path().join("agent-bar"));
        files.finish(&outcome()).unwrap();
        assert_eq!(files.begin(&marker(NOW), NOW).unwrap(), Begin::Started);
        assert_eq!(
            std::fs::read_to_string(&files.running).unwrap(),
            "{\"schemaVersion\":1,\"operation\":\"update\",\"txid\":\"0123456789abcdef0123456789abcdef\",\"startedAt\":\"2026-09-22T16:40:05Z\",\"targetVersion\":\"10.6.2\"}\n"
        );
        assert_eq!(
            entries(&dir.path().join("agent-bar")),
            ["update-running.json"]
        );
    }

    #[test]
    fn begin_refuses_while_a_live_marker_exists() {
        let dir = tempfile::tempdir().unwrap();
        let files = UpdateStateFiles::in_state_dir(dir.path());
        let first = marker(NOW - Duration::seconds(179));
        assert_eq!(
            files.begin(&first, first.started_at).unwrap(),
            Begin::Started
        );
        let before = std::fs::read(&files.running).unwrap();
        assert_eq!(
            files.begin(&marker(NOW), NOW).unwrap(),
            Begin::AlreadyRunning
        );
        assert_eq!(std::fs::read(&files.running).unwrap(), before);
    }

    #[test]
    fn begin_replaces_a_stale_or_unreadable_marker() {
        let dir = tempfile::tempdir().unwrap();
        let files = UpdateStateFiles::in_state_dir(dir.path());
        for stale in [
            UpdateDocument::new(marker(NOW - Duration::seconds(180)))
                .to_json_line()
                .unwrap(),
            UpdateDocument::new(marker(NOW + Duration::seconds(5)))
                .to_json_line()
                .unwrap(),
            "{not json".to_owned(),
        ] {
            std::fs::write(&files.running, &stale).unwrap();
            assert_eq!(
                files.begin(&marker(NOW), NOW).unwrap(),
                Begin::Started,
                "{stale}"
            );
            assert!(std::fs::read_to_string(&files.running)
                .unwrap()
                .contains("\"startedAt\":\"2026-09-22T16:40:05Z\""));
        }
    }

    fn other_marker() -> UpdateRunning {
        UpdateRunning {
            txid: "fedcba9876543210fedcba9876543210".to_owned(),
            ..marker(NOW)
        }
    }

    #[test]
    fn a_launcher_that_writes_after_our_check_wins_alone() {
        for existing in [
            None,
            Some(
                UpdateDocument::new(marker(NOW - Duration::seconds(600)))
                    .to_json_line()
                    .unwrap(),
            ),
        ] {
            let dir = tempfile::tempdir().unwrap();
            let files = UpdateStateFiles::in_state_dir(dir.path());
            if let Some(stale) = &existing {
                std::fs::write(&files.running, stale).unwrap();
            }
            let mut rival = None;
            let ours = files
                .begin_racing(&marker(NOW), NOW, || {
                    if rival.is_none() {
                        rival = Some(files.begin(&other_marker(), NOW).unwrap());
                    }
                })
                .unwrap();
            assert_eq!(
                (ours, rival),
                (Begin::AlreadyRunning, Some(Begin::Started)),
                "{existing:?}"
            );
            assert!(std::fs::read_to_string(&files.running)
                .unwrap()
                .contains("fedcba9876543210fedcba9876543210"));
            assert_eq!(entries(dir.path()), ["update-running.json"]);
        }
    }

    #[test]
    fn a_marker_that_changed_after_it_was_read_is_put_back() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("update-running.json");
        std::fs::write(&path, "fresh").unwrap();
        assert!(!remove_if_unchanged(&path, b"stale").unwrap());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "fresh");
        assert!(remove_if_unchanged(&path, b"fresh").unwrap());
        assert!(!remove_if_unchanged(&path, b"fresh").unwrap());
        assert!(entries(dir.path()).is_empty());
    }

    #[test]
    fn finish_writes_the_result_and_removes_the_marker() {
        let dir = tempfile::tempdir().unwrap();
        let files = UpdateStateFiles::in_state_dir(dir.path());
        std::fs::write(&files.running, "{}").unwrap();
        files.finish(&outcome()).unwrap();
        assert_eq!(
            std::fs::read_to_string(&files.result).unwrap(),
            "{\"schemaVersion\":1,\"operation\":\"update\",\"result\":\"updated\",\"fromVersion\":\"10.6.1\",\"installedVersion\":\"10.6.2\",\"restartRequired\":true,\"finishedAt\":\"2026-09-22T16:40:05Z\"}\n"
        );
        assert_eq!(entries(dir.path()), ["update-result.json"]);
    }

    #[test]
    fn a_failed_write_leaves_no_partial_result_and_keeps_the_marker() {
        for fail in [
            AtomicFailPoint::Write,
            AtomicFailPoint::FsyncTemp,
            AtomicFailPoint::Rename,
        ] {
            let dir = tempfile::tempdir().unwrap();
            let files = UpdateStateFiles::in_state_dir(dir.path());
            std::fs::write(&files.running, "{}").unwrap();
            let err = files
                .finish_with(&FailingMutator::new(fail), &outcome())
                .unwrap_err();
            assert!(err.to_string().starts_with("injected"), "{err}");
            assert_eq!(entries(dir.path()), ["update-running.json"], "{fail:?}");
        }
    }
}
