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

1. `update apply` starts its transient unit as `--service-type=oneshot` with
   two `ExecStartPost=` steps: a `notify-send` toast, then
   `omarchy-restart-shell`. Oneshot runs `ExecStartPost=` only after
   `omarchy plugin update` exits 0, so a failed or rolled-back update never
   restarts the shell. A missing `notify-send` drops the toast; a missing
   `omarchy-restart-shell` fails closed like `omarchy` and `systemd-run`.
   Both paths are embedded in unit command lines, so any path with
   whitespace, quotes, `%`, `$`, or `\` fails closed.
2. `Service.qml` checks for updates two minutes after the helper answers and
   every six hours after that. When the check reports a plain available
   update, it applies it through the same handoff the Settings button uses.
   It does not check or apply while the popup is open, while maintenance is
   in flight, or when the setting is off. It never applies
   `reinstall_required`. A failed automatic check paints nothing and waits
   for the next tick.
3. `settings.json` gains an optional `updates.automatic` boolean. Absent
   means `true`, so every existing document keeps parsing and gets automatic
   updates. Settings shows it as the "Update automatically" toggle.

## Contract changes

- `UX-041` becomes: `Check for updates` performs an explicit network request;
  `UX-041A` adds the automatic check and apply above.
- `SET-028` defines `updates.automatic`.
- `MIG-020` and the unit description in `03`, `06`, and `08` gain the
  oneshot `ExecStartPost=` steps.

## Consequences

Installs still on 10.3.22 cannot receive this release on their own. Their
running code never reaches the helper, so each needs
`omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell`
once. Installs on 10.3.23 receive it after one Settings update and one shell
restart. From this release on, updates arrive and reload without either step.
