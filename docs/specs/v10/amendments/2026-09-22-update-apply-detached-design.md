# The update runs in a transient unit and reports through a state file

Date: 2026-09-22
Status: approved
Supersedes in part: `2026-09-22-update-apply-in-popup-design.md` (CLI-029A,
CLI-029B, UX-043A, UX-043B)

## Context

The first update-apply design ran the plugin manager as a child of the
helper, on a popup lane, and expected the running `Service.qml` to receive
the result. Review against the Omarchy shell source on 2026-09-22 showed
that this cannot work for a successful update:

- `services/PluginRegistry.qml` runs `inotifywait -m -r` on
  `~/.config/omarchy/plugins` and emits `localPluginChanged` for any write
  outside `.git/`. `shell.qml` reloads every plugin service without
  `keepLoaded` about 150 ms later. The journal on this machine shows 46
  such reloads of `othavi0.agent-bar` since 2026-09-21.
- The fast-forward writes the tree, so the shell destroys the old
  `Service` while the helper is still validating. `HelperLane` stops its
  process on destruction, the helper dies, and its result never reaches
  any QML instance. The new instance starts idle and knows nothing.
- The helper's 120 s timeout killed only its direct child; `git` and
  `omarchy-plugin-validate` kept running after the helper reported.
- `classify` consulted the tree version only on exit 0, so a fast-forward
  followed by a failed `rescanPlugins` reported `failed` with the new
  version and `restartRequired: false`.

Only outcomes that write nothing (`up_to_date`, `local_changes`,
`fetch_failed`) reached the popup. The three reviewers agreed on the tree
version as the source of truth and on killing the plugin manager's whole
process group on timeout.

## Decision

1. `CLI-029A`: `update apply` validates the confirmation document, logs
   `confirmed <targetVersion>` on stderr, resolves `omarchy` and
   `systemd-run` to absolute paths (exit `PLUGIN` when either is missing),
   and starts a transient unit
   `systemd-run --user --collect --no-block --unit=agent-bar-update-<txid>
   --property=RuntimeMaxSec=240 -- <helper> update run <txid>`. The 240 s
   limit leaves a minute past the 60 s lock wait plus the 120 s
   plugin-manager timeout. It writes the marker
   `$XDG_STATE_HOME/agent-bar/update-running.json`
   (`{"schemaVersion":1,"operation":"update","txid":"<txid>",
   "startedAt":"<RFC 3339>","targetVersion":"<v>",
   "fromVersion":"<tree version>"}`) before starting the unit and prints
   `{"schemaVersion":1,"operation":"update","result":"started",
   "unit":"<unit>"}`. It returns before any write to the plugin tree. The
   marker appears by hard link from a temporary file, which fails when any
   marker exists, so two racing launchers never both start a unit. An
   existing marker younger than 240 s whose `txid` has no result file makes
   `update apply` print `{"result":"already_running"}` and start nothing.
   Any other marker is stale: `update apply` takes it over only while it
   still holds the bytes it read, and never removes a marker another
   launcher wrote meanwhile.
2. `CLI-029C`: `update run <txid>` is the unit body. It takes exactly one
   argument, the 32 lowercase hex digits of the run's `txid`; any other
   form exits `2`. It takes the exclusive maintenance lock with a bounded
   wait (60 s of retries, then `result: "locked"`) and holds it for the
   plugin-manager run. A status collection or settings apply that starts
   meanwhile waits on the shared lock, up to the run's 120 s budget,
   rather than failing. It reads
   the tree version from `bundle.json`, runs
   `omarchy plugin update othavi0.agent-bar --yes` in its own process group
   with `GIT_TERMINAL_PROMPT=0`, stdin closed, and a 120 s timeout that
   kills the group, then reads the tree version again. `after != before`
   is `updated` whatever the exit status or timeout. Otherwise exit 0 is
   `up_to_date`; a non-zero exit maps by the plugin manager's stderr
   (`cannot fast-forward` to `local_changes`, `fetch failed` to
   `fetch_failed`, `failed validation` to `validation_failed`, else
   `failed`); a timeout is `timed_out`. It writes
   `$XDG_STATE_HOME/agent-bar/update-result.json` atomically (temporary
   file plus rename), `{"schemaVersion":1,"operation":"update",
   "txid":"<txid>","result":"<result>","fromVersion":"<before>",
   "installedVersion":"<after>","restartRequired":<after != before>,
   "finishedAt":"<RFC 3339>"}`, deletes the running marker only when it
   carries the same `txid`, and exits 0. A run whose marker is missing
   still runs and writes its result, which the popup or a later service
   start consumes.
   Raw plugin-manager output never enters the file. The stderr matching is
   the only coupling to the external script and is marked as such in code.
