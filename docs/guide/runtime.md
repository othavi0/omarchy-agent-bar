# Runtime

## Owned paths

| Path | Purpose |
| --- | --- |
| `$HOME/.config/omarchy/plugins/othavi0.agent-bar/` | Complete plugin bundle |
| `$XDG_CONFIG_HOME/agent-bar/settings.json` | Canonical product settings |
| `$XDG_CACHE_HOME/agent-bar/status-v2.json` | Normalized provider cache |
| `$XDG_CACHE_HOME/agent-bar/status.lock` | Cross-process collection lock |
| `$XDG_CACHE_HOME/agent-bar/notification-state-v2.json` | Alert deduplication |
| `$XDG_CACHE_HOME/agent-bar/notification.lock` | Alert evaluation/dispatch lock |
| `$XDG_STATE_HOME/agent-bar/backups/` | Backups left by the retired v9 settings migration and `doctor clean` |
| `$XDG_STATE_HOME/agent-bar/maintenance.lock` | Stable shared/exclusive mutation gate |
| `$XDG_STATE_HOME/agent-bar/update-running.json` | Marker for an update unit that is running |
| `$XDG_STATE_HOME/agent-bar/update-result.json` | Result of the last update unit, until `update status` reads it |

Default XDG paths are `~/.config`, `~/.cache`, and `~/.local/state`.

The plugin root and Omarchy `shell.json` always use `$HOME/.config/omarchy` in
production.

## Bundle

The plugin bundle contains manifest, `bundle.json`, QML, approved icons, the
terminal helper, private Rust helper, `README.md`, `LICENSE`, and
`preview.png`. `bundle.json` records ID, version, target, Omarchy contract,
minimum Quickshell version, source commit, the CI run that built and
attested the private helper (`buildRun`), and hash/size/mode for every
other file.

The installed plugin directory is a git checkout of this repository
(`othavi0/omarchy-agent-bar`): the repository root is the plugin tree
(see [ADR 0006](../adr/0006-single-repository-distribution.md)), so
`omarchy plugin add` clones it directly and `omarchy plugin update`
fast-forwards it in place. `bundle.json` is also the sole discovery
document `update check` reads, fetched over HTTPS directly from the
repository's `master` branch rather than from the local checkout, so a
check works even before the first update.

No global `agent-bar`, application entry, package, or standalone binary
exists.

## Settings

```json
{
  "schemaVersion": 1,
  "providers": [
    { "id": "claude", "enabled": true },
    { "id": "codex", "enabled": true },
    { "id": "grok", "enabled": false },
    { "id": "antigravity", "enabled": false }
  ],
  "display": {
    "metric": "remaining"
  },
  "refreshIntervalSeconds": 60,
  "notifications": {
    "enabled": true
  }
}
```

The service checks for a new release only when the user clicks `Check for
updates` in the Settings About tab; there is no background schedule. When a
release is available, Settings shows the target version, an
`Update to <version>` button, a release-notes link, a marketplace-page
link, and, on its own read-only line, the command to run in a terminal:
`omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell`.
The plugin installs code only after the user confirms that button. It then
runs `update apply`, which starts a transient user unit that calls
`omarchy plugin update` once, and polls `update status` until the unit
finishes. The plugin never reloads the shell on its own; the user presses
`Restart shell` when the update reports `updated`.

There is no `updates` block in the product settings any more. A document
written by 10.3.24 through 10.5.1 that still carries
`"updates": { "automatic": <bool> }` is tolerated on read and dropped on the
next write; any other key inside it is still rejected.

Unknown keys and invalid/duplicate/missing providers are rejected. Reads never
rewrite. Applies validate before lock and atomic replacement. File mode is
`0600`.

While maintenance holds the exclusive lock, apply validates first and then
waits for the lock; the settings file is untouched until the lock is
granted.

## Cache

Cache contains normalized status only. It does not contain:

- credentials or tokens;
- raw provider output or headers;
- account identifiers;
- monetary values;
- local session history.

Corrupt cache is quarantined and rebuilt. Temporary provider failure retains
last good data as stale.

