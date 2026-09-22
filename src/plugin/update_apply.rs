use std::path::Path;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::plugin::maintenance::MaintenanceError;
use crate::plugin::paths::PLUGIN_ID;
use crate::providers::{ProcessError, ProcessOutput, ProcessRunner, ProcessSpec};

/// Budget for one `omarchy plugin update` run (CLI-029A).
pub const UPDATE_APPLY_TIMEOUT: Duration = Duration::from_secs(120);

/// Exact TTY phrase required for interactive `update apply` (CLI-029).
pub const UPDATE_TTY_PHRASE: &str = "update agent-bar";

/// TTY prompt text written to stderr.
pub const UPDATE_TTY_PROMPT: &str = "Type update agent-bar to continue:";

/// Non-TTY structured `update apply` confirmation (CLI-029).
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateConfirmation {
    pub schema_version: u32,
    pub operation: String,
    pub confirmed: bool,
    pub target_version: String,
}

impl UpdateConfirmation {
    /// Parse exactly one JSON object with optional surrounding whitespace.
    pub fn parse_strict(bytes: &[u8]) -> Result<Self, MaintenanceError> {
        let text = std::str::from_utf8(bytes)
            .map_err(|_| MaintenanceError::msg("update confirmation is not valid UTF-8"))?;
        let doc: Self = serde_json::from_str(text)
            .map_err(|e| MaintenanceError::msg(format!("malformed update confirmation: {e}")))?;
        doc.validate()?;
        Ok(doc)
    }

    fn validate(&self) -> Result<(), MaintenanceError> {
        if self.schema_version != 1 {
            return Err(MaintenanceError::msg(
                "update confirmation schemaVersion must be 1",
            ));
        }
        if self.operation != "update" {
            return Err(MaintenanceError::msg(
                "update confirmation operation must be \"update\"",
            ));
        }
        if !self.confirmed {
            return Err(MaintenanceError::msg(
                "update confirmation requires confirmed: true",
            ));
        }
        if !is_release_version(&self.target_version) {
            return Err(MaintenanceError::msg(
                "update confirmation targetVersion must be major.minor.patch",
            ));
        }
        Ok(())
    }
}

/// Closed `update apply` result set (CLI-029B).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum UpdateApplyResult {
    Updated,
    UpToDate,
    LocalChanges,
    FetchFailed,
    ValidationFailed,
    TimedOut,
    Failed,
}

impl UpdateApplyResult {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Updated => "updated",
            Self::UpToDate => "up_to_date",
            Self::LocalChanges => "local_changes",
            Self::FetchFailed => "fetch_failed",
            Self::ValidationFailed => "validation_failed",
            Self::TimedOut => "timed_out",
            Self::Failed => "failed",
        }
    }
}

/// Exact `update apply` stdout document (CLI-029B).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateApplyReport {
    pub schema_version: u32,
    pub operation: &'static str,
    pub result: UpdateApplyResult,
    pub installed_version: String,
    pub restart_required: bool,
}

impl UpdateApplyReport {
    fn new(result: UpdateApplyResult, installed_version: String) -> Self {
        Self {
            schema_version: 1,
            operation: "update",
            result,
            installed_version,
            restart_required: result == UpdateApplyResult::Updated,
        }
    }

    pub fn to_stdout_json(&self) -> Result<String, MaintenanceError> {
        let mut line = serde_json::to_string(self)?;
        line.push('\n');
        Ok(line)
    }
}

#[derive(Deserialize)]
struct TreeReceipt {
    version: String,
}

/// The installed tree version: `version` in the plugin root's `bundle.json`.
pub fn read_tree_version(plugin_root: &Path) -> Result<String, MaintenanceError> {
    let path = plugin_root.join("bundle.json");
    let bytes = std::fs::read(&path)
        .map_err(|e| MaintenanceError::msg(format!("read {}: {e}", path.display())))?;
    let receipt: TreeReceipt = serde_json::from_slice(&bytes)
        .map_err(|e| MaintenanceError::msg(format!("malformed {}: {e}", path.display())))?;
    if !is_release_version(&receipt.version) {
        return Err(MaintenanceError::msg(format!(
            "{} version is not major.minor.patch",
            path.display()
        )));
    }
    Ok(receipt.version)
}

