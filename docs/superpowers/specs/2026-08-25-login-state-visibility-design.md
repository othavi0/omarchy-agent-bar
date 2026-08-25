# Login state visibility across providers

Status: approved design, pending implementation plan.
Decision date: 2026-08-25. Decided by the repository owner in session;
tracked on the wayfinder map
[Login state visibility across providers (#63)](https://github.com/othavi0/omarchy-agent-bar/issues/63).

Two symptoms observed on a live install on 2026-08-25 drive this amendment:

1. Codex installed but not logged in (`codex login status` → `Not logged
   in`) rendered as `provider_error` "Codex rate limits were not available."
   with a `Retry` action. The user could not tell that the fix was to log in.
2. Right after `omarchy plugin add` + enable, the Claude chip showed `—` with
   the severity glyph for five minutes although the account was logged in.

This document is the change-control record for `JSON-004`, `UX-030`,
`CACHE-004`, `CACHE-006`, and `ARCH-021`. Every other requirement in
`docs/specs/v10/` is unchanged.

## Evidence (research branches)

- `research/codex-unauthenticated-signal` —
  `docs/research/codex-unauthenticated-signal.md`
- `research/first-collection-after-install` —
  `docs/research/first-collection-after-install.md`
- `research/login-refresh-ipc` — `docs/research/login-refresh-ipc.md`

Findings that the decisions below rest on:

- `CodexAdapter::collect` never produces `ProviderResult::Unauthenticated`.
  The app-server path maps every `account/rateLimits/read` error to
  `AppServerOutcome::Failed`; the session-log fallback then either returns old
  data or a retryable `provider_error`.
- When unauthenticated, the Codex app-server answers
  `account/rateLimits/read` with JSON-RPC code `-32600` and the message
  `codex account authentication required to read rate limits`. The code is
  shared with unrelated invalid-request cases and `error.data` is null, so
  only the message discriminates. `~/.codex/auth.json` absence is reliable
  only under the default `File` credential store (`Keyring`, `Auto`, and
  `Ephemeral` stores keep no file), and `codex login status` exits 1 for both
  "not logged in" and unrelated failures.
- The first collection after install was live (cache and lock files were
  created in the same 100 ms as the collection). One failed Claude HTTPS call
  was cached with Claude's 300 s success TTL because `descriptor_ttl` has no
  state arm and `is_fresh` compares timestamps only. `Service.qml` never
  re-kicks after a non-ready result. An always-bypass initial collection
  would not have changed the outcome.
- The post-login refresh already exists: `agent-bar login <id>` runs the
  provider's login command and, only on exit status 0, calls
  `omarchy-shell -q othavi0.agent-bar refresh <id>` (`ARCH-020`/`ARCH-021`,
  `tests/login.rs`). The Bash launcher `exec`s into the terminal and never
  regains control, so it does not and must not call IPC itself.

## Decisions

### D1. Codex classifies unauthenticated (refines `JSON-004`)

- `codex_app_server` gains an `AppServerOutcome::Unauthenticated` variant.
  It is produced when the `account/rateLimits/read` response carries an
  `error` whose `message` contains the substring `authentication required`
  (ASCII case-insensitive). Any other error stays `Failed`.
- `CodexAdapter::collect` returns `unauthenticated(ProviderId::Codex, …,
  "Codex is not authenticated.", login_available(discovery))` on that
  outcome, before the session-log fallback. Old session-log rate limits are
  never presented for an unauthenticated account (`JSON-007`).
- `~/.codex/auth.json` presence and `codex login status` are not used as
  signals. They are documented as corroborating evidence for live QA only.
- Matching an explicit, allowlisted substring inside a Rust adapter is the
  same mechanism `classify_amp_failure` already uses. It remains forbidden in
  QML and forbidden as a general control-flow pattern (`CONTEXT.md`, "terms
  to avoid"); each substring is a literal constant with a unit test and a
  comment naming the upstream source file it was read from.
- The message is not a versioned upstream contract. A Codex release that
  changes it degrades to today's behavior (`provider_error` + `Retry`), never
  to a wrong "connected" state. `docs/dev/new-provider.md` records the
  substring and the upstream file to re-check on Codex upgrades.
- Audit: Claude, Grok, Amp, and Antigravity already classify explicit auth
  failures through the shared `unauthenticated(...)` helper. No change; the
  implementation plan adds one negative test per provider proving an
  operational failure with the word `auth` in it is not classified as
  unauthenticated (the Amp rule generalized).

### D2. Popup-only differentiation (confirms `UX-030`, `UX-032A`)

- The bar chip renders `—` for `unauthenticated` exactly as it does today for
  every non-ready state. No login glyph, no text.
- The popup provider view shows the existing popup copy (title `Not signed in
  to <Provider>`, body `Signing in opens the official <Provider> CLI.`, from
  `CoreView.js`), and the single action from the envelope: `Sign in` when
  login discovery succeeded, otherwise `Install guide` (Antigravity has no
  login command and always takes this branch).
- "Never logged in" and "session expired" share the same copy. The
  distinction is not observable reliably across providers and the remedy is
  identical.
- No desktop notification is emitted for `unauthenticated`. Notification
  thresholds keep applying to percentage windows only.

### D3. Post-login refresh contract (confirms `ARCH-021`)

- Unchanged: the helper's `login` command requests a cache-bypass refresh of
  that provider only when the provider login exits 0.
- A cancelled or failed login (non-zero exit, signal, closed terminal)
  changes nothing: the popup keeps its current typed state until the next
  poll. No new state, error code, or schema field.
- Live confirmation (real `codex login` in the terminal, chip updates without
  `Retry`) is a step of the final authorized QA gate for this amendment.

### D4. Non-ready rows are never served from cache (refines `CACHE-004`, `CACHE-006`)

- In the coordinator freshness check, a cache row whose `state` is not
  `ready` or `stale` is never fresh: the next `status` call with
  `cache use` re-collects that provider live. Catalog TTLs keep governing
  `ready` and `stale` rows only.
- Non-ready rows are still written to the cache document. Stale retention
  (`CACHE-021`..`CACHE-024`), cross-process singleflight, and
  `cache bypass` semantics are unchanged.
- `Service.qml` adds no re-kick timer or backoff. The poll interval (default
  60 s) is the only automatic retry cadence, so a transient failure after
  install or boot is visible for at most one interval instead of the
  provider's success TTL.
- A failure on the very first collection (no last good data) follows the same
  rule as a failure with stale retention available.

### Ruled out

- Initial-collection cache bypass: does not fix symptom 2 and adds a code
  path.
- Distinct bar-chip glyph for login state; desktop notifications for
  unauthenticated providers.
- Service-side re-kick with backoff.

## Testing (extends `07-testing-and-acceptance.md`)

- Codex app-server fake returning the `-32600` error with the upstream
  message → `unauthenticated`, `action.kind` = `login` when the login
  executable is discovered, `view_installation` otherwise; the same fake with
  a different message → `provider_error`.
- Session-log fixture present plus unauthenticated app-server → still
  `unauthenticated` (no obsolete usage).
- Coordinator: a cached `provider_error` row inside its catalog TTL is
  re-collected under `cache use`; a cached `ready` row inside TTL is served.
- QML: `unauthenticated` snapshot renders `—` in the chip, the title above,
  and exactly one action in the popup; `dispatchAction` routes `login` to
  `loginProvider`.
- Live QA gate: fresh install with one provider logged out, then log in from
  the popup, then confirm the chip updates on the exit-0 refresh.

## Follow-ups outside this amendment

- `docs/dev/new-provider.md`: add "how the adapter proves unauthenticated"
  to the checklist.
- `CONTEXT.md` already defines **Unauthenticated** and **Initial collection**
  (commit `1d14733`).
