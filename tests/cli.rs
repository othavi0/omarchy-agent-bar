use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;

use agent_bar::cli::{
    parse, CacheMode, Command, ConfigCommand, ConfigInput, HelpTopic, NotificationMode, ProviderId,
    StatusFormat, StatusOptions, UpdateCommand, GRAMMAR, PLUGIN, SUCCESS, VALIDATION,
};
use assert_cmd::Command as CargoBin;
use tempfile::tempdir;

fn words(args: &[&str]) -> Vec<String> {
    args.iter().map(|s| (*s).to_owned()).collect()
}

fn status_opts(
    format: StatusFormat,
    provider: Option<ProviderId>,
    cache: CacheMode,
    notifications: NotificationMode,
) -> StatusOptions {
    StatusOptions {
        format,
        provider,
        cache,
        notifications,
    }
}

#[test]
fn bare_agent_bar_equals_status_format_human() {
    assert_eq!(
        parse(words(&[])).unwrap(),
        Command::Status(StatusOptions::default())
    );
    assert_eq!(
        parse(words(&["status"])).unwrap(),
        Command::Status(StatusOptions::default())
    );
}

#[test]
fn all_24_status_clause_order_permutations_parse() {
    let clauses = [
        ("format", "json"),
        ("provider", "claude"),
        ("cache", "bypass"),
        ("notifications", "evaluate"),
    ];
    let mut count = 0usize;
    for a in 0..4 {
        for b in 0..4 {
            if b == a {
                continue;
            }
            for c in 0..4 {
                if c == a || c == b {
                    continue;
                }
                for d in 0..4 {
                    if d == a || d == b || d == c {
                        continue;
                    }
                    let order = [a, b, c, d];
                    let mut args = vec!["status".to_owned()];
                    for &idx in &order {
                        args.push(clauses[idx].0.to_owned());
                        args.push(clauses[idx].1.to_owned());
                    }
                    let cmd = parse(args).unwrap_or_else(|e| panic!("perm {order:?}: {e:?}"));
                    assert_eq!(
                        cmd,
                        Command::Status(status_opts(
                            StatusFormat::Json,
                            Some(ProviderId::Claude),
                            CacheMode::Bypass,
                            NotificationMode::Evaluate,
                        )),
                        "perm {order:?}"
                    );
                    count += 1;
                }
            }
        }
    }
    assert_eq!(count, 24);
}

#[test]
fn status_rejects_duplicates_missing_values_and_unknowns() {
    let cases = [
        words(&["status", "format"]),
        words(&["status", "format", "json", "format", "human"]),
        words(&["status", "provider"]),
        words(&["status", "provider", "nope"]),
        words(&["status", "cache", "maybe"]),
        words(&["status", "notifications", "always"]),
        words(&["status", "unknown"]),
        words(&[
            "status", "format", "json", "provider", "claude", "provider", "amp",
        ]),
    ];
    for args in cases {
        let err = parse(args.clone()).unwrap_err();
        assert_eq!(err.exit_code, GRAMMAR, "{args:?}");
    }
}

#[test]
fn retired_amp_provider_id_is_an_ordinary_unknown_provider_error() {
    // Amp was retired 2026-09-17: `amp` is now unrecognized exactly like any
    // id that was never in the catalog, both for `status provider` and for
    // `login`.
    let err = parse(words(&["status", "provider", "amp"])).unwrap_err();
    assert_eq!(err.exit_code, GRAMMAR);
    let err = parse(words(&["login", "amp"])).unwrap_err();
    assert_eq!(err.exit_code, GRAMMAR);
}

#[test]
fn status_accepts_each_provider_and_format() {
    for provider in ProviderId::ALL {
        let cmd = parse(words(&[
            "status",
            "provider",
            provider.as_str(),
            "format",
            "human",
        ]))
        .unwrap();
        assert_eq!(
            cmd,
            Command::Status(status_opts(
                StatusFormat::Human,
                Some(provider),
                CacheMode::Use,
                NotificationMode::Skip,
            ))
        );
    }
    assert_eq!(
        parse(words(&["status", "format", "json", "cache", "use"])).unwrap(),
        Command::Status(status_opts(
            StatusFormat::Json,
            None,
            CacheMode::Use,
            NotificationMode::Skip,
        ))
    );
}

