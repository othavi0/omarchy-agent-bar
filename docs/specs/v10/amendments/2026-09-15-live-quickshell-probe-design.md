# `update check` probes the installed Quickshell instead of a constant

Date: 2026-09-15
Status: approved

## Context

`BUNDLE-021`'s compatibility gate compares the distribution repository's
`bundle.json` `minimumQuickshellVersion` against the Quickshell installed on
the machine, and sets `latestCompatible` to `null` when the installed
Quickshell is too old. `UpdateCheckProbe::default()`, the only probe the CLI
ever constructed, set `quickshell_version` to `MINIMUM_QUICKSHELL_VERSION`
(the build's own constant, `"0.3.0"`) instead of asking the machine. Because
`UpdateCheckDocument::validate` also requires a receipt's
`minimumQuickshellVersion` to equal that same constant whenever it offers a
release, the probe and the receipt were always equal: the gate could never
observe an installed Quickshell older than the constant it was compiled
against, so it could never fire in production. `UpdateCheck::run` itself
already compared whichever `quickshell_version` a caller passed in
correctly; only the production probe was wrong.

## Decision

1. `UpdateCheckProbe::live()` probes the installed Quickshell by running
   `qs --version` through the existing argv-only `ProcessRunner` seam
   (`src/providers/process.rs`), with a 2-second timeout and no shell. It
   parses the first whitespace-delimited token in stdout that parses as a
   semantic version (`Quickshell 0.3.1 (revision , distributed by Arch
   Linux)` yields `0.3.1`).
2. A probe failure — spawn failure, non-zero exit, timeout, or unparsable
   output — is typed fallback data, never a process failure: `live()` falls
   back to `MINIMUM_QUICKSHELL_VERSION` and prints one warning line to
   stderr. `update check` still completes and still writes exactly one
   schema-v1 JSON document to stdout.
3. `dispatch_update_check` (`src/cli/mod.rs`) calls `UpdateCheckProbe::live()`
   instead of `UpdateCheckProbe::default()`. `UpdateCheckProbe::default()` is
   unchanged (still the build minimum) and stays the base every other test
   and code path builds on with `..UpdateCheckProbe::default()`.
4. `current.quickshellVersion` in the `update check` JSON document is now
   the version actually reported by the installed `qs`, not a build
   constant. The fixtures in `tests/fixtures/update-check/*.json` keep their
   literal `"0.3.0"` byte-for-byte: they are parsed directly through
   `UpdateCheckDocument::parse_json`/`to_stdout_json` in
   `tests/update_check_parity.rs` and never touch the live probe, so their
   bytes describe the document shape, not a claim about any particular
   installed Quickshell.

## Contract changes

- `MIG-021` (`06`): unchanged in mechanism (the git-checkout /
  `reinstallRequired` sentinel), but `current.quickshellVersion` is now
  documented as the live-probed installed Quickshell version, with the
  build-minimum fallback above.
- `BUNDLE-021` (`08`): the sentence describing when `latestCompatible` is
  `null` now names the actual comparison — the receipt's
  `minimumQuickshellVersion` against the live-probed
  `current.quickshellVersion` — instead of the vaguer "incompatible with
  the local install".
- No CLI grammar, JSON schema, or exit-code change: `update check`'s shape,
  the `03` command list, and the accepted help topics are unaffected.

## Consequences

`update check` can now correctly report `latestCompatible: null` on a
machine whose installed Quickshell is older than a release's stated
minimum, which it could never do before this change. A machine without a
working `qs --version` (missing binary, hung process, unexpected output)
degrades to the same always-compatible assumption the code made
everywhere before this change, with a stderr warning instead of a silent
constant.
