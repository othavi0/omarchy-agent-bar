mod command;
mod exit;
mod grammar;

pub use command::{
    CacheMode, Command, ConfigCommand, ConfigInput, HelpTopic, NotificationMode, ProviderId,
    StatusFormat, StatusOptions, UpdateCommand,
};
pub use exit::{
    CliFailure, GENERIC_FAILURE, GRAMMAR, INTERNAL, PLUGIN, SERIALIZATION, SUCCESS, VALIDATION,
};
pub use grammar::parse;

use std::io::{self, BufRead, IsTerminal, Write};
use std::path::{Path, PathBuf};

use serde::Serialize;

pub fn version_stdout() -> String {
    format!("{}\n", env!("CARGO_PKG_VERSION"))
}

fn provider_word_list() -> String {
    ProviderId::ALL
        .iter()
        .map(|id| id.as_str())
        .collect::<Vec<_>>()
        .join(", ")
}

pub fn help_text(topic: Option<HelpTopic>) -> String {
    match topic {
        None => {
            let mut out = String::new();
            out.push_str("Agent Bar — Omarchy Quattro plugin helper\n");
            out.push('\n');
            out.push_str("The normal interface is the othavi0.agent-bar Quickshell plugin.\n");
            out.push_str("This private helper is for diagnostics, recovery, and tests.\n");
            out.push('\n');
            out.push_str("Usage:\n");
            out.push_str("  agent-bar\n");
            out.push_str("  agent-bar status [format human|json] [provider <id>]\n");
            out.push_str("                 [cache use|bypass] [notifications evaluate|skip]\n");
            out.push_str("  agent-bar login <provider>\n");
            out.push_str("  agent-bar config show\n");
            out.push_str("  agent-bar config apply stdin|file <path>|json <value>\n");
            out.push_str("  agent-bar update [check|apply]\n");
            out.push_str("  agent-bar uninstall [purge]\n");
            out.push_str("  agent-bar reset claude <reset-id>\n");
            out.push_str("  agent-bar help [<command>]\n");
            out.push_str("  agent-bar version\n");
            out.push('\n');
            out.push_str(&format!("Providers: {}\n", provider_word_list()));
            out
        }
        Some(HelpTopic::Status) => "status — collect provider quota windows\n\
             \n\
             Arguments (any order, each at most once):\n\
               format human|json          default: human\n\
               provider <id>              single provider (even if disabled)\n\
               cache use|bypass           default: use\n\
               notifications evaluate|skip  default: skip\n\
             \n\
             Bare agent-bar equals status format human.\n"
            .to_owned(),
        // Antigravity signs in inside its own CLI, so it has no login verb.
        Some(HelpTopic::Login) => {
            "login <provider> — delegate to the official provider login command\n\
             Providers: claude, codex, grok\n"
                .to_owned()
        }
        Some(HelpTopic::Config) => "config show — print canonical settings JSON (read-only)\n\
             config apply stdin|file <path>|json <value> — replace settings\n"
            .to_owned(),
        Some(HelpTopic::Update) => format!(
            "update — print usage; no interactive flow\n\
             update check — report whether a newer release exists (read-only)\n\
             update apply — install the latest release through the Omarchy\n\
             plugin manager after confirmation; the shell restart stays yours\n\
             update run — the body of the unit update apply starts\n\
             From a terminal you can also run '{UPDATE_COMMAND}'.\n"
        ),
        Some(HelpTopic::Uninstall) => {
            "uninstall — remove the plugin (keeps settings and backups)\n\
             uninstall purge — also delete settings and owned backups\n\
             Both forms require confirmation.\n"
                .to_owned()
        }
        Some(HelpTopic::Reset) => "reset claude <reset-id> — claim one banked Claude usage reset\n\
             Fetches fresh usage, claims the reset only if it is still\n\
             claimable, and prints one JSON result line. Never retried.\n"
            .to_owned(),
        Some(HelpTopic::Help) => "help [<command>] — show general or topic help\n".to_owned(),
        Some(HelpTopic::Version) => {
            "version — print the helper semantic version and exit\n".to_owned()
        }
    }
}