#[test]
fn login_config_update_uninstall_forms() {
    assert_eq!(
        parse(words(&["login", "grok"])).unwrap(),
        Command::Login(ProviderId::Grok)
    );
    assert_eq!(
        parse(words(&["config", "show"])).unwrap(),
        Command::Config(ConfigCommand::Show)
    );
    assert_eq!(
        parse(words(&["config", "apply", "stdin"])).unwrap(),
        Command::Config(ConfigCommand::Apply(ConfigInput::Stdin))
    );
    assert_eq!(
        parse(words(&["config", "apply", "file", "/tmp/settings.json"])).unwrap(),
        Command::Config(ConfigCommand::Apply(ConfigInput::File(PathBuf::from(
            "/tmp/settings.json"
        ))))
    );
    assert_eq!(
        parse(words(&[
            "config",
            "apply",
            "json",
            r#"{"schemaVersion":1}"#
        ]))
        .unwrap(),
        Command::Config(ConfigCommand::Apply(ConfigInput::Json(
            r#"{"schemaVersion":1}"#.into()
        )))
    );
    assert_eq!(
        parse(words(&["update"])).unwrap(),
        Command::Update(UpdateCommand::Interactive)
    );
    assert_eq!(
        parse(words(&["update", "check"])).unwrap(),
        Command::Update(UpdateCommand::Check)
    );
    assert_eq!(
        parse(words(&["update", "apply"])).unwrap(),
        Command::Update(UpdateCommand::Apply)
    );
    assert_eq!(
        parse(words(&["update", "run"])).unwrap(),
        Command::Update(UpdateCommand::Run)
    );
    assert_eq!(
        parse(words(&["uninstall"])).unwrap(),
        Command::Uninstall { purge: false }
    );
    assert_eq!(
        parse(words(&["uninstall", "purge"])).unwrap(),
        Command::Uninstall { purge: true }
    );
}

#[test]
fn reset_claude_accepts_each_known_id_shape() {
    for id in ["juniper-tide", "cedar-ember:opus55-launch-promax-20260921"] {
        assert_eq!(
            parse(words(&["reset", "claude", id])).unwrap(),
            Command::Reset {
                reset_id: id.to_owned()
            },
            "{id}"
        );
    }
}

#[test]
fn reset_rejects_missing_arguments_wrong_provider_and_extra_words() {
    for extra in [
        words(&["reset"]),
        words(&["reset", "claude"]),
        words(&["reset", "codex", "codex-credits"]),
        words(&["reset", "grok", "weekly"]),
        words(&["reset", "claude", "juniper-tide", "extra"]),
        words(&["reset", "claude", "--flag"]),
    ] {
        let err = parse(extra.clone()).unwrap_err();
        assert_eq!(err.exit_code, GRAMMAR, "{extra:?}");
    }
}

#[test]
fn update_subcommand_arguments_are_grammar_errors() {
    for extra in [
        words(&["update", "run", "now"]),
        words(&["update", "apply", "10.0.0"]),
        words(&["update", "apply", "extra", "words"]),
    ] {
        let err = parse(extra.clone()).unwrap_err();
        assert_eq!(err.exit_code, GRAMMAR, "{extra:?}");
    }
}

#[test]
fn setup_and_doctor_are_grammar_errors() {
    for extra in [
        words(&["setup"]),
        words(&["setup", "extra"]),
        words(&["doctor"]),
        words(&["doctor", "scan"]),
        words(&["doctor", "clean"]),
    ] {
        let err = parse(extra.clone()).unwrap_err();
        assert_eq!(err.exit_code, GRAMMAR, "{extra:?}");
    }
}

#[test]
fn help_topics_accepted_and_rejected() {
    assert_eq!(parse(words(&["help"])).unwrap(), Command::Help(None));
    for topic in HelpTopic::ALL {
        assert_eq!(
            parse(words(&["help", topic.as_str()])).unwrap(),
            Command::Help(Some(topic))
        );
    }
    let err = parse(words(&["help", "waybar"])).unwrap_err();
    assert_eq!(err.exit_code, GRAMMAR);
    let err = parse(words(&["help", "menu"])).unwrap_err();
    assert_eq!(err.exit_code, GRAMMAR);
}