3. `CLI-029B`: `update status` prints exactly one JSON object:
   `{"schemaVersion":1,"operation":"update","status":"none"}` when neither
   file exists, `{"status":"running","startedAt":..,"targetVersion":..}`
   while the marker is younger than 240 s, `{"status":"finished", ...the
   result document fields...}` when the result file exists, whatever its
   `txid`. Reading the result file consumes it, together with the marker
   when that carries the same `txid`. A marker older than 240 s with no
   result is reported once as `{"status":"finished", "txid":"<marker
   txid>", ...}` and deleted, and only the marker this read judged is
   deleted. The tree decides its result: a tree version that differs from
   the marker's `fromVersion` is `updated` with `restartRequired: true`,
   and any other tree is `failed`. `update status` exits `5` when a state
   file cannot be read or renamed.
4. `UX-043A`: Confirm runs `update apply` on the update lane (30 s
   deadline). On `started` or `already_running` the About tab enters
   `updating` (`Updating… this takes a few seconds.`, buttons disabled),
   and the service polls `update status` every 2 s on the same lane for up
   to 240 s, the unit limit. Polling of provider status continues; a collection that
   starts while the run holds the exclusive lock waits for it (item 2).
5. `UX-043B`: On every service start, after the version probe succeeds and
   before the first status poll, the service runs `update status` once.
   `running` enters `updating` and starts the 2 s poll. `finished` with
   `restartRequired: true` sets `restartPending` on the service and the
   About phase `restart_required` (`<version> installed. Restart the
   shell to load it.`, `Restart shell`, `Later`). `finished` with any
   other result sets `update_failed` with the typed line and keeps `Check
   for updates` visible. `none` does nothing. The same handling applies to
   a `finished` seen by the 2 s poll.
6. `UX-043C`: While `restartPending` holds, the popup's status view shows
   one banner line `<version> installed. Restart the shell to load it.`
   with `Restart shell`; the bar chip does not change. The flag clears on
   `restartShell()` or when a later `update status` returns `none` after a
   restart (the result file was consumed).
7. `UX-043D`: `update_failed` keeps `Check for updates` visible and the
   `Update to <version>` button enabled for `fetch_failed`, `timed_out`,
   `locked`, and `failed`; for `local_changes` and `validation_failed` the
   button is hidden until the next check.
8. The maintenance handoff (`beginMaintenanceHandoff`, lanes blocked) is
   used by `uninstall` only. The update never blocks other lanes in QML;
   a helper command on another lane can still wait on the lock (item 2).

## Consequences

A successful update survives the shell's plugin reload: the unit finishes
under systemd, the result lands in a state file, and the recreated
`Service.qml` reads it at startup and shows the restart prompt. The popup
closes when the shell reloads the plugin; reopening it shows the banner.
Failures that write nothing reach the same instance through the 2 s poll.
A timeout kills the whole plugin-manager tree, and the tree version, not
the exit status, decides `updated`. The update no longer stops provider
polling; the recreated instance probes the new helper and keeps reading
status, so the chips stay live until the restart.