pub fn dispatch(command: Command) -> Result<(), CliFailure> {
    match command {
        Command::Version => {
            print!("{}", version_stdout());
            Ok(())
        }
        Command::Help(topic) => {
            print!("{}", help_text(topic));
            Ok(())
        }
        Command::Update(UpdateCommand::Interactive) => dispatch_update_interactive(),
        Command::Update(UpdateCommand::Check) => dispatch_update_check(),
        Command::Update(UpdateCommand::Apply) => dispatch_update_apply(),
        Command::Update(UpdateCommand::Run) => dispatch_update_run(),
        Command::Config(config) => dispatch_config(config),
        Command::Login(provider) => dispatch_login(provider),
        Command::Status(opts) => dispatch_status(opts),
        Command::Uninstall { purge } => dispatch_uninstall(purge),
        Command::Reset { reset_id } => dispatch_reset(reset_id),
    }
}

/// Pure uninstall confirmation gate (TTY phrase or non-TTY structured JSON).
///
/// Standard uninstall does not read stdin until preflight has already succeeded
/// (caller responsibility). Exit code 3 on any confirmation failure; zero mutation
/// happens inside this function.
pub fn confirm_uninstall<R, E>(
    is_tty: bool,
    purge: bool,
    stdin: &mut R,
    stderr: &mut E,
) -> Result<(), CliFailure>
where
    R: BufRead,
    E: Write,
{
    use crate::plugin::{UninstallConfirmation, UNINSTALL_TTY_PHRASE, UNINSTALL_TTY_PROMPT};

    if is_tty {
        confirm_tty_phrase(
            "uninstall",
            UNINSTALL_TTY_PROMPT,
            UNINSTALL_TTY_PHRASE,
            stdin,
            stderr,
        )
    } else {
        let buf = read_all(stdin)?;
        UninstallConfirmation::parse_strict(&buf, purge)
            .map_err(|err| CliFailure::validation(err.to_string()))?;
        Ok(())
    }
}

/// `update apply` confirmation gate (CLI-029): the TTY phrase, or exactly one
/// structured JSON document on stdin. Returns the confirmed `targetVersion`,
/// which only the JSON form carries. Exit code 3 on any failure, before any
/// lock or process.
pub fn confirm_update<R, E>(
    is_tty: bool,
    stdin: &mut R,
    stderr: &mut E,
) -> Result<Option<String>, CliFailure>
where
    R: BufRead,
    E: Write,
{
    use crate::plugin::{UpdateConfirmation, UPDATE_TTY_PHRASE, UPDATE_TTY_PROMPT};

    if is_tty {
        confirm_tty_phrase(
            "update",
            UPDATE_TTY_PROMPT,
            UPDATE_TTY_PHRASE,
            stdin,
            stderr,
        )?;
        Ok(None)
    } else {
        let buf = read_all(stdin)?;
        let doc = UpdateConfirmation::parse_strict(&buf)
            .map_err(|err| CliFailure::validation(err.to_string()))?;
        Ok(Some(doc.target_version))
    }
}

fn confirm_tty_phrase<R, E>(
    operation: &str,
    prompt: &str,
    phrase: &str,
    stdin: &mut R,
    stderr: &mut E,
) -> Result<(), CliFailure>
where
    R: BufRead,
    E: Write,
{
    write!(stderr, "{prompt}").map_err(|err| CliFailure::internal(err.to_string()))?;
    let _ = stderr.flush();
    let mut line = String::new();
    match stdin.read_line(&mut line) {
        Ok(0) => Err(CliFailure::validation(format!(
            "{operation} confirmation aborted"
        ))),
        Ok(_) => {
            if line.trim_end_matches(['\r', '\n']) == phrase {
                Ok(())
            } else {
                Err(CliFailure::validation(format!(
                    "{operation} confirmation rejected"
                )))
            }
        }
        Err(err) => Err(CliFailure::internal(err.to_string())),
    }
}

