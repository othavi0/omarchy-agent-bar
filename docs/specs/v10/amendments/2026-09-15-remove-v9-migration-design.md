# The v9 migration, `setup`, and `doctor` are removed

Date: 2026-09-15
Status: approved

## Context

Agent Bar v9 was the last Waybar-era product. It shipped on 2026-07-21 and
v10.0.0 replaced it on 2026-07-26. Since then the helper has carried three
commands that exist only to move a v9 install onto v10: `setup`, which
migrates settings and strips Agent Bar's inline keys from `shell.json`,
and `doctor scan` and `doctor clean`, which classify and remove Waybar-era
artifacts under the home directory.

Nothing in the product calls them. The Quickshell plugin never builds a
`setup` or `doctor` argv, no script or workflow invokes them, and the
Omarchy plugin manager knows nothing about them. A v9 `settings.json` sits
at the same XDG path as the v10 file but carries `"version": 3` and a
`waybar` block, so every v10 read has rejected it since v10.0.0. A v9 user
who moved to v10 therefore either ran `setup` by hand in the first days or
deleted the file and saved fresh settings from the UI. Seven weeks later
no install is waiting on `setup`. The code behind the three commands is
`src/settings/migration.rs`, `src/plugin/doctor.rs`, and
`src/plugin/ownership.rs`, about 1,500 lines with their tests, compiled
into every release and re-verified on every commit.

## Decision

1. `setup`, `doctor scan`, and `doctor clean` are grammar errors, exit `2`,
   like any other unknown verb. `help setup` and `help doctor` are grammar
   errors too. The usage text drops both commands.
2. `src/settings/migration.rs`, `src/plugin/doctor.rs`, and
   `src/plugin/ownership.rs` are deleted together with their tests and
   fixtures. The v9 matcher for the literal `agent-bar.usage` plugin ID goes
   with them.
3. Settings reads keep tolerating a document that predates a provider added
   later to the catalog (`SET-024`). The in-place rewrite that `setup`
   performed for that case (`MIG-009A`) is gone. The next Settings save
   writes the full document from the UI, which already carries every
   catalog provider, so the file converges without a dedicated command.
4. The backup layout under `$XDG_STATE_HOME/agent-bar/backups/` stays
   documented only for backups that already exist on disk. `uninstall`
   keeps preserving them (`CLI-026`) and `uninstall purge` keeps removing
   them (`CLI-027`).

## Contract changes

- `CLI-009`, `CLI-024`, and `CLI-025` are **Retired**. `CLI-030` covers
  `uninstall` only.
- `MIG-007` through `MIG-017` are **Retired**. `MIG-001`, `MIG-002A`, and
  `MIG-006` now describe only backups that exist on disk. The transaction
  model in `06` covers no in-process writer; `uninstall` delegates to the
  Omarchy plugin manager as before.
- The ownership classification section of `06` is removed.
- `SET-024` loses its `setup` clause. A read still fills a missing provider
  in memory; `apply` still rejects a document missing a provider.
- `03` drops `setup` and `doctor` from the command list and from the
  accepted help topics.
- `BUNDLE-*` entries that name `setup` or `doctor` drop them.

## Consequences

An install that still holds an unmigrated v9 `settings.json` has had no
working bar since v10.0.0, because `status` and `config show` reject the
file before any provider runs. Its recovery changes from `agent-bar setup`
to deleting the file and saving settings from the UI. The troubleshooting
guide says so. Inline Agent Bar keys left in `shell.json` by v9 stay where
they are; v10 never reads them. The helper loses three commands nobody
calls and the crate loses about 1,500 lines that had to stay green on
every release. The active-legacy scan keeps refusing `src/setup.rs` and
`src/doctor.rs` so the commands do not come back under another name.