#[test]
fn double_dash_aliases_and_legacy_rejections() {
    assert_eq!(parse(words(&["--help"])).unwrap(), Command::Help(None));
    assert_eq!(parse(words(&["--version"])).unwrap(), Command::Version);
    assert_eq!(parse(words(&["version"])).unwrap(), Command::Version);

    let action_right = concat!("action", "-", "right");
    let menu_font = concat!("menu", "-", "font");
    let legacy: Vec<Vec<&str>> = vec![
        vec!["menu"],
        vec!["waybar"],
        vec!["watch"],
        vec![action_right],
        vec!["remove"],
        vec![menu_font],
        vec!["assets-install"],
        vec!["-t"],
        vec!["-v"],
        vec!["--format", "json"],
        vec!["--json"],
        vec!["--provider", "claude"],
        vec!["--verbose"],
        vec!["--watch"],
        vec!["--yes"],
        vec!["status", "--format", "json"],
        vec!["config", "apply", "--json", "{}"],
    ];
    for args in legacy {
        let owned: Vec<String> = args.iter().map(|s| (*s).to_owned()).collect();
        let err = parse(owned.clone()).unwrap_err();
        assert_eq!(err.exit_code, GRAMMAR, "{args:?}");
    }
}

#[test]
fn binary_version_prints_exact_package_semver_only() {
    let assert = CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .arg("version")
        .assert()
        .code(SUCCESS)
        .stdout(format!("{}\n", env!("CARGO_PKG_VERSION")))
        .stderr("");
    let _ = assert;

    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .arg("--version")
        .assert()
        .code(SUCCESS)
        .stdout(format!("{}\n", env!("CARGO_PKG_VERSION")))
        .stderr("");
}

#[test]
fn binary_version_does_not_require_config_home() {
    let dir = tempdir().unwrap();
    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .arg("version")
        .env("HOME", dir.path())
        .env("XDG_CONFIG_HOME", dir.path().join("missing-config"))
        .env("XDG_CACHE_HOME", dir.path().join("missing-cache"))
        .env("XDG_STATE_HOME", dir.path().join("missing-state"))
        .assert()
        .code(SUCCESS)
        .stdout(format!("{}\n", env!("CARGO_PKG_VERSION")))
        .stderr("");
}

#[test]
fn binary_grammar_errors_exit_2() {
    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .args(["status", "format", "xml"])
        .assert()
        .code(GRAMMAR)
        .stdout("");
    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .args(["--verbose"])
        .assert()
        .code(GRAMMAR)
        .stdout("");
    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .args(["menu"])
        .assert()
        .code(GRAMMAR)
        .stdout("");
    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .args(["setup", "plugins-dir", "/tmp/x"])
        .assert()
        .code(GRAMMAR)
        .stdout("");
}

#[test]
fn binary_reset_rejects_a_malformed_id_before_any_io() {
    // Validation fails before any filesystem or network access, so this is
    // deterministic regardless of the machine's real Claude credentials.
    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .args(["reset", "claude", "Not A Valid Id!"])
        .assert()
        .code(VALIDATION)
        .stdout("");
}

#[test]
fn binary_reset_rejects_an_id_without_a_claim_program_before_any_io() {
    assert_eq!(
        parse(words(&["reset", "claude", "codex-credits"])).unwrap(),
        Command::Reset {
            reset_id: "codex-credits".to_owned()
        }
    );
    let dir = tempdir().unwrap();
    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .args(["reset", "claude", "codex-credits"])
        .env("HOME", dir.path())
        .env("PATH", dir.path())
        .assert()
        .code(VALIDATION)
        .stdout("");
}

#[test]
fn binary_help_mentions_plugin_first_product() {
    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .arg("help")
        .assert()
        .code(SUCCESS)
        .stdout(predicates::str::contains("Quickshell plugin"))
        .stdout(predicates::str::contains("diagnostics"))
        .stderr("");
}

#[test]
fn binary_help_names_both_update_subcommands() {
    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .arg("help")
        .assert()
        .code(SUCCESS)
        .stdout(predicates::str::contains(
            "agent-bar update [check|apply]\n",
        ));
    CargoBin::cargo_bin("agent-bar")
        .unwrap()
        .args(["help", "update"])
        .assert()
        .code(SUCCESS)
        .stdout(predicates::str::contains("update check"))
        .stdout(predicates::str::contains("update apply"));
}

fn tree_entries(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir).unwrap().flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path.clone());
            }
            out.push(path);
        }
    }
    out.sort();
    out
}