fn read_all<R: BufRead>(stdin: &mut R) -> Result<Vec<u8>, CliFailure> {
    let mut buf = Vec::new();
    stdin
        .read_to_end(&mut buf)
        .map_err(|err| CliFailure::internal(err.to_string()))?;
    Ok(buf)
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct UninstallDelegation<'a> {
    schema_version: u32,
    operation: &'static str,
    purged: bool,
    delegated: bool,
    unit: &'a str,
}

fn remove_dir_all_idempotent(path: &Path) -> Result<(), CliFailure> {
    match std::fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(CliFailure::plugin(format!(
            "remove {}: {err}",
            path.display()
        ))),
    }
}

fn dispatch_uninstall(purge: bool) -> Result<(), CliFailure> {
    use crate::plugin::{
        resolve_absolute_executable, txid_from_bytes, CommandRunner, PluginPaths,
        ProcessCommandRunner,
    };
    use crate::settings::default_settings_path;
    use crate::support::maintenance_gate::MaintenanceGate;
    use crate::support::{Clock, SystemClock};

    let home = std::env::var_os("HOME")
        .ok_or_else(|| CliFailure::plugin("HOME is required for uninstall".to_string()))?;
    let home = PathBuf::from(home);
    let xdg_state = std::env::var_os("XDG_STATE_HOME").map(PathBuf::from);
    let paths = PluginPaths::production(home.clone(), xdg_state);

    let gate = MaintenanceGate::open(&paths.maintenance_lock)
        .map_err(|e| CliFailure::plugin(format!("open maintenance lock: {e}")))?;
    let exclusive = gate
        .lock_exclusive()
        .map_err(|e| CliFailure::plugin(format!("exclusive maintenance lock: {e}")))?;

    let omarchy_bin =
        resolve_absolute_executable("omarchy").map_err(|e| CliFailure::plugin(e.to_string()))?;
    let systemd_run = resolve_absolute_executable("systemd-run")
        .map_err(|e| CliFailure::plugin(e.to_string()))?;

    let is_tty = io::stdin().is_terminal();
    let stdin = io::stdin();
    let mut locked_in = stdin.lock();
    let stderr = io::stderr();
    let mut locked_err = stderr.lock();
    confirm_uninstall(is_tty, purge, &mut locked_in, &mut locked_err)?;

    if purge {
        let settings_dir = default_settings_path()
            .parent()
            .map(Path::to_path_buf)
            .ok_or_else(|| {
                CliFailure::plugin("settings path has no parent directory".to_string())
            })?;
        let cache_dir = {
            let base = std::env::var_os("XDG_CACHE_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| home.join(".cache"));
            base.join("agent-bar")
        };
        remove_dir_all_idempotent(&settings_dir)?;
        remove_dir_all_idempotent(&cache_dir)?;
    }

    drop(exclusive);
    if purge {
        remove_dir_all_idempotent(&paths.xdg_state)?;
    }

    let clock = SystemClock;
    let txid = txid_from_bytes(format!("uninstall:{}", Clock::now_utc(&clock)).as_bytes());
    let unit = format!("agent-bar-remove-{txid}.service");
    let unit_flag = format!("--unit={unit}");

    let argv: [&str; 9] = [
        "--user",
        "--collect",
        unit_flag.as_str(),
        "--",
        omarchy_bin.as_str(),
        "plugin",
        "remove",
        "othavi0.agent-bar",
        "--yes",
    ];

    let runner = ProcessCommandRunner;
    let out = runner
        .run(&systemd_run, &argv)
        .map_err(|e| CliFailure::plugin(e.to_string()))?;
    if out.code != 0 {
        return Err(CliFailure::plugin(format!(
            "failed to start remove unit: {}",
            out.stderr.trim()
        )));
    }

    let doc = UninstallDelegation {
        schema_version: 1,
        operation: "uninstall",
        purged: purge,
        delegated: true,
        unit: &unit,
    };
    let json = serde_json::to_string(&doc).map_err(|e| CliFailure::plugin(e.to_string()))?;
    println!("{json}");
    Ok(())
}

/// True when the live plugin root is not a git checkout (BUNDLE-021 v-next):
/// `omarchy plugin update` can only fast-forward a git-managed install, so a
/// tarball-installed tree must be reinstalled via `omarchy plugin add`.
fn reinstall_required() -> Result<bool, CliFailure> {
    use crate::plugin::PluginPaths;

    let home = std::env::var_os("HOME")
        .ok_or_else(|| CliFailure::plugin("HOME is required for update check".to_string()))?;
    let xdg_state = std::env::var_os("XDG_STATE_HOME").map(PathBuf::from);
    let paths = PluginPaths::production(PathBuf::from(home), xdg_state);
    Ok(!paths.plugin_root.join(".git").is_dir())
}

fn dispatch_update_check() -> Result<(), CliFailure> {
    use crate::plugin::{ReqwestReleaseHttp, UpdateCheck, UpdateCheckProbe};
    use crate::support::SystemClock;

    let http = ReqwestReleaseHttp::new().map_err(|e| CliFailure::plugin(e.to_string()))?;
    let clock = SystemClock;
    let probe = UpdateCheckProbe::live();
    let doc = UpdateCheck::run(&http, &clock, &probe, reinstall_required()?)
        .map_err(|e| CliFailure::plugin(e.to_string()))?;
    let json = doc
        .to_stdout_json()
        .map_err(|e| CliFailure::plugin(e.to_string()))?;
    print!("{json}");
    Ok(())
}

/// The terminal fallback for installing a reported release. `omarchy plugin
/// update` fast-forwards the tree but does not reload a running shell, so the
/// restart is part of the command. `CoreMaintenance.js` shows the same text.
pub const UPDATE_COMMAND: &str =
    "omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell";

#[derive(Serialize)]
#[serde(tag = "result", rename_all = "snake_case")]
enum UpdateLaunch {
    Started { unit: String },
    AlreadyRunning,
}

/// `update apply` (CLI-029A): confirm, claim the running marker, and hand the
/// run to a transient unit. It returns before anything writes the plugin
/// tree, so a shell reload of the plugin cannot cut the run short.
fn dispatch_update_apply() -> Result<(), CliFailure> {
    use crate::plugin::update_state::{
        Begin, UpdateDocument, UpdateRunning, UpdateStateFiles, UPDATE_RUN_WINDOW,
    };
    use crate::plugin::{
        resolve_absolute_executable, txid_from_bytes, CommandRunner, ProcessCommandRunner,
    };
    use crate::support::{Clock, SystemClock};

    let is_tty = io::stdin().is_terminal();
    let stdin = io::stdin();
    let mut locked_in = stdin.lock();
    let stderr = io::stderr();
    let mut locked_err = stderr.lock();
    let target_version = confirm_update(is_tty, &mut locked_in, &mut locked_err)?;
    drop(locked_err);
    match &target_version {
        Some(version) => eprintln!("agent-bar: update apply: confirmed {version}"),
        None => eprintln!("agent-bar: update apply: confirmed"),
    }

    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| CliFailure::plugin("HOME is required for update apply".to_string()))?;
    let state_home = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".local/state"));
    resolve_absolute_executable("omarchy").map_err(|e| CliFailure::plugin(e.to_string()))?;
    let systemd_run = resolve_absolute_executable("systemd-run")
        .map_err(|e| CliFailure::plugin(e.to_string()))?;
    let helper = std::env::current_exe()
        .and_then(std::fs::canonicalize)
        .map_err(|e| CliFailure::plugin(format!("resolve helper path: {e}")))?;

    let clock = SystemClock;
    let now = Clock::now_utc(&clock);
    let txid = txid_from_bytes(format!("update:{now}:{}", std::process::id()).as_bytes());
    let files = UpdateStateFiles::in_state_dir(&state_home.join("agent-bar"));
    let marker = UpdateRunning {
        txid: txid.clone(),
        started_at: now,
        target_version,
    };
    let print = |launch: UpdateLaunch| -> Result<(), CliFailure> {
        let line = UpdateDocument::new(launch)
            .to_json_line()
            .map_err(|e| CliFailure::internal(e.to_string()))?;
        print!("{line}");
        Ok(())
    };
    let begin = files
        .begin(&marker, now)
        .map_err(|e| CliFailure::plugin(format!("write update marker: {e}")))?;
    if begin == Begin::AlreadyRunning {
        return print(UpdateLaunch::AlreadyRunning);
    }

    let unit = format!("agent-bar-update-{txid}");
    let mut argv = vec![
        "--user".to_owned(),
        "--collect".to_owned(),
        "--no-block".to_owned(),
        format!("--unit={unit}"),
        format!(
            "--property=RuntimeMaxSec={}",
            UPDATE_RUN_WINDOW.whole_seconds()
        ),
        format!("--setenv=HOME={}", home.display()),
        format!("--setenv=XDG_STATE_HOME={}", state_home.display()),
    ];
    if let Some(path) = std::env::var_os("PATH") {
        argv.push(format!("--setenv=PATH={}", path.to_string_lossy()));
    }
    argv.extend([
        "--".to_owned(),
        helper.display().to_string(),
        "update".to_owned(),
        "run".to_owned(),
    ]);
    let argv: Vec<&str> = argv.iter().map(String::as_str).collect();
    let started = ProcessCommandRunner
        .run(&systemd_run, &argv)
        .map_err(|e| e.to_string())
        .and_then(|out| {
            if out.code == 0 {
                Ok(())
            } else {
                Err(out.stderr.trim().to_owned())
            }
        });
    if let Err(reason) = started {
        let _ = files.abandon();
        return Err(CliFailure::plugin(format!(
            "failed to start update unit: {reason}"
        )));
    }
    print(UpdateLaunch::Started { unit })
}

