# Migration and Legacy Removal

Amended by the plugin-ID rename (2026-08-06):
`docs/specs/v10/amendments/2026-08-06-plugin-id-rename-design.md`. The plugin ID
is `othavi0.agent-bar`; it read `agent-bar.usage` when this document was
approved.

## Transaction model

Since git-plugin-distribution (2026-08-05), plugin-directory mutation (fresh
install, update, and uninstall) is delegated to the Omarchy plugin manager,
which owns its own git-based fetch, fast-forward, validation, and rollback;
see "Update and uninstall transactions" below. Since the 2026-09-15
amendment retired v9-to-v10 settings migration and `doctor clean`, there is
no in-process writer left: nothing in this crate stages, backs up, or
writes a legacy artifact or a migrated `settings.json` at runtime. The
requirements below describe only backups that already exist on disk from
before that amendment.

- `MIG-001`: No affected path changes before preflight and backup succeed.
- `MIG-002A`: Durable backups live under XDG state, one directory per
  operation timestamp.
- `MIG-006`: Backups never live inside a directory being replaced.

`MIG-002` (same-filesystem staging), `MIG-003` (transaction journal),
`MIG-004` (staged-validation rollback), and `MIG-005` (verified rollback
report) described a stage, exchange, and journal pipeline that no live
command path ever used; that dead machinery was removed 2026-08-05 along
with the code that implemented it.

## Backup layout

```text
$XDG_STATE_HOME/agent-bar/backups/<timestamp>/
├── manifest.json
├── settings/
├── plugin/
├── shell/
└── legacy/
```

The manifest records:

- operation and transaction ID;
- source and restoration paths;
- ownership classification and evidence;
- before hash, size, type, and permissions;
- planned action;
- backup relative path;
- after hash when an operation succeeds.

## v9-to-v10 migration

- `MIG-007`: **Retired**, removed by the 2026-09-15 amendment. There is no
  migration command; `setup` no longer exists.
- `MIG-008`: **Retired**, removed by the 2026-09-15 amendment. The v9
  plugin-ID matcher for legacy `agent-bar.usage` `shell.json` data is gone
  with migration.
- `MIG-009`: **Retired**, removed by the 2026-09-15 amendment. There is no
  migration step to preserve provider or layout fields.
- `MIG-009A`: **Retired**, removed by the 2026-09-15 amendment. The
  in-place provider-injection rewrite is gone. A read still tolerates a
  missing provider in memory, and the next Settings save from the UI writes
  it to disk; see `SET-024`.
- `MIG-010`: **Retired**, removed by the 2026-09-15 amendment. There is no
  migration step to move settings into `settings.json`.
- `MIG-011`: **Retired**, removed by the 2026-09-15 amendment. There is no
  migration step to remove inline settings from `shell.json`.
- `MIG-012`: **Retired**, removed by the 2026-09-15 amendment. Migration no
  longer touches bar entries; fresh install and update stay under
  `MIG-019A`.
- `MIG-013`: **Retired**, removed by the 2026-09-15 amendment. Migration no
  longer runs `bar plugin add`; the unconditional-add prohibition stays in
  force for install and update under `MIG-019A`.
- `MIG-014`: **Retired**, removed by the 2026-09-15 amendment. There is no
  migration report for unknown legacy keys.
- `MIG-015`: **Retired**, removed by the 2026-09-15 amendment. There is no
  migration step to abort.
- `MIG-016`: **Retired**, removed by the 2026-09-15 amendment. There is no
  migration step to re-run.
- `MIG-017`: **Retired**, removed by the 2026-09-15 amendment. Fresh
  install defaults and bar-entry placement stay under `MIG-019A`.
- `MIG-018`: Rescan reloads staged QML without altering placement.
- `MIG-019`: Shell restart is a last resort after a valid rescan fails.
- `MIG-019A`: Since git-plugin-distribution (2026-08-05), fresh installation
  is `omarchy plugin add <dist-repo-url>`, which clones, validates, moves
  the tree, and, after a separate confirmation or `--enable`, enables it
  and adds a missing bar entry. An already-installed but disabled plugin may
  still be enabled directly with `omarchy plugin enable othavi0.agent-bar`.
  Neither path ever follows with `omarchy bar plugin add`.
- `MIG-019B`: Update does not edit `shell.json`.
- `MIG-019C`: Rollback restores the exact previous `shell.json` bytes.

The doctor-facing ownership classification (`owned/current`, `owned/legacy`,
`modified legacy`, `ambiguous`, `unrelated`) that `CLEAN-001` through
`CLEAN-007` described is retired with `doctor scan` and `doctor clean`
themselves by the 2026-09-15 amendment. `src/plugin/ownership.rs` stays in
the crate: `bundle.rs` calls its `hash_bytes` for plugin-bundle SHA-256
receipt hashing, unrelated to doctor's legacy-artifact classification.

## Installed legacy removal

Before the 2026-09-15 amendment retired it, migration removed, once
ownership was proven:

- generated Agent Bar Waybar module entries;
- generated Agent Bar Waybar CSS blocks;
- Waybar-specific installed scripts and menu routes;
- obsolete TUI-only installed helpers;
- `usage.redb` and Postcard history cache;
- obsolete notification/cache state;
- ManagedGit metadata and known old standalone-install artifacts;
- old Agent Bar inline shell settings after successful migration;
- QML files replaced by the complete staged v10 bundle.

No cleanup may:

