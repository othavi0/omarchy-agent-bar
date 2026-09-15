# `account` and `error.code` leave the status document

Date: 2026-09-15
Status: approved

## Context

Schema v2 carries two fields the plugin never reads. `account.label` is
extracted by the Claude, Grok, and Codex adapters, sanitized, validated,
cached in `status-v2.json`, and serialized on every poll, and no QML file
renders it. `error.code` duplicates the classification that `state`
already carries; the UI branches on `state` and reads `error.message` and
`error.retryable`. The provider rules say account identifiers never enter
the cache or the UI, and the cache file on disk was the one place they
still did.

## Decision

1. `account` is removed from `ProviderStatus`, `ProviderResult::Ready`,
   the cache entry, the v2 JSON, the JSON schema, and the fixtures. The
   adapters stop extracting account labels; `sanitize_account_label` and
   the fields it fed go with them.
2. `error.code` and the `ErrorCode` enum are removed. `error` keeps
   `message` and `retryable`. Where a code drove a branch inside the
   helper, the branch reads `state` instead.
3. Schema version stays 2. Removing an optional field that no consumer
   reads does not change what a v2 reader can rely on. A cached document
   written by an earlier helper that still carries `account` or
   `error.code` is read with those keys ignored, never rejected, so the
   first poll after an update does not drop the cache.

## Contract changes

- `03-cli-and-json-contract.md`: the v2 field table drops `account` and
  `error.code`; the `ProviderError` shape is `{ message, retryable }`.
- `05-settings-cache-and-notifications.md`: the cache entry mirrors the
  status row, so it drops the same fields; the tolerance rule for old
  cache files is stated once there.
- `schemas/status-v2.json` (or the file that carries the schema) drops
  both properties.
- `01-product-contract.md` and the provider rules in `CLAUDE.md` already
  forbid account identifiers in the UI and the cache; no wording change.

## Consequences

The status document loses two fields, the cache file stops holding an
account label, and two adapters lose their account parsing. A reader
of the JSON contract has one less optional shape to think about. Nothing
the bar shows changes.