#[test]
fn binary_update_apply_rejects_bad_confirmation_before_any_side_effect() {
    let good_shape =
        r#"{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":"10.7.0"}"#;
    let cases: Vec<String> = vec![
        String::new(),
        "   \n".to_owned(),
        "{not-json".to_owned(),
        r#"{"schemaVersion":1,"operation":"update","confirmed":false,"targetVersion":"10.7.0"}"#
            .to_owned(),
        r#"{"schemaVersion":2,"operation":"update","confirmed":true,"targetVersion":"10.7.0"}"#
            .to_owned(),
        r#"{"schemaVersion":1,"operation":"uninstall","confirmed":true,"targetVersion":"10.7.0"}"#
            .to_owned(),
        r#"{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":""}"#
            .to_owned(),
        r#"{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":"10.7"}"#
            .to_owned(),
        r#"{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":"10.7.0-rc1"}"#
            .to_owned(),
        r#"{"schemaVersion":1,"operation":"update","confirmed":true}"#.to_owned(),
        r#"{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":"10.7.0","extra":1}"#
            .to_owned(),
        format!("{good_shape}{good_shape}"),
        format!("{good_shape}\n{{}}"),
    ];
    for input in cases {
        let dir = tempdir().unwrap();
        let home = dir.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        let empty_path = dir.path().join("empty-path");
        std::fs::create_dir_all(&empty_path).unwrap();
        CargoBin::cargo_bin("agent-bar")
            .unwrap()
            .args(["update", "apply"])
            .env("HOME", &home)
            .env_remove("XDG_STATE_HOME")
            .env_remove("XDG_CACHE_HOME")
            .env_remove("XDG_CONFIG_HOME")
            .env("PATH", &empty_path)
            .write_stdin(input.clone())
            .assert()
            .code(VALIDATION)
            .stdout("");
        assert!(
            tree_entries(dir.path()) == vec![empty_path.clone(), home.clone()],
            "input {input:?} left side effects: {:?}",
            tree_entries(dir.path())
        );
    }
}

const UPDATE_CONFIRMATION: &str =
    r#"{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":"10.7.0"}"#;

fn update_apply_home(dir: &Path, version: &str) -> PathBuf {
    let home = dir.join("home");
    let root = home.join(".config/omarchy/plugins/othavi0.agent-bar");
    std::fs::create_dir_all(&root).unwrap();
    std::fs::write(
        root.join("bundle.json"),
        format!(r#"{{"schemaVersion":1,"version":"{version}"}}"#),
    )
    .unwrap();
    home
}

fn run_update_apply(home: &Path, path: &Path) -> std::process::Output {
    let mut child = StdCommand::new(assert_cmd::cargo::cargo_bin("agent-bar"))
        .args(["update", "apply"])
        .env("HOME", home)
        .env("XDG_STATE_HOME", home.join("state"))
        .env("PATH", path)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    {
        use std::io::Write as _;
        let mut stdin = child.stdin.take().unwrap();
        stdin.write_all(UPDATE_CONFIRMATION.as_bytes()).unwrap();
    }
    child.wait_with_output().unwrap()
}

struct LaunchFixture {
    home: PathBuf,
    path_dir: PathBuf,
    systemd_argv: PathBuf,
    marker: PathBuf,
}

fn launch_fixture(dir: &Path, systemd_run_exit: i32) -> LaunchFixture {
    let home = update_apply_home(dir, "10.6.1");
    let path_dir = dir.join("pathbin");
    let systemd_argv = dir.join("systemd-run-argv.bin");
    write_executable(&path_dir.join("omarchy"), "#!/bin/bash\nexit 99\n");
    write_executable(
        &path_dir.join("systemd-run"),
        &format!(
            "#!/bin/bash\n: > '{argv}'\nfor a in \"$@\"; do printf '%s\\0' \"$a\" >> '{argv}'; done\nexit {systemd_run_exit}\n",
            argv = systemd_argv.display()
        ),
    );
    LaunchFixture {
        marker: home.join("state/agent-bar/update-running.json"),
        home,
        path_dir,
        systemd_argv,
    }
}

fn stdout_json(output: &std::process::Output) -> serde_json::Value {
    serde_json::from_slice(&output.stdout).unwrap_or_else(|err| {
        panic!(
            "stdout {:?} is not JSON ({err}); stderr={}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        )
    })
}

#[test]
fn binary_update_apply_starts_the_run_unit_and_writes_the_marker() {
    let dir = tempdir().unwrap();
    let fx = launch_fixture(dir.path(), 0);
    let output = run_update_apply(&fx.home, &fx.path_dir);
    assert_eq!(output.status.code(), Some(SUCCESS));
    assert_eq!(
        String::from_utf8_lossy(&output.stderr),
        "agent-bar: update apply: confirmed 10.7.0\n"
    );
    let doc = stdout_json(&output);
    let unit = doc["unit"].as_str().unwrap().to_owned();
    let txid = unit.strip_prefix("agent-bar-update-").unwrap().to_owned();
    assert_eq!(txid.len(), 32);
    assert!(txid.bytes().all(|b| b.is_ascii_hexdigit()));
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        format!("{{\"schemaVersion\":1,\"operation\":\"update\",\"result\":\"started\",\"unit\":\"{unit}\"}}\n")
    );

    let helper = std::fs::canonicalize(assert_cmd::cargo::cargo_bin("agent-bar")).unwrap();
    assert_eq!(
        read_nul_argv(&fx.systemd_argv),
        [
            "--user".to_owned(),
            "--collect".to_owned(),
            "--no-block".to_owned(),
            format!("--unit={unit}"),
            "--property=RuntimeMaxSec=180".to_owned(),
            format!("--setenv=HOME={}", fx.home.display()),
            format!(
                "--setenv=XDG_STATE_HOME={}",
                fx.home.join("state").display()
            ),
            format!("--setenv=PATH={}", fx.path_dir.display()),
            "--".to_owned(),
            helper.display().to_string(),
            "update".to_owned(),
            "run".to_owned(),
        ]
    );

    let marker: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&fx.marker).unwrap()).unwrap();
    assert_eq!(marker["schemaVersion"], 1);
    assert_eq!(marker["operation"], "update");
    assert_eq!(marker["txid"], txid.as_str());
    assert_eq!(marker["targetVersion"], "10.7.0");
    let started = marker["startedAt"].as_str().unwrap();
    let started =
        time::OffsetDateTime::parse(started, &time::format_description::well_known::Rfc3339)
            .unwrap();
    assert!(
        (time::OffsetDateTime::now_utc() - started)
            .whole_seconds()
            .abs()
            < 60
    );
}

