# Agent Bar v10 Specification

Status: **implemented, published as `v10.0.0`, live-accepted (2026-07-27),
and amended by the git-native plugin distribution conversion (2026-08-05)**

Approved on: 2026-07-26 · Merged: [PR #25](https://github.com/othavi0/agent-bar/pull/25) ·
Release: [v10.0.0](https://github.com/othavi0/agent-bar/releases/tag/v10.0.0)

This directory is the canonical product and engineering contract for Agent Bar
v10.

The plugin update/uninstall, distribution, and installation model is
superseded by the git-native plugin distribution design, approved
2026-08-05:
[docs/specs/v10/amendments/2026-08-05-git-plugin-distribution-design.md](amendments/2026-08-05-git-plugin-distribution-design.md).
That design is this specification's change-control record for
`01-product-contract.md` (PROD-007, PROD-010, the Maintain journey),
`03-cli-and-json-contract.md` (the maintenance grammar and CLI-024..031),
`06-migration-and-legacy-removal.md` (MIG-019A, MIG-020..026), and
`08-plugin-bundle-and-release.md` (the distribution-repository model). Every
other file in this directory, and every other requirement, still describes
the current, unamended contract.

The login-state visibility design, approved 2026-08-25, refines `JSON-004`,
`UX-030`, `CACHE-004`, `CACHE-006`, and `ARCH-021`:
[docs/specs/v10/amendments/2026-08-25-login-state-visibility-design.md](amendments/2026-08-25-login-state-visibility-design.md).

The session-window-leads design, approved 2026-09-04, amends `UX-020C` and
`UX-020D`:
[docs/specs/v10/amendments/2026-09-04-session-window-leads-design.md](amendments/2026-09-04-session-window-leads-design.md).

The plugin-root design, approved 2026-09-10, amends the Quattro injection
contract in `02-target-architecture.md` and Omarchy contract `1` in
`08-plugin-bundle-and-release.md`:
[docs/specs/v10/amendments/2026-09-10-plugin-root-from-service-url-design.md](amendments/2026-09-10-plugin-root-from-service-url-design.md).

The automatic-updates design, approved 2026-09-10, added `UX-041A`,
`SET-028`, and `CLI-029A` and amended `CLI-029` and `MIG-020`. It is
superseded by the 2026-09-14 update-execution removal below:
[docs/specs/v10/amendments/2026-09-10-automatic-updates-design.md](amendments/2026-09-10-automatic-updates-design.md).

The update-execution removal, approved 2026-09-14, supersedes the
2026-09-10 automatic-updates design above. The marketplace maintainer
blocked verification because the plugin ran `omarchy plugin update ...
--yes` on its own, replacing reviewed code with mutable remote `HEAD`. The
plugin now only checks for updates; it never fetches, installs, or
restarts the shell. `update apply`, `update run`, `UX-041A`'s apply
behavior, and `updates.automatic` are removed; `UX-042`, `SET-028`,
`CLI-029`, `CLI-029A`, `MIG-020`, `MIG-025`, `BUNDLE-020`, `BUNDLE-022`,
`BUNDLE-025`, and `BUNDLE-026` are amended or retired, and `UX-043` is
removed outright:
[docs/specs/v10/amendments/2026-09-14-remove-update-execution-design.md](amendments/2026-09-14-remove-update-execution-design.md).

The v9 migration, setup, and doctor removal, approved 2026-09-15, retires
the helper commands and code that existed only to move a v9 install onto
v10. `setup`, `doctor scan`, and `doctor clean` are now grammar errors like
any other unknown verb. `CLI-009`, `CLI-024`, and `CLI-025` are retired,
and `CLI-030` narrows to cover `uninstall` only; `MIG-007` through
`MIG-017` are retired; `SET-024` loses its `setup` clause, since a read
still fills a missing provider in memory and the next Settings save writes
the full document; and `BUNDLE-*` entries that named `setup` or `doctor`
drop them:
[docs/specs/v10/amendments/2026-09-15-remove-v9-migration-design.md](amendments/2026-09-15-remove-v9-migration-design.md).

The Codex app-server-only design, approved 2026-09-15, drops the
session-log fallback the Codex adapter tried after `codex app-server`
failed or timed out. Codex collection now has one path. `ARCH-022`'s
`codex` row loses the session-log source and the "before filesystem
fallback" retry note; the `07-testing-and-acceptance.md` raw-input
allowlist no longer names Codex `session_log`:
[docs/specs/v10/amendments/2026-09-15-codex-app-server-only-design.md](amendments/2026-09-15-codex-app-server-only-design.md).

## Product statement

Agent Bar v10 is an Omarchy Quattro Quickshell plugin. Its only graphical
surface is the Quickshell bar widget and consolidated popup. A Rust executable
is bundled inside the plugin as a private helper for provider collection,
normalization, settings, cache, migration, update, and uninstall.

Agent Bar v10 is not a terminal UI, a Waybar module, a standalone desktop
application, an AUR product, or a cargo-binstall product.

## Canonical reading order

1. [01-product-contract.md](01-product-contract.md)
2. [02-target-architecture.md](02-target-architecture.md)
3. [03-cli-and-json-contract.md](03-cli-and-json-contract.md)
4. [04-quickshell-ux-and-accessibility.md](04-quickshell-ux-and-accessibility.md)
5. [05-settings-cache-and-notifications.md](05-settings-cache-and-notifications.md)
6. [06-migration-and-legacy-removal.md](06-migration-and-legacy-removal.md)
7. [07-testing-and-acceptance.md](07-testing-and-acceptance.md)
8. [08-plugin-bundle-and-release.md](08-plugin-bundle-and-release.md)
9. [amendments/](amendments/) — approved design changes, in date order,
   frozen as written on their approval date (the numbered files above carry
   the current contract where they differ):
   [2026-08-05 git plugin distribution](amendments/2026-08-05-git-plugin-distribution-design.md),
   [2026-08-06 plugin ID rename](amendments/2026-08-06-plugin-id-rename-design.md),
   [2026-08-06 remove chip tooltip](amendments/2026-08-06-remove-chip-tooltip-design.md),
   [2026-08-11 monorepo migration](amendments/2026-08-11-monorepo-migration-design.md),
   [2026-08-25 login-state visibility](amendments/2026-08-25-login-state-visibility-design.md),
   [2026-09-04 session window leads](amendments/2026-09-04-session-window-leads-design.md),
   [2026-09-10 plugin root from Service URL](amendments/2026-09-10-plugin-root-from-service-url-design.md),
   [2026-09-10 automatic updates](amendments/2026-09-10-automatic-updates-design.md)
   (superseded),
   [2026-09-10 Antigravity third-party windows](amendments/2026-09-10-antigravity-third-party-windows-design.md),
   [2026-09-10 Settings tabs and rail state](amendments/2026-09-10-settings-tabs-and-rail-state-design.md),
   [2026-09-14 update execution removed](amendments/2026-09-14-remove-update-execution-design.md),
   [2026-09-15 v9 migration removed](amendments/2026-09-15-remove-v9-migration-design.md),
   [2026-09-15 Codex app-server only](amendments/2026-09-15-codex-app-server-only-design.md).

When two statements conflict, the earlier contract in this reading order wins
unless a later file explicitly identifies the requirement ID it refines.

## Requirement IDs

| Prefix | Area |
| --- | --- |
| `PROD` | Product scope and user-facing behavior |
| `ARCH` | Architecture and ownership |
| `CLI` | Private helper command grammar |
| `JSON` | Status schema and provider states |
| `UX` | Quickshell interaction and visual behavior |
| `A11Y` | Keyboard, focus, motion, and accessibility |
| `SET` | Settings |
| `CACHE` | Cache and refresh coordination |
| `NOTIFY` | Usage notifications |
| `MIG` | v9-to-v10 migration |
| `CLEAN` | Legacy removal and ownership |
| `BUNDLE` | Plugin assembly, installation, update, and uninstall |
| `TEST` | Verification and acceptance |
| `DOC` | Documentation |

Requirement IDs are stable. An implementation may not silently weaken,
rename, or delete a requirement. A necessary deviation must be documented in
the PR and approved before work continues.

## Language policy

- All v10 UI copy, tooltips, notifications, accessibility labels, CLI help,
  terminal output, active documentation, specifications, tests, and release
  material are English.
- Commands, code identifiers, JSON keys, provider IDs, and technical names are
  English.
- Provider trademarks and official command names retain their original form.
- v10 does not add an internationalization layer.
- Changelog release sections beginning at `## [9.0.0]` and ADR bodies
  `0001`–`0003` remain untouched historical evidence and are excluded from
  the active legacy gate; the language gate scans every tracked file except
  those with a binary or lockfile extension (`png`, `jpg`, `jpeg`, `svg`,
  `ico`, `lock`) and the one allowlisted fixture named in
  `tests/active_language.rs`. `CHANGELOG.md` Unreleased,
  the ADR index, and ADR 0004 remain active and must pass.

Documentation requirements:

- `DOC-001`: All active v10 product and engineering documentation is English.
- `DOC-002`: Active commands and JSON examples are executable contract tests.
- `DOC-003`: Changelog releases 9.0.0 and older, ADR bodies 0001–0003,
  dated release notes under `docs/releases/`, and `docs/specs/v10/**` are
  preserved and excluded from the legacy token scan; Unreleased, the ADR
  index, and ADR 0004 are active. The language gate excludes only files
  with a binary or lockfile extension and the allowlisted fixture named in
  `tests/active_language.rs`.
- `DOC-004`: Active docs describe only the plugin-first v10 target after
  implementation completes.
- `DOC-005`: Before implementation completes, active docs clearly label target
  behavior and do not claim that v10 is already installed.

## Change control

- This specification changes only after explicit user approval, recorded as
  a dated file under `amendments/`.
- Implementation does not redefine the specification.
- No merge, tag, GitHub Release, or live installation is authorized by this
  specification alone.
