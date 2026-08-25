# How Codex Signals Not-Logged-In

Research for [issue #64](https://github.com/othavi0/omarchy-agent-bar/issues/64)
(child of #63). Question: which observable, credential-free signals tell the
Codex adapter the user is unauthenticated?

Primary sources: the `openai/codex` repository (`main` branch, read via
`gh search code` / `raw.githubusercontent.com` on 2026-08-25), the local
Codex CLI binary (`codex-cli 0.149.1`, installed via mise), and this repo's
`src/providers/codex_app_server.rs` / `src/providers/adapters.rs`.

## Signal table

| Signal | Reliability | Version range checked | Notes |
|---|---|---|---|
| `codex login status` exit code | Medium | `codex-cli 0.149.1` (current `main`); not traced further back | Exits `0` when any auth mode is loaded, `1` on **both** "Not logged in" and on an unrelated error reading auth state. Exit code alone cannot distinguish "unauthenticated" from "auth store broken." Must also parse stderr text `"Not logged in"` vs `"Error checking login status: {err}"`. |
| `~/.codex/auth.json` absence | Medium-High, config-dependent | `main`, `AuthCredentialsStoreMode` in `codex-rs/config/src/types.rs` | File is the **default** store (`AuthCredentialsStoreMode::File`), but Codex also supports `Keyring`, `Auto` (keyring-with-file-fallback), and `Ephemeral` (memory-only, never touches disk). Under those non-default modes, `auth.json` can be absent even while the user is logged in, and present-but-stale after logout via keyring purge in rare error paths. File shape (from `codex-rs/login/src/auth/storage.rs`, `AuthDotJson`): keys `auth_mode`, `OPENAI_API_KEY`, `tokens`, `last_refresh`, `agent_identity`, `personal_access_token`, `bedrock_api_key`, `bedrock_access_keys` — presence of the file plus a non-null value in one of the credential-bearing keys implies logged-in; we did not need to read values, only key presence, to check this locally. |
| `account/rateLimits/read` JSON-RPC error when unauthenticated | Medium | `main`, `codex-rs/app-server/src/request_processors/account_processor.rs` + `codex-rs/app-server/src/error_code.rs` | Handler `get_account_rate_limits_response` checks `self.auth_manager.auth().await`; when `None` it returns a JSON-RPC error with code `-32600` (`INVALID_REQUEST_ERROR_CODE`) and message `"codex account authentication required to read rate limits"`. A related but distinct case — API-key auth that isn't backed by the Codex/ChatGPT backend — returns the same `-32600` code with message `"chatgpt authentication required to read rate limits"`. **The `-32600` code is not unique to auth**: `grep` of the same file shows ~18 other `invalid_request(...)` call sites (bad login id, empty Bedrock key, invalid thread id, etc.) that share the identical error code. The `error.data` field is always `None` — there is no structured/machine-readable discriminator, only the free-text `message`. Reliable detection requires substring-matching the message, and that message is an implementation-detail string, not a documented/versioned API contract. |

## Local verification (read-only, no credentials read)

```
$ codex --version
codex-cli 0.149.1

$ codex login status
Not logged in
$ echo $?
1

$ ls ~/.codex/auth.json
(not present)
```

This matches `run_login_status` in `codex-rs/cli/src/login.rs`: `Ok(None)` from
`auth_config.load_auth(...)` prints `"Not logged in"` and calls
`std::process::exit(1)`.

## Current local code (`src/providers/codex_app_server.rs`, `src/providers/adapters.rs`)

- `run_appserver_protocol_outcome` (codex_app_server.rs:401-408) treats **any**
  JSON-RPC error on `account/rateLimits/read` (id 2) identically:
  `AppServerOutcome::Failed`. It does not inspect `msg.error`'s `code` or
  `message`, so an auth failure and a transient backend error are
  indistinguishable at this layer.
- `CodexAdapter::collect` (adapters.rs:277-333) only branches on
  `AppServerOutcome::{Ok, TimedOut, Failed}`. On `Failed` it falls through to
  the session-log fallback, then to `missing_collection` (if the exe truly
  isn't found) or a generic `ProviderResult::ProviderError` — it never
  produces `ProviderResult::Unauthenticated`. Every other adapter in this file
  (Amp, Grok, Claude, Antigravity) does classify explicit login failures into
  `ProviderResult::Unauthenticated` via the `unauthenticated(...)` helper in
  `src/providers/adapter.rs`; Codex is the outlier that never reaches that
  branch today.
- The existing test `appserver_protocol_id2_error_returns_none_quickly` in
  `codex_app_server.rs` already sends a scripted `id=2` error
  (`{"code":401,"message":"unauthorized"}`) to exercise the fast-fail path,
  but `401`/`"unauthorized"` do not match the real server's wire shape
  (`-32600` / `"codex account authentication required to read rate
  limits"`). The test currently only proves "any error short-circuits",
  not "an auth-shaped error is classified as unauthenticated" — because the
  adapter doesn't classify it as such at all yet.

## Recommendation

Match the `account/rateLimits/read` JSON-RPC error message (not the shared
`-32600` code alone) against the two known upstream substrings —
`"authentication required"` covers both `"codex account authentication
required..."` and `"chatgpt authentication required..."` — inside
`run_appserver_protocol_outcome`, propagate that as a new
`AppServerOutcome::Unauthenticated` variant (mirroring how `codex_app_server.rs`
already distinguishes `TimedOut` from `Failed`), and have `CodexAdapter::collect`
map it to `unauthenticated(...)` the same way the Amp/Grok/Claude/Antigravity
adapters do; treat `~/.codex/auth.json` absence and `codex login status` exit
code only as corroborating, not authoritative, signals, since both are
undermined by non-default `AuthCredentialsStoreMode` settings and by exit-1
also covering unrelated status-check errors.