Per-provider cache TTLs are fixed in the catalog: Claude 300 seconds;
Codex, Grok, and Antigravity 90 seconds each. Only `ready` and `stale`
rows are served from cache. A failure row with no last good data is
re-collected on the next poll, so on a fresh install or after the cache is
cleared a transient failure is visible for at most one refresh interval. When
last good data exists, the retained `stale` reading is served for the
provider's TTL instead.

## Update state

`update apply` and `update run` talk to each other only through two files
in `$XDG_STATE_HOME/agent-bar/`. Both are JSON documents with
`schemaVersion` 1 and `operation` `update`, written with mode `0600`.

- `update-running.json` holds `txid`, `startedAt`, `targetVersion`, and
  `fromVersion`, the installed version when the run started. `update
  apply` creates it before it starts the unit, and `update run <txid>`
  deletes it after it writes the result, only when the marker carries the
  same `txid`. A marker older than 240 seconds, the unit's `RuntimeMaxSec`,
  belongs to a unit that systemd has already stopped.
- `update-result.json` holds `txid`, `result`, `fromVersion`,
  `installedVersion`, `restartRequired`, and `finishedAt`. `update run`
  writes it through a temporary file and a rename, so a reader never sees
  a partial file.

`update status` deletes the result file when it reports it, together with
the marker of the same `txid`. It deletes a stale marker when it reports
it; the run is `updated` when the installed version differs from the
marker's `fromVersion`, and `failed` otherwise. A new `update apply`
replaces a stale marker and deletes a result left by an earlier run. Neither file holds plugin-manager
output, credentials, or account data. Deleting both files by hand is
always safe; the next `update status` then prints `none`.

## Provider data sources

- Claude may use local credentials plus provider HTTP. Before the usage
  request the helper best-effort runs the discovered `claude --version`; a
  parsed version adds `User-Agent: claude-cli/<version> (external, cli)` and
  `x-app: cli` so the account's banked usage-reset grants (`cedar_ember`,
  `juniper_tide`) are included in the response. Windows collect the same
  either way. `agent-bar reset claude <reset-id>` claims one of those
  grants; it reads the account's organization uuid from
  `$HOME/.claude.json`, which is never logged, cached, or echoed back.
- Codex uses the `codex app-server` JSON-RPC only. A Codex CLI older than
  the app-server subcommand reports a typed provider error instead.
- Grok may use local auth for an authenticated billing HTTPS request. The
  CLI's access token lives six hours; when it is expired and the `grok`
  executable is installed, the helper runs `grok models` headless so the CLI
  renews it, then re-reads the auth file. Until a renewed token works, the
  previous reading, when the cache holds one, stays on the bar as `stale`;
  a first collection with an expired token reports the session expired.
- Antigravity uses its official `agy --print /usage --output-format json`
  command, reads the Gemini (`gemini-weekly`, `gemini-5h`) and Claude/GPT
  (`3p-weekly`, `3p-5h`) buckets by id, and reads no credential files. The
  two families have separate quotas; the lower of the two session windows
  leads the chip. A full bucket shows no reset, because its window
  only starts on first use. It requires `agy` 1.1.11 or newer; older builds send
  `/usage` to the model as a prompt instead of printing usage data. Before
  every `agy` run the helper sends one unauthenticated `GET` to
  `https://oauth2.googleapis.com/`; if that request fails at the transport
  level the provider reports `network_error` ("Antigravity is unreachable.")
  and `agy` is not started, because an offline `agy --print` with a token
  close to expiry opens a Google sign-in tab in the browser on its own.

Collection discovery is separate from interactive login-CLI discovery.

## Stalled service recovery

The shared QML service gives each helper process lane a deadline. If two
different lanes time out before any helper callback completes, the popup shows
that Agent Bar has lost contact with its helper. Select `Restart shell` to run
`omarchy-restart-shell`. A failed Settings load keeps its existing error text
and offers the same action.

## Privacy

Logs, screenshots, checkpoints, and cache redact tokens, credentials, raw
payloads, headers, and account identifiers. External display strings are
sanitized English plain text.

## Permissions

Settings, cache, and backups are restricted to the user. Bundle executable
files are `0755`; nonexecutables use deterministic nonexecutable modes.
Bundles contain no symlinks.