/// The body of the `agent-bar-update-<txid>` unit (CLI-029C). Every outcome,
/// including a missing `omarchy`, lands in `update-result.json`; only a
/// failure to publish that file is a process failure.
fn dispatch_update_run() -> Result<(), CliFailure> {
    use crate::plugin::update_apply::{run_update, LockWait};
    use crate::plugin::update_state::UpdateStateFiles;
    use crate::plugin::{resolve_absolute_executable, PluginPaths};
    use crate::providers::TokioProcessRunner;
    use crate::support::maintenance_gate::MaintenanceGate;
    use crate::support::SystemClock;

    let home = std::env::var_os("HOME")
        .ok_or_else(|| CliFailure::plugin("HOME is required for update run".to_string()))?;
    let xdg_state = std::env::var_os("XDG_STATE_HOME").map(PathBuf::from);
    let paths = PluginPaths::production(PathBuf::from(home), xdg_state);
    let gate = MaintenanceGate::open(&paths.maintenance_lock)
        .map_err(|e| CliFailure::plugin(format!("open maintenance lock: {e}")))?;
    let omarchy = resolve_absolute_executable("omarchy").ok();

    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|err| CliFailure::internal(err.to_string()))?;
    let outcome = runtime.block_on(run_update(
        &TokioProcessRunner,
        &SystemClock,
        &gate,
        LockWait::RUN,
        omarchy.as_deref(),
        &paths.plugin_root,
    ));
    UpdateStateFiles::in_state_dir(&paths.xdg_state)
        .finish(&outcome)
        .map_err(|e| CliFailure::plugin(format!("write update result: {e}")))?;
    eprintln!("agent-bar: update run: {}", outcome.result.as_str());
    Ok(())
}

