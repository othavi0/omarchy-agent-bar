# Private Helper Commands

The helper is bundled inside the plugin and is not the normal user interface.
Users interact through the Quickshell UI; these commands support diagnostics,
recovery, and the shared service.

Resolve it with:

```bash
PLUGIN="$HOME/.config/omarchy/plugins/othavi0.agent-bar/bin/agent-bar"
```

## Status

```text
agent-bar
agent-bar status
agent-bar status format human|json
agent-bar status provider <id>
agent-bar status cache use|bypass
agent-bar status notifications evaluate|skip
```

Status arguments may appear in any order and at most once. Defaults:

```text
format human
provider all enabled
cache use
notifications skip
```

Examples:

```bash
"$PLUGIN" status
"$PLUGIN" status format json provider claude
"$PLUGIN" status provider codex cache bypass format json
```

Only the shared Quickshell service uses `notifications evaluate`.

## Login

```bash
"$PLUGIN" login claude
"$PLUGIN" login codex
"$PLUGIN" login grok
```

Login delegates to the official provider CLI. Agent Bar never receives
credentials and preserves the meaningful provider exit status.

Antigravity has no login command; its catalog entry carries an empty login
argv, so `"$PLUGIN" login antigravity` never launches a CLI and fails with
`Antigravity has no login command; sign in inside the provider CLI instead`.

## Settings

```bash
"$PLUGIN" config show
"$PLUGIN" config apply stdin
"$PLUGIN" config apply file /path/to/settings.json
"$PLUGIN" config apply json '{"schemaVersion":1,"providers":[{"id":"claude","enabled":true},{"id":"codex","enabled":true},{"id":"grok","enabled":false},{"id":"antigravity","enabled":false}],"display":{"metric":"remaining"},"refreshIntervalSeconds":60,"notifications":{"enabled":true,"reminderMinutes":120}}'
```

`show` is read-only. `apply` requires one complete valid settings document and
returns the canonical stored document.

## Plugin integration

Install and update go through `omarchy plugin add|update othavi0.agent-bar`.
There is no `setup` or `doctor` command; both were removed with the v9
migration they existed to support. See "Recovering a v9 settings file" in
[docs/guide/troubleshooting.md](troubleshooting.md) for the manual
recovery path.

## Update

```bash
"$PLUGIN" update
"$PLUGIN" update check
"$PLUGIN" update apply
```

- Bare `update` has no interactive flow. It prints usage that names
  `update check`, `update apply`, and the terminal fallback command, then
  exits `3`.
- `update check` returns machine-readable compatibility metadata read from
  this repository's own `bundle.json` git receipt (the repository root is
  the plugin tree; see [ADR 0006](../adr/0006-single-repository-distribution.md)).
  It never fetches, installs, or restarts the shell. It only reports what
  is available.
- `update apply` installs the release that `master` holds, through the
  Omarchy plugin manager, after one confirmation (see
  [docs/specs/v10/amendments/2026-09-22-update-apply-in-popup-design.md](../specs/v10/amendments/2026-09-22-update-apply-in-popup-design.md)).
  It runs in the foreground and never on a schedule. `update run` is a
  grammar error like any other unknown argument.

`update apply` requires confirmation before it takes any lock or starts
any process:

- On a TTY, type the exact phrase `update agent-bar` at the prompt.
- On non-TTY stdin, provide exactly one JSON confirmation document:

  ```json
  {
    "schemaVersion": 1,
    "operation": "update",
    "confirmed": true,
    "targetVersion": "10.7.0"
  }
  ```

  `targetVersion` must be a `major.minor.patch` string and `confirmed`
  must be `true`. Unknown fields and trailing bytes after the object are
  rejected with exit `3`.

After confirmation, the command takes the maintenance lock, reads the
installed version from the plugin root's `bundle.json`, and runs
`omarchy plugin update othavi0.agent-bar --yes` with a 120 second timeout.
It prints one stdout JSON line:

```json
{
  "schemaVersion": 1,
  "operation": "update",
  "result": "updated",
  "installedVersion": "10.7.0",
  "restartRequired": true
}
```

| `result` | Meaning |
| --- | --- |
| `updated` | The plugin manager succeeded and the installed version changed. Restart the shell to load it. |
| `up_to_date` | The plugin manager succeeded and the installed version did not change. |
| `local_changes` | The plugin folder has local changes, so the fast-forward was refused. |
| `fetch_failed` | The plugin manager could not fetch from GitHub. |
| `validation_failed` | The new tree failed `omarchy-plugin-validate` and was rolled back. |
| `timed_out` | The plugin manager did not finish within 120 seconds. |
| `failed` | Any other outcome. |

