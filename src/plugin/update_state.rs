use std::io;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime};

use crate::plugin::update_apply::UpdateOutcome;
use crate::support::{replace_atomically_with, FileMutator, StdFileMutator};

/// How long a running marker counts as live. It equals the unit's
/// `RuntimeMaxSec`, after which systemd has stopped the run.
pub const UPDATE_RUN_WINDOW: Duration = Duration::seconds(180);

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

    /// Claim the update slot (CLI-029A). A live marker wins; a stale or
    /// unreadable one and any unread result from an earlier run are cleared.
    /// The marker appears by hard link, so two racing launchers cannot both
    /// see `Started`.
    pub fn begin(&self, marker: &UpdateRunning, now: OffsetDateTime) -> io::Result<Begin> {
        if self.read_marker()?.is_some_and(|live| live.is_live(now)) {
            return Ok(Begin::AlreadyRunning);
        }
        remove_if_present(&self.running)?;
        remove_if_present(&self.result)?;
        let line = UpdateDocument::new(marker)
            .to_json_line()
            .map_err(io::Error::other)?;
        let staged = self
            .running
            .with_file_name(format!(".update-running-{}.tmp", marker.txid));
        replace_atomically_with(&StdFileMutator, &staged, line.as_bytes(), 0o600)?;
        let linked = std::fs::hard_link(&staged, &self.running);
        remove_if_present(&staged)?;
        match linked {
            Ok(()) => Ok(Begin::Started),
            Err(err) if err.kind() == io::ErrorKind::AlreadyExists => Ok(Begin::AlreadyRunning),
            Err(err) => Err(err),
        }
    }

    /// Drop the marker of a run whose unit never started.
    pub fn abandon(&self) -> io::Result<()> {
        remove_if_present(&self.running)
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
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(err) => return Err(err),
    };
    Ok(serde_json::from_slice::<UpdateDocument<T>>(&bytes)
        .ok()
        .filter(|doc| doc.schema_version == 1 && doc.operation == "update"))
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
    use crate::plugin::update_apply::UpdateResult;
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
