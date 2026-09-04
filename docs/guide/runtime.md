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
| `$XDG_STATE_HOME/agent-bar/backups/` | Exact settings-migration and `doctor clean` backups |
| `$XDG_STATE_HOME/agent-bar/maintenance.lock` | Stable shared/exclusive mutation gate |

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
    { "id": "amp", "enabled": false },
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
Codex, Amp, Grok, and Antigravity 90 seconds each. Only `ready` and `stale`
rows are served from cache. A failure row with no last good data is
re-collected on the next poll, so on a fresh install or after the cache is
cleared a transient failure is visible for at most one refresh interval. When
last good data exists, the retained `stale` reading is served for the
provider's TTL instead.

## Provider data sources

- Claude may use local credentials plus provider HTTP.
- Codex may use app-server with a bounded local fallback.
- Amp uses its official usage command.
- Grok may use local auth for an authenticated billing HTTPS request. The
  CLI's access token lives six hours; when it is expired and the `grok`
  executable is installed, the helper runs `grok models` headless so the CLI
  renews it, then re-reads the auth file. Until a renewed token works, the
  previous reading, when the cache holds one, stays on the bar as `stale`;
  a first collection with an expired token reports the session expired.
- Antigravity uses its official `agy --print /usage --output-format json`
  command, reads the `gemini-weekly` and `gemini-5h` buckets by id, and reads
  no credential files. It requires `agy` 1.1.11 or newer; older builds send
  `/usage` to the model as a prompt instead of printing usage data.

Collection discovery is separate from interactive login-CLI discovery.

## Stalled service recovery

The shared QML service gives each helper process lane a deadline. If two
different lanes time out before any helper callback completes, the popup shows
that Agent Bar has lost contact with its helper. Select `Restart shell` to run
`omarchy-restart-shell`. A failed Settings load keeps its existing error text
and offers the same action.

## Privacy

Logs, screenshots, checkpoints, cache, and doctor reports redact tokens,
credentials, raw payloads, headers, and account identifiers. External display
strings are sanitized English plain text.

## Permissions

Settings, cache, and backups are restricted to the user. Bundle executable
files are `0755`; nonexecutables use deterministic nonexecutable modes.
Bundles contain no symlinks.
