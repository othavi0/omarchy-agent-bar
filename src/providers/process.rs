use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio::time::timeout;

use crate::support::redact::redact_process_bytes;

/// Exact argv process specification. Never join into a shell string.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessSpec {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub env: Vec<(String, String)>,
    pub clear_env: bool,
    pub timeout: Duration,
    pub max_stdout_bytes: usize,
    pub max_stderr_bytes: usize,
    pub own_process_group: bool,
}

impl ProcessSpec {
    pub fn new(
        program: impl Into<PathBuf>,
        args: impl IntoIterator<Item = impl Into<String>>,
    ) -> Self {
        Self {
            program: program.into(),
            args: args.into_iter().map(Into::into).collect(),
            env: Vec::new(),
            clear_env: false,
            timeout: Duration::from_secs(10),
            max_stdout_bytes: 1024 * 1024,
            max_stderr_bytes: 1024 * 1024,
            own_process_group: false,
        }
    }

    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    pub fn with_max_output(mut self, max: usize) -> Self {
        self.max_stdout_bytes = max;
        self.max_stderr_bytes = max;
        self
    }

    pub fn with_env(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.env.push((key.into(), value.into()));
        self
    }

    /// Start the process as the leader of a new process group, so a timeout
    /// kills every descendant rather than only the direct child.
    pub fn with_own_process_group(mut self) -> Self {
        self.own_process_group = true;
        self
    }

    pub fn with_quiet_terminal(self) -> Self {
        self.with_env("NO_COLOR", "1").with_env("TERM", "dumb")
    }
}

/// Captured process output after redaction of controls/ANSI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessOutput {
    pub exit_code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
    pub timed_out: bool,
    pub stdout_truncated: bool,
    pub stderr_truncated: bool,
}

/// Process runner failure independent of provider domain state.
#[derive(Debug)]
pub enum ProcessError {
    Io(std::io::Error),
    Spawn(String),
}

impl std::fmt::Display for ProcessError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(err) => write!(f, "{err}"),
            Self::Spawn(msg) => write!(f, "{msg}"),
        }
    }
}

impl std::error::Error for ProcessError {}

impl From<std::io::Error> for ProcessError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

/// Runnable process seam for adapters and tests (object-safe).
pub trait ProcessRunner: Send + Sync {
    fn run<'a>(
        &'a self,
        spec: &'a ProcessSpec,
    ) -> std::pin::Pin<
        Box<dyn std::future::Future<Output = Result<ProcessOutput, ProcessError>> + Send + 'a>,
    >;
}

/// Tokio-backed runner: argv only, never `sh -c` / `bash -lc` / `eval`.
#[derive(Debug, Default, Clone, Copy)]
pub struct TokioProcessRunner;

impl ProcessRunner for TokioProcessRunner {
    fn run<'a>(
        &'a self,
        spec: &'a ProcessSpec,
    ) -> std::pin::Pin<
        Box<dyn std::future::Future<Output = Result<ProcessOutput, ProcessError>> + Send + 'a>,
    > {
        Box::pin(run_process(spec))
    }
}