fn dispatch_update_interactive() -> Result<(), CliFailure> {
    eprintln!("agent-bar update has no interactive flow.");
    eprintln!("Use 'agent-bar update check' to look for a new release.");
    eprintln!("Use 'agent-bar update apply' to install it after confirmation.");
    eprintln!("From a terminal you can also run '{UPDATE_COMMAND}'.");
    Err(CliFailure {
        message: String::new(),
        exit_code: VALIDATION,
    })
}

fn dispatch_status(opts: StatusOptions) -> Result<(), CliFailure> {
    use crate::settings::default_maintenance_lock_path;
    use crate::status::{format_human, CollectRequest, StatusCoordinator};
    use crate::support::maintenance_gate::shared_gate;

    let gate = shared_gate(default_maintenance_lock_path())
        .map_err(|err| CliFailure::internal(err.to_string()))?;
    let coordinator = StatusCoordinator::production(gate).map_err(CliFailure::internal)?;
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|err| CliFailure::internal(err.to_string()))?;
    let envelope = runtime
        .block_on(coordinator.collect(CollectRequest {
            format: opts.format,
            provider: opts.provider,
            cache: opts.cache,
            notifications: opts.notifications,
        }))
        .map_err(|err| CliFailure {
            message: err.to_string(),
            exit_code: SERIALIZATION,
        })?;

    match opts.format {
        StatusFormat::Json => {
            let line = envelope.to_json_line().map_err(|err| CliFailure {
                message: err.message().to_owned(),
                exit_code: err.exit_code(),
            })?;
            print!("{line}");
        }
        StatusFormat::Human => {
            print!("{}", format_human(&envelope));
        }
    }
    Ok(())
}

