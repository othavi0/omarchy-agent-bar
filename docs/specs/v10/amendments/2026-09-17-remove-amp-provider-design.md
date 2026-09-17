# Amp leaves the provider catalog

Date: 2026-09-17
Status: approved

## Context

The owner decided to drop Amp (Amp CLI, ampcode) as a monitored provider.
Amp scraped `amp usage` text through three hand-maintained regexes with no
official documentation for that command, the retry policy the catalog
declared was never implemented, and the daily window could disappear
silently on an out-of-range percentage. The remaining four providers,
Claude, Codex, Grok, and Antigravity, stay unchanged.

## Decision

1. `ProviderId::Amp`, `AmpAdapter`, `classify_amp_failure`,
   `amp_from_usage_text`, its three regexes, and the `AMP` catalog
   descriptor are deleted, along with the Amp icon, fixtures, and every
   QML/JS reference to the `amp` catalog entry. `ProviderId::ALL` and the
   locked catalog order become Claude, Codex, Grok, Antigravity.
2. An installed settings.json can carry a legacy
   `{"id":"amp","enabled":<bool>}` provider entry from before this
   release. `Settings::parse_with_policy` strips that exact two-key shape
   from the raw JSON `Value` before deserializing, the same way it already
   strips the legacy `updates` block. Any other shape naming `amp` (an
   extra field, a non-boolean `enabled`) is left in place, so it still
   fails with the ordinary unknown-provider or unknown-field error.
   `ORIGINAL_V10_PROVIDERS` drops to Claude, Codex, Grok: a document that
   still lists all three, plus a tolerated legacy `amp` row, still counts
   as complete and gets Antigravity filled in by `FillFromCatalog`, exactly
   as it did before Amp existed in this list. This is a read-time
   in-memory repair; `SET-007` still holds, and the file is never rewritten
   until the user runs `config apply`.
3. A cached `status-v2.json` or `notification-state-v2.json` row keyed
   `amp` is discarded on load instead of quarantining the whole document.
   Both stores already had a whole-document quarantine path for a
   deserialize failure; a legacy `amp` row previously took that whole-file
   path (the cached document embeds `status.id`/`providerId` as a typed
   `ProviderId`, so it fails to deserialize once `amp` is not a variant).
   The fix strips the `amp` key from the raw JSON before deserializing, so
   a genuinely unknown key still quarantines the document, but this one
   expected legacy key does not.
4. `agent-bar provider amp` and `agent-bar login amp` become an ordinary
   unknown-provider grammar error, the same as any id that was never in
   the catalog. `scripts/agent-bar-open-terminal` drops `amp` from its
   accepted provider list.
5. `tests/active_legacy_scan.rs` forbids the specific compound symbols
   `AmpAdapter`, `AMP_ADAPTER`, `ampcode`, `icons/amp.svg`, and
   `ProviderId::Amp`, not the bare word `amp` (which still appears,
   correctly, in the tolerated legacy id string and its tests). The scan
   allowlists `tests/fixtures/settings-v1/legacy-amp-entry-tolerated.json`.

## Contract changes

- `01-product-contract.md`, `02-target-architecture.md`,
  `03-cli-and-json-contract.md`, `04-quickshell-ux-and-accessibility.md`,
  `05-settings-cache-and-notifications.md`,
  `06-migration-and-legacy-removal.md`, `07-testing-and-acceptance.md`,
  and `08-plugin-bundle-and-release.md`: every provider list, table, and
  example settings/status document drops `amp`; the JSON contract example
  and the status-v2 fixtures that stood in for a generic `cli_missing`/
  `provider_error` case now use Grok and Codex instead.
- `schemas/settings-v1.schema.json` and `schemas/status-v2.schema.json`
  drop `amp` from the provider id enum. New documents cannot declare it;
  the Rust-side tolerance in Decision 2 is a read-time exception these
  schemas do not need to encode, the same way they do not encode the
  legacy `updates` block.
- `CLAUDE.md`'s product-boundaries list and `Cargo.toml`'s package
  description read "Claude, Codex, Grok, and Antigravity."

## Consequences

A fresh install and an upgraded install both show four providers. An
upgraded install that had Amp enabled loses that row from the bar; nothing
else in its settings, cache, or notification history is disturbed. A
reader of the provider catalog has one less CLI-scraping integration, and
one less unofficial text format, to reason about.