/// Execute `spec` without a shell, enforcing timeout and output caps.
pub async fn run_process(spec: &ProcessSpec) -> Result<ProcessOutput, ProcessError> {
    let program_name = spec
        .program
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("");
    if matches!(program_name, "sh" | "bash" | "zsh" | "dash")
        && spec.args.first().is_some_and(|a| a == "-c" || a == "-lc")
    {
        return Err(ProcessError::Spawn(
            "shell process invocation is forbidden".into(),
        ));
    }

    let mut command = Command::new(&spec.program);
    command
        .args(&spec.args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    if spec.clear_env {
        command.env_clear();
    }
    for (key, value) in &spec.env {
        command.env(key, value);
    }
    if spec.own_process_group {
        command.process_group(0);
    }

    let mut child = command.spawn().map_err(|err| {
        ProcessError::Spawn(format!("failed to spawn {}: {err}", spec.program.display()))
    })?;
    let group_leader = child.id().filter(|_| spec.own_process_group);

    let mut stdout_pipe = child.stdout.take();
    let mut stderr_pipe = child.stderr.take();
    let max_out = spec.max_stdout_bytes;
    let max_err = spec.max_stderr_bytes;

    let read_fut = async {
        let stdout_task = async {
            let mut buf = Vec::new();
            let mut truncated = false;
            if let Some(pipe) = stdout_pipe.as_mut() {
                let mut chunk = [0u8; 8192];
                loop {
                    let n = pipe.read(&mut chunk).await?;
                    if n == 0 {
                        break;
                    }
                    if truncated {
                        // Drain so the child cannot block on a full pipe.
                        continue;
                    }
                    let remaining = max_out.saturating_sub(buf.len());
                    if remaining == 0 {
                        truncated = true;
                        continue;
                    }
                    let take = n.min(remaining);
                    buf.extend_from_slice(&chunk[..take]);
                    if take < n {
                        truncated = true;
                    }
                }
            }
            Ok::<_, std::io::Error>((buf, truncated))
        };
        let stderr_task = async {
            let mut buf = Vec::new();
            let mut truncated = false;
            if let Some(pipe) = stderr_pipe.as_mut() {
                let mut chunk = [0u8; 8192];
                loop {
                    let n = pipe.read(&mut chunk).await?;
                    if n == 0 {
                        break;
                    }
                    if truncated {
                        continue;
                    }
                    let remaining = max_err.saturating_sub(buf.len());
                    if remaining == 0 {
                        truncated = true;
                        continue;
                    }
                    let take = n.min(remaining);
                    buf.extend_from_slice(&chunk[..take]);
                    if take < n {
                        truncated = true;
                    }
                }
            }
            Ok::<_, std::io::Error>((buf, truncated))
        };
        let (stdout, stderr) = tokio::join!(stdout_task, stderr_task);
        Ok::<_, std::io::Error>((stdout?, stderr?))
    };

    let wait_fut = async {
        let status = child.wait().await?;
        Ok::<_, std::io::Error>(status)
    };

    let joined = timeout(spec.timeout, async {
        let ((stdout, stderr), status) = tokio::try_join!(read_fut, wait_fut)?;
        Ok::<_, std::io::Error>((stdout, stderr, status))
    })
    .await;

    match joined {
        Ok(Ok(((stdout_raw, stdout_truncated), (stderr_raw, stderr_truncated), status))) => {
            Ok(ProcessOutput {
                exit_code: status.code(),
                stdout: redact_process_bytes(&stdout_raw),
                stderr: redact_process_bytes(&stderr_raw),
                timed_out: false,
                stdout_truncated,
                stderr_truncated,
            })
        }
        Ok(Err(err)) => Err(ProcessError::Io(err)),
        Err(_elapsed) => {
            if let Some(pgid) = group_leader {
                kill_process_group(pgid);
            }
            let _ = child.kill().await;
            let _ = child.wait().await;
            Ok(ProcessOutput {
                exit_code: None,
                stdout: String::new(),
                stderr: String::new(),
                timed_out: true,
                stdout_truncated: false,
                stderr_truncated: false,
            })
        }
    }
}

fn kill_process_group(pgid: u32) {
    let Ok(pgid) = libc::pid_t::try_from(pgid) else {
        return;
    };
    // SAFETY: kill(2) takes plain integers and touches no memory; a negative
    // pid addresses the group this runner created with process_group(0).
    unsafe {
        libc::kill(-pgid, libc::SIGKILL);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[tokio::test]
    async fn stdin_is_closed_for_every_process() {
        let spec =
            ProcessSpec::new("/bin/cat", Vec::<String>::new()).with_timeout(Duration::from_secs(5));
        let out = run_process(&spec).await.expect("cat spawns");
        assert!(!out.timed_out, "cat waited on stdin");
        assert_eq!(out.exit_code, Some(0));
        assert_eq!(out.stdout, "");
    }

    #[tokio::test]
    async fn preserves_argv_and_exit_code() {
        let spec = ProcessSpec::new("/bin/echo", ["hello", "world"]);
        let out = TokioProcessRunner.run(&spec).await.unwrap();
        assert_eq!(out.exit_code, Some(0));
        assert_eq!(out.stdout.trim_end(), "hello world");
        assert!(!out.timed_out);
    }

    #[tokio::test]
    async fn timeout_kills_and_reaps() {
        let spec = ProcessSpec::new("/bin/sleep", ["5"]).with_timeout(Duration::from_millis(100));
        let out = TokioProcessRunner.run(&spec).await.unwrap();
        assert!(out.timed_out);
        assert_eq!(out.exit_code, None);
    }

    fn process_is_gone(pid: &str) -> bool {
        match std::fs::read_to_string(format!("/proc/{pid}/stat")) {
            Err(_) => true,
            Ok(stat) => stat
                .rsplit_once(") ")
                .is_some_and(|(_, rest)| rest.starts_with('Z')),
        }
    }

    #[tokio::test]
    async fn timeout_kills_the_whole_process_group() {
        let dir = tempfile::tempdir().unwrap();
        let pid_file = dir.path().join("grandchild.pid");
        let script = dir.path().join("spawn.sh");
        std::fs::write(
            &script,
            format!(
                "/bin/sleep 30 &\necho $! > '{}'\nwait\n",
                pid_file.display()
            ),
        )
        .unwrap();
        let spec = ProcessSpec::new("/bin/bash", [script.display().to_string()])
            .with_own_process_group()
            .with_timeout(Duration::from_millis(500));
        let out = TokioProcessRunner.run(&spec).await.unwrap();
        assert!(out.timed_out);
        let pid = std::fs::read_to_string(&pid_file).unwrap();
        let pid = pid.trim();
        let deadline = std::time::Instant::now() + Duration::from_secs(3);
        while !process_is_gone(pid) && std::time::Instant::now() < deadline {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        assert!(
            process_is_gone(pid),
            "grandchild {pid} survived the timeout"
        );
    }

    #[tokio::test]
    async fn enforces_stdout_limit() {
        let program = if Path::new("/usr/bin/printf").exists() {
            "/usr/bin/printf"
        } else {
            "/bin/echo"
        };
        let spec = if program.ends_with("printf") {
            ProcessSpec::new(program, ["%1024s", "x"])
                .with_max_output(64)
                .with_timeout(Duration::from_secs(2))
        } else {
            ProcessSpec::new(program, ["x".repeat(200)])
                .with_max_output(64)
                .with_timeout(Duration::from_secs(2))
        };
        let out = TokioProcessRunner.run(&spec).await.unwrap();
        assert!(out.stdout.len() <= 64 || out.stdout_truncated);
        if program.ends_with("printf") {
            assert!(out.stdout_truncated || out.stdout.len() == 64);
            assert!(out.stdout.len() <= 64);
        }
    }

    #[tokio::test]
    async fn redacts_ansi_from_stdout() {
        let program = if Path::new("/usr/bin/printf").exists() {
            "/usr/bin/printf"
        } else {
            return;
        };
        let spec = ProcessSpec::new(program, [r"%b", r"\033[31mred\033[0m"]);
        let out = TokioProcessRunner.run(&spec).await.unwrap();
        assert_eq!(out.stdout, "red");
        assert!(!out.stdout.contains('\u{1b}'));
    }

    #[tokio::test]
    async fn rejects_shell_dash_c() {
        let spec = ProcessSpec::new("/bin/sh", ["-c", "echo pwned"]);
        let err = TokioProcessRunner.run(&spec).await.unwrap_err();
        assert!(err.to_string().contains("shell"));
    }

    #[tokio::test]
    async fn env_injection_without_joining_argv() {
        let program = if Path::new("/usr/bin/printenv").exists() {
            "/usr/bin/printenv"
        } else if Path::new("/bin/printenv").exists() {
            "/bin/printenv"
        } else {
            return;
        };
        let spec = ProcessSpec::new(program, ["AGENT_BAR_TEST_ENV"])
            .with_env("AGENT_BAR_TEST_ENV", "ok-value")
            .with_timeout(Duration::from_secs(2));
        let out = TokioProcessRunner.run(&spec).await.unwrap();
        assert_eq!(out.stdout.trim_end(), "ok-value");
    }
}