Every result exits `0`. `installedVersion` is the version on disk after
the run, and `restartRequired` is `true` only for `updated`. The plugin
manager's own output never reaches stdout, and stderr gets one line with
the result name. Exit `3` means the confirmation was rejected, and exit
`5` means `HOME`, `omarchy`, the maintenance lock, or the installed
`bundle.json` was unavailable. The command never restarts the shell.

When an update is available, the Settings About tab offers
`Update to <version>`, which runs `update apply`, and also shows the
command for a terminal:

```bash
omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell
```

## Uninstall

```bash
"$PLUGIN" uninstall
"$PLUGIN" uninstall purge
```

Both forms require confirmation before any mutation:

- On a TTY, type the exact phrase `uninstall agent-bar` at the prompt.
- On non-TTY stdin, provide a strict JSON confirmation document:

  ```json
  {
    "schemaVersion": 1,
    "operation": "uninstall",
    "confirmed": true,
    "purgeSettingsAndBackups": false
  }
  ```

  `purgeSettingsAndBackups` must match the invoked form (`true` only for
  `uninstall purge`), `confirmed` must be `true`, and trailing bytes after
  the JSON object are rejected.

After confirmation, `uninstall` purges only Agent Bar's own XDG state, then
delegates unconditionally to `omarchy plugin remove othavi0.agent-bar --yes`
as a detached transient unit — that command owns the plugin tree and the
`shell.json` entry now. Standard uninstall preserves settings, cache, and
migration backups. Purge additionally removes `$XDG_CONFIG_HOME/agent-bar`,
`$XDG_CACHE_HOME/agent-bar`, and `$XDG_STATE_HOME/agent-bar` before the
handoff. Both forms print one stdout JSON line once the handoff is accepted:

```json
{
  "schemaVersion": 1,
  "operation": "uninstall",
  "purged": false,
  "delegated": true,
  "unit": "agent-bar-remove-<txid>.service"
}
```

## Reset

```bash
"$PLUGIN" reset claude <reset-id>
```

Claims one banked Claude usage reset (a `resets[].id` from `status`, such as
`cedar-ember:opus55-launch-promax-20260921` or `juniper-tide`). The command
fetches fresh usage first and claims the id only if that fresh response still
lists it as `claimable`; it never retries the claim. stdout is exactly one
JSON line:

```json
{
  "schemaVersion": 1,
  "operation": "reset",
  "provider": "claude",
  "resetId": "cedar-ember:opus55-launch-promax-20260921",
  "result": "reset",
  "resetsLeft": 0,
  "cooldownUntil": null,
  "clears": ["session", "weekly"]
}
```

`result` is one of `reset`, `already_used`, `not_limited`, `cooldown`,
`ineligible`, `unavailable`, `unauthenticated`, `network_error`,
`provider_error`, or `unconfirmed`. Every one of them exits `0`, because they
are typed data, not process failures. `unconfirmed` means the POST left the
machine and the helper could not read a known result back, so the reset may
have been consumed; the popup refreshes the provider to find out. `unavailable` means the claim cannot be made from this
machine right now: the fresh usage response does not list the id as
`claimable`, or `$HOME/.claude.json` has no valid
`oauthAccount.organizationUuid`. Signing in again does not fix the second
case. A reset id that fails validation, or that names no
claim program (`codex-credits`), exits `3` (`VALIDATION`) before any
filesystem or network access; a provider other than `claude` is
a grammar error (exit `2`).

## Help and version

```bash
"$PLUGIN" help
"$PLUGIN" help status
"$PLUGIN" version
"$PLUGIN" --help
"$PLUGIN" --version
```

`--help` and `--version` are the only supported double-dash aliases. Every
other flag or v9 command is rejected.

## Output and exit codes

JSON mode writes one object plus newline to stdout. Logs and diagnostics use
stderr.

| Code | Meaning |
| --- | --- |
| `0` | Request processed; provider failures may still be typed data |
| `1` | Generic operation failure, including login pre-flight failures |
| `2` | CLI grammar or unsupported value |
| `3` | Settings/input validation surfaced by `config` commands |
| `4` | Status/schema/serialization invariant; `status` also exits 4 when settings fail to load |
| `5` | Plugin integration or delegation failure |
| `70` | Unexpected internal failure |

`login <provider>` passes the delegated provider CLI's own exit code
through verbatim when the login command runs and fails; the reserved codes
above apply to the helper's own failures.

Set `RUST_LOG` for diagnostics. There is no verbose command option.