fn dispatch_login(provider: ProviderId) -> Result<(), CliFailure> {
    use crate::providers::adapter::run_login;
    use crate::providers::{adapter_for, ExecutionEnvironment, TokioProcessRunner};

    let adapter = adapter_for(provider);
    let env = ExecutionEnvironment::from_process();
    let discovery = adapter
        .discover(&env)
        .map_err(|err| CliFailure::validation(err.to_string()))?;
    if adapter.descriptor().login_argv.is_empty() {
        return Err(CliFailure {
            message: format!(
                "{} has no login command; sign in inside the provider CLI instead",
                adapter.descriptor().display_name
            ),
            exit_code: GENERIC_FAILURE,
        });
    }
    if discovery.login_executable().is_none() {
        return Err(CliFailure {
            message: format!(
                "{} login executable was not found; install the provider CLI first",
                adapter.descriptor().display_name
            ),
            exit_code: GENERIC_FAILURE,
        });
    }

    let runner = TokioProcessRunner;
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|err| CliFailure::internal(err.to_string()))?;
    let outcome = runtime
        .block_on(run_login(adapter, &discovery, &runner, &runner))
        .map_err(|err| CliFailure {
            message: err.to_string(),
            exit_code: GENERIC_FAILURE,
        })?;
    if outcome.exit_code == 0 {
        Ok(())
    } else {
        Err(CliFailure {
            message: String::new(),
            exit_code: outcome.exit_code,
        })
    }
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct ResetStdout<'a> {
    schema_version: u32,
    operation: &'static str,
    provider: &'static str,
    reset_id: &'a str,
    result: &'static str,
    resets_left: Option<u32>,
    #[serde(with = "time::serde::rfc3339::option")]
    cooldown_until: Option<time::OffsetDateTime>,
    clears: &'a [String],
}