fn write_marker(path: &Path, started_at: time::OffsetDateTime) -> String {
    let started = started_at
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap();
    let body = format!(
        "{{\"schemaVersion\":1,\"operation\":\"update\",\"txid\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"startedAt\":\"{started}\",\"targetVersion\":\"10.7.0\"}}\n"
    );
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, &body).unwrap();
    body
}

#[test]
fn binary_update_apply_refuses_while_a_run_is_live() {
    let dir = tempdir().unwrap();
    let fx = launch_fixture(dir.path(), 0);
    let body = write_marker(
        &fx.marker,
        time::OffsetDateTime::now_utc() - time::Duration::seconds(30),
    );
    let output = run_update_apply(&fx.home, &fx.path_dir);
    assert_eq!(output.status.code(), Some(SUCCESS));
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        "{\"schemaVersion\":1,\"operation\":\"update\",\"result\":\"already_running\"}\n"
    );
    assert!(!fx.systemd_argv.exists());
    assert_eq!(std::fs::read_to_string(&fx.marker).unwrap(), body);
}

#[test]
fn binary_update_apply_replaces_a_stale_marker() {
    let dir = tempdir().unwrap();
    let fx = launch_fixture(dir.path(), 0);
    write_marker(
        &fx.marker,
        time::OffsetDateTime::now_utc() - time::Duration::seconds(181),
    );
    let output = run_update_apply(&fx.home, &fx.path_dir);
    assert_eq!(stdout_json(&output)["result"], "started");
    assert!(fx.systemd_argv.exists());
}

#[test]
fn binary_update_apply_needs_systemd_run_and_omarchy() {
    for missing in ["systemd-run", "omarchy"] {
        let dir = tempdir().unwrap();
        let fx = launch_fixture(dir.path(), 0);
        std::fs::remove_file(fx.path_dir.join(missing)).unwrap();
        let output = run_update_apply(&fx.home, &fx.path_dir);
        assert_eq!(output.status.code(), Some(PLUGIN), "{missing}");
        assert!(output.stdout.is_empty());
        assert!(!fx.marker.exists());
    }
}

#[test]
fn binary_update_apply_drops_the_marker_when_the_unit_does_not_start() {
    let dir = tempdir().unwrap();
    let fx = launch_fixture(dir.path(), 1);
    let output = run_update_apply(&fx.home, &fx.path_dir);
    assert_eq!(output.status.code(), Some(PLUGIN));
    assert!(output.stdout.is_empty());
    assert!(fx.systemd_argv.exists());
    assert!(!fx.marker.exists());
}

fn run_update_unit(home: &Path, path: &Path) -> std::process::Output {
    StdCommand::new(assert_cmd::cargo::cargo_bin("agent-bar"))
        .args(["update", "run"])
        .env("HOME", home)
        .env("XDG_STATE_HOME", home.join("state"))
        .env("PATH", path)
        .stdin(std::process::Stdio::null())
        .output()
        .unwrap()
}

