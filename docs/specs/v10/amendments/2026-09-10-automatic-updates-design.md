# Automatic updates that reload the shell

Date: 2026-09-10
Status: approved

## Context

Omarchy 4.0.3 stopped handing third-party plugins `manifest.__sourceDir`.
Agent Bar 10.3.22 read its helper path from that field, so on every updated
machine no process lane started, including the update check. Release 10.3.23
fixed the path, but it could reach those machines only through a terminal
command, because nothing in Omarchy updates plugins on its own: the
`omarchy update` flow runs user hooks only, and the plugin menu offers no
update entry.

A second gap showed up in the same verification. `omarchy plugin update`
fast-forwards the tree and asks the shell to rescan plugins, and the rescan
does not reload a running `Service.qml`. After an update, on 10.3.23 as on
earlier versions, the old QML kept running against the new tree until the
next shell restart, whether the update came from the terminal or from the
Settings button.

The owner asked for updates that reach users without a terminal, with a
Settings switch to turn them off.

## Decision

1. `update apply` queues a transient unit with `systemd-run --user --collect
   --no-block --property=RuntimeMaxSec=25h` whose command is the helper's
   own `update run`, and returns at once. It still fails closed, before any
   unit starts, when `omarchy`, `omarchy-restart-shell`, or `systemd-run` is
   missing.
2. `update run` is the unit's body. It reads the plugin `HEAD`, runs
   `omarchy plugin update othavi0.agent-bar --yes` under a ten-minute
   `timeout`, and reads `HEAD` again. An unchanged `HEAD` ends the run with
   no toast and no restart, which covers "is up to date" exits and installs
   whose `origin` lags the official release. A moved `HEAD` sends a
   `notify-send` toast when available (its failure is ignored) and then runs
   `omarchy-restart-shell`. That command refuses while the session is
   locked, so the restart is retried every minute for up to a day. A second
   `update run` while one holds `$XDG_STATE_HOME/agent-bar/update-run.lock`
   exits at once. The run never takes the maintenance lock, so status and
   settings keep working during a long fetch.
3. `Service.qml` checks for updates two minutes after the helper answers and
   every six hours after that. When the check reports a plain available
   update, it applies it through the same handoff the Settings button uses.
   It does not check or apply until the boot settings read succeeded, while
   the popup is open, while maintenance is in flight, or when the setting is
   off. It never applies `reinstall_required`. A failed automatic check
   paints nothing and waits for the next tick. A click on `Check for
   updates` during a silent automatic check adopts it as a manual check.
4. `settings.json` gains an optional `updates.automatic` boolean. Absent
   means `true`, so every existing document keeps parsing and gets automatic
   updates. Settings shows it as the "Update automatically" toggle.

## Contract changes

- `UX-041A` adds the automatic check and apply; `UX-041` is unchanged.
- `SET-028` defines `updates.automatic`.
- `MIG-020` and the unit description in `03`, `06`, and `08` describe the
  `update run` unit.
- `CLI` grammar gains `update run`.

## Consequences

Installs still on 10.3.22 cannot receive this release on their own. Their
running code never reaches the helper, so each needs
`omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell`
once. Installs on 10.3.23 receive it after one Settings update and one shell
restart. From this release on, updates arrive and reload without either step.