fn update_spec(omarchy: &str) -> ProcessSpec {
    ProcessSpec::new(omarchy, ["plugin", "update", PLUGIN_ID, "--yes"])
        .with_env("GIT_TERMINAL_PROMPT", "0")
        .with_quiet_terminal()
        .with_timeout(UPDATE_APPLY_TIMEOUT)
}

/// Run the Omarchy plugin manager once and classify what it did (CLI-029A).
/// An unreadable tree version before the run is an error; every outcome of
/// the run itself is a typed result.
pub async fn apply_update<R: ProcessRunner>(
    runner: &R,
    omarchy: &str,
    plugin_root: &Path,
) -> Result<UpdateApplyReport, MaintenanceError> {
    let before = read_tree_version(plugin_root)?;
    let outcome = runner.run(&update_spec(omarchy)).await;
    let after = read_tree_version(plugin_root).ok();
    let result = classify(&outcome, &before, after.as_deref());
    Ok(UpdateApplyReport::new(result, after.unwrap_or(before)))
}

fn classify(
    outcome: &Result<ProcessOutput, ProcessError>,
    before: &str,
    after: Option<&str>,
) -> UpdateApplyResult {
    let output = match outcome {
        Ok(output) => output,
        Err(_) => return UpdateApplyResult::Failed,
    };
    if output.timed_out {
        return UpdateApplyResult::TimedOut;
    }
    if output.exit_code == Some(0) {
        return match after {
            Some(version) if version != before => UpdateApplyResult::Updated,
            Some(_) => UpdateApplyResult::UpToDate,
            None => UpdateApplyResult::Failed,
        };
    }
    let stderr = output.stderr.as_str();
    if stderr.contains("cannot fast-forward") {
        UpdateApplyResult::LocalChanges
    } else if stderr.contains("fetch failed") {
        UpdateApplyResult::FetchFailed
    } else if stderr.contains("failed validation") {
        UpdateApplyResult::ValidationFailed
    } else {
        UpdateApplyResult::Failed
    }
}