#[test]
fn binary_update_run_publishes_the_result_file_and_drops_the_marker() {
    let dir = tempdir().unwrap();
    let home = update_apply_home(dir.path(), "10.6.1");
    let state = home.join("state/agent-bar");
    std::fs::create_dir_all(&state).unwrap();
    std::fs::write(state.join("update-running.json"), "{}").unwrap();
    let path_dir = dir.path().join("pathbin");
    write_executable(
        &path_dir.join("omarchy"),
        r#"#!/bin/bash
echo 'Updated othavi0.agent-bar.'
echo 'omarchy-shell: IPC timed out' >&2
printf '{"schemaVersion":1,"version":"10.6.2"}' > "$HOME/.config/omarchy/plugins/othavi0.agent-bar/bundle.json"
exit 1
"#,
    );
    let output = run_update_unit(&home, &path_dir);
    assert_eq!(output.status.code(), Some(SUCCESS));
    assert!(output.stdout.is_empty());
    assert_eq!(
        String::from_utf8_lossy(&output.stderr),
        "agent-bar: update run: updated\n"
    );
    let result: serde_json::Value =
        serde_json::from_slice(&std::fs::read(state.join("update-result.json")).unwrap()).unwrap();
    assert_eq!(result["schemaVersion"], 1);
    assert_eq!(result["operation"], "update");
    assert_eq!(result["result"], "updated");
    assert_eq!(result["fromVersion"], "10.6.1");
    assert_eq!(result["installedVersion"], "10.6.2");
    assert_eq!(result["restartRequired"], true);
    assert!(result["finishedAt"]
        .as_str()
        .is_some_and(|t| t.ends_with('Z')));
    assert!(!state.join("update-running.json").exists());
}

#[test]
fn binary_update_run_without_omarchy_still_publishes_failed() {
    let dir = tempdir().unwrap();
    let home = update_apply_home(dir.path(), "10.6.1");
    let empty_path = dir.path().join("empty-path");
    std::fs::create_dir_all(&empty_path).unwrap();
    let output = run_update_unit(&home, &empty_path);
    assert_eq!(output.status.code(), Some(SUCCESS));
    assert_eq!(
        String::from_utf8_lossy(&output.stderr),
        "agent-bar: update run: failed\n"
    );
    let result: serde_json::Value = serde_json::from_slice(
        &std::fs::read(home.join("state/agent-bar/update-result.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(result["result"], "failed");
    assert_eq!(result["installedVersion"], "10.6.1");
}

#[test]
fn binary_interactive_update_rejects_non_tty() {
    let dir = tempdir().unwrap();
    let home = dir.path();
    let bin = assert_cmd::cargo::cargo_bin("agent-bar");
    let mut child = StdCommand::new(&bin)
        .arg("update")
        .env("HOME", home)
        .env("XDG_STATE_HOME", home.join("state"))
        .env("XDG_CACHE_HOME", home.join("cache"))
        .env("XDG_CONFIG_HOME", home.join("config"))
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    drop(child.stdin.take());
    let output = child.wait_with_output().unwrap();
    assert_eq!(output.status.code(), Some(VALIDATION));
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("update check")
            && stderr.contains("update apply")
            && stderr
                .contains("omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell"),
        "stderr={stderr}"
    );
}

fn write_executable(path: &Path, body: &str) {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).unwrap();
    }
    std::fs::write(path, body).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(path).unwrap().permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(path, perms).unwrap();
    }
}

fn recording_shim_body(out: &Path) -> String {
    format!(
        r#"#!/usr/bin/env bash
set -euo pipefail
: > "{out}"
for a in "$@"; do
  printf '%s\0' "$a" >> "{out}"
done
exit 0
"#,
        out = out.display()
    )
}

fn read_nul_argv(path: &Path) -> Vec<String> {
    let bytes = std::fs::read(path).unwrap_or_default();
    bytes
        .split(|b| *b == 0)
        .filter(|s| !s.is_empty())
        .map(|s| String::from_utf8_lossy(s).into_owned())
        .collect()
}

struct UninstallFixture {
    home: PathBuf,
    settings_dir: PathBuf,
    cache_dir: PathBuf,
    state_dir: PathBuf,
    shell_path: PathBuf,
    shell_before: &'static [u8],
    path_dir: PathBuf,
    systemd_run_argv: PathBuf,
}

