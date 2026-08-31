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
   [2026-08-25 login-state visibility](amendments/2026-08-25-login-state-visibility-design.md).

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
  the active legacy gate; the language gate scans every tracked text file
  except the one allowlisted fixture named in `tests/active_language.rs`. `CHANGELOG.md` Unreleased,
  the ADR index, and ADR 0004 remain active and must pass.

Documentation requirements:

- `DOC-001`: All active v10 product and engineering documentation is English.
- `DOC-002`: Active commands and JSON examples are executable contract tests.
- `DOC-003`: Changelog releases 9.0.0 and older, ADR bodies 0001–0003,
  dated release notes under `docs/releases/`, and `docs/specs/v10/**` are
  preserved and excluded from the legacy token scan; Unreleased, the ADR
  index, and ADR 0004 are active. The language gate excludes only the
  allowlisted fixture named in `tests/active_language.rs`.
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
