# Documentation

Active product and engineering documentation for Agent Bar.

## User and operator guide

- [Integration](guide/integration.md): install, migration, update,
  uninstall, and ownership through the native Omarchy plugin flow.
- [Runtime](guide/runtime.md) — owned paths, settings, cache, privacy, and
  state.
- [Troubleshooting](guide/troubleshooting.md) — typed provider and plugin
  failures.
- [Commands](guide/commands.md) — private helper diagnostics and recovery
  grammar.

## Engineering

- [Architecture](dev/architecture.md) — shared service, Rust helper, and
  data flow.
- [JSON output](dev/json-output.md) — status schema v2.
- [New provider](dev/new-provider.md) — adapter and fixture checklist.
- [Omarchy integration](dev/omarchy-shell.md) — Quattro plugin contract.
- [Releasing](dev/releasing.md) — automatic release pipeline and manual
  boundary.
- [ADRs](adr/README.md) — durable architectural decisions.
- [Domain vocabulary](../CONTEXT.md) — canonical terms.

## Releases

- [Release notes](releases/README.md) — one tracked file per published
  version, consumed by the automatic release pipeline.

## Canonical v10 package

- [Specification index](specs/v10/README.md)
- [Design amendments](specs/v10/amendments/) — approved changes to the
  original v10 contract, newest last.

## Historical records

`CHANGELOG.md` release sections 9.0.0 and older and ADR bodies 0001–0003
preserve earlier design and delivery history. The Unreleased changelog section and
the ADR index remain active.