fn seed_uninstall_fixture(root: &Path) -> UninstallFixture {
    let home = root.join("home");
    let config = home.join("config");
    let cache = home.join("cache");
    let state = home.join("state");
    std::fs::create_dir_all(&home).unwrap();

    let settings_dir = config.join("agent-bar");
    std::fs::create_dir_all(&settings_dir).unwrap();
    std::fs::write(
        settings_dir.join("settings.json"),
        br#"{"schemaVersion":1}"#,
    )
    .unwrap();

    let cache_dir = cache.join("agent-bar");
    std::fs::create_dir_all(&cache_dir).unwrap();
    std::fs::write(cache_dir.join("status-v2.json"), b"{}").unwrap();
    std::fs::write(cache_dir.join("notification-state-v1.json"), b"{}").unwrap();

    let shell_path = home.join(".config/omarchy/shell.json");
    std::fs::create_dir_all(shell_path.parent().unwrap()).unwrap();
    let shell_before: &'static [u8] = br#"{"bar":{"left":[{"id":"othavi0.agent-bar"}]}}"#;
    std::fs::write(&shell_path, shell_before).unwrap();

    let path_dir = root.join("pathbin");
    write_executable(&path_dir.join("omarchy"), "#!/usr/bin/env bash\nexit 0\n");
    let systemd_run_argv = root.join("systemd-run-argv.bin");
    write_executable(
        &path_dir.join("systemd-run"),
        &recording_shim_body(&systemd_run_argv),
    );

    UninstallFixture {
        home,
        settings_dir,
        cache_dir,
        state_dir: state,
        shell_path,
        shell_before,
        path_dir,
        systemd_run_argv,
    }
}

fn run_uninstall(
    fx: &UninstallFixture,
    args: &[&str],
    confirmation: &[u8],
) -> std::process::Output {
    let path = format!(
        "{}:{}",
        fx.path_dir.display(),
        std::env::var("PATH").unwrap_or_default()
    );
    let bin = assert_cmd::cargo::cargo_bin("agent-bar");
    let mut child = StdCommand::new(&bin)
        .arg("uninstall")
        .args(args)
        .env("HOME", &fx.home)
        .env("XDG_STATE_HOME", &fx.state_dir)
        .env("XDG_CACHE_HOME", fx.cache_dir.parent().unwrap())
        .env("XDG_CONFIG_HOME", fx.settings_dir.parent().unwrap())
        .env("PATH", &path)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    {
        use std::io::Write as _;
        let mut stdin = child.stdin.take().unwrap();
        stdin.write_all(confirmation).unwrap();
    }
    child.wait_with_output().unwrap()
}

#[test]
fn uninstall_purge_removes_xdg_state_and_delegates_remove() {
    let dir = tempdir().unwrap();
    let fx = seed_uninstall_fixture(dir.path());

    let confirmation = br#"{"schemaVersion":1,"operation":"uninstall","confirmed":true,"purgeSettingsAndBackups":true}"#;
    let output = run_uninstall(&fx, &["purge"], confirmation);
    assert!(
        output.status.success(),
        "stderr={} stdout={}",
        String::from_utf8_lossy(&output.stderr),
        String::from_utf8_lossy(&output.stdout)
    );

    let stdout = String::from_utf8_lossy(&output.stdout);
    let lines: Vec<&str> = stdout.trim_end_matches('\n').lines().collect();
    assert_eq!(lines.len(), 1, "stdout must be exactly one line: {stdout}");
    let doc: serde_json::Value = serde_json::from_str(lines[0]).unwrap();
    assert_eq!(doc["schemaVersion"], 1);
    assert_eq!(doc["operation"], "uninstall");
    assert_eq!(doc["purged"], true);
    assert_eq!(doc["delegated"], true);
    let unit = doc["unit"].as_str().expect("unit is a string");
    assert!(
        unit.starts_with("agent-bar-remove-") && unit.ends_with(".service"),
        "unit={unit}"
    );

    assert!(!fx.settings_dir.exists(), "purge must remove settings dir");
    assert!(!fx.cache_dir.exists(), "purge must remove cache dir");
    assert!(
        !fx.state_dir.join("agent-bar").exists(),
        "purge must remove state dir"
    );

    let shell_after = std::fs::read(&fx.shell_path).unwrap();
    assert_eq!(
        shell_after, fx.shell_before,
        "uninstall must never touch shell.json — omarchy owns it now"
    );

    let argv = read_nul_argv(&fx.systemd_run_argv);
    assert!(
        argv.ends_with(&[
            "plugin".to_string(),
            "remove".to_string(),
            "othavi0.agent-bar".to_string(),
            "--yes".to_string(),
        ]),
        "argv={argv:?}"
    );
    assert_eq!(argv.first().map(String::as_str), Some("--user"));
    assert!(argv.contains(&"--collect".to_string()));
    assert!(argv.iter().any(|a| a == &format!("--unit={unit}")));
    assert!(argv.contains(&"--".to_string()));
}

