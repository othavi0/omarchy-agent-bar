# Codex collection is app-server only

Date: 2026-09-15
Status: approved

## Context

The Codex adapter read rate limits through two ordered paths. First it tried
`codex app-server` JSON-RPC `account/rateLimits/read`, with one hand-rolled
retry after a 250 ms sleep on timeout. When that path timed out or failed, it
fell back to a bounded walk of `$HOME/.codex/sessions`, scanning JSONL
session logs for the newest `token_count` event that carried rate limits.
That fallback lived in `src/providers/codex_session_log.rs`, about 260 lines
plus its tests and fixture.

The fallback existed for Codex CLIs built before `app-server` shipped
(2026-07-27, commit `441df17`). On this machine, `codex-cli 0.154.0` serves
rate limits live through app-server; the owner confirmed no supported Codex
build still needs the session-log path and decided to drop it.

The retry itself duplicated the shared mechanism: the Codex adapter slept a
literal 250 ms, the same value the catalog's `RetryPolicy::OneTransient`
already computes as `CODEX.retry_delay()`, but read from neither the
catalog nor the generic retry helper other adapters share.

## Decision

1. Codex collection is app-server only. There is one read path:
   `codex app-server` JSON-RPC `account/rateLimits/read`. No filesystem
   fallback exists.
2. `src/providers/codex_session_log.rs`, its `mod` line, its tests, and its
   fixture (`tests/fixtures/providers/codex/session-token-count.jsonl`) are
   deleted.
3. The Codex adapter's hand-rolled sleep-and-retry is deleted. `providers/retry.rs`
   gains a generic `retry_once_if_transient` helper: run an operation once,
   and if the caller judges the result transient, wait the descriptor's
   retry delay and run it once more. `http_get_with_retry` is rewritten on
   top of this helper so HTTP and subprocess adapters share one retry
   mechanism. The Codex adapter calls it with `AppServerOutcome::TimedOut`
   as the transient predicate; the delay comes from `CODEX.retry_delay()`
   (`RetryPolicy::OneTransient`, 250 ms), the same policy Claude already
   uses for its HTTP retry. No gap: the shared mechanism expresses the
   subprocess retry exactly as it expressed the HTTP one.
4. When the app-server call fails or times out (after the one retry), the
   adapter returns the typed result that mapping already produced for that
   branch: `ProviderResult::ProviderError { message: "Codex rate limits
   were not available.", retryable: true }`. A missing `codex` executable
   returns `cli_missing` before any app-server call is attempted; this no
   longer falls through to a session-log read first, since none exists.
   `AppServerOutcome::Unauthenticated` still maps to `unauthenticated`,
   unchanged.

## Contract changes

- `02-target-architecture.md`: the `CollectionContext` prose no longer
  calls Codex collection "composite app-server/session-log"; it is
  app-server only. The locked provider table's `codex` row drops the
  session-log source and the "before filesystem fallback" retry note
  (`ARCH-022`).
- `07-testing-and-acceptance.md`: the raw-input allowlist no longer names
  Codex `session_log`, since no code path reads or mentions it.

## Consequences

A Codex CLI older than the `app-server` subcommand now reports a typed
`provider_error` ("Codex rate limits were not available.") instead of
silently reading a stale on-disk session log. The user updates Codex to a
build that supports `app-server`. Agent Bar never again reads
`$HOME/.codex/sessions`, so a corrupted or huge session log can no longer
affect Codex collection. The adapter loses about 260 lines of filesystem
walking and its own test suite; the retry duplication between the Codex
adapter and the catalog's retry policy is gone.
