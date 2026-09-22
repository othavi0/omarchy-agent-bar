use std::path::Path;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use time::OffsetDateTime;

use crate::plugin::maintenance::MaintenanceError;
use crate::plugin::paths::PLUGIN_ID;
use crate::providers::{ProcessError, ProcessOutput, ProcessRunner, ProcessSpec};
use crate::support::{Clock, ExclusiveMaintenanceGuard, MaintenanceGate};

/// Budget for one `omarchy plugin update` run; a timeout kills its whole
/// process group (CLI-029C).
pub const UPDATE_RUN_TIMEOUT: Duration = Duration::from_secs(120);

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

/// Closed update result set (CLI-029C).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UpdateResult {
    Updated,
    UpToDate,
    LocalChanges,
    FetchFailed,
    ValidationFailed,
    TimedOut,
    Locked,
    Failed,
}

impl UpdateResult {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Updated => "updated",
            Self::UpToDate => "up_to_date",
            Self::LocalChanges => "local_changes",
            Self::FetchFailed => "fetch_failed",
            Self::ValidationFailed => "validation_failed",
            Self::TimedOut => "timed_out",
            Self::Locked => "locked",
            Self::Failed => "failed",
        }
    }
}

/// What one `update run` did, as written to `update-result.json`
/// (CLI-029C). A version is `None` only when `bundle.json` was unreadable.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateOutcome {
    pub result: UpdateResult,
    pub from_version: Option<String>,
    pub installed_version: Option<String>,
    pub restart_required: bool,
    #[serde(with = "time::serde::rfc3339")]
    pub finished_at: OffsetDateTime,
}

impl UpdateOutcome {
    pub fn new(
        result: UpdateResult,
        from_version: Option<String>,
        installed_version: Option<String>,
        finished_at: OffsetDateTime,
    ) -> Self {
        Self {
            result,
            from_version,
            installed_version,
            restart_required: result == UpdateResult::Updated,
            finished_at,
        }
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
        .with_own_process_group()
        .with_timeout(UPDATE_RUN_TIMEOUT)
}

/// How long `update run` keeps retrying the maintenance lock.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LockWait {
    pub interval: Duration,
    pub limit: Duration,
}

impl LockWait {
    pub const RUN: Self = Self {
        interval: Duration::from_millis(500),
        limit: Duration::from_secs(60),
    };
}

async fn wait_for_exclusive(
    gate: &MaintenanceGate,
    wait: LockWait,
) -> std::io::Result<Option<ExclusiveMaintenanceGuard>> {
    let deadline = tokio::time::Instant::now() + wait.limit;
    loop {
        if let Some(guard) = gate.try_lock_exclusive()? {
            return Ok(Some(guard));
        }
        if tokio::time::Instant::now() >= deadline {
            return Ok(None);
        }
        tokio::time::sleep(wait.interval).await;
    }
}

/// The body of the transient update unit (CLI-029C). Every path ends in a
/// typed outcome; the caller publishes it.
pub async fn run_update<R: ProcessRunner, C: Clock>(
    runner: &R,
    clock: &C,
    gate: &MaintenanceGate,
    wait: LockWait,
    omarchy: Option<&str>,
    plugin_root: &Path,
) -> UpdateOutcome {
    let finish = |result, from: Option<String>, installed: Option<String>| {
        UpdateOutcome::new(result, from, installed, clock.now_utc())
    };
    let _guard = match wait_for_exclusive(gate, wait).await {
        Ok(Some(guard)) => guard,
        Ok(None) => {
            let tree = read_tree_version(plugin_root).ok();
            return finish(UpdateResult::Locked, tree.clone(), tree);
        }
        Err(_) => return finish(UpdateResult::Failed, None, None),
    };
    let Ok(before) = read_tree_version(plugin_root) else {
        return finish(UpdateResult::Failed, None, None);
    };
    let Some(omarchy) = omarchy else {
        return finish(UpdateResult::Failed, Some(before.clone()), Some(before));
    };
    let outcome = runner.run(&update_spec(omarchy)).await;
    let after = read_tree_version(plugin_root).ok();
    let result = classify(&outcome, &before, after.as_deref());
    finish(result, Some(before), after)
}