#[test]
fn uninstall_without_purge_preserves_xdg_state_and_delegates_remove() {
    let dir = tempdir().unwrap();
    let fx = seed_uninstall_fixture(dir.path());

    let confirmation = br#"{"schemaVersion":1,"operation":"uninstall","confirmed":true,"purgeSettingsAndBackups":false}"#;
    let output = run_uninstall(&fx, &[], confirmation);
    assert!(
        output.status.success(),
        "stderr={} stdout={}",
        String::from_utf8_lossy(&output.stderr),
        String::from_utf8_lossy(&output.stdout)
    );

    let stdout = String::from_utf8_lossy(&output.stdout);
    let doc: serde_json::Value = serde_json::from_str(stdout.trim_end()).unwrap();
    assert_eq!(doc["schemaVersion"], 1);
    assert_eq!(doc["operation"], "uninstall");
    assert_eq!(doc["purged"], false);
    assert_eq!(doc["delegated"], true);
    let unit = doc["unit"].as_str().expect("unit is a string");
    assert!(unit.starts_with("agent-bar-remove-") && unit.ends_with(".service"));

    assert!(
        fx.settings_dir.join("settings.json").is_file(),
        "without purge, settings must survive"
    );
    assert!(
        fx.cache_dir.join("status-v2.json").is_file(),
        "without purge, cache must survive"
    );
    assert!(
        fx.state_dir.join("agent-bar").exists(),
        "without purge, state dir must survive"
    );

    let shell_after = std::fs::read(&fx.shell_path).unwrap();
    assert_eq!(
        shell_after, fx.shell_before,
        "uninstall must never touch shell.json — omarchy owns it now"
    );

    let argv = read_nul_argv(&fx.systemd_run_argv);
    assert!(
        argv.ends_with(&[
            "plugin".to_string(),
            "remove".to_string(),
            "othavi0.agent-bar".to_string(),
            "--yes".to_string(),
        ]),
        "argv={argv:?}"
    );
}

#[test]
fn uninstall_purge_fails_closed_without_touching_state_when_omarchy_missing() {
    let dir = tempdir().unwrap();
    let fx = seed_uninstall_fixture(dir.path());
    std::fs::remove_file(fx.path_dir.join("omarchy")).unwrap();

    let bin = assert_cmd::cargo::cargo_bin("agent-bar");
    let mut child = StdCommand::new(&bin)
        .args(["uninstall", "purge"])
        .env("HOME", &fx.home)
        .env("XDG_STATE_HOME", &fx.state_dir)
        .env("XDG_CACHE_HOME", fx.cache_dir.parent().unwrap())
        .env("XDG_CONFIG_HOME", fx.settings_dir.parent().unwrap())
        .env("PATH", &fx.path_dir)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    {
        use std::io::Write as _;
        let mut stdin = child.stdin.take().unwrap();
        if let Err(err) = stdin.write_all(
            br#"{"schemaVersion":1,"operation":"uninstall","confirmed":true,"purgeSettingsAndBackups":true}"#,
        ) {
            assert_eq!(
                err.kind(),
                std::io::ErrorKind::BrokenPipe,
                "only an early preflight exit may close stdin"
            );
        }
    }
    let output = child.wait_with_output().unwrap();

    assert!(
        !output.status.success(),
        "must fail closed when omarchy cannot be resolved: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "no delegation document on preflight failure"
    );

    assert!(
        fx.settings_dir.join("settings.json").is_file(),
        "settings must survive a failed tool resolution"
    );
    assert!(
        fx.cache_dir.join("status-v2.json").is_file(),
        "cache must survive a failed tool resolution"
    );
    assert!(
        fx.state_dir.join("agent-bar").exists(),
        "state dir must survive a failed tool resolution"
    );

    let shell_after = std::fs::read(&fx.shell_path).unwrap();
    assert_eq!(
        shell_after, fx.shell_before,
        "uninstall must never touch shell.json — omarchy owns it now"
    );
}