fn is_release_version(version: &str) -> bool {
    let parts: Vec<&str> = version.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|part| !part.is_empty() && part.bytes().all(|b| b.is_ascii_digit()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::sync::Mutex;
    use tempfile::{tempdir, TempDir};

    type RunOutcome = Result<ProcessOutput, ProcessError>;

    struct ScriptedRunner {
        outcome: Mutex<Option<RunOutcome>>,
        installs: Option<(PathBuf, &'static str)>,
        specs: Mutex<Vec<ProcessSpec>>,
    }

    impl ScriptedRunner {
        fn new(outcome: RunOutcome) -> Self {
            Self {
                outcome: Mutex::new(Some(outcome)),
                installs: None,
                specs: Mutex::new(Vec::new()),
            }
        }

        fn installing(mut self, root: &Path, version: &'static str) -> Self {
            self.installs = Some((root.to_path_buf(), version));
            self
        }

        fn specs(&self) -> Vec<ProcessSpec> {
            self.specs.lock().unwrap_or_else(|e| e.into_inner()).clone()
        }
    }

    impl ProcessRunner for ScriptedRunner {
        fn run<'a>(
            &'a self,
            spec: &'a ProcessSpec,
        ) -> std::pin::Pin<Box<dyn std::future::Future<Output = RunOutcome> + Send + 'a>> {
            self.specs
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .push(spec.clone());
            if let Some((root, version)) = &self.installs {
                write_tree_version(root, version);
            }
            let outcome = self
                .outcome
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .take()
                .unwrap_or_else(|| Err(ProcessError::Spawn("runner already used".into())));
            Box::pin(async move { outcome })
        }
    }

    fn write_tree_version(root: &Path, version: &str) {
        std::fs::write(
            root.join("bundle.json"),
            format!(
                r#"{{"schemaVersion":1,"pluginId":"othavi0.agent-bar","version":"{version}"}}"#
            ),
        )
        .unwrap();
    }

    fn plugin_root(version: &str) -> TempDir {
        let dir = tempdir().unwrap();
        write_tree_version(dir.path(), version);
        dir
    }

    fn exited(code: i32, stdout: &str, stderr: &str) -> RunOutcome {
        Ok(ProcessOutput {
            exit_code: Some(code),
            stdout: stdout.to_owned(),
            stderr: stderr.to_owned(),
            timed_out: false,
            stdout_truncated: false,
            stderr_truncated: false,
        })
    }

    async fn run(runner: &ScriptedRunner, root: &Path) -> UpdateApplyReport {
        apply_update(runner, "/usr/bin/omarchy", root)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn changed_tree_version_is_updated_and_needs_a_restart() {
        let root = plugin_root("10.6.2");
        let runner = ScriptedRunner::new(exited(0, "Updated othavi0.agent-bar.\n", ""))
            .installing(root.path(), "10.7.0");
        let report = run(&runner, root.path()).await;
        assert_eq!(
            report.to_stdout_json().unwrap(),
            "{\"schemaVersion\":1,\"operation\":\"update\",\"result\":\"updated\",\"installedVersion\":\"10.7.0\",\"restartRequired\":true}\n"
        );
    }

    #[tokio::test]
    async fn unchanged_tree_version_is_up_to_date() {
        let root = plugin_root("10.6.2");
        let runner = ScriptedRunner::new(exited(0, "othavi0.agent-bar is up to date.\n", ""));
        let report = run(&runner, root.path()).await;
        assert_eq!(
            report.to_stdout_json().unwrap(),
            "{\"schemaVersion\":1,\"operation\":\"update\",\"result\":\"up_to_date\",\"installedVersion\":\"10.6.2\",\"restartRequired\":false}\n"
        );
    }

    #[tokio::test]
    async fn documented_plugin_manager_failures_map_to_their_results() {
        for (stderr, expected) in [
            (
                "omarchy-plugin-update: cannot fast-forward 'othavi0.agent-bar'; you have local changes in /home/u/.config/omarchy/plugins/othavi0.agent-bar\n",
                UpdateApplyResult::LocalChanges,
            ),
            (
                "fatal: unable to access 'https://github.com/'\nomarchy-plugin-update: fetch failed for 'othavi0.agent-bar'\n",
                UpdateApplyResult::FetchFailed,
            ),
            (
                "omarchy-plugin-update: update of 'othavi0.agent-bar' failed validation; rolled back\n",
                UpdateApplyResult::ValidationFailed,
            ),
            (
                "omarchy-plugin-update: refusing to continue without confirmation; pass --yes\n",
                UpdateApplyResult::Failed,
            ),
        ] {
            let root = plugin_root("10.6.2");
            let runner = ScriptedRunner::new(exited(1, "", stderr));
            let report = run(&runner, root.path()).await;
            assert_eq!(report.result, expected, "{stderr}");
            assert_eq!(report.installed_version, "10.6.2");
            assert!(!report.restart_required);
        }
    }

    #[tokio::test]
    async fn timeout_is_timed_out_and_reports_the_tree_on_disk() {
        let root = plugin_root("10.6.2");
        let runner = ScriptedRunner::new(Ok(ProcessOutput {
            exit_code: None,
            stdout: String::new(),
            stderr: String::new(),
            timed_out: true,
            stdout_truncated: false,
            stderr_truncated: false,
        }));
        let report = run(&runner, root.path()).await;
        assert_eq!(report.result, UpdateApplyResult::TimedOut);
        assert_eq!(report.installed_version, "10.6.2");
        assert!(!report.restart_required);
    }

    #[tokio::test]
    async fn spawn_failure_and_unreadable_tree_after_success_are_failed() {
        let root = plugin_root("10.6.2");
        let runner = ScriptedRunner::new(Err(ProcessError::Spawn("no such file".into())));
        let report = run(&runner, root.path()).await;
        assert_eq!(report.result, UpdateApplyResult::Failed);
        assert_eq!(report.installed_version, "10.6.2");

        let root = plugin_root("10.6.2");
        let runner = ScriptedRunner::new(exited(0, "Updated othavi0.agent-bar.\n", ""))
            .installing(root.path(), "not-a-version");
        let report = run(&runner, root.path()).await;
        assert_eq!(report.result, UpdateApplyResult::Failed);
        assert_eq!(report.installed_version, "10.6.2");
        assert!(!report.restart_required);
    }

    #[tokio::test]
    async fn runs_the_plugin_manager_once_non_interactively() {
        let root = plugin_root("10.6.2");
        let runner = ScriptedRunner::new(exited(0, "", ""));
        run(&runner, root.path()).await;
        let specs = runner.specs();
        assert_eq!(specs.len(), 1);
        let spec = &specs[0];
        assert_eq!(spec.program, PathBuf::from("/usr/bin/omarchy"));
        assert_eq!(
            spec.args,
            ["plugin", "update", "othavi0.agent-bar", "--yes"]
        );
        assert!(spec
            .env
            .contains(&("GIT_TERMINAL_PROMPT".to_owned(), "0".to_owned())));
        assert_eq!(spec.timeout, Duration::from_secs(120));
    }

    #[tokio::test]
    async fn missing_tree_version_runs_nothing() {
        let root = tempdir().unwrap();
        let runner = ScriptedRunner::new(exited(0, "", ""));
        assert!(apply_update(&runner, "/usr/bin/omarchy", root.path())
            .await
            .is_err());
        assert!(runner.specs().is_empty());
    }

    #[test]
    fn result_names_match_serialization() {
        for result in [
            UpdateApplyResult::Updated,
            UpdateApplyResult::UpToDate,
            UpdateApplyResult::LocalChanges,
            UpdateApplyResult::FetchFailed,
            UpdateApplyResult::ValidationFailed,
            UpdateApplyResult::TimedOut,
            UpdateApplyResult::Failed,
        ] {
            assert_eq!(
                serde_json::to_value(result).unwrap(),
                serde_json::Value::String(result.as_str().to_owned())
            );
        }
    }

    const GOOD: &str =
        r#"{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":"10.7.0"}"#;

    #[test]
    fn accepts_one_document_with_surrounding_whitespace() {
        let doc = UpdateConfirmation::parse_strict(format!("\n  {GOOD}\n\n").as_bytes()).unwrap();
        assert_eq!(doc.target_version, "10.7.0");
    }

    #[test]
    fn rejects_every_other_shape() {
        for bad in [
            String::new(),
            "null".to_owned(),
            "[]".to_owned(),
            format!("{GOOD}{GOOD}"),
            format!("{GOOD} x"),
            GOOD.replace("\"confirmed\":true", "\"confirmed\":false"),
            GOOD.replace("\"schemaVersion\":1", "\"schemaVersion\":2"),
            GOOD.replace("\"update\"", "\"uninstall\""),
            GOOD.replace("10.7.0", ""),
            GOOD.replace("10.7.0", "10.7"),
            GOOD.replace("10.7.0", "10.7.0.1"),
            GOOD.replace("10.7.0", "v10.7.0"),
            GOOD.replace("10.7.0", "10..0"),
            GOOD.replace("10.7.0", "10.7.0-rc1"),
            GOOD.replace("\"10.7.0\"", "10"),
            GOOD.replace("}", ",\"purgeSettingsAndBackups\":false}"),
            r#"{"schemaVersion":1,"operation":"update","confirmed":true}"#.to_owned(),
        ] {
            assert!(
                UpdateConfirmation::parse_strict(bad.as_bytes()).is_err(),
                "{bad:?}"
            );
        }
        assert!(UpdateConfirmation::parse_strict(&[0xff, 0xfe]).is_err());
    }
}
