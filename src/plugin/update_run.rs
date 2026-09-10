//! `update run`: the body of the detached update unit.
//!
//! `omarchy plugin update` fast-forwards the tree and rescans plugins, and a
//! rescan does not reload a running `Service.qml`. This step decides whether
//! the shell must restart: only when the fast-forward actually moved `HEAD`.
//! A locked session refuses `omarchy-restart-shell`, so the restart is
//! retried on a fixed cadence until the session unlocks or the budget ends.

use std::path::Path;
use std::time::Duration;

use crate::plugin::{CommandRunner, OmarchyError, PLUGIN_ID};

/// Absolute executables the run needs. `notify` is optional: a toast is a
/// courtesy and never gates the restart.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateRunTools {
    pub git: String,
    pub timeout: String,
    pub omarchy: String,
    pub restart_shell: String,
    pub notify: Option<String>,
}

/// Time budget for one run.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateRunLimits {
    /// Hard ceiling for `omarchy plugin update` (a stalled `git fetch`).
    pub update_timeout_secs: u64,
    /// Wait between refused restart attempts.
    pub restart_retry: Duration,
    /// Restart attempts before giving up.
    pub max_restart_attempts: u32,
}

impl Default for UpdateRunLimits {
    /// Ten minutes for the update; a restart attempt every minute for a day.
    fn default() -> Self {
        Self {
            update_timeout_secs: 600,
            restart_retry: Duration::from_secs(60),
            max_restart_attempts: 1440,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UpdateRunOutcome {
    /// The fast-forward found nothing new: no toast, no restart.
    UpToDate,
    /// `HEAD` moved and the shell restarted onto the new tree.
    Updated,
    /// `omarchy plugin update` failed or timed out (its exit code); it owns
    /// the rollback, and the shell is left alone.
    UpdateFailed(i32),
    /// `HEAD` moved but every restart attempt was refused.
    RestartGaveUp,
}

fn head(runner: &dyn CommandRunner, git: &str, plugin_root: &Path) -> Result<String, OmarchyError> {
    let root = plugin_root.to_string_lossy();
    let out = runner.run(git, &["-C", root.as_ref(), "rev-parse", "HEAD"])?;
    let sha = out.stdout.trim().to_string();
    if out.code != 0 || sha.is_empty() {
        return Err(OmarchyError::Message(format!(
            "cannot read the plugin commit: {}",
            out.stderr.trim()
        )));
    }
    Ok(sha)
}

/// Update the plugin, then restart the shell only if the tree changed.
pub fn run_update(
    runner: &dyn CommandRunner,
    sleep: &dyn Fn(Duration),
    tools: &UpdateRunTools,
    plugin_root: &Path,
    limits: &UpdateRunLimits,
) -> Result<UpdateRunOutcome, OmarchyError> {
    let before = head(runner, &tools.git, plugin_root)?;

    let timeout_secs = limits.update_timeout_secs.to_string();
    let update = runner.run(
        &tools.timeout,
        &[
            "--kill-after=10",
            timeout_secs.as_str(),
            tools.omarchy.as_str(),
            "plugin",
            "update",
            PLUGIN_ID,
            "--yes",
        ],
    )?;
    if update.code != 0 {
        return Ok(UpdateRunOutcome::UpdateFailed(update.code));
    }

    if head(runner, &tools.git, plugin_root)? == before {
        return Ok(UpdateRunOutcome::UpToDate);
    }

    // Toasts persist across the shell restart below, so notify first.
    if let Some(notify) = &tools.notify {
        let _ = runner.run(
            &tools.timeout,
            &[
                "10",
                notify.as_str(),
                "--app-name=Agent Bar",
                "Agent Bar updated",
                "The shell is reloading to finish the update.",
            ],
        );
    }

    for attempt in 0..limits.max_restart_attempts {
        if attempt > 0 {
            sleep(limits.restart_retry);
        }
        if let Ok(out) = runner.run(&tools.restart_shell, &[]) {
            if out.code == 0 {
                return Ok(UpdateRunOutcome::Updated);
            }
        }
    }
    Ok(UpdateRunOutcome::RestartGaveUp)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::plugin::{CommandOutput, CommandRunner, OmarchyError};
    use std::cell::RefCell;
    use std::path::Path;
    use std::time::Duration;

    /// Scripted runner: answers by program name, records every call.
    struct FakeRunner {
        heads: RefCell<Vec<&'static str>>,
        update_code: i32,
        restart_codes: RefCell<Vec<i32>>,
        notify_fails: bool,
        calls: RefCell<Vec<Vec<String>>>,
    }

    impl FakeRunner {
        fn new(heads: &[&'static str], update_code: i32, restart_codes: &[i32]) -> Self {
            Self {
                heads: RefCell::new(heads.to_vec()),
                update_code,
                restart_codes: RefCell::new(restart_codes.to_vec()),
                notify_fails: false,
                calls: RefCell::new(Vec::new()),
            }
        }

        fn programs(&self) -> Vec<String> {
            self.calls
                .borrow()
                .iter()
                .map(|c| {
                    // `timeout` wraps the real program: report what it runs.
                    if c[0] == "/usr/bin/timeout" {
                        c.iter()
                            .skip(1)
                            .find(|a| a.starts_with('/'))
                            .cloned()
                            .unwrap_or_default()
                    } else {
                        c[0].clone()
                    }
                })
                .collect()
        }
    }

    fn ok(code: i32, stdout: &str) -> Result<CommandOutput, OmarchyError> {
        Ok(CommandOutput {
            code,
            stdout: stdout.to_string(),
            stderr: String::new(),
        })
    }

    impl CommandRunner for FakeRunner {
        fn run(&self, program: &str, args: &[&str]) -> Result<CommandOutput, OmarchyError> {
            let mut call = vec![program.to_string()];
            call.extend(args.iter().map(|a| a.to_string()));
            self.calls.borrow_mut().push(call);
            let target = if program == "/usr/bin/timeout" {
                args.iter()
                    .find(|a| a.starts_with('/'))
                    .copied()
                    .unwrap_or("")
            } else {
                program
            };
            match target {
                "/usr/bin/git" => {
                    let head = self.heads.borrow_mut().remove(0);
                    ok(0, &format!("{head}\n"))
                }
                "/usr/bin/omarchy" => ok(self.update_code, ""),
                "/usr/bin/notify-send" if self.notify_fails => {
                    Err(OmarchyError::Message("no notification server".to_string()))
                }
                "/usr/bin/notify-send" => ok(0, ""),
                "/usr/bin/omarchy-restart-shell" => {
                    let code = self.restart_codes.borrow_mut().remove(0);
                    ok(code, "")
                }
                other => panic!("unexpected program {other}"),
            }
        }
    }

    fn tools(notify: bool) -> UpdateRunTools {
        UpdateRunTools {
            git: "/usr/bin/git".to_string(),
            timeout: "/usr/bin/timeout".to_string(),
            omarchy: "/usr/bin/omarchy".to_string(),
            restart_shell: "/usr/bin/omarchy-restart-shell".to_string(),
            notify: notify.then(|| "/usr/bin/notify-send".to_string()),
        }
    }

    fn limits(max_restart_attempts: u32) -> UpdateRunLimits {
        UpdateRunLimits {
            update_timeout_secs: 600,
            restart_retry: Duration::from_secs(60),
            max_restart_attempts,
        }
    }

    fn run(runner: &FakeRunner, notify: bool, attempts: u32) -> (UpdateRunOutcome, u32) {
        let sleeps = RefCell::new(0u32);
        let outcome = run_update(
            runner,
            &|d: Duration| {
                assert_eq!(d, Duration::from_secs(60));
                *sleeps.borrow_mut() += 1;
            },
            &tools(notify),
            Path::new("/plugins/othavi0.agent-bar"),
            &limits(attempts),
        )
        .unwrap();
        let count = *sleeps.borrow();
        (outcome, count)
    }

    #[test]
    fn up_to_date_neither_notifies_nor_restarts() {
        let runner = FakeRunner::new(&["aaa", "aaa"], 0, &[]);
        let (outcome, sleeps) = run(&runner, true, 3);
        assert_eq!(outcome, UpdateRunOutcome::UpToDate);
        assert_eq!(sleeps, 0);
        assert_eq!(
            runner.programs(),
            ["/usr/bin/git", "/usr/bin/omarchy", "/usr/bin/git"]
        );
    }

    #[test]
    fn a_moved_head_notifies_then_restarts_the_shell() {
        let runner = FakeRunner::new(&["aaa", "bbb"], 0, &[0]);
        let (outcome, sleeps) = run(&runner, true, 3);
        assert_eq!(outcome, UpdateRunOutcome::Updated);
        assert_eq!(sleeps, 0);
        assert_eq!(
            runner.programs(),
            [
                "/usr/bin/git",
                "/usr/bin/omarchy",
                "/usr/bin/git",
                "/usr/bin/notify-send",
                "/usr/bin/omarchy-restart-shell"
            ]
        );
        let calls = runner.calls.borrow();
        assert_eq!(
            calls[1],
            [
                "/usr/bin/timeout",
                "--kill-after=10",
                "600",
                "/usr/bin/omarchy",
                "plugin",
                "update",
                "othavi0.agent-bar",
                "--yes"
            ]
        );
        assert_eq!(
            calls[0],
            [
                "/usr/bin/git",
                "-C",
                "/plugins/othavi0.agent-bar",
                "rev-parse",
                "HEAD"
            ]
        );
    }

    #[test]
    fn a_failed_update_never_restarts() {
        let runner = FakeRunner::new(&["aaa"], 1, &[]);
        let (outcome, _) = run(&runner, true, 3);
        assert_eq!(outcome, UpdateRunOutcome::UpdateFailed(1));
        assert_eq!(runner.programs(), ["/usr/bin/git", "/usr/bin/omarchy"]);
    }

    #[test]
    fn a_refused_restart_is_retried_until_the_session_unlocks() {
        // omarchy-restart-shell exits 1 while the session is locked.
        let runner = FakeRunner::new(&["aaa", "bbb"], 0, &[1, 1, 0]);
        let (outcome, sleeps) = run(&runner, false, 5);
        assert_eq!(outcome, UpdateRunOutcome::Updated);
        assert_eq!(sleeps, 2);
    }

    #[test]
    fn the_restart_budget_ends_without_a_restart() {
        let runner = FakeRunner::new(&["aaa", "bbb"], 0, &[1, 1, 1]);
        let (outcome, sleeps) = run(&runner, false, 3);
        assert_eq!(outcome, UpdateRunOutcome::RestartGaveUp);
        assert_eq!(sleeps, 2);
    }

    #[test]
    fn a_failing_or_missing_notifier_never_blocks_the_restart() {
        let mut runner = FakeRunner::new(&["aaa", "bbb"], 0, &[0]);
        runner.notify_fails = true;
        let (outcome, _) = run(&runner, true, 3);
        assert_eq!(outcome, UpdateRunOutcome::Updated);

        let runner = FakeRunner::new(&["aaa", "bbb"], 0, &[0]);
        let (outcome, _) = run(&runner, false, 3);
        assert_eq!(outcome, UpdateRunOutcome::Updated);
        assert!(!runner
            .programs()
            .iter()
            .any(|p| p == "/usr/bin/notify-send"));
    }
}
