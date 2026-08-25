# Login State Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codex reports `unauthenticated` (with the `Sign in` action) instead of a generic `provider_error`, and a failed collection is never served from cache, so the bar recovers on the next poll instead of after the provider's success TTL.

**Architecture:** Two Rust-only changes. (1) The Codex app-server protocol gains an `Unauthenticated` outcome recognised from the upstream error message, and `CodexAdapter::collect` maps it through the shared `unauthenticated(...)` helper before any session-log fallback. (2) `CacheDocument::is_fresh` becomes state-aware: only `ready`/`stale` rows can be fresh, so every other row is re-collected under `cache use`. QML needs no change: `CoreView.js` already renders `unauthenticated` with the `Not signed in to <Provider>` title, `—` chip, and the envelope's single action.

**Tech Stack:** Rust 2021, tokio, serde_json, `time`; existing fake seams (`ScriptedHttpClient`, `ScriptedProcess`, `MapFileSystem`, `FixedClock`, `tokio::io::duplex`).

**Spec:** `docs/superpowers/specs/2026-08-25-login-state-visibility-design.md` (decisions D1–D4; refines `JSON-004`, `UX-030`, `CACHE-004`, `CACHE-006`, `ARCH-021`).

## Global Constraints

- Rust/Cargo and QML only. No production `unwrap()` or `expect()` (tests may use them).
- Raw provider output, tokens, and account identifiers never enter logs, cache, or `ProviderResult`.
- Provider failures are typed data, never process failures; status JSON stays one schema-v2 object plus newline.
- Substring matching on a provider message is allowed only inside a Rust adapter, on a literal constant with a unit test and a comment naming the upstream source file. Never in QML.
- Every checkpoint runs: `cargo fmt --check`, `cargo test`, `cargo clippy --all-targets -- -D warnings`, `git diff --check`. Docs changes also run `cargo test --test active_language`.
- Commits: English Conventional Commit subject, at most 50 characters. No AI attribution anywhere.
- Work on branch `autentificaca` (already pushed; PR #70 holds the spec).

---

### Task 1: `AppServerOutcome::Unauthenticated` in the Codex protocol

**Files:**
- Modify: `src/providers/codex_app_server.rs:19-24` (enum), `:401-408` (id=2 error branch), tests module at the end of the file.

**Interfaces:**
- Produces: `AppServerOutcome::Unauthenticated` (new unit variant) returned by `run_appserver_protocol_outcome` and therefore by `fetch_rate_limits_via_appserver` when the `account/rateLimits/read` error message contains `authentication required`.
- Produces: `pub(crate) const CODEX_AUTH_REQUIRED_MARKER: &str = "authentication required";`

- [ ] **Step 1: Write the failing protocol test**

Append inside the existing `mod tests` of `src/providers/codex_app_server.rs`, next to `appserver_protocol_id2_error_returns_none_quickly`:

```rust
    #[tokio::test]
    async fn appserver_protocol_auth_required_error_is_unauthenticated() {
        let (client, server) = duplex(64 * 1024);
        let (client_read, client_write) = tokio::io::split(client);

        tokio::spawn(async move {
            let (read_half, mut write_half) = tokio::io::split(server);
            let mut lines = BufReader::new(read_half).lines();
            let _ = lines.next_line().await; // initialize
            write_half.write_all(br#"{"id":0,"result":{}}"#).await.expect("init");
            write_half.write_all(b"\n").await.expect("nl");
            loop {
                let line = match lines.next_line().await {
                    Ok(Some(l)) => l,
                    _ => break,
                };
                if line.contains("account/read") {
                    write_half
                        .write_all(br#"{"id":1,"result":{"account":{}}}"#)
                        .await
                        .expect("account");
                    write_half.write_all(b"\n").await.expect("nl");
                } else if line.contains("account/rateLimits/read") {
                    // Upstream: codex-rs/app-server/src/request_processors/account_processor.rs
                    write_half
                        .write_all(br#"{"id":2,"error":{"code":-32600,"message":"codex account authentication required to read rate limits"}}"#)
                        .await
                        .expect("err");
                    write_half.write_all(b"\n").await.expect("nl");
                    break;
                }
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        });

        let out = run_appserver_protocol_outcome(
            client_read,
            client_write,
            "10.0.0",
            Duration::from_secs(5),
        )
        .await;
        assert!(
            matches!(out, AppServerOutcome::Unauthenticated),
            "expected Unauthenticated, got {out:?}"
        );
    }

    #[tokio::test]
    async fn appserver_protocol_other_id2_error_stays_failed() {
        let (client, server) = duplex(64 * 1024);
        let (client_read, client_write) = tokio::io::split(client);

        tokio::spawn(async move {
            let (read_half, mut write_half) = tokio::io::split(server);
            let mut lines = BufReader::new(read_half).lines();
            let _ = lines.next_line().await;
            write_half.write_all(br#"{"id":0,"result":{}}"#).await.expect("init");
            write_half.write_all(b"\n").await.expect("nl");
            loop {
                let line = match lines.next_line().await {
                    Ok(Some(l)) => l,
                    _ => break,
                };
                if line.contains("account/read") {
                    write_half
                        .write_all(br#"{"id":1,"result":{"account":{}}}"#)
                        .await
                        .expect("account");
                    write_half.write_all(b"\n").await.expect("nl");
                } else if line.contains("account/rateLimits/read") {
                    // Same -32600 code, unrelated message: must NOT classify as auth.
                    write_half
                        .write_all(br#"{"id":2,"error":{"code":-32600,"message":"invalid request: unknown thread"}}"#)
                        .await
                        .expect("err");
                    write_half.write_all(b"\n").await.expect("nl");
                    break;
                }
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        });

        let out = run_appserver_protocol_outcome(
            client_read,
            client_write,
            "10.0.0",
            Duration::from_secs(5),
        )
        .await;
        assert!(matches!(out, AppServerOutcome::Failed), "got {out:?}");
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cargo test --lib codex_app_server::tests::appserver_protocol_auth_required_error_is_unauthenticated`
Expected: compile error `no variant named Unauthenticated`.

- [ ] **Step 3: Add the variant, the marker, and the classification**

In `src/providers/codex_app_server.rs`, replace the enum:

```rust
/// Literal marker read from upstream
/// `codex-rs/app-server/src/request_processors/account_processor.rs`
/// ("codex account authentication required to read rate limits"). JSON-RPC
/// code -32600 is shared with unrelated invalid-request errors, so only the
/// message discriminates. Re-check on Codex upgrades (docs/dev/new-provider.md).
pub(crate) const CODEX_AUTH_REQUIRED_MARKER: &str = "authentication required";

#[derive(Debug)]
pub enum AppServerOutcome {
    Ok(Vec<u8>),
    TimedOut,
    Failed,
    /// `account/rateLimits/read` refused because no Codex account is signed in.
    Unauthenticated,
}
```

Add a helper right below the enum:

```rust
/// True when the JSON-RPC `error` value carries the upstream auth marker.
/// Only the message is inspected; nothing from it is logged or retained.
fn error_is_auth_required(error: &serde_json::Value) -> bool {
    error
        .get("message")
        .and_then(|m| m.as_str())
        .map(|m| m.to_ascii_lowercase().contains(CODEX_AUTH_REQUIRED_MARKER))
        .unwrap_or(false)
}
```

Replace the id=2 error branch (`Some(2) => { if msg.error.is_some() { ... return AppServerOutcome::Failed; }`) with:

```rust
                    Some(2) => {
                        if let Some(error) = msg.error.as_ref() {
                            // Immediate failure; do not wait for hard timeout.
                            if error_is_auth_required(error) {
                                log::debug!("Codex app-server: account not authenticated");
                                return AppServerOutcome::Unauthenticated;
                            }
                            log::debug!(
                                "Codex app-server account/rateLimits/read returned error"
                            );
                            return AppServerOutcome::Failed;
                        }
```

Add a pure unit test for the helper in the same tests module:

```rust
    #[test]
    fn auth_marker_is_case_insensitive_and_message_only() {
        let hit = serde_json::json!({"code": -32600, "message": "Codex account AUTHENTICATION REQUIRED to read rate limits"});
        assert!(error_is_auth_required(&hit));
        let code_only = serde_json::json!({"code": -32600});
        assert!(!error_is_auth_required(&code_only));
        let data_only = serde_json::json!({"code": -32600, "message": "boom", "data": "authentication required"});
        assert!(!error_is_auth_required(&data_only));
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cargo test --lib codex_app_server`
Expected: all pass, including the three new tests. If `run_appserver_protocol` (the `Option<Vec<u8>>` wrapper) has an exhaustive `match` on the outcome, add `AppServerOutcome::Unauthenticated => None`.

- [ ] **Step 5: Commit**

```bash
git add src/providers/codex_app_server.rs
git commit -m "feat(codex): classify app-server auth error"
```

---

### Task 2: `CodexAdapter` returns `unauthenticated`

**Files:**
- Modify: `src/providers/adapters.rs:296-310` (app-server branch inside `CodexAdapter::collect`), tests module.

**Interfaces:**
- Consumes: `AppServerOutcome::Unauthenticated` (Task 1); `unauthenticated(id, name, message, login_available, url, retryable)` from `src/providers/adapter.rs:222`; `login_available(discovery)`; `CODEX.installation_url`.
- Produces: `ProviderResult::Unauthenticated { id: Codex, message: "Codex is not authenticated.", retryable: false, .. }`.

- [ ] **Step 1: Write the failing adapter test with a fake `codex` executable**

The adapter spawns the collection executable directly (`tokio::process::Command`), so the test writes a tiny Bash fake into a temp dir. Append to the tests module of `src/providers/adapters.rs`:

```rust
    /// Writes an executable fake `codex` that speaks just enough app-server
    /// protocol to answer initialize, account/read, and refuse rateLimits.
    fn write_fake_codex_unauthenticated(dir: &Path) -> std::path::PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let exe = dir.join("codex");
        let script = r#"#!/usr/bin/env bash
# Fake Codex app-server: signed-out account.
[[ "$1" == "app-server" ]] || exit 2
while IFS= read -r line; do
  case "$line" in
    *'"initialize"'*) printf '%s\n' '{"id":0,"result":{}}' ;;
    *'account/rateLimits/read'*) printf '%s\n' '{"id":2,"error":{"code":-32600,"message":"codex account authentication required to read rate limits"}}' ;;
    *'account/read'*) printf '%s\n' '{"id":1,"result":{"account":{}}}' ;;
  esac
done
"#;
        std::fs::write(&exe, script).expect("write fake codex");
        std::fs::set_permissions(&exe, std::fs::Permissions::from_mode(0o755)).expect("chmod");
        exe
    }

    #[tokio::test]
    async fn codex_unauthenticated_appserver_ignores_session_log() {
        let dir = tempfile::tempdir().expect("tempdir");
        let home = dir.path().join("home");
        let sessions = home.join(".codex/sessions/2026/07/28");
        std::fs::create_dir_all(&sessions).expect("mkdir");
        // Old usage on disk must NOT be presented for a signed-out account (JSON-007).
        std::fs::write(
            sessions.join("rollout.jsonl"),
            concat!(
                r#"{"timestamp":"2026-07-28T10:00:00Z","type":"event","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.5,"window_minutes":10080}}}}"#,
                "\n"
            ),
        )
        .expect("write jsonl");
        let exe = write_fake_codex_unauthenticated(dir.path());

        let env = ExecutionEnvironment { home, path_dirs: vec![], grok_home: None };
        let clock = FixedClock(datetime!(2026-08-25 12:00:00 UTC));
        let fs = MapFileSystem::default();
        let process = empty_process();
        let http = ScriptedHttpClient::single(Err(HttpError::Network("unused".into())));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(&exe);
        let result = CODEX_ADAPTER.collect(&ctx, &discovery).await;
        match result {
            ProviderResult::Unauthenticated { id, message, login_available, retryable, .. } => {
                assert_eq!(id, ProviderId::Codex);
                assert_eq!(message, "Codex is not authenticated.");
                assert!(login_available, "discovery_with_exe resolves the login exe");
                assert!(!retryable);
            }
            other => panic!("expected Unauthenticated, got {other:?}"),
        }
    }
```

The HTTP client is never reached by the Codex adapter; any scripted response works. If `empty_process()` does not exist in this tests module, use `ScriptedProcess::one(fake_process_output(0, "", ""))`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cargo test --lib adapters::tests::codex_unauthenticated_appserver_ignores_session_log`
Expected: FAIL with `expected Unauthenticated, got Ready { .. }` (the session-log fallback currently wins).

- [ ] **Step 3: Map the outcome in the adapter**

In `CodexAdapter::collect`, after the timeout retry and before the session-log fallback, replace:

```rust
                if let AppServerOutcome::Ok(bytes) = outcome {
                    return codex_from_rate_limits_json(&bytes, context.clock.now_utc());
                }
```

with:

```rust
                match outcome {
                    AppServerOutcome::Ok(bytes) => {
                        return codex_from_rate_limits_json(&bytes, context.clock.now_utc());
                    }
                    // JSON-004 / JSON-007: a signed-out account never falls
                    // through to obsolete session-log usage.
                    AppServerOutcome::Unauthenticated => {
                        return unauthenticated(
                            ProviderId::Codex,
                            CODEX.display_name,
                            "Codex is not authenticated.",
                            login_available(discovery),
                            CODEX.installation_url,
                            false,
                        );
                    }
                    AppServerOutcome::TimedOut | AppServerOutcome::Failed => {}
                }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cargo test --lib adapters::tests::codex_`
Expected: PASS for the new test and the existing Codex tests (`/nonexistent/codex` still falls through to the session log).

- [ ] **Step 5: Run the full gate and commit**

```bash
cargo fmt --check && cargo test && cargo clippy --all-targets -- -D warnings && git diff --check
git add src/providers/adapters.rs
git commit -m "feat(codex): report unauthenticated state"
```

---

### Task 3: Audit tests — an operational failure mentioning "auth" is never `unauthenticated`

**Files:**
- Modify: `src/providers/adapters.rs` tests module only.

**Interfaces:**
- Consumes: existing helpers `ScriptedHttpClient::single`, `MapFileSystem`, `discovery_with_exe`, `FixedClock`, `fake_process_output`, `classify_antigravity_failure`, `grok_test_env_and_auth`, `CLAUDE_USAGE_URL`, `GROK_BILLING_URL`. Amp already has `amp_network_flavored_auth_substring_is_not_unauthenticated`.

- [ ] **Step 1: Write the three tests**

```rust
    #[tokio::test]
    async fn claude_500_with_auth_wording_is_not_unauthenticated() {
        let http = ScriptedHttpClient::single(Ok(HttpResponse {
            status: 500,
            final_url: CLAUDE_USAGE_URL.into(),
            body: br#"{"error":"authorization server unavailable"}"#.to_vec(),
        }));
        let process = ScriptedProcess::one(fake_process_output(0, "", ""));
        let mut fs = MapFileSystem::default();
        fs.files.insert(
            std::path::PathBuf::from("/home/u/.claude/.credentials.json"),
            br#"{"claudeAiOauth":{"accessToken":"SECRET_TOKEN_VALUE","subscriptionType":"pro"}}"#
                .to_vec(),
        );
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/home/u"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(Path::new("/usr/bin/claude"));
        let result = CLAUDE_ADAPTER.collect(&ctx, &discovery).await;
        assert!(!format!("{result:?}").contains("SECRET_TOKEN_VALUE"));
        assert!(
            !matches!(result, ProviderResult::Unauthenticated { .. }),
            "status 500 is operational, got {result:?}"
        );
    }

    #[tokio::test]
    async fn grok_500_with_auth_wording_is_not_unauthenticated() {
        let http = ScriptedHttpClient::single(Ok(HttpResponse {
            status: 500,
            final_url: GROK_BILLING_URL.into(),
            body: br#"{"error":"authorization server unavailable"}"#.to_vec(),
        }));
        let process = empty_process();
        let mut fs = MapFileSystem::default();
        let env = grok_test_env_and_auth(&mut fs);
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = Discovery {
            collection: CollectionAvailability::Missing,
            login: LoginAvailability::Available {
                executable: std::path::PathBuf::from("/usr/bin/grok"),
            },
        };
        let result = GROK_ADAPTER.collect(&ctx, &discovery).await;
        assert!(
            !matches!(result, ProviderResult::Unauthenticated { .. }),
            "status 500 is operational, got {result:?}"
        );
    }

    #[test]
    fn antigravity_auth_wording_without_marker_is_not_unauthenticated() {
        let out = fake_process_output(1, "", "authorization server unavailable");
        let result = classify_antigravity_failure(&out, true);
        assert!(matches!(result, ProviderResult::ProviderError { .. }), "got {result:?}");
    }
```

- [ ] **Step 2: Run them**

Run: `cargo test --lib adapters::tests::` with each test name.
Expected: all three PASS on first run (they pin current behaviour; Claude and Grok classify by HTTP status only, Antigravity by the `not signed in` marker). If one fails, that adapter has a real classification bug: stop and report it instead of loosening the assertion.

- [ ] **Step 3: Commit**

```bash
git add src/providers/adapters.rs
git commit -m "test: pin auth wording is not unauthenticated"
```

---

### Task 4: Non-ready cache rows are never fresh

**Files:**
- Modify: `src/cache/schema.rs:68-70` (`is_fresh`), tests in `src/status/coordinator.rs`.

**Interfaces:**
- Produces: `CacheDocument::is_fresh(&self, id, now) -> bool` now returns `false` for any row whose `status.state()` is not `ProviderState::Ready | ProviderState::Stale`, regardless of `expires_at`. The `CacheMode::Bypass` branch in the coordinator is untouched.

- [ ] **Step 1: Write the failing coordinator test**

Append inside `mod tests` of `src/status/coordinator.rs`, after `cache_hit_reports_source_cache`:

```rust
    #[tokio::test]
    async fn cached_provider_error_inside_ttl_is_recollected() {
        let dir = tempfile::tempdir().unwrap();
        let now = datetime!(2026-08-25 11:50:31 UTC);
        let coord = coord_at(dir.path(), now);
        // A failure row that would still be inside Claude's 300 s success TTL.
        let failed = fallback_provider_error(ProviderId::Claude, "Claude returned no limits.");
        let entry = entry_from_status(failed, now, now, std::time::Duration::from_secs(300));
        coord
            .cache_store
            .merge_provider(ProviderId::Claude, entry, now)
            .unwrap();

        let envelope = coord
            .collect(CollectRequest {
                format: StatusFormat::Json,
                provider: Some(ProviderId::Claude),
                cache: CacheMode::Use,
                notifications: NotificationMode::Skip,
            })
            .await
            .unwrap();
        let row = &envelope.providers()[0];
        assert_ne!(
            row.source(),
            Some(DataSource::Cache),
            "non-ready rows must be re-collected under cache use"
        );
        // coord_at has no credentials and no executables: the live result is a
        // typed failure again, proving the collection ran instead of the cache.
        assert_ne!(row.state(), ProviderState::Ready);
    }

    #[test]
    fn cache_document_non_ready_row_is_never_fresh() {
        let now = datetime!(2026-08-25 11:50:31 UTC);
        let mut doc = CacheDocument::empty();
        let failed = fallback_provider_error(ProviderId::Codex, "Codex rate limits were not available.");
        doc.providers.insert(
            "codex".into(),
            entry_from_status(failed, now, now, std::time::Duration::from_secs(90)),
        );
        assert!(!doc.is_fresh(ProviderId::Codex, now));
        let ready = ready_claude(now);
        doc.providers.insert(
            "claude".into(),
            entry_from_status(ready, now, now, std::time::Duration::from_secs(300)),
        );
        assert!(doc.is_fresh(ProviderId::Claude, now));
        assert!(!doc.is_fresh(ProviderId::Claude, now + time::Duration::seconds(301)));
    }
```

If `CacheDocument` is not already imported in the tests module, add `use crate::cache::schema::CacheDocument;`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cargo test --lib coordinator::tests::cached_provider_error_inside_ttl_is_recollected` and `cargo test --lib coordinator::tests::cache_document_non_ready_row_is_never_fresh`
Expected: both FAIL (`source() == Some(Cache)` / `is_fresh` returned true).

- [ ] **Step 3: Make `is_fresh` state-aware**

In `src/cache/schema.rs` replace the method:

```rust
    /// A row is fresh only while inside its TTL AND holding usable data.
    /// Failure rows (cli_missing, unauthenticated, rate_limited,
    /// network_error, provider_error) are written for stale retention and
    /// singleflight bookkeeping but are never served from cache, so the next
    /// `cache use` collection retries live (CACHE-004/006 amendment,
    /// docs/superpowers/specs/2026-08-25-login-state-visibility-design.md D4).
    pub fn is_fresh(&self, id: ProviderId, now: OffsetDateTime) -> bool {
        self.get(id).is_some_and(|entry| {
            now < entry.expires_at
                && matches!(
                    entry.status.state(),
                    ProviderState::Ready | ProviderState::Stale
                )
        })
    }
```

and extend the import: `use crate::status::schema::{ProviderState, ProviderStatus};`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cargo test --lib coordinator` and `cargo test --lib cache`
Expected: PASS. `cache_hit_reports_source_cache`, `temporary_failure_retains_prior_ready_as_stale`, `auth_failure_does_not_retain_stale_usage`, and `bypass_accepts_generation_started_at_or_after_request` keep passing (stale rows stay fresh; bypass path unchanged).

- [ ] **Step 5: Run the full gate and commit**

```bash
cargo fmt --check && cargo test && cargo clippy --all-targets -- -D warnings && git diff --check
git add src/cache/schema.rs src/status/coordinator.rs
git commit -m "fix(cache): never serve non-ready rows"
```

---

### Task 5: Documentation and spec alignment

**Files:**
- Modify: `docs/dev/new-provider.md:117-131` (Error mapping).
- Modify: `docs/guide/runtime.md` (cache section — find the paragraph that describes provider TTL).
- Modify: `docs/superpowers/specs/2026-08-25-login-state-visibility-design.md` (D2 title copy).

**Interfaces:**
- Consumes: `CODEX_AUTH_REQUIRED_MARKER` (Task 1) — name it verbatim in the docs.

- [ ] **Step 1: Amend the error-mapping section of `docs/dev/new-provider.md`**

Replace the last paragraph of "## Error mapping" (`Temporary failure with last good data ... Control flow never uses regex over the message.`) with:

```markdown
Temporary failure with last good data becomes `stale` at the coordinator.
Failure rows are cached only for stale retention; they are never served fresh,
so the next automatic collection retries live.

Messages are safe English copy. Control flow never uses regex over a
human message. The one allowed exception is an explicit, allowlisted
substring inside the Rust adapter, when the provider exposes no typed signal:
each marker is a literal constant, has a unit test for a look-alike that must
NOT match, and carries a comment naming the upstream source file it was read
from. Examples: Amp's `not signed` / `sign in` / `unauthorized` / `please log
in`, Antigravity's `not signed in`, Codex's `CODEX_AUTH_REQUIRED_MARKER`
(`authentication required`, from
`codex-rs/app-server/src/request_processors/account_processor.rs`). Re-verify
the upstream text when bumping a provider CLI.

Prove unauthenticated explicitly: a signed-out account must never fall through
to obsolete on-disk usage (`JSON-007`); add a test that pairs the signed-out
signal with a stale local fixture and asserts `unauthenticated`.
```

- [ ] **Step 2: Add one sentence to the cache description in `docs/guide/runtime.md`**

`docs/guide/runtime.md` lists `status-v2.json` in its paths table (line 9) with no prose on freshness. Add this paragraph directly after that table (after the `Default XDG paths ...` line):

```markdown
Only `ready` and `stale` rows are served from cache; any failure row is
re-collected on the next poll, so a transient failure is visible for at most
one refresh interval.
```

- [ ] **Step 3: Align spec D2 with the existing QML copy**

In the spec, D2 second bullet, replace `title \`<Provider> is not authenticated.\`, no body copy beyond the typed message` with `the existing popup copy (title \`Not signed in to <Provider>\`, body \`Signing in opens the official <Provider> CLI.\`, from \`CoreView.js\`)`.

- [ ] **Step 4: Verify**

Run: `cargo test --test active_language --test active_docs && git diff --check`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/dev/new-provider.md docs/guide/runtime.md docs/superpowers/specs/2026-08-25-login-state-visibility-design.md
git commit -m "docs: unauthenticated markers and cache rule"
```

---

### Task 6: Final gate, QML regression, and live QA

**Files:** none modified.

- [ ] **Step 1: Full Rust gate**

```bash
cargo fmt --check && cargo test && cargo clippy --all-targets -- -D warnings && git diff --check
```

Expected: all green.

- [ ] **Step 2: QML regression (no QML changed; proves the contract still renders)**

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 QT_LOGGING_TO_CONSOLE=1 \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml -import /usr/share/omarchy/shell -import . -o -,txt
omarchy plugin validate .
```

Expected: `tst_ProviderStates::test_unauthenticated_connect_or_install` and `test_state_copy_unauthenticated` pass; validate reports OK.

- [ ] **Step 3: Helper-level proof on the dev build (read-only, no live config touched)**

```bash
cargo build --release
./target/release/agent-bar status provider codex cache bypass format json | jq '.providers[0] | {state, action: .action.kind, error: .error.code}'
```

Expected with Codex signed out on this machine: `{"state":"unauthenticated","action":"login","error":"authentication_required"}`.

- [ ] **Step 4: Push and update the PR**

```bash
git push origin autentificaca
gh pr edit 70 --title "feat: login state visibility" --body "$(cat <<'EOF'
Implements docs/superpowers/specs/2026-08-25-login-state-visibility-design.md (map #63).

- Codex: app-server "authentication required" error → `unauthenticated` + `Sign in`; session-log usage is never shown for a signed-out account.
- Cache: only `ready`/`stale` rows are fresh; failure rows re-collect on the next poll (fixes the 5-minute `—` after install).
- Audit tests pin that Claude/Grok/Antigravity/Amp do not classify operational "auth" wording as unauthenticated.
- Docs: new-provider checklist, runtime cache rule, spec D2 copy aligned with CoreView.js.

Gate: cargo fmt/test/clippy, git diff --check, qmltestrunner, omarchy plugin validate.
EOF
)"
```

- [ ] **Step 5: Live QA gate (user, after merge and `omarchy plugin update`)**

Checklist for the user, not the agent:
1. With Codex signed out, open the popup: Codex shows `Not signed in to Codex` and `Sign in`; the chip shows `—`.
2. Click `Sign in`, complete `codex login` in the terminal, close it: within a few seconds the chip shows a percentage without pressing Retry.
3. Clear `$XDG_CACHE_HOME/agent-bar/status-v2.json` (or use a fresh install), disconnect the network, restart the shell, and wait one poll: Claude shows `Cannot reach Claude`; reconnect: it recovers on the next poll (≤ 60 s). With last good data present, a blip shows the retained reading as `stale` and recovers within the provider's TTL — that is expected.

Record the result in `docs/history/qa/` per the release runbook.

---

## Self-review

- **Spec coverage.** D1 → Tasks 1–3 (marker, adapter mapping, audit tests, docs pointer in Task 5). D2 → no code change; Task 5 aligns the spec copy with `CoreView.js`; Task 6 step 2 re-runs the QML tests. D3 → unchanged contract; Task 6 step 5 is the live check. D4 → Task 4. "Ruled out" items add no work. Testing section: app-server fake with/without marker (Task 1), session-log + unauthenticated (Task 2), coordinator freshness (Task 4), QML (Task 6), live QA (Task 6).
- **Placeholders.** Task 2 names two helper fallbacks (`HttpError` variant, `empty_process`) with the exact alternative to use; Task 5 step 2 requires an `rg` to locate the paragraph — the inserted text is given verbatim.
- **Type consistency.** `AppServerOutcome::Unauthenticated` (Task 1) is matched in Task 2; `unauthenticated(...)` six-argument signature copied from `src/providers/adapter.rs:222`; `CacheDocument::is_fresh(id, now)` signature unchanged; `fallback_provider_error(id, &str)` and `entry_from_status(status, started, completed, ttl)` match `src/status/coordinator.rs:296` and `src/cache/store.rs:193`.
