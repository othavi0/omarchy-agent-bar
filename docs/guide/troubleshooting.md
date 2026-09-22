# Troubleshooting

Resolve the private helper:

```bash
PLUGIN="$HOME/.config/omarchy/plugins/othavi0.agent-bar/bin/agent-bar"
```

## Recovering a v9 settings file

A v9 `settings.json` still carries `"version": 3` and a `waybar` block.
Every v10 read (`status`, `config show`) rejects that document, so a
plugin still holding one has shown no working bar since v10.0.0. There is
no `setup` or migration command to fix it: delete or move the file, then
open Settings once and save; the UI writes a fresh v10 document that
already carries the full provider catalog.

```bash
mv "$XDG_CONFIG_HOME/agent-bar/settings.json" \
  "$XDG_CONFIG_HOME/agent-bar/settings.json.v9.bak"
```

## One provider is unavailable

```bash
"$PLUGIN" status provider claude format human cache bypass
```

Interpret the typed state:

| State | Action |
| --- | --- |
| `cli_missing` | Use `Install guide`; Agent Bar does not install it |
| `unauthenticated` | Use `Sign in` when login is available; otherwise use `Install guide` |
| `rate_limited` | Wait for the provider or reset; do not relogin blindly |
| `network_error` | Check network, then `Check again` |
| `provider_error` | Inspect safe stderr diagnostics with `RUST_LOG` |
| `stale` | Last good data is visible; refresh failed temporarily |

## Chip shows `—`

The provider is connected but exposes no normalized percentage quota for that
account. Agent Bar intentionally does not show spend, balance, or credits as a
substitute percentage.

## Codex Retry loops with “rate limits not available”

Ensure the Codex CLI is logged in and supports the `app-server` subcommand.
Agent Bar collects Codex rate limits through the `codex app-server` JSON-RPC
`account/rateLimits/read` method only. A Codex CLI older than the
app-server subcommand reports this `provider_error` on every attempt.
Update Codex to a build that supports `app-server`, then retry:

```bash
"$PLUGIN" status provider codex format human cache bypass
```

## Antigravity CLI 1.1.11 or newer is required.

Agent Bar checks `agy --version` before every usage collection. Builds older
than 1.1.11 forward the `/usage` slash command to the model as an ordinary
prompt instead of printing usage data, so Agent Bar refuses to run it and
reports this `provider_error` instead. Update `agy` to 1.1.11 or newer, then
retry:

```bash
"$PLUGIN" status provider antigravity format human cache bypass
```

## Grok shows `—` or missing Weekly

When billing returns no usable percentage and no earlier percentage exists,
Grok is connected with empty windows and the chip shows `—`. A later empty
response keeps the last percentage on the chip. Weekly reset comes from the
billing period end.
Context is no longer a product window.

## Grok shows Sign in after hours idle

The Grok CLI's access token lives six hours and nothing renews it while the
CLI is idle. Agent Bar checks the expiry before every request; when it has
passed and the `grok` executable is installed, the helper runs `grok models`
headless so the CLI renews the token, and the chip keeps the last reading as
stale meanwhile. If the chip still says Sign in, one of three things
happened: the executable was not found on `PATH`, `$GROK_HOME/bin`,
`~/.grok/bin`, or `~/.local/bin`; the CLI ran but could not renew (refresh
token revoked, or offline); or the CLI itself is signed out. Running `grok`
once in a terminal resolves all three.

## Popup does not appear

Check:

```bash
omarchy plugin validate "$HOME/.config/omarchy/plugins/othavi0.agent-bar"
omarchy-shell shell rescanPlugins
```

Then inspect:

- manifest ID and version;
- `service` and `bar-widget` entry points;
- one exact `othavi0.agent-bar` entry in `shell.json`;
- helper/manifest version equality.

Do not run `omarchy bar plugin add` over an existing entry; it can reset
placement.

If the popup reports that Agent Bar lost contact with its helper, use its
`Restart shell` button. The banner appears after helper calls stall in two
process lanes.

## Settings stay on "Loading" or report "could not be loaded" after an update

`omarchy plugin update` replaces the plugin tree and the helper on disk, but
the QML already running keeps the old code until the shell restarts. When the
new helper lists a provider the old QML does not know, Settings cannot finish
its load; a release before 10.3.13 stayed on "Loading" forever, current
releases show "Settings could not be loaded". Either way:

Use the `Restart shell` button in Settings, or run the command directly:

```bash
omarchy-restart-shell
```

## Settings do not save

```bash
"$PLUGIN" config show
```

Confirm the settings file is valid and user-owned. Save errors leave the
previous file intact. Use `RUST_LOG=debug` only with sanitized output.

While uninstall holds the exclusive maintenance lock, `config apply` waits
for the lock after validating; it completes once uninstall finishes, and the
settings file is untouched until then. `update check` takes no lock.

## Update available or update failed

When Settings shows a new version, click `Update to <version>` and
confirm. The popup runs `update apply`, which runs
`omarchy plugin update othavi0.agent-bar --yes` and reports one result.
From a terminal, the same update is:

```bash
omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell
```

`omarchy plugin update` owns the actual result. Its failure modes, with
the `update apply` result each one produces:

- **Non-fast-forward** (`local_changes`): `omarchy plugin update` refuses
  to update a plugin directory with local modifications or diverged
  history. It never force-pushes or overwrites. Run `git status` in
  `~/.config/omarchy/plugins/othavi0.agent-bar`, resolve or discard the
  local change, then retry.
- **Fetch failure** (`fetch_failed`): GitHub was unreachable. Retry when
  the network is back.
- **Validation failure after fetch** (`validation_failed`): the update
  fetches, fast-forwards, and re-validates with `omarchy-plugin-validate`.
  A failing validation runs `git reset --hard ORIG_HEAD` automatically,
  restoring the previous version; nothing is left half-installed.
- **Timeout** (`timed_out`): the plugin manager did not finish within 120
  seconds. The installed version on disk is reported unchanged unless the
  fast-forward had already happened.
- **Not a git checkout**: a plugin directory installed before the git-based
  distribution has no `.git`. `omarchy plugin update` silently skips it in
  a bulk run and refuses it outright when targeted by ID. See
  [Migrating a pre-conversion install](integration.md#migrating-a-pre-conversion-install)
  for the detection, the reinstall commands, and what survives.

`omarchy plugin update` does not reload a running shell by itself. After
`updated`, press `Restart shell` in Settings or run `omarchy-restart-shell`
so the new QML loads.

Confirm the outcome with:

```bash
"$PLUGIN" version
"$PLUGIN" status
```

## Collect diagnostics

Provide:

- Agent Bar version.
- Omarchy and Quickshell versions.
- Exact status command and exit code.
- Typed provider state.

Never include credential files, raw provider payloads, tokens, account labels,
or live `shell.json` contents that expose unrelated user configuration.
