# Updates are checked, never executed

Date: 2026-09-14
Status: approved
Supersedes: `2026-09-10-automatic-updates-design.md`

## Context

The Omarchy plugin marketplace verifies a plugin at one exact commit. On
2026-09-11 the maintainer blocked the verification request for release
10.5.1 (omacom/omarchy-plugin-marketplace#4979) because the plugin, with
`updates.automatic` on by default, ran
`omarchy plugin update othavi0.agent-bar --yes` on its own. That command
fetches `origin HEAD` and fast-forwards to it; Omarchy 4.0.3 offers no way
to name a commit, tag, or ref. The plugin therefore replaced reviewed code
with whatever `master` held at run time, and the maintainer required "a
separately verified immutable target before any automatic update is
installed".

The marketplace documents the same gap in its `VERIFICATION.md`:
commit-bound installation "remains unavailable until Omarchy provides an
exact-SHA installation and update interface". Other plugins blocked for the
same reason were verified again only after they stopped executing updates
altogether; a default-off toggle with a confirmation dialog was blocked as
well. Pinning the update to the marketplace's verified commit would replace
the Omarchy plugin manager with a git pipeline of our own and would deliver
an update only after each release had been reviewed by hand, which today
takes weeks.

## Decision

1. The helper keeps `update check` unchanged. `update apply` and
   `update run` are removed, together with the transient update unit, the
   `update-run.lock` gate, and the restart retry loop. `update` with no
   argument prints usage pointing at `update check` and at the user-run
   `omarchy plugin update othavi0.agent-bar`, and exits `3`.
2. The plugin never fetches, installs, or restarts the shell after
   downloading code. When a check reports an available release, Settings
   shows the target version, a `Release notes` link, a `Marketplace page`
   link to `https://plugins.omarchy.org/plugin.html?id=othavi0.agent-bar`,
   and the command the user runs in a terminal:
   `omarchy plugin update othavi0.agent-bar && omarchy-restart-shell`.
   The `Restart shell` button shown when Settings fails to load stays; it
   downloads nothing.
3. The scheduled check stays as it was: two minutes after the helper
   answers and every six hours after that, skipped while the popup is
   open, while maintenance is in flight, or before the boot settings read
   succeeded. It only paints the maintenance state. A failed scheduled
   check paints nothing. A click on `Check for updates` during a silent
   check adopts it.
4. `updates.automatic` is removed from the settings contract. A document
   written by 10.3.24 through 10.5.1 that carries
   `"updates": { "automatic": <bool> }` still reads (`SET-007`); the block
   is ignored and never written back. Any other key inside `updates`, a
   non-boolean `automatic`, or a non-object `updates` is rejected
   (`SET-006`). The Settings About tab loses the `Update automatically`
   toggle.

## Contract changes

- `UX-041A` now describes the scheduled check only; it never applies.
- `UX-042` shows `Marketplace page` and the terminal command instead of
  `Update to <version>`; `UX-043` (update confirmation) is removed.
- `SET-028` becomes the legacy-block tolerance rule above.
- `CLI-029` and `CLI-029A` are removed; `update apply` and `update run` are
  grammar errors.
- `MIG-020` is removed; `MIG-025` covers `uninstall` only. The unit
  descriptions in `03`, `06`, and `08` drop the update unit.
- `BUNDLE-022`, `BUNDLE-025`, and `BUNDLE-026` drop `update apply`.

## Consequences

Installs on 10.3.24 through 10.5.1 apply this release on their own once,
through the automatic update they still run, and then never again. From
this release on, the plugin tells the user that a release exists and the
user installs it with the Omarchy plugin manager. The marketplace
verification request is retargeted to the release commit of this change.