fn classify(
    outcome: &Result<ProcessOutput, ProcessError>,
    before: &str,
    after: Option<&str>,
) -> UpdateResult {
    if after.is_some_and(|version| version != before) {
        return UpdateResult::Updated;
    }
    let Ok(output) = outcome else {
        return UpdateResult::Failed;
    };
    if output.timed_out {
        return UpdateResult::TimedOut;
    }
    match (output.exit_code, after) {
        (Some(0), Some(_)) => UpdateResult::UpToDate,
        (Some(0), None) => UpdateResult::Failed,
        _ => classify_failure(&output.stderr),
    }
}

/// These phrases are the external contract with
/// `/usr/share/omarchy/bin/omarchy-plugin-update`, which prints them on
/// stderr before exiting 1. A rewording there degrades the result to
/// `failed`; it never turns a failure into success.
fn classify_failure(stderr: &str) -> UpdateResult {
    if stderr.contains("cannot fast-forward") {
        UpdateResult::LocalChanges
    } else if stderr.contains("fetch failed") {
        UpdateResult::FetchFailed
    } else if stderr.contains("failed validation") {
        UpdateResult::ValidationFailed
    } else {
        UpdateResult::Failed
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

    struct FixedClock;

    impl Clock for FixedClock {
        fn now_utc(&self) -> OffsetDateTime {
            time::macros::datetime!(2026-09-22 16:40:05 UTC)
        }
    }

    const QUICK_WAIT: LockWait = LockWait {
        interval: Duration::from_millis(10),
        limit: Duration::from_millis(60),
    };

    fn gate_in(root: &Path) -> MaintenanceGate {
        MaintenanceGate::open(root.join("state/maintenance.lock")).unwrap()
    }

    fn timed_out() -> RunOutcome {
        Ok(ProcessOutput {
            exit_code: None,
            stdout: String::new(),
            stderr: String::new(),
            timed_out: true,
            stdout_truncated: false,
            stderr_truncated: false,
        })
    }

    async fn unit_run(runner: &ScriptedRunner, root: &Path) -> UpdateOutcome {
        run_update(
            runner,
            &FixedClock,
            &gate_in(root),
            QUICK_WAIT,
            Some("/usr/bin/omarchy"),
            root,
        )
        .await
    }

    fn outcome_json(outcome: &UpdateOutcome) -> String {
        serde_json::to_string(outcome).unwrap()
    }

    #[tokio::test]
    async fn run_reports_updated_when_the_tree_moved_whatever_the_exit() {
        for (label, outcome) in [
            ("exit 0", exited(0, "Updated othavi0.agent-bar.\n", "")),
            (
                "exit 1 after a failed rescan",
                exited(
                    1,
                    "Updated othavi0.agent-bar.\n",
                    "omarchy-shell: timed out\n",
                ),
            ),
            ("timeout", timed_out()),
        ] {
            let root = plugin_root("10.6.1");
            let runner = ScriptedRunner::new(outcome).installing(root.path(), "10.6.2");
            let outcome = unit_run(&runner, root.path()).await;
            assert_eq!(
                outcome_json(&outcome),
                "{\"result\":\"updated\",\"fromVersion\":\"10.6.1\",\"installedVersion\":\"10.6.2\",\"restartRequired\":true,\"finishedAt\":\"2026-09-22T16:40:05Z\"}",
                "{label}"
            );
        }
    }

    #[tokio::test]
    async fn run_maps_an_unchanged_tree_by_exit_status_and_stderr() {
        for (outcome, expected) in [
            (exited(0, "othavi0.agent-bar is up to date.\n", ""), "up_to_date"),
            (
                exited(1, "", "omarchy-plugin-update: cannot fast-forward 'othavi0.agent-bar'; you have local changes in /h\n"),
                "local_changes",
            ),
            (
                exited(1, "", "omarchy-plugin-update: fetch failed for 'othavi0.agent-bar'\n"),
                "fetch_failed",
            ),
            (
                exited(1, "", "omarchy-plugin-update: update of 'othavi0.agent-bar' failed validation; rolled back\n"),
                "validation_failed",
            ),
            (timed_out(), "timed_out"),
            (exited(1, "", "omarchy-plugin-update: plugin 'x' is not installed\n"), "failed"),
            (Err(ProcessError::Spawn("no such file".into())), "failed"),
        ] {
            let root = plugin_root("10.6.1");
            let runner = ScriptedRunner::new(outcome);
            let outcome = unit_run(&runner, root.path()).await;
            assert_eq!(
                outcome_json(&outcome),
                format!("{{\"result\":\"{expected}\",\"fromVersion\":\"10.6.1\",\"installedVersion\":\"10.6.1\",\"restartRequired\":false,\"finishedAt\":\"2026-09-22T16:40:05Z\"}}")
            );
        }
    }

    #[tokio::test]
    async fn run_with_an_unreadable_tree_after_exit_0_is_failed() {
        let root = plugin_root("10.6.1");
        let runner = ScriptedRunner::new(exited(0, "Updated othavi0.agent-bar.\n", ""))
            .installing(root.path(), "not-a-version");
        let outcome = unit_run(&runner, root.path()).await;
        assert_eq!(
            outcome_json(&outcome),
            "{\"result\":\"failed\",\"fromVersion\":\"10.6.1\",\"installedVersion\":null,\"restartRequired\":false,\"finishedAt\":\"2026-09-22T16:40:05Z\"}"
        );
    }

    #[tokio::test]
    async fn run_is_locked_when_the_lock_stays_held_and_runs_nothing() {
        let root = plugin_root("10.6.1");
        let gate = gate_in(root.path());
        let _held = gate.lock_exclusive().unwrap();
        let runner = ScriptedRunner::new(exited(0, "", ""));
        let outcome = unit_run(&runner, root.path()).await;
        assert_eq!(outcome.result, UpdateResult::Locked);
        assert_eq!(outcome.installed_version.as_deref(), Some("10.6.1"));
        assert!(runner.specs().is_empty());
    }

    #[tokio::test]
    async fn run_waits_for_a_lock_released_within_the_limit() {
        let root = plugin_root("10.6.1");
        let held = gate_in(root.path()).lock_exclusive().unwrap();
        let release = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(150));
            drop(held);
        });
        let runner = ScriptedRunner::new(exited(0, "", ""));
        let outcome = run_update(
            &runner,
            &FixedClock,
            &gate_in(root.path()),
            LockWait {
                interval: Duration::from_millis(20),
                limit: Duration::from_secs(5),
            },
            Some("/usr/bin/omarchy"),
            root.path(),
        )
        .await;
        release.join().unwrap();
        assert_eq!(outcome.result, UpdateResult::UpToDate);
        assert_eq!(runner.specs().len(), 1);
    }

    #[tokio::test]
    async fn run_starts_the_plugin_manager_in_its_own_group_non_interactively() {
        let root = plugin_root("10.6.1");
        let runner = ScriptedRunner::new(exited(0, "", ""));
        unit_run(&runner, root.path()).await;
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
        assert!(spec.own_process_group);
        assert_eq!(spec.timeout, Duration::from_secs(120));
    }

    #[tokio::test]
    async fn run_without_a_readable_tree_or_omarchy_fails_without_running() {
        let root = tempdir().unwrap();
        let runner = ScriptedRunner::new(exited(0, "", ""));
        let outcome = unit_run(&runner, root.path()).await;
        assert_eq!(
            outcome_json(&outcome),
            "{\"result\":\"failed\",\"fromVersion\":null,\"installedVersion\":null,\"restartRequired\":false,\"finishedAt\":\"2026-09-22T16:40:05Z\"}"
        );

        let root = plugin_root("10.6.1");
        let outcome = run_update(
            &runner,
            &FixedClock,
            &gate_in(root.path()),
            QUICK_WAIT,
            None,
            root.path(),
        )
        .await;
        assert_eq!(outcome.result, UpdateResult::Failed);
        assert!(runner.specs().is_empty());
    }

    #[test]
    fn result_names_match_serialization() {
        for result in [
            UpdateResult::Updated,
            UpdateResult::UpToDate,
            UpdateResult::LocalChanges,
            UpdateResult::FetchFailed,
            UpdateResult::ValidationFailed,
            UpdateResult::TimedOut,
            UpdateResult::Locked,
            UpdateResult::Failed,
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