/// `reset claude <reset-id>` (CLI-032..037). The reset id's shape and its
/// claim program are validated here, at exit VALIDATION, before any
/// filesystem or network I/O; grammar already rejected a non-Claude provider.
fn dispatch_reset(reset_id: String) -> Result<(), CliFailure> {
    use crate::providers::catalog::{ExecutionEnvironment, CLAUDE};
    use crate::providers::http::ReqwestHttpClient;
    use crate::providers::process::TokioProcessRunner;
    use crate::providers::{claim_claude_reset, ClaimTarget, ResetContext};
    use crate::status::schema::validate_reset_id;
    use crate::support::{RealFileSystem, SystemClock};

    validate_reset_id(&reset_id).map_err(|err| CliFailure::validation(err.message().to_owned()))?;
    if ClaimTarget::parse(&reset_id).is_none() {
        return Err(CliFailure::validation(format!(
            "usage reset '{reset_id}' cannot be claimed"
        )));
    }

    let env = ExecutionEnvironment::from_process();
    let http = ReqwestHttpClient::new(CLAUDE.timeout)
        .map_err(|err| CliFailure::internal(err.to_string()))?;
    let process = TokioProcessRunner;
    let fs = RealFileSystem;
    let clock = SystemClock;
    let ctx = ResetContext {
        env: &env,
        clock: &clock,
        fs: &fs,
        process: &process,
        http: &http,
    };

    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|err| CliFailure::internal(err.to_string()))?;
    let report = runtime.block_on(claim_claude_reset(&ctx, &reset_id));

    let doc = ResetStdout {
        schema_version: 1,
        operation: "reset",
        provider: "claude",
        reset_id: &reset_id,
        result: report.result.as_str(),
        resets_left: report.resets_left,
        cooldown_until: report.cooldown_until,
        clears: &report.clears,
    };
    let json = serde_json::to_string(&doc).map_err(|err| CliFailure::internal(err.to_string()))?;
    println!("{json}");
    Ok(())
}

