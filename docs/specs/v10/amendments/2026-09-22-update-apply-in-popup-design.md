# The popup applies an update after one confirmation

Date: 2026-09-22
Status: approved
Supersedes in part: `2026-09-14-remove-update-execution-design.md`

## Context

Since the 2026-09-14 amendment the popup only prints the command
`GIT_PAGER=cat omarchy plugin update othavi0.agent-bar && omarchy-restart-shell`
for the user to paste into a terminal. Measured on 2026-09-22:

- Run in a terminal, the command works. `omarchy plugin update` fetches
  `origin HEAD`, prints the whole diff (about 2000 lines for 10.6.2), asks
  `gum confirm` at the bottom, fast-forwards, runs
  `omarchy-plugin-validate`, and calls `omarchy-shell shell rescanPlugins`.
  The rescan does not reload `Service.qml`; only `omarchy-restart-shell`
  does.
- Run anywhere that is not a TTY (a launcher, a script, a non-interactive
  shell), `omarchy-plugin-update` exits 1 with `refusing to continue
  without confirmation; pass --yes`. The owner hit this output.
- `update check` reads `bundle.json` from `raw.githubusercontent.com`
  (`master`). The CDN lags a release by minutes: two minutes after the
  10.6.2 release the check still said `available: false`.

The owner reviewed four prototypes on 2026-09-22 and chose an in-popup
update: one `Update to <version>` button, one confirmation, the helper
runs the Omarchy plugin manager, then a `Restart shell` button. The owner
made that choice knowing the marketplace blocked verification of a plugin
that installs code from mutable `master` (omacom/omarchy-plugin-marketplace
#4979, 2026-09-11) and that a confirmation dialog did not unblock other
plugins. Marketplace verification is no longer a goal of this design.

## Decision

1. `agent-bar update apply` returns to the grammar. It is the only way the
   plugin installs code, it runs only from the popup after the user
   confirms, and it never runs on a schedule. `update run`, the transient
   unit, the `update-run.lock` gate, and the restart retry loop of the
   2026-09-10 design stay removed.
2. `CLI-029`: In a non-TTY, `update apply` reads exactly one JSON document
   from stdin, the same way `uninstall` does (`CLI-027`, `CLI-028`):
   `{"schemaVersion":1,"operation":"update","confirmed":true,
   "targetVersion":"<version>"}`. Any other input exits `VALIDATION`. In a
   TTY it asks for the same confirmation phrase pattern `uninstall` uses.
3. `CLI-029A`: The command takes the maintenance lock, resolves `omarchy`
   to an absolute path (exit `PLUGIN` when missing), records the installed
   tree version, runs `omarchy plugin update othavi0.agent-bar --yes` as a
   child with `GIT_TERMINAL_PROMPT=0`, stdin closed, and a 120 second
   timeout, then records the tree version again. It does not restart the
   shell, does not touch settings or cache, and does not retry.
4. `CLI-029B`: stdout is exactly one JSON object plus newline:

```json
{
  "schemaVersion": 1,
  "operation": "update",
  "result": "updated",
  "installedVersion": "10.6.2",
  "restartRequired": true
}
```

   `result` is one of `updated` (exit 0 and the tree version changed),
   `up_to_date` (exit 0 and the version did not change), `local_changes`,
   `fetch_failed`, `validation_failed`, `timed_out`, or `failed`. The four
   failure kinds come from the plugin manager's exit status plus its
   documented stderr lines (`cannot fast-forward`, `fetch failed`, `failed
   validation`); an unmatched failure is `failed`. Every result exits `0`.
   Raw plugin-manager output never reaches stdout. `restartRequired` is
   true only for `updated`.
5. `UX-042`: When a check reports a release, the About tab shows the
   installed version, `Update to <version>` as the primary button,
   `Release notes`, `Marketplace page`, and under them the fallback
   command for a terminal, now
   `omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell`.
6. `UX-043`: `Update to <version>` opens a `ConfirmDialog` titled
   `Update to <version>?` with the message `Omarchy fetches the release,
   validates it, and installs it. The bar keeps working until you restart
   the shell.` and the confirm text `Update`. One confirmation, no arming.
7. `UX-043A`: Confirm runs `update apply` through the maintenance handoff
   (lanes blocked, polling stopped, same as `uninstall`) on its own lane
   with a 150 second deadline. The About tab shows `Updating… this takes a
   few seconds.` with every button disabled.
8. `UX-043B`: On `updated`, the tab shows `<version> installed. Restart the
   shell to load it.` with `Restart shell` as the primary button (the
   existing restart action) and `Later`. Polling stays stopped until the
   restart, because the running QML and the new helper disagree on the
   version. The state survives closing and reopening the popup. On
   `up_to_date` the tab returns to the up-to-date state. On a failure the
   tab shows one plain-text line per result (`The plugin folder has local
   changes. Run git status in ~/.config/omarchy/plugins/othavi0.agent-bar.`,
   `Could not reach GitHub. Try again.`, `The update failed validation and
   was rolled back. You are still on <installed>.`, `The update timed out.
   You are still on <installed>.`, `The update did not finish. You are
   still on <installed>.`), re-enables the buttons, and keeps the fallback
   command visible. A lane timeout or a non-zero helper exit renders as
   `failed`.
9. `UX-041` is unchanged: the only check is the explicit button.

## Consequences

The user updates from the popup in two clicks and a restart click, and
never sees the plugin manager's diff or prompt. Running the fallback
command outside a terminal now works because it carries `--yes`. The
plugin installs whatever `master` holds at that moment, which is what the
marketplace refused to verify; the owner accepts that. The 2026-09-14
amendment keeps its other decisions: no scheduled check, no
`updates.automatic` setting, no restart after downloading code.
