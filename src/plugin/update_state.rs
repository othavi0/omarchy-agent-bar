use std::io;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::plugin::update_apply::UpdateOutcome;
use crate::support::{replace_atomically_with, FileMutator, StdFileMutator};

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