- rewrite unrelated Waybar modules or CSS formatting;
- remove another Omarchy plugin;
- alter general bar position, layout, theme, Hyprland, or terminal settings;
- follow symlinks outside an owned root;
- recursively delete an unresolved or broad path.

## Source removal

The implementation deletes, rather than disables:

- `src/tui/**` and all TUI snapshots;
- `src/action_right.rs`;
- `src/usage/**`;
- `src/waybar/**`;
- Waybar, terminal-dashboard, Pango, chart, history, local-cost, and currency
  formatters no longer needed by human status;
- provider-reported spend, credit balance, and monetary extra fields;
- v9 QML monolith after replacement components exist;
- legacy CLI variants, hidden TTY fallback, watch/NDJSON behavior, and
  compatibility aliases;
- legacy schemas, fixtures, integration tests, and snapshots;
- unused feature flags and dependencies.

Expected dependency removals include:

```text
ratatui
crossterm
tui-input
throbber-widgets-tui
tachyonfx
redb
postcard
async-trait
serial_test
temp-env
insta
```

The implementation must prove each dependency is unused before editing
`Cargo.toml`. It must also reassess Waybar/Pango-only and history-only
dependencies from the actual post-refactor graph.

`doctor scan` and `doctor clean` and the report they produced are retired
by the 2026-09-15 amendment; see `CLI-024` and `CLI-025`.

## Terminal login helper

The Bash helper is retained only for interactive provider login and rewritten:

- accept exactly two arguments: `login <provider>`;
- allow only `claude`, `codex`, `amp`, and `grok`;
- resolve a physical absolute plugin root from the directory containing
  `BASH_SOURCE[0]`;
- verify `<absolute-plugin-root>/bin/agent-bar` is a regular executable;
- `exec xdg-terminal-exec --app-id=org.omarchy.terminal
  --title=Agent Bar Login -- <absolute-plugin-root>/bin/agent-bar login
  <provider>` through argv;
- let `xdg-terminal-exec` honor the user's configured Omarchy terminal;
- preserve `"$@"` and provider exit status;
- never use an emulator fallback table, `command -v agent-bar`, `cmd="$*"`,
  `eval`, `sh -c`, or `bash -lc`.

## Update and uninstall transactions

Replaced by git-plugin-distribution (2026-08-05):
`docs/specs/v10/amendments/2026-08-05-git-plugin-distribution-design.md`.
Uninstall no longer stages, exchanges, or rolls back the plugin directory
itself; it hands its live mutation to the Omarchy CLI as a detached
transient `systemd-run --user` unit, so the helper process can return as
soon as the handoff is accepted without depending on the QML service it may
be running under.

Amended by the 2026-09-14 update-execution removal:
`docs/specs/v10/amendments/2026-09-14-remove-update-execution-design.md`.
Update no longer mutates the plugin directory, queues a unit, or restarts
the shell at all; the helper keeps only the read-only `update check`, and
the user runs `omarchy plugin update othavi0.agent-bar &&
omarchy-restart-shell` themself.

- `MIG-020`: **Retired**, removed by the 2026-09-14 amendment. `update
  apply` and its detached unit no longer exist.
- `MIG-021`: `update check` reads the distribution repository's
  `bundle.json` receipt over HTTPS and reports `reinstallRequired: true`,
  forcing `available`/`latestCompatible` null, whenever the live plugin root
  has no `.git` directory, since a pre-conversion tree cannot be
  fast-forwarded and must be reinstalled through `omarchy plugin add`.
- `MIG-022`: `uninstall` purges only Agent Bar's own XDG state (with
  `purge`) under the exclusive maintenance lock, then detaches
  unconditionally to `omarchy plugin remove othavi0.agent-bar --yes`, which
  owns disabling the bar entry, deleting the plugin directory, and
  rescanning.
- `MIG-023`: Standard uninstall preserves settings, cache configuration, and
  migration backups; only the purge form removes them, and only before the
  detached handoff.
- `MIG-024`: Purge and the detached remove are ordered and disjoint: purge
  never touches the plugin directory, and `omarchy plugin remove` never
  touches `$XDG_CONFIG_HOME/agent-bar`, `$XDG_CACHE_HOME/agent-bar`, or
  `$XDG_STATE_HOME/agent-bar`.
- `MIG-025` (amended 2026-09-14): `uninstall` resolves `omarchy` and
  `systemd-run` to absolute executable paths before consuming the
  confirmation or purging any state, so a missing tool fails closed before
  anything destructive happens. `update` performs no such resolution: it
  has no mutation to fail closed before.
- `MIG-026`: A non-git plugin root removed by `omarchy plugin remove` is
  backed up by Omarchy to a timestamped sibling rather than deleted
  (verified Omarchy behavior), so the one-time migration path is safe.
  Agent Bar settings live outside the plugin directory and always survive
  it.

The pre-conversion stage/quarantine sibling and cross-filesystem-safe
quarantine paths (`PluginPaths::stage_dir`, `quarantine_dir`,
`settings_quarantine`, `cache_quarantine`, `backups_quarantine`) are no
longer produced by any live command path. `PluginPaths::backups_dir`
(`$XDG_STATE_HOME/agent-bar/backups/<stamp>/`) holds no live writer either
since the 2026-09-15 amendment retired the v9-to-v10 settings migration and
`doctor clean` that used to write there; existing backups under that path
stay in place, and `uninstall` still preserves or, with `purge`, removes
them (`CLI-026`, `CLI-027`).