fn dispatch_config(command: ConfigCommand) -> Result<(), CliFailure> {
    use crate::settings::{SettingsStore, StoreError};
    use std::io::Read;

    let store = SettingsStore::with_paths(
        crate::settings::store::default_settings_path(),
        crate::settings::store::default_maintenance_lock_path(),
    )
    .map_err(|err| CliFailure::validation(err.to_string()))?;

    let map_store_err = |err: StoreError| match err {
        StoreError::Validation(v) => CliFailure::validation(v.message().to_owned()),
        StoreError::Io(io_err) => CliFailure::validation(io_err.to_string()),
    };

    match command {
        ConfigCommand::Show => {
            let doc = store.show().map_err(map_store_err)?;
            let line = doc
                .to_canonical_json_line()
                .map_err(|err| CliFailure::validation(err.message().to_owned()))?;
            print!("{line}");
            Ok(())
        }
        ConfigCommand::Apply(input) => {
            let raw = match input {
                ConfigInput::Stdin => {
                    let mut buf = String::new();
                    io::stdin()
                        .read_to_string(&mut buf)
                        .map_err(|err| CliFailure::validation(err.to_string()))?;
                    buf
                }
                ConfigInput::File(path) => std::fs::read_to_string(&path)
                    .map_err(|err| CliFailure::validation(err.to_string()))?,
                ConfigInput::Json(value) => value,
            };
            let stored = store.apply_raw(raw.as_bytes()).map_err(map_store_err)?;
            let line = stored
                .to_canonical_json_line()
                .map_err(|err| CliFailure::validation(err.message().to_owned()))?;
            print!("{line}");
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn help_footer_lists_every_closed_provider() {
        let help = help_text(None);
        let expected = ProviderId::ALL
            .iter()
            .map(|id| id.as_str())
            .collect::<Vec<_>>()
            .join(", ");
        let line = help
            .lines()
            .find(|line| line.starts_with("Providers: "))
            .unwrap_or_default();
        assert_eq!(line, format!("Providers: {expected}"));
        for id in ProviderId::ALL {
            assert!(line.contains(id.as_str()), "{line}");
        }
    }

    #[test]
    fn version_stdout_is_package_semver_plus_newline() {
        let out = version_stdout();
        assert_eq!(out, format!("{}\n", env!("CARGO_PKG_VERSION")));
        assert!(!out.contains('\0'));
    }

    #[test]
    fn uninstall_tty_accepts_exact_phrase() {
        let mut stdin = Cursor::new(b"uninstall agent-bar\n".as_slice());
        let mut stderr = Vec::new();
        confirm_uninstall(true, false, &mut stdin, &mut stderr).unwrap();
        assert!(String::from_utf8_lossy(&stderr).contains("Type uninstall agent-bar to continue:"));
    }

    #[test]
    fn uninstall_tty_rejects_wrong_phrase_and_eof() {
        let mut stdin = Cursor::new(b"nope\n".as_slice());
        let mut stderr = Vec::new();
        let err = confirm_uninstall(true, false, &mut stdin, &mut stderr).unwrap_err();
        assert_eq!(err.exit_code, VALIDATION);

        let mut stdin = Cursor::new(Vec::new());
        let err = confirm_uninstall(true, true, &mut stdin, &mut stderr).unwrap_err();
        assert_eq!(err.exit_code, VALIDATION);
    }

    #[test]
    fn update_tty_accepts_exact_phrase_only() {
        let mut stdin = Cursor::new(b"update agent-bar\n".as_slice());
        let mut stderr = Vec::new();
        assert_eq!(confirm_update(true, &mut stdin, &mut stderr).unwrap(), None);
        assert_eq!(
            String::from_utf8_lossy(&stderr),
            "Type update agent-bar to continue:"
        );

        for input in [b"update\n".as_slice(), b"uninstall agent-bar\n", b""] {
            let mut stdin = Cursor::new(input);
            let err = confirm_update(true, &mut stdin, &mut Vec::new()).unwrap_err();
            assert_eq!(err.exit_code, VALIDATION, "{input:?}");
        }
    }

    #[test]
    fn update_json_confirmation_accepts_the_contract_document() {
        let good = br#"{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":"10.7.0"}"#;
        let mut stdin = Cursor::new(good.as_slice());
        assert_eq!(
            confirm_update(false, &mut stdin, &mut Vec::new()).unwrap(),
            Some("10.7.0".to_owned())
        );

        let mut stdin = Cursor::new(b"update agent-bar\n".as_slice());
        let err = confirm_update(false, &mut stdin, &mut Vec::new()).unwrap_err();
        assert_eq!(err.exit_code, VALIDATION);
    }

    #[test]
    fn uninstall_json_confirmation_matrix() {
        let good = br#"{"schemaVersion":1,"operation":"uninstall","confirmed":true,"purgeSettingsAndBackups":false}"#;
        let mut stdin = Cursor::new(good.as_slice());
        let mut stderr = Vec::new();
        confirm_uninstall(false, false, &mut stdin, &mut stderr).unwrap();

        let mut stdin = Cursor::new(good.as_slice());
        let err = confirm_uninstall(false, true, &mut stdin, &mut stderr).unwrap_err();
        assert_eq!(err.exit_code, VALIDATION);

        let bad = br#"{"schemaVersion":1,"operation":"uninstall","confirmed":false,"purgeSettingsAndBackups":false}"#;
        let mut stdin = Cursor::new(bad.as_slice());
        let err = confirm_uninstall(false, false, &mut stdin, &mut stderr).unwrap_err();
        assert_eq!(err.exit_code, VALIDATION);

        let mut stdin = Cursor::new(b"{not-json".as_slice());
        let err = confirm_uninstall(false, false, &mut stdin, &mut stderr).unwrap_err();
        assert_eq!(err.exit_code, VALIDATION);

        let mut stdin = Cursor::new(
            br#"{"schemaVersion":1,"operation":"uninstall","confirmed":true,"purgeSettingsAndBackups":false}{}"#
                .as_slice(),
        );
        let err = confirm_uninstall(false, false, &mut stdin, &mut stderr).unwrap_err();
        assert_eq!(err.exit_code, VALIDATION);
    }
}
