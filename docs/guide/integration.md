# Plugin Integration and Ownership

## Installation

Agent Bar installs through the native Omarchy plugin flow. There is no
Agent Bar-authored installer.

```bash
omarchy plugin add https://github.com/othavi0/omarchy-agent-bar.git
```

This clones the repository directly — the repository root is the plugin
tree ([ADR 0006](../adr/0006-single-repository-distribution.md)) — validates
the clone with `omarchy-plugin-validate`, and moves it to
`$HOME/.config/omarchy/plugins/othavi0.agent-bar`. Omarchy then asks whether
to enable the plugin now; enabling it prompts for a bar section, defaulting
to `right` from the manifest's `barWidget.defaultSection` when the prompt is
skipped.

Update and remove use the matching Omarchy commands, or the Settings
Maintenance buttons, which delegate to them:

```bash
omarchy plugin update othavi0.agent-bar
omarchy plugin remove othavi0.agent-bar
```

`omarchy plugin update` fetches, fast-forwards, and re-validates the
checkout; a failing validation rolls back automatically with
`git reset --hard ORIG_HEAD`. It refuses a non-git plugin directory outright
when targeted by ID, and silently skips one in a bulk `omarchy plugin
update` run.

Do not follow any of these commands with `omarchy bar plugin add`. That
command can remove and recreate the bar entry, losing its section, index,
and inline fields.

## Migrating a pre-conversion install

Installs from before this release are plain directories, not git checkouts,
so `omarchy plugin update` cannot fast-forward them. `update check` detects
the missing `.git` and reports `reinstallRequired: true`; the Settings UI
shows a one-time migration instruction instead of a false "up to date":

```bash
omarchy plugin remove othavi0.agent-bar
omarchy plugin add https://github.com/othavi0/omarchy-agent-bar.git
```

`omarchy plugin remove` backs up a non-git plugin directory to a timestamped
sibling rather than deleting it, so this is safe even before the reinstall
completes. Agent Bar's own settings, cache, and backups live outside the
plugin directory under XDG paths and are untouched by either command.

## Placement

`shell.json` owns plugin presence and placement. Agent Bar:

- creates one `{ "id": "othavi0.agent-bar" }` entry only when enabled, either
  through the `omarchy plugin add` placement prompt or a later
  `omarchy plugin enable othavi0.agent-bar`;
- does not edit `shell.json` during update;
- removes only its own entry during uninstall, which `omarchy plugin
  remove` performs.

## Settings migration

Valid v9 provider enablement/order, used/remaining mode, refresh interval, and
notification preference migrate to the strict v10 settings document through
`agent-bar setup`, which takes no arguments and only migrates settings. It
does not create, move, or validate any plugin tree.

Invalid recognized values abort before replacement. Unknown fields remain in
the backup/report and do not enter v10. Repeated migration is idempotent.

There is no v9 runtime compatibility layer after migration.

## Update and uninstall delegation

`update apply` and `uninstall` no longer stage, exchange, or roll back the
plugin directory themselves. Uninstall resolves `omarchy` and `systemd-run`
to absolute executable paths; update apply additionally resolves
`omarchy-restart-shell`, `git`, and `timeout`. Both then hand their live
mutation to the Omarchy CLI as a detached transient unit:

```text
systemd-run --user --collect --no-block --unit=agent-bar-update-<txid>.service \
  --property=RuntimeMaxSec=25h -- <plugin>/bin/agent-bar update run

systemd-run --user --collect --unit=agent-bar-remove-<txid>.service \
  -- <omarchy> plugin remove othavi0.agent-bar --yes
```

Detachment lets the helper return as soon as systemd accepts the unit,
without depending on the shell process that started it. `update run` wraps
`omarchy plugin update othavi0.agent-bar --yes` (ten-minute timeout), which
owns the git fast-forward and its own validation rollback; `omarchy plugin
remove` owns disabling the bar entry, deleting (or backing up) the plugin
directory, and rescanning. Both commands hold the shared exclusive
maintenance lock only for the purge/preflight/handoff step, not for the
delegated mutation itself; `update run` uses its own lock so two runs never
overlap.

The rescan `omarchy plugin update` triggers does not reload a running
`Service.qml`. `update run` therefore compares the plugin `HEAD` before and
after: when it moved, it shows a toast and runs `omarchy-restart-shell`,
retrying every minute while a locked session refuses it; when it did not,
or the update failed, the shell is left alone. With `updates.automatic` on,
the service starts this same path by itself: a check two minutes after start
and every six hours, applied only while the popup is closed.

## Ownership

Artifacts are classified as:

- owned/current;
- owned/legacy;
- modified legacy;
- ambiguous;
- unrelated.

Only owned/legacy may be removed automatically. A known-looking path is not
enough; ownership requires a receipt, marker, expected content/hash, or another
documented proof.

`doctor scan` is read-only. `doctor clean` backs up before removing confirmed
legacy. Modified and ambiguous paths remain untouched.

## Uninstall

See [Uninstall](commands.md#uninstall) for the command forms, confirmation
flow, and preserved/removed paths.

Purge removes the settings and cache directories under the exclusive
maintenance lock, then releases the lock before it removes
`$XDG_STATE_HOME/agent-bar`, which holds the lock file. Purge and the
delegated remove are disjoint by construction: purge never touches
the plugin directory, and `omarchy plugin remove` never touches Agent Bar's
own XDG state.

## Live safety

Tests use injected plugin roots and isolated XDG paths. Live
`$HOME/.config/omarchy` mutation is limited to the final approved QA gate with
exact backup and verified rollback.
