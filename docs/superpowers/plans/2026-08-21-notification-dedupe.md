# Notification Dedupe and Reminder Cadence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the once-per-poll notification loop by making a notification's
identity `(providerId, windowId)` instead of a jittering timestamp, and repeat
each alert on a user-configurable cadence instead of never.

**Architecture:** `notification-state-v2.json` keys one row per window;
`resetAt` becomes observed data compared through a 60-second jitter tolerance;
a new `notifiedAt` drives the reminder; `notifications.reminderMinutes`
(15..=1440, default 120) is added to settings across all three places that
enforce the closed key set. Emission and pruning stay inside
`NotificationEvaluator::evaluate`; QML gains one `NumberField`.

**Tech Stack:** Rust (serde, `time` 0.3, `fs2`, `log`), QML/JS for Quickshell.
No Node, npm, or any JS toolchain — QML tests run under Qt6 `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-08-21-notification-dedupe-design.md`

## Global Constraints

- Rust/Cargo and QML only. No Node, npm, Bun, pnpm, Yarn, ts-node, Deno.
- No production `unwrap()` or `expect()`. Test code may use them.
- Status JSON stdout stays exactly one schema-v2 object plus newline. Logs go
  to stderr.
- Provider operational failures are typed data, not process failures.
- Render external strings as plain text. QML never parses raw provider output.
- Settings reads never write. Explicit apply/migration uses lock and atomic
  replacement.
- Active docs and public copy are English ASCII — `tests/active_language.rs`
  fails the build on any alphabetic non-ASCII character in a tracked
  non-excluded file. `docs/superpowers/**` is excluded but is still written in
  English.
- Conventional Commit subjects in English, at most 50 characters.
- Never bypass hooks, force-push, merge, tag, or publish without explicit
  authorization. Do not commit unless the owner asked for it.
- Every checkpoint runs: `cargo fmt --check`, `cargo test`,
  `cargo clippy --all-targets -- -D warnings`, `git diff --check`.
- QML/plugin changes additionally run, with these exact binary paths (the
  `PATH` `qmllint` is a silent stub and the `PATH` `qmltestrunner` is Qt5 and
  fails silently):

```bash
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell ./*.qml components/*.qml
omarchy plugin validate .
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 QT_LOGGING_TO_CONSOLE=1 \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml \
  -import /usr/share/omarchy/shell -import . -o -,txt
```

- `qmllint` exits 0 while printing warnings and cannot resolve `qs.*` imports.
  Read its output for what your change introduced; never treat its exit code as
  a verdict.

## Deviation from the spec

The spec's Observability section asked the doctor to "parse the v2 state and
report it unreadable or non-unique". `DoctorReport`
(`src/plugin/doctor.rs:27`) carries only `findings`/`removable`/`retained`/
`read_only`/`removed`/`backup_root`, every existing check is path-existence
plus hash classification, and the doctor never opens a JSON file. That check
would mean a new report contract for a failure mode Task 1 makes unreachable,
against a file `NotificationStateStore::load` already quarantines on its own.
Task 6 therefore adds only the v1 legacy entry to the doctor; observability
lands as the two `log::warn!` calls in Task 5. Nothing else in the spec is
reduced.

## File Structure

| File | Responsibility after this plan |
| --- | --- |
| `src/notifications/state.rs` | v2 schema, one key definition, jitter tolerance, pruning primitive |
| `src/notifications/mod.rs` | emission decision, reminder cadence, pruning call, warn on save failure |
| `src/settings/schema.rs` | `reminder_minutes` field, range constants, range validation, key allowlist |
| `src/settings/migration.rs` | v9 migration emits the default |
| `schemas/settings-v1.schema.json` | optional `reminderMinutes` property |
| `src/status/coordinator.rs` | `log::warn!` instead of `eprintln!` |
| `src/plugin/doctor.rs` | v1 state file listed as legacy |
| `CoreService.js` | `reminderMinutes` in `defaultSettings()` |
| `CoreSettings.js` | `setReminderMinutes` setter and draft validation |
| `SettingsView.qml` | "Remind me every / minutes" `NumberField` |
| `Service.qml` | `setReminderMinutes` draft wrapper |

---

### Task 1: Notification state v2 — one key, jitter tolerance

**Files:**
- Modify: `src/notifications/state.rs`
- Modify: `src/notifications/mod.rs` (call sites only; the algorithm changes in Task 3)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `pub const NOTIFICATION_STATE_VERSION: u32 = 2`
  - `pub const RESET_JITTER_TOLERANCE: time::Duration`
  - `NotificationEntry { provider_id: String, window_id: String, reset_at: Option<OffsetDateTime>, level: NotificationLevel, notified_at: OffsetDateTime }`
  - `NotificationEntry::key(&self) -> (&str, &str)`
  - `NotificationState::same_window(Option<OffsetDateTime>, Option<OffsetDateTime>) -> bool`
  - `NotificationState::entry_for(&self, ProviderId, &str) -> Option<&NotificationEntry>`
  - `NotificationState::remove_key(&mut self, ProviderId, &str)` — reset argument dropped
  - `NotificationState::prune_ready_provider(&mut self, ProviderId, &[&str], OffsetDateTime, bool)`
  - `NotificationPaths::from_cache_home` now yields `notification-state-v2.json`
  - test helper `store_in(&tempfile::TempDir) -> NotificationStateStore` in `mod.rs`'s test module
  - `level_for` is REMOVED; call sites use `entry_for`

`CRITICAL_USED_PERCENT`, `WARNING_USED_PERCENT`, `NotificationLevel` and the
module path `agent_bar::notifications::state` must survive unchanged —
`tests/severity_parity.rs:7` imports them by exact name.

This task ends with the crate compiling and the incident's exact reproduction
covered by a test. Task 3 then adds the reminder on top.

- [ ] **Step 1: Write the failing unit tests**

Add to the `#[cfg(test)] mod tests` block at the bottom of
`src/notifications/state.rs`, keeping the file's existing lowercase snake_case
naming:

```rust
    #[test]
    fn sub_second_reset_jitter_is_the_same_window() {
        // The Claude usage endpoint derives resets_at from its own clock per
        // response, so the same window returns with millisecond drift. v1
        // treated that as a new key, which is what produced the notification
        // loop this test exists to prevent.
        let a = datetime!(2026-08-21 11:59:59.707742 UTC);
        let b = datetime!(2026-08-21 11:59:59.854947 UTC);
        let c = datetime!(2026-08-21 12:00:00.024238 UTC);
        assert!(NotificationState::same_window(Some(a), Some(b)));
        assert!(NotificationState::same_window(Some(a), Some(c)));
        assert!(NotificationState::same_window(None, None));
    }

    #[test]
    fn a_real_window_advance_is_not_the_same_window() {
        let now = datetime!(2026-08-21 11:59:59 UTC);
        let next_week = datetime!(2026-08-28 11:59:59 UTC);
        assert!(!NotificationState::same_window(Some(now), Some(next_week)));
        assert!(!NotificationState::same_window(Some(now), None));
        assert!(!NotificationState::same_window(None, Some(now)));
        // Just outside the tolerance, so the boundary is pinned, not implied.
        let just_past = datetime!(2026-08-21 12:01:00.001 UTC);
        assert!(!NotificationState::same_window(Some(now), Some(just_past)));
    }

    #[test]
    fn upsert_replaces_a_jittered_row_instead_of_appending() {
        let mut state = NotificationState::empty();
        state.upsert(NotificationEntry {
            provider_id: "claude".into(),
            window_id: "weekly-model:fable".into(),
            reset_at: Some(datetime!(2026-08-21 11:59:59.854947 UTC)),
            level: NotificationLevel::Warning,
            notified_at: datetime!(2026-08-21 10:31:56 UTC),
        });
        state.upsert(NotificationEntry {
            provider_id: "claude".into(),
            window_id: "weekly-model:fable".into(),
            reset_at: Some(datetime!(2026-08-21 11:59:59.707742 UTC)),
            level: NotificationLevel::Critical,
            notified_at: datetime!(2026-08-21 10:37:56 UTC),
        });
        assert_eq!(state.entries.len(), 1);
        assert_eq!(state.entries[0].level, NotificationLevel::Critical);
        // The exact document that made save() fail with "duplicate
        // notification key" on the reporting install.
        state.validate().unwrap();
    }

    #[test]
    fn prune_drops_elapsed_and_absent_windows_on_a_live_reading() {
        let now = datetime!(2026-08-21 12:00:00 UTC);
        let mut state = NotificationState::empty();
        for (window, reset) in [
            ("live", Some(datetime!(2026-08-28 12:00:00 UTC))),
            ("elapsed", Some(datetime!(2026-08-12 00:00:00 UTC))),
            ("vanished", Some(datetime!(2026-08-28 12:00:00 UTC))),
        ] {
            state.upsert(NotificationEntry {
                provider_id: "claude".into(),
                window_id: window.into(),
                reset_at: reset,
                level: NotificationLevel::Warning,
                notified_at: datetime!(2026-08-21 10:00:00 UTC),
            });
        }
        state.prune_ready_provider(ProviderId::Claude, &["live", "elapsed"], now, true);
        let kept: Vec<&str> = state.entries.iter().map(|e| e.window_id.as_str()).collect();
        assert_eq!(kept, vec!["live"]);
    }

    #[test]
    fn prune_keeps_elapsed_rows_when_the_reading_came_from_cache() {
        // A Ready provider can be served straight from cache for up to its
        // TTL (300s for Claude) while still reporting the pre-reset
        // timestamp. Treating that as proof the window restarted would rearm
        // against a reading the provider never confirmed.
        let now = datetime!(2026-08-21 12:00:00 UTC);
        let mut state = NotificationState::empty();
        state.upsert(NotificationEntry {
            provider_id: "claude".into(),
            window_id: "weekly".into(),
            reset_at: Some(datetime!(2026-08-21 11:59:59 UTC)),
            level: NotificationLevel::Critical,
            notified_at: datetime!(2026-08-21 10:00:00 UTC),
        });
        state.prune_ready_provider(ProviderId::Claude, &["weekly"], now, false);
        assert_eq!(state.entries.len(), 1, "cache reading is not evidence");
    }

    #[test]
    fn prune_leaves_other_providers_untouched() {
        let now = datetime!(2026-08-21 12:00:00 UTC);
        let mut state = NotificationState::empty();
        state.upsert(NotificationEntry {
            provider_id: "amp".into(),
            window_id: "daily".into(),
            reset_at: Some(datetime!(2026-08-12 00:00:00 UTC)),
            level: NotificationLevel::Critical,
            notified_at: datetime!(2026-08-11 23:00:00 UTC),
        });
        state.prune_ready_provider(ProviderId::Claude, &[], now, true);
        assert_eq!(state.entries.len(), 1);
    }
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cargo test --lib notifications::state`
Expected: compile errors — `same_window`, `prune_ready_provider`, and the
`notified_at` field do not exist.

- [ ] **Step 3: Bump the version constant and add the tolerance**

In `src/notifications/state.rs`, replace line 16 and add the tolerance below it:

```rust
pub const NOTIFICATION_STATE_VERSION: u32 = 2;

/// How far two observed reset timestamps may drift and still describe the same
/// quota window.
///
/// The Claude usage endpoint derives `resets_at` from its own clock on every
/// response — within one envelope its three windows come back with distinct
/// microseconds — so no two collections ever agree byte-for-byte. Sixty
/// seconds swallows that drift with orders of magnitude to spare and stays
/// negligible against a 5h or 7d window.
pub const RESET_JITTER_TOLERANCE: time::Duration = time::Duration::seconds(60);
```

- [ ] **Step 4: Add `notified_at` to the entry and give it one key**

Replace the `NotificationEntry` struct (lines 51-59) with:

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NotificationEntry {
    pub provider_id: String,
    pub window_id: String,
    /// Last observed reset for this window. Evidence, not identity: see
    /// `RESET_JITTER_TOLERANCE`.
    #[serde(with = "time::serde::rfc3339::option")]
    pub reset_at: Option<OffsetDateTime>,
    pub level: NotificationLevel,
    /// When the last successful dispatch happened; drives the reminder.
    #[serde(with = "time::serde::rfc3339")]
    pub notified_at: OffsetDateTime,
}

impl NotificationEntry {
    /// The one definition of a notification's identity.
    ///
    /// v1 spelled this comparison out by hand in four places; `validate`
    /// truncated the reset to whole seconds while the other three compared
    /// nanoseconds, and the disagreement blocked every write.
    pub fn key(&self) -> (&str, &str) {
        (self.provider_id.as_str(), self.window_id.as_str())
    }
}
```

- [ ] **Step 5: Route every comparison through that key**

In `impl NotificationState`, replace `validate`'s key block (lines 87-94),
`sort_entries` (99-113), `level_for` (115-131), `upsert` (133-141) and
`remove_key` (143-154) with:

```rust
    pub fn validate(&self) -> Result<(), NotificationStateError> {
        if self.schema_version != NOTIFICATION_STATE_VERSION {
            return Err(NotificationStateError::Version);
        }
        let mut keys = std::collections::HashSet::new();
        for entry in &self.entries {
            if ProviderId::parse_word(&entry.provider_id).is_none() {
                return Err(NotificationStateError::UnknownProvider(
                    entry.provider_id.clone(),
                ));
            }
            if !keys.insert(entry.key()) {
                return Err(NotificationStateError::DuplicateKey);
            }
        }
        Ok(())
    }

    pub fn sort_entries(&mut self) {
        self.entries.sort_by(|a, b| a.key().cmp(&b.key()));
    }

    /// True when two observed resets describe the same quota window.
    pub fn same_window(
        saved: Option<OffsetDateTime>,
        observed: Option<OffsetDateTime>,
    ) -> bool {
        match (saved, observed) {
            (None, None) => true,
            (Some(a), Some(b)) => (a - b).abs() <= RESET_JITTER_TOLERANCE,
            _ => false,
        }
    }

    pub fn entry_for(
        &self,
        provider: ProviderId,
        window_id: &str,
    ) -> Option<&NotificationEntry> {
        self.entries
            .iter()
            .find(|e| e.key() == (provider.as_str(), window_id))
    }

    pub fn upsert(&mut self, entry: NotificationEntry) {
        self.entries.retain(|e| e.key() != entry.key());
        self.entries.push(entry);
        self.sort_entries();
    }

    pub fn remove_key(&mut self, provider: ProviderId, window_id: &str) {
        self.entries
            .retain(|e| e.key() != (provider.as_str(), window_id));
    }

    /// Drop rows for one `Ready` provider whose window vanished from the
    /// envelope, or whose reset already elapsed on a live reading.
    ///
    /// `is_live` guards the elapsed branch specifically. A `Ready` provider
    /// can be served straight from cache for up to its TTL while still
    /// reporting the pre-reset timestamp (`for_cache_hit` in
    /// `src/status/schema.rs` clones the windows unchanged and keeps the state
    /// `Ready`), so an elapsed reset is only evidence the window restarted
    /// when this cycle actually reached the provider.
    pub fn prune_ready_provider(
        &mut self,
        provider: ProviderId,
        live_windows: &[&str],
        now: OffsetDateTime,
        is_live: bool,
    ) {
        self.entries.retain(|e| {
            if e.provider_id != provider.as_str() {
                return true;
            }
            if !live_windows.contains(&e.window_id.as_str()) {
                return false;
            }
            if !is_live {
                return true;
            }
            e.reset_at.map(|ts| ts > now).unwrap_or(true)
        });
    }
```

After this replacement `Ordering` is referenced nowhere in the file — it lived
only in the old `sort_entries`. Delete its import from the top of
`src/notifications/state.rs`:

```rust
use std::cmp::Ordering;
```

Leave every other import (`std::fs`, `std::io`, `std::path::{Path, PathBuf}`,
`fs2::FileExt`, and the rest) untouched. Skipping this fails
`cargo clippy --all-targets -- -D warnings` at the final checkpoint with
`unused_imports`.

- [ ] **Step 6: Point the version error and the path at v2**

In the `Display` impl for `NotificationStateError`, replace the hardcoded `1`
(line 168) so the message can never drift from the constant again:

```rust
            Self::Version => write!(
                f,
                "notification state schemaVersion must be {NOTIFICATION_STATE_VERSION}"
            ),
```

In `NotificationPaths::from_cache_home` (line 185), change the state filename
only — the lock filename is deliberately reused:

```rust
            state: root.join("notification-state-v2.json"),
            lock: root.join("notification.lock"),
```

- [ ] **Step 7: Fix the pre-existing tests this breaks**

`rearm_on_reset_change` (line 300) asserts v1 semantics that no longer exist.
Replace it wholesale — the behaviour it guarded now lives in
`a_real_window_advance_is_not_the_same_window`:

```rust
    #[test]
    fn entry_for_finds_a_row_regardless_of_reset_drift() {
        let mut state = NotificationState::empty();
        state.upsert(NotificationEntry {
            provider_id: "claude".into(),
            window_id: "session".into(),
            reset_at: Some(datetime!(2026-07-26 22:00:00 UTC)),
            level: NotificationLevel::Warning,
            notified_at: datetime!(2026-07-26 18:42:00 UTC),
        });
        let found = state.entry_for(ProviderId::Claude, "session").unwrap();
        assert_eq!(found.level, NotificationLevel::Warning);
        assert!(state.entry_for(ProviderId::Claude, "weekly").is_none());
    }
```

`store_round_trip` constructs a `NotificationEntry` literal and must gain
`notified_at: datetime!(2026-07-26 18:42:00 UTC)`. Its tempdir path (line 323)
is the one remaining place in this file spelling `notification-state-v1.json`;
change it to `notification-state-v2.json` for consistency.

- [ ] **Step 8: Write the integration test that proves the loop is gone**

Add to `#[cfg(test)] mod tests` in `src/notifications/mod.rs`, alongside the
existing `envelope_with_used` / `envelope_with_reset` helpers. The `store_in`
helper is introduced here and reused by Tasks 3 and 4:

```rust
    fn store_in(dir: &tempfile::TempDir) -> NotificationStateStore {
        NotificationStateStore::new(
            NotificationPaths {
                state: dir.path().join("nstate.json"),
                lock: dir.path().join("n.lock"),
            },
            Arc::new(MaintenanceGate::open(dir.path().join("m.lock")).unwrap()),
        )
    }

    #[tokio::test]
    async fn sub_second_reset_jitter_does_not_renotify() {
        // The incident, end to end: three consecutive collections of the same
        // Claude window, each carrying a different microsecond reset. Before
        // this task that dispatched three times and persisted nothing.
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(&dir);
        let runner = ScriptedNotify {
            specs: Mutex::new(Vec::new()),
            fail: false,
        };
        let dispatcher = NotifySendDispatcher::new(runner);
        let settings = SettingsDocument::defaults();
        let eval = NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: datetime!(2026-08-21 10:31:56 UTC),
        };
        for reset in [
            datetime!(2026-08-21 11:59:59.707742 UTC),
            datetime!(2026-08-21 11:59:59.854947 UTC),
            datetime!(2026-08-21 12:00:00.024238 UTC),
        ] {
            eval.evaluate(&envelope_with_reset(96.0, reset)).await.unwrap();
        }
        assert_eq!(dispatcher.runner.specs.lock().unwrap().len(), 1);
        let state = store.load().unwrap();
        assert_eq!(state.entries.len(), 1, "one row per window, not per reset");
    }

    #[tokio::test]
    async fn recovery_below_the_threshold_clears_the_row() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(&dir);
        let runner = ScriptedNotify {
            specs: Mutex::new(Vec::new()),
            fail: false,
        };
        let dispatcher = NotifySendDispatcher::new(runner);
        let settings = SettingsDocument::defaults();
        let reset = datetime!(2026-08-21 22:00:00 UTC);
        let eval = NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: datetime!(2026-08-21 10:00:00 UTC),
        };
        eval.evaluate(&envelope_with_reset(96.0, reset)).await.unwrap();
        assert_eq!(store.load().unwrap().entries.len(), 1);
        eval.evaluate(&envelope_with_reset(10.0, reset)).await.unwrap();
        assert!(store.load().unwrap().entries.is_empty());
    }
```

- [ ] **Step 9: Run and confirm the crate does not compile**

Run: `cargo test --lib notifications::`
Expected: FAIL to compile. A `cargo test` filter selects which tests run, not
what gets built, so the whole lib target must compile first — and
`src/notifications/mod.rs` still calls `state.remove_key(id, window.id(), window.resets_at())`
with three arguments and `state.level_for(...)`, both of which Step 5 removed.
That compile error is this step's expected red state.

- [ ] **Step 10: Adapt the evaluator to the new key**

Three mechanical edits inside `evaluate` in `src/notifications/mod.rs`. The
emission algorithm itself does not change here — Task 3 owns that.

The rearm call loses its reset argument:

```rust
                let Some(level) = NotificationLevel::from_used_percent(used) else {
                    // Recovery below the warning threshold rearms.
                    state.remove_key(id, window.id());
                    continue;
                };
```

The lookup moves to `entry_for`:

```rust
                let prev = state.entry_for(id, window.id()).map(|e| e.level);
```

And the row written after a successful dispatch gains its timestamp:

```rust
                    state.upsert(NotificationEntry {
                        provider_id: item.provider_id.as_str().to_owned(),
                        window_id: item.window_id.clone(),
                        reset_at: item.reset_at,
                        level: item.level,
                        notified_at: self.now,
                    });
```

- [ ] **Step 11: Run the tests and confirm they pass**

Run: `cargo test --lib notifications::`
Expected: PASS, including the pre-existing
`escalates_warning_then_critical_once_each` and both new integration tests.
`sub_second_reset_jitter_does_not_renotify` passing is the incident fixed.

- [ ] **Step 12: Commit**

```bash
git add src/notifications/state.rs src/notifications/mod.rs
git commit -m "fix: key notification state by window, not reset"
```

---

### Task 2: Settings gain `reminderMinutes`

**Files:**
- Modify: `src/settings/schema.rs`
- Modify: `src/settings/migration.rs:451-465`
- Modify: `schemas/settings-v1.schema.json:41-51`
- Create: `tests/fixtures/settings-v1/invalid-reminder-minutes.json`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `NotificationSettings { enabled: bool, reminder_minutes: u32 }`,
  `DEFAULT_REMINDER_MINUTES: u32 = 120`, `MIN_REMINDER_MINUTES: u32 = 15`,
  `MAX_REMINDER_MINUTES: u32 = 1440`. Task 3 reads
  `settings.notifications.reminder_minutes`.

Three independent gates enforce the closed key set and all three must change
together, or the field is rejected somewhere despite looking correct
everywhere else: the struct's `deny_unknown_fields`, the hand-written
allowlist in `reject_unknown_top_level` (`src/settings/schema.rs:227`), and
`schemas/settings-v1.schema.json`. The top-level `ALLOWED` array does NOT
change — `reminderMinutes` nests under the already-allowed `notifications`.

- [ ] **Step 1: Write the failing tests**

Add to `#[cfg(test)] mod tests` in `src/settings/schema.rs`, matching the
existing verb-first snake_case style:

```rust
    #[test]
    fn reminder_minutes_defaults_when_absent() {
        // Settings reads never rewrite (SET-007), so an existing settings.json
        // predating this field must parse and take the default silently.
        let doc = br#"{"schemaVersion":1,"providers":[{"id":"claude","enabled":true},{"id":"codex","enabled":true},{"id":"amp","enabled":true},{"id":"grok","enabled":true}],"display":{"metric":"remaining"},"refreshIntervalSeconds":60,"notifications":{"enabled":true}}"#;
        let parsed = Settings::parse_strict(doc).unwrap();
        assert_eq!(parsed.notifications.reminder_minutes, DEFAULT_REMINDER_MINUTES);
        assert_eq!(parsed.notifications.reminder_minutes, 120);
    }

    #[test]
    fn reminder_minutes_round_trips_and_rejects_out_of_range() {
        let mut doc = Settings::defaults();
        doc.notifications.reminder_minutes = MIN_REMINDER_MINUTES;
        doc.validate().unwrap();
        doc.notifications.reminder_minutes = MAX_REMINDER_MINUTES;
        doc.validate().unwrap();

        doc.notifications.reminder_minutes = MIN_REMINDER_MINUTES - 1;
        let err = doc.validate().unwrap_err();
        assert!(err.message().contains("reminderMinutes"));

        doc.notifications.reminder_minutes = MAX_REMINDER_MINUTES + 1;
        assert!(doc.validate().is_err());
    }

    #[test]
    fn reminder_minutes_survives_the_hand_written_allowlist() {
        // deny_unknown_fields is not the only gate: reject_unknown_top_level
        // walks raw JSON before deserialization and would reject the key on
        // its own.
        let doc = br#"{"schemaVersion":1,"providers":[{"id":"claude","enabled":true},{"id":"codex","enabled":true},{"id":"amp","enabled":true},{"id":"grok","enabled":true}],"display":{"metric":"remaining"},"refreshIntervalSeconds":60,"notifications":{"enabled":true,"reminderMinutes":240}}"#;
        let parsed = Settings::parse_strict(doc).unwrap();
        assert_eq!(parsed.notifications.reminder_minutes, 240);
    }
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cargo test --lib settings::schema`
Expected: compile errors — `DEFAULT_REMINDER_MINUTES`, `MIN_REMINDER_MINUTES`,
`MAX_REMINDER_MINUTES` and the field do not exist.

- [ ] **Step 3: Add the constants**

In `src/settings/schema.rs`, directly after `MIN_REFRESH`/`MAX_REFRESH`
(lines 12-13), matching their plain `const` style:

```rust
const MIN_REMINDER_MINUTES: u32 = 15;
const MAX_REMINDER_MINUTES: u32 = 1440;
/// Two hours. Hourly was judged too frequent by the product owner; the field
/// exists so this is a default, not a floor.
const DEFAULT_REMINDER_MINUTES: u32 = 120;

pub(crate) fn default_reminder_minutes() -> u32 {
    DEFAULT_REMINDER_MINUTES
}
```

The three constants stay private: the `#[cfg(test)] mod tests` block at the
bottom of this file is a descendant module reached through `use super::*`, so
Step 1's tests already see them. `default_reminder_minutes` must be
`pub(crate)`, and this is not conditional — `src/settings/mod.rs` declares
`pub mod migration;` and `pub mod schema;` as siblings, so a private function
in `schema` is unreachable from `migration` by any path, fully qualified or
not, and Step 5 would fail to compile with
"function `default_reminder_minutes` is private".

- [ ] **Step 4: Extend the struct**

Replace `NotificationSettings` (lines 63-68). A bare `#[serde(default)]` would
yield `0`, not 120, so the named default function is required:

```rust
/// Notifications block.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NotificationSettings {
    pub enabled: bool,
    /// Minutes between repeats of an alert that is still above its threshold.
    /// Optional on read so documents written before this field stay valid.
    #[serde(default = "default_reminder_minutes")]
    pub reminder_minutes: u32,
}
```

- [ ] **Step 5: Update both struct literals and both allowlists**

`Settings::defaults()` at line 134:

```rust
            notifications: NotificationSettings {
                enabled: true,
                reminder_minutes: DEFAULT_REMINDER_MINUTES,
            },
```

`src/settings/migration.rs` at line 456 — v9 documents have no reminder
concept, so this is the default, never a migrated value:

```rust
        notifications: NotificationSettings {
            enabled: notify_enabled,
            reminder_minutes: crate::settings::schema::default_reminder_minutes(),
        },
```

The range check, inserted in `validate()` immediately after the
`refresh_interval_seconds` block (line 160), copying its phrasing exactly:

```rust
        if !(MIN_REMINDER_MINUTES..=MAX_REMINDER_MINUTES)
            .contains(&self.notifications.reminder_minutes)
        {
            return Err(SettingsError::new(format!(
                "reminderMinutes must be in {MIN_REMINDER_MINUTES}..={MAX_REMINDER_MINUTES}"
            )));
        }
```

The hand-written allowlist at `src/settings/schema.rs:227`:

```rust
            if key != "enabled" && key != "reminderMinutes" {
```

- [ ] **Step 6: Update the JSON Schema**

In `schemas/settings-v1.schema.json`, replace the `notifications` block
(lines 41-51). `reminderMinutes` must NOT join `required` — two existing valid
fixtures omit it and `tests/schema_contract.rs` asserts they pass:

```json
    "notifications": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "enabled"
      ],
      "properties": {
        "enabled": {
          "type": "boolean"
        },
        "reminderMinutes": {
          "type": "integer",
          "minimum": 15,
          "maximum": 1440
        }
      }
    }
```

- [ ] **Step 7: Add the invalid fixture**

`tests/schema_contract.rs` auto-discovers `invalid-*.json` by filename prefix,
so this file needs no test-code change. Create
`tests/fixtures/settings-v1/invalid-reminder-minutes.json`:

```json
{
  "schemaVersion": 1,
  "providers": [
    { "id": "claude", "enabled": true },
    { "id": "codex", "enabled": true },
    { "id": "amp", "enabled": true },
    { "id": "grok", "enabled": true }
  ],
  "display": {
    "metric": "remaining"
  },
  "refreshIntervalSeconds": 60,
  "notifications": {
    "enabled": true,
    "reminderMinutes": 5
  }
}
```

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `cargo test --lib settings:: && cargo test --test schema_contract`
Expected: PASS, including the pre-existing
`defaults_validate_and_round_trip` and
`apply_raw_round_trip_matches_fixture_shape` — the latter compares
`valid-defaults.json` against `Settings::defaults()`, so it proves the serde
default and the constant agree.

- [ ] **Step 9: Commit**

```bash
git add src/settings/schema.rs src/settings/migration.rs \
  schemas/settings-v1.schema.json tests/fixtures/settings-v1/invalid-reminder-minutes.json
git commit -m "feat: add notifications.reminderMinutes setting"
```

---

### Task 3: Emission decision and reminder cadence

**Files:**
- Modify: `src/notifications/mod.rs` (`NotificationEvaluator::evaluate`)

**Interfaces:**
- Consumes: `NotificationState::same_window`, `entry_for`, and the `store_in`
  test helper from Task 1; `settings.notifications.reminder_minutes` from
  Task 2.
- Produces: an `evaluate` whose emission decision covers window advance,
  escalation, reminder, and de-escalation. Task 4 inserts pruning into the
  same function.

- [ ] **Step 1: Write the failing tests**

Add to `#[cfg(test)] mod tests` in `src/notifications/mod.rs`:

```rust
    #[tokio::test]
    async fn a_new_window_renotifies() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(&dir);
        let runner = ScriptedNotify {
            specs: Mutex::new(Vec::new()),
            fail: false,
        };
        let dispatcher = NotifySendDispatcher::new(runner);
        let settings = SettingsDocument::defaults();
        let eval = NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: datetime!(2026-08-21 10:31:56 UTC),
        };
        eval.evaluate(&envelope_with_reset(96.0, datetime!(2026-08-21 11:59:59 UTC)))
            .await
            .unwrap();
        eval.evaluate(&envelope_with_reset(96.0, datetime!(2026-08-28 11:59:59 UTC)))
            .await
            .unwrap();
        assert_eq!(dispatcher.runner.specs.lock().unwrap().len(), 2);
        let state = store.load().unwrap();
        assert_eq!(state.entries.len(), 1, "the advance replaces, never appends");
    }

    #[tokio::test]
    async fn the_same_level_repeats_only_after_the_reminder_elapses() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(&dir);
        let runner = ScriptedNotify {
            specs: Mutex::new(Vec::new()),
            fail: false,
        };
        let dispatcher = NotifySendDispatcher::new(runner);
        let settings = SettingsDocument::defaults(); // reminderMinutes == 120
        let reset = datetime!(2026-08-21 22:00:00 UTC);
        let first = datetime!(2026-08-21 10:00:00 UTC);
        let envelope = envelope_with_reset(96.0, reset);

        // A fresh evaluator per instant: `now` is a field, not an argument.
        NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: first,
        }
        .evaluate(&envelope)
        .await
        .unwrap();

        NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: first + time::Duration::minutes(119),
        }
        .evaluate(&envelope)
        .await
        .unwrap();
        assert_eq!(
            dispatcher.runner.specs.lock().unwrap().len(),
            1,
            "one minute short of the reminder must stay silent"
        );

        NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: first + time::Duration::minutes(120),
        }
        .evaluate(&envelope)
        .await
        .unwrap();
        assert_eq!(dispatcher.runner.specs.lock().unwrap().len(), 2);
    }

    #[tokio::test]
    async fn de_escalation_lowers_the_tracked_level_without_notifying() {
        // Critical -> Warning while still above 90 must not dispatch
        // (NOTIFY-002), but the stored level has to follow the window down.
        // If it stays Critical, the reminder arm never matches again and the
        // user stops hearing about a window that is still at 92 percent.
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(&dir);
        let runner = ScriptedNotify {
            specs: Mutex::new(Vec::new()),
            fail: false,
        };
        let dispatcher = NotifySendDispatcher::new(runner);
        let settings = SettingsDocument::defaults();
        let reset = datetime!(2026-08-21 22:00:00 UTC);
        let first = datetime!(2026-08-21 10:00:00 UTC);

        NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: first,
        }
        .evaluate(&envelope_with_reset(96.0, reset))
        .await
        .unwrap();

        NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: first + time::Duration::minutes(5),
        }
        .evaluate(&envelope_with_reset(92.0, reset))
        .await
        .unwrap();
        assert_eq!(
            dispatcher.runner.specs.lock().unwrap().len(),
            1,
            "dropping a level never speaks"
        );
        let state = store.load().unwrap();
        assert_eq!(state.entries[0].level, NotificationLevel::Warning);

        // The reminder now fires at the level the window is actually at.
        NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: first + time::Duration::minutes(121),
        }
        .evaluate(&envelope_with_reset(92.0, reset))
        .await
        .unwrap();
        assert_eq!(dispatcher.runner.specs.lock().unwrap().len(), 2);
    }
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cargo test --lib notifications::`
Expected: the crate compiles (Task 1 left it building) and three tests FAIL on
assertions, not on syntax:

- `a_new_window_renotifies` — 1 dispatch, expected 2. Task 1's carried-over
  logic only escalates, so a genuinely new window stays silent.
- `the_same_level_repeats_only_after_the_reminder_elapses` — 1 dispatch,
  expected 2 on the third evaluation.
- `de_escalation_lowers_the_tracked_level_without_notifying` — the stored
  level is still `Critical`.

- [ ] **Step 3: Rewrite the evaluation body**

Replace `evaluate`'s body, from the `enabled` guard through the dispatch loop:

```rust
    pub async fn evaluate(&self, envelope: &StatusEnvelope) -> Result<(), String> {
        if !self.settings.notifications.enabled {
            return Ok(());
        }
        let reminder = time::Duration::minutes(i64::from(
            self.settings.notifications.reminder_minutes,
        ));

        let mut state = self.store.load().map_err(|err| err.to_string())?;
        let order: Vec<ProviderId> = self.settings.providers.iter().map(|p| p.id.0).collect();

        // Collect candidates in settings provider order, then window order.
        let mut pending: Vec<PendingNotification> = Vec::new();
        for id in order {
            let Some(provider) = envelope.providers().iter().find(|p| p.id() == id) else {
                continue;
            };
            if provider.state() != ProviderState::Ready {
                // NOTIFY-006: stale/failures do not trigger.
                continue;
            }
            for window in provider.windows() {
                let used = window.used_percent();
                let observed = window.resets_at();
                let Some(level) = NotificationLevel::from_used_percent(used) else {
                    // Recovery below the warning threshold rearms.
                    state.remove_key(id, window.id());
                    continue;
                };
                let saved = state.entry_for(id, window.id()).cloned();
                let should_emit = match saved.as_ref() {
                    // Never spoken for this window.
                    None => true,
                    // The window advanced; a genuinely new quota period.
                    Some(prev)
                        if !NotificationState::same_window(prev.reset_at, observed) =>
                    {
                        true
                    }
                    // NOTIFY-002: severity only ever escalates.
                    Some(prev) if level > prev.level => true,
                    // Same severity: the reminder decides, not the poll.
                    Some(prev) if level == prev.level => {
                        self.now - prev.notified_at >= reminder
                    }
                    // De-escalation inside the same window. NOTIFY-002 forbids
                    // speaking, but the tracked severity must follow the window
                    // down or the reminder can never match again, silencing a
                    // window that is still above its threshold.
                    Some(prev) => {
                        state.upsert(NotificationEntry {
                            provider_id: id.as_str().to_owned(),
                            window_id: window.id().to_owned(),
                            reset_at: observed,
                            level,
                            notified_at: prev.notified_at,
                        });
                        false
                    }
                };
                if should_emit {
                    pending.push(PendingNotification {
                        provider_id: id,
                        provider_name: provider.name().to_owned(),
                        window_id: window.id().to_owned(),
                        window_label: window.label().to_owned(),
                        used_percent: used,
                        remaining_percent: window.remaining_percent(),
                        metric: self.settings.display.metric,
                        reset_at: observed,
                        reset_in: observed
                            .map(|ts| crate::support::countdown::reset_countdown(self.now, ts)),
                        level,
                    });
                }
            }
        }

        // Persist silent rearms and de-escalations first.
        self.store.save(&state).map_err(|err| err.to_string())?;

        for item in pending {
            match self.dispatcher.dispatch(&item).await {
                Ok(()) => {
                    state.upsert(NotificationEntry {
                        provider_id: item.provider_id.as_str().to_owned(),
                        window_id: item.window_id.clone(),
                        reset_at: item.reset_at,
                        level: item.level,
                        notified_at: self.now,
                    });
                    // Persist after each success (at-least-once algorithm).
                    self.store.save(&state).map_err(|err| err.to_string())?;
                }
                Err(err) => {
                    // Leave the row unadvanced; stop later notifications.
                    return Err(err);
                }
            }
        }
        Ok(())
    }
```

`saved` is cloned out of `state` before the match, so mutating `state` inside
the de-escalation arm does not conflict with the borrow.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cargo test --lib notifications::`
Expected: PASS, including the pre-existing
`escalates_warning_then_critical_once_each` — it evaluates three times at one
fixed `now`, so `now - notified_at` is zero and the reminder never fires,
leaving its assertion of exactly two dispatches intact.

- [ ] **Step 5: Commit**

```bash
git add src/notifications/mod.rs
git commit -m "feat: repeat alerts on a reminder, not per poll"
```

---

### Task 4: Prune elapsed and vanished windows

**Files:**
- Modify: `src/notifications/mod.rs` (`evaluate`, inside the provider loop)

**Interfaces:**
- Consumes: `NotificationState::prune_ready_provider` from Task 1.
- Produces: nothing new; bounds the state file to live windows.

- [ ] **Step 1: Write the failing tests**

```rust
    #[tokio::test]
    async fn evaluate_prunes_rows_for_windows_a_ready_provider_no_longer_reports() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(&dir);
        let mut seeded = NotificationState::empty();
        seeded.upsert(NotificationEntry {
            provider_id: "claude".into(),
            window_id: "weekly-model:retired".into(),
            reset_at: Some(datetime!(2026-08-28 12:00:00 UTC)),
            level: NotificationLevel::Critical,
            notified_at: datetime!(2026-08-20 10:00:00 UTC),
        });
        store.save(&seeded).unwrap();

        let runner = ScriptedNotify {
            specs: Mutex::new(Vec::new()),
            fail: false,
        };
        let dispatcher = NotifySendDispatcher::new(runner);
        let settings = SettingsDocument::defaults();
        NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: datetime!(2026-08-21 10:00:00 UTC),
        }
        .evaluate(&envelope_with_used(10.0))
        .await
        .unwrap();

        let state = store.load().unwrap();
        assert!(
            state.entries.is_empty(),
            "a window the provider stopped reporting must not linger forever"
        );
    }

    #[tokio::test]
    async fn evaluate_keeps_rows_for_providers_absent_from_the_envelope() {
        // Pruning is Ready-only. A provider missing from this envelope has
        // confirmed nothing, so its dedupe must survive or it notifies again
        // the moment it recovers. The sibling case — present but not Ready —
        // is covered by evaluate_keeps_rows_for_a_stale_provider below.
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(&dir);
        let mut seeded = NotificationState::empty();
        seeded.upsert(NotificationEntry {
            provider_id: "amp".into(),
            window_id: "daily".into(),
            reset_at: Some(datetime!(2026-08-12 00:00:00 UTC)),
            level: NotificationLevel::Critical,
            notified_at: datetime!(2026-08-11 23:00:00 UTC),
        });
        store.save(&seeded).unwrap();

        let runner = ScriptedNotify {
            specs: Mutex::new(Vec::new()),
            fail: false,
        };
        let dispatcher = NotifySendDispatcher::new(runner);
        let settings = SettingsDocument::defaults();
        NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: datetime!(2026-08-21 10:00:00 UTC),
        }
        .evaluate(&envelope_with_used(10.0))
        .await
        .unwrap();

        assert_eq!(store.load().unwrap().entries.len(), 1);
    }

    #[tokio::test]
    async fn evaluate_keeps_rows_for_a_stale_provider() {
        // Present in the envelope but not Ready: the provider confirmed
        // nothing this cycle, so neither pruning nor rearming may touch it
        // (NOTIFY-006). No pre-existing test covered this — the guard was
        // only a comment.
        use crate::status::schema::{ErrorCode, ProviderAction, ProviderError};

        let dir = tempfile::tempdir().unwrap();
        let store = store_in(&dir);
        let mut seeded = NotificationState::empty();
        seeded.upsert(NotificationEntry {
            provider_id: "claude".into(),
            window_id: "session".into(),
            reset_at: Some(datetime!(2026-08-12 00:00:00 UTC)),
            level: NotificationLevel::Critical,
            notified_at: datetime!(2026-08-11 23:00:00 UTC),
        });
        store.save(&seeded).unwrap();

        let window = UsageWindow::try_new("session", "Session", 5.0, 95.0, None).unwrap();
        let stale = ProviderStatus::stale(
            ProviderId::Claude,
            "Claude",
            None,
            None,
            vec![window],
            datetime!(2026-08-20 10:00:00 UTC),
            ProviderError::new(ErrorCode::NetworkError, "Network error.", true),
            ProviderAction::retry("Retry"),
        )
        .unwrap();
        let envelope = StatusEnvelope::try_new_for_package(
            datetime!(2026-08-21 10:00:00 UTC),
            StatusRequest {
                provider: None,
                cache: CacheMode::Use,
            },
            vec![stale],
        )
        .unwrap();

        let runner = ScriptedNotify {
            specs: Mutex::new(Vec::new()),
            fail: false,
        };
        let dispatcher = NotifySendDispatcher::new(runner);
        let settings = SettingsDocument::defaults();
        NotificationEvaluator {
            store: &store,
            dispatcher: &dispatcher,
            settings: &settings,
            now: datetime!(2026-08-21 10:00:00 UTC),
        }
        .evaluate(&envelope)
        .await
        .unwrap();

        assert_eq!(store.load().unwrap().entries.len(), 1);
        assert!(dispatcher.runner.specs.lock().unwrap().is_empty());
    }
```

`envelope_with_used` builds a Claude-only envelope with a single `session`
window at `DataSource::Live`, which is what the first two tests need: Claude
is Ready and live with one window, and Amp never appears.

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cargo test --lib notifications::`
Expected: `evaluate_prunes_rows_for_windows_a_ready_provider_no_longer_reports`
FAILS with the retired row still present. The other two pass already — they are
the guards that keep the fix from over-reaching, and a fix that breaks them is
worse than no fix.

- [ ] **Step 3: Prune before evaluating the provider's windows**

In `evaluate`, immediately after the `ProviderState::Ready` guard and before
the `for window in provider.windows()` loop:

```rust
            // Pruning runs before the window loop, so the rearms, upserts and
            // de-escalations below are never undone by it. The elapsed-reset
            // branch needs a live reading: a Ready provider can be replayed
            // from cache for up to its TTL while still reporting the
            // pre-reset timestamp, and treating that as proof the window
            // restarted would fire an alert about a window that already reset.
            let live_reading = provider.source() == Some(DataSource::Live);
            let live: Vec<&str> = provider.windows().iter().map(|w| w.id()).collect();
            state.prune_ready_provider(id, &live, self.now, live_reading);
```

Add `DataSource` to the existing status-schema import at the top of
`src/notifications/mod.rs`:

```rust
use crate::status::schema::{DataSource, ProviderState, StatusEnvelope};
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cargo test --lib notifications::`
Expected: PASS, all tests from Tasks 1, 3 and 4.

- [ ] **Step 5: Commit**

```bash
git add src/notifications/mod.rs
git commit -m "feat: prune stale notification rows"
```

---

### Task 5: Make persistence failure visible

**Files:**
- Modify: `src/notifications/mod.rs` (dispatch loop)
- Modify: `src/status/coordinator.rs:214-216`

**Interfaces:**
- Consumes: the dispatch loop from Task 3.
- Produces: no API change.

This task has no unit test. The repository has zero precedent for asserting on
`log::warn!` output — the two existing call sites (`src/cache/store.rs:168`
and `quarantine()` in `src/notifications/state.rs:261`) are both untested, and
inventing a log-capture harness for two lines is not worth a new test pattern.
Step 4 verifies it by reproducing the original incident instead, which is
stronger evidence than a string assertion.

- [ ] **Step 1: Name the failing window in the notification module**

In `evaluate`'s dispatch loop, replace the `self.store.save(&state).map_err(|err| err.to_string())?;`
that follows a successful dispatch with:

```rust
                    if let Err(err) = self.store.save(&state) {
                        // The incident this replaces ran for days behind a bare
                        // stderr line nobody reads.
                        log::warn!(
                            "notification state save failed for {}/{}: {err}",
                            item.provider_id.as_str(),
                            item.window_id
                        );
                        return Err(err.to_string());
                    }
```

- [ ] **Step 2: Replace the bare stderr print at the call site**

`src/status/coordinator.rs` line 215:

```rust
            if let Err(err) = evaluator.evaluate(&envelope).await {
                log::warn!("notification evaluation failed: {err}");
            }
```

`log` is already a dependency (`Cargo.toml:29`) and `main.rs` initializes
`env_logger` at `LevelFilter::Warn` to stderr, so this prints by default. No
`Cargo.toml` change.

- [ ] **Step 3: Run the full suite**

Run: `cargo test`
Expected: PASS. `cargo clippy --all-targets -- -D warnings` must also be clean —
an unused `err` binding or a stray `eprintln!` import will fail it.

- [ ] **Step 4: Reproduce the original incident and confirm it is fixed**

Build the helper and run it three times against a frozen cache with a
`notify-send` shim, exactly as the incident was diagnosed:

```bash
cargo build --release
LAB=$(mktemp -d)
mkdir -p "$LAB/cache/agent-bar" "$LAB/config/agent-bar" "$LAB/bin"
cp ~/.cache/agent-bar/status-v2.json "$LAB/cache/agent-bar/"
cp ~/.config/agent-bar/settings.json "$LAB/config/agent-bar/"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "NOTIFY: $*" >> "$NOTIFY_LOG"\nexit 0\n' > "$LAB/bin/notify-send"
chmod +x "$LAB/bin/notify-send"
python3 - "$LAB/cache/agent-bar/status-v2.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
for v in d["providers"].values(): v["expiresAt"]="2027-01-01T00:00:00Z"
json.dump(d,open(p,"w"),indent=1)
PY
export XDG_CACHE_HOME="$LAB/cache" XDG_CONFIG_HOME="$LAB/config"
export NOTIFY_LOG="$LAB/notify.log" PATH="$LAB/bin:$PATH"
: > "$NOTIFY_LOG"
for i in 1 2 3; do
  ./target/release/agent-bar status format json cache use notifications evaluate \
    >/dev/null 2>>"$LAB/err.log"
done
echo "dispatches: $(wc -l < "$NOTIFY_LOG")"
cat "$LAB/err.log"
cat "$LAB/cache/agent-bar/notification-state-v2.json"
```

Expected: `dispatches: 1` (or `0` if the seeded cache is below 90%), empty
`err.log`, and a state file holding exactly one row per above-threshold
window. Before this plan the same script produced three dispatches, three
`duplicate notification key` lines, and zero rows. If the local
`settings.json` still has `"enabled": false` from the incident mitigation, set
it to `true` inside `$LAB` only — never in `~/.config`.

- [ ] **Step 5: Commit**

```bash
git add src/notifications/mod.rs src/status/coordinator.rs
git commit -m "fix: log notification persistence failures"
```

---

### Task 6: Retire the v1 state file

**Files:**
- Modify: `src/plugin/doctor.rs:39-59`

**Interfaces:**
- Consumes: the v2 filename from Task 1.
- Produces: no API change.

- [ ] **Step 1: Write the failing test**

Add to the inline `#[cfg(test)] mod tests` in `src/plugin/doctor.rs`. This
assertion needs no filesystem, so it does not depend on the
`seed_owned_legacy_file` harness the other doctor tests use:

```rust
    #[test]
    fn legacy_candidates_include_the_v1_notification_state() {
        let home = Path::new("/home/example");
        let candidates = default_legacy_candidates(home);
        assert!(candidates
            .contains(&home.join(".cache/agent-bar/notification-state-v1.json")));
        // The v9 filename stays listed; v1 joins it rather than replacing it.
        assert!(candidates.contains(&home.join(".cache/agent-bar/notify-state.json")));
    }
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cargo test --lib plugin::doctor`
Expected: FAIL — the v1 path is not in the list.

- [ ] **Step 3: Add the entry**

In `default_legacy_candidates`, extend the existing v9 comment block:

```rust
        // Old notification state filenames (v9, and v1 superseded by v2)
        cache.join("agent-bar/notify-state.json"),
        cache.join("agent-bar/notification-state-v1.json"),
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cargo test --lib plugin::doctor`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/plugin/doctor.rs
git commit -m "chore: list v1 notification state as legacy"
```

---

### Task 7: Settings UI for the reminder

**Files:**
- Modify: `CoreService.js:303-316` (`defaultSettings`)
- Modify: `CoreSettings.js` (setter near line 215, validator near line 234)
- Modify: `Service.qml` (setter wrapper near line 229)
- Modify: `SettingsView.qml` (read model near line 42, Notifications block at 246-264)
- Test: `tests/qml/tst_Settings.qml`
- Test: `tests/qml/tst_SettingsRaces.qml`

**Interfaces:**
- Consumes: the `reminderMinutes` wire field from Task 2.
- Produces: `Core.setReminderMinutes(draft, minutes)`,
  `Service.setReminderMinutes(minutes)`, and the draft key
  `draft.notifications.reminderMinutes`.

The Rust read path fills the serde default before `config show` prints, so the
key is always present in a loaded draft. The validator may therefore require
it, exactly like every other field — no accept-if-absent branch, which would
be a pattern this file does not have.

The bounds are duplicated between the validator and the `NumberField`, matching
how `refreshIntervalSeconds` already spells `30`/`3600` in both places. Do not
introduce a shared constant here; that would be a new pattern, not the
surrounding one.

- [ ] **Step 1: Write the failing tests**

Add to `tests/qml/tst_Settings.qml`, following its existing
`test_display_metric_and_interval_bounds` shape:

```qml
  function test_reminder_minutes_bounds() {
    var d = Service.defaultSettings()
    compare(d.notifications.reminderMinutes, 120)
    compare(Core.validateSettingsDraft(d).ok, true)

    d = Core.setReminderMinutes(d, 15)
    compare(d.notifications.reminderMinutes, 15)
    d = Core.setReminderMinutes(d, 1440)
    compare(d.notifications.reminderMinutes, 1440)

    var bad = Core.setReminderMinutes(d, 5)
    compare(Core.validateSettingsDraft(bad).ok, false)
    bad = Core.setReminderMinutes(d, 2000)
    compare(Core.validateSettingsDraft(bad).ok, false)
  }
```

And extend the existing `test_settings_view_source_contracts` with the exact
copy this task ships — this suite treats near-miss label text as a contract
violation, so the strings are pinned here and nowhere else:

```qml
    verify(src.indexOf("Remind me every") >= 0)
    verify(src.indexOf('text: "minutes"') >= 0)
```

- [ ] **Step 2: Write the failing race test**

The spec requires the new control to hold under an in-flight save, not just in
isolation. Add to `tests/qml/tst_SettingsRaces.qml`, mirroring
`test_payload_immutable_after_edit_during_save`:

```qml
  function test_reminder_minutes_immutable_after_edit_during_save() {
    h.reset()
    h.openSettings("a")
    h.applyRead(h.activeSettingsReadGeneration, Service.defaultSettings(), 0)
    h.mutate(function (d) { return Core.setReminderMinutes(d, 240) })
    h.save()
    var captured = JSON.parse(h.pendingSettingsPayload)
    compare(captured.notifications.reminderMinutes, 240)
    // Edits while saving are locked
    h.mutate(function (d) { return Core.setReminderMinutes(d, 60) })
    compare(JSON.parse(h.pendingSettingsPayload).notifications.reminderMinutes, 240)
    compare(h.settingsState.pendingPayload.notifications.reminderMinutes, 240)
  }
```

The harness needs no change: `h.mutate` takes any mutator, and
`Core`/`Service` already alias `CoreSettings.js`/`CoreService.js` at the top
of the file.

- [ ] **Step 3: Run the tests and confirm they fail**

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 QT_LOGGING_TO_CONSOLE=1 \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml \
  -import /usr/share/omarchy/shell -import . -o -,txt
```

Expected: both new tests FAIL. `test_reminder_minutes_bounds` fails — `Core.setReminderMinutes` is
not a function and `d.notifications.reminderMinutes` is `undefined`. Use the
Qt6 binary path: the `PATH` `qmltestrunner` is Qt5 and fails silently, writing
errors only to journald.

- [ ] **Step 4: Add the default to the QML-side canonical draft**

`CoreService.js`, in `defaultSettings()`:

```js
    notifications: { enabled: true, reminderMinutes: 120 }
```

- [ ] **Step 5: Add the setter and the validation**

`CoreSettings.js`, immediately after `setNotificationsEnabled` (line 221),
mirroring its lazy-init and `setRefreshInterval`'s non-clamping rounding — an
out-of-range value must reach the validator, not be silently corrected:

```js
function setReminderMinutes(draft, minutes) {
  var next = cloneDraft(draft)
  if (!next.notifications)
    next.notifications = { enabled: true, reminderMinutes: 120 }
  var n = Math.round(Number(minutes))
  if (!isFinite(n))
    n = 120
  next.notifications.reminderMinutes = n
  return next
}
```

In `validateSettingsDraft`, replace the single notifications branch (line
233-234) with:

```js
  if (!draft.notifications || typeof draft.notifications.enabled !== "boolean")
    return { ok: false, reason: "notifications" }
  var reminder = Number(draft.notifications.reminderMinutes)
  if (!isFinite(reminder) || reminder !== Math.floor(reminder)
      || reminder < 15 || reminder > 1440)
    return { ok: false, reason: "notifications.reminderMinutes" }
```

- [ ] **Step 6: Wire the service method**

`Service.qml`, directly after `setNotificationsEnabled` (line 233):

```qml
  function setReminderMinutes(minutes) {
    mutateSettingsDraft(function (d) {
      return Settings.setReminderMinutes(d, minutes)
    })
  }
```

No `IpcHandler` function is added — that handler exposes only `health` and
`refresh`, and settings never travel through it.

- [ ] **Step 7: Add the control**

`SettingsView.qml`, alongside `intervalSec` (line 42):

```qml
  readonly property int reminderMinutes: {
    if (draft && draft.notifications
        && isFinite(Number(draft.notifications.reminderMinutes)))
      return Number(draft.notifications.reminderMinutes)
    return 120
  }
```

Then, inside the existing Notifications `Column`, directly below the `Toggle`
block, copying the "Refresh every" Row verbatim in structure — including the
sibling-label technique, which exists because the host `NumberField` has no
suffix property and the spin box cannot be anchored from a sibling:

```qml
      Row {
        spacing: Style.spacing.lg

        NumberField {
          id: reminderField
          label: "Remind me every"
          value: root.reminderMinutes
          from: 15
          to: 1440
          stepSize: 15
          foreground: root.foreground
          fontFamily: root.fontFamily
          onModified: function (v) {
            if (root.agentService)
              root.agentService.setReminderMinutes(v)
          }
        }

        // Same sibling-label technique as the refresh interval above: the
        // host NumberField exposes no suffix property, and the spin box is a
        // child of a sibling, which QML refuses to anchor to.
        Text {
          y: reminderField.y + reminderField.field.y
             + (reminderField.field.height - height) / 2
          text: "minutes"
          color: Util.alpha(root.foreground, 0.72)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          Accessible.ignored: true
        }
      }
```

The enclosing `Column` already carries `opacity: root.locked ? 0.55 : 1.0` and
`enabled: !root.locked`, so the new field inherits the locked state with no
extra binding.

- [ ] **Step 8: Run the QML gates**

```bash
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell ./*.qml components/*.qml
omarchy plugin validate .
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 QT_LOGGING_TO_CONSOLE=1 \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml \
  -import /usr/share/omarchy/shell -import . -o -,txt
```

Expected: `qmltestrunner` PASSES every case including
`test_settings_view_source_contracts` and `tst_SettingsRaces`. `qmllint` exits
0 while printing the usual `qs.*` unresolved-import and unqualified-access
warnings for every plugin file; read its output only for warnings your change
introduced, and never treat its exit code as a verdict.

- [ ] **Step 9: Commit**

```bash
git add CoreService.js CoreSettings.js Service.qml SettingsView.qml \
  tests/qml/tst_Settings.qml tests/qml/tst_SettingsRaces.qml
git commit -m "feat: settings control for reminder cadence"
```

---

### Task 8: Amend the specification and docs

**Files:**
- Modify: `docs/specs/v10/05-settings-cache-and-notifications.md` (lines 8-22, 76, 184-199)
- Modify: `docs/specs/v10/REQUIREMENTS_MATRIX.md:94`
- Modify: `docs/guide/runtime.md:11`
- Modify: `docs/guide/commands.md:61`
- Modify: `CHANGELOG.md` (`## [Unreleased]`)

**Interfaces:**
- Consumes: every behaviour from Tasks 1-7.
- Produces: the written contract those tasks now implement.

All of this text is active documentation: plain-ASCII English only, or
`tests/active_language.rs` fails the build. Every ```json fence in an active
doc is validated against `schemas/settings-v1.schema.json` by
`tests/active_docs.rs`, so the canonical example must stay schema-valid.

- [ ] **Step 1: Rewrite the NOTIFY requirements**

Replace `NOTIFY-001` (lines 184-185):

```markdown
- `NOTIFY-001`: Notification key is provider ID and window ID. The reset
  timestamp is recorded as an observation, never as identity: providers may
  derive it from their own clock and return a different value for the same
  window on every collection.
```

Replace `NOTIFY-003` (lines 187-188):

```markdown
- `NOTIFY-003`: While a window stays at the same severity, the alert repeats at
  most once per `notifications.reminderMinutes`, measured from the last
  successful dispatch.
```

Replace `NOTIFY-005` (lines 190-191):

```markdown
- `NOTIFY-005`: Recovery below 90, a change between `null` and a timestamp, or
  a reset moving by more than the jitter tolerance silently rearms. A window
  the provider stops reporting is pruned, and so is one whose reset has
  elapsed; both only while that provider is `ready`.
```

Add after `NOTIFY-012`:

```markdown
- `NOTIFY-013`: Two observed resets describe the same window when they differ
  by at most 60 seconds. Sub-second drift is expected: a provider may compute
  `resets_at` from its own clock per response.
- `NOTIFY-014`: `notifications.reminderMinutes` is an integer in `15..=1440`,
  default `120`. It is optional on read so documents written before the field
  existed stay valid, and is written on every explicit apply.
```

- [ ] **Step 2: Update the cache file list and the canonical settings example**

Line 76 of the same file:

```text
$XDG_CACHE_HOME/agent-bar/notification-state-v2.json
```

And the canonical settings block near line 8:

```json
  "notifications": {
    "enabled": true,
    "reminderMinutes": 120
  }
```

- [ ] **Step 3: Update the remaining docs**

`docs/guide/runtime.md` line 11:

```markdown
| `$XDG_CACHE_HOME/agent-bar/notification-state-v2.json` | Alert deduplication |
```

`docs/guide/commands.md` line 61 — the inline `config apply json` example ends
with `"notifications":{"enabled":true}`; make it
`"notifications":{"enabled":true,"reminderMinutes":120}`.

`docs/specs/v10/REQUIREMENTS_MATRIX.md` line 94, extended to cover the two new
IDs in the existing row format:

```markdown
| `NOTIFY-001`–`NOTIFY-010` | 7 | transition, persistence, recovery, dispatch tests |
| `NOTIFY-013`–`NOTIFY-014` | 7 | jitter-tolerance, reminder-cadence, settings-range tests |
```

Leave `docs/specs/v10/09-implementation-plan.md` alone: its settings example
omits `reminderMinutes`, which is exactly the optional-on-read case, and it
stays schema-valid.

- [ ] **Step 4: Write the changelog entry**

Under `## [Unreleased]` in `CHANGELOG.md`:

```markdown
### Changed

- fix: key notification state by window, not reset
- feat: repeat alerts on a configurable reminder
```

- [ ] **Step 5: Run the documentation gates**

Run: `cargo test --test active_docs && cargo test --test active_language && cargo test`
Expected: PASS. `active_language` fails on any non-ASCII letter; `active_docs`
fails if a JSON fence stops validating or a relative Markdown link breaks.

- [ ] **Step 6: Commit**

```bash
git add docs/specs/v10/05-settings-cache-and-notifications.md \
  docs/specs/v10/REQUIREMENTS_MATRIX.md docs/guide/runtime.md \
  docs/guide/commands.md CHANGELOG.md
git commit -m "docs: amend NOTIFY contract for window keys"
```

---

## Final checkpoint

Run every gate from Global Constraints, in one pass, before declaring the work
done:

```bash
cargo fmt --check
cargo test
cargo clippy --all-targets -- -D warnings
git diff --check
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell ./*.qml components/*.qml
omarchy plugin validate .
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 QT_LOGGING_TO_CONSOLE=1 \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml \
  -import /usr/share/omarchy/shell -import . -o -,txt
```

Then review the diff for secrets, shell construction, legacy leakage, and
unrelated changes, and stop at the mandatory checkpoint. Do not merge, tag, or
publish.

Live QA, on the authorized gate only: re-enable notifications
(`notifications.enabled` was set to `false` while this bug was mitigated),
confirm the bar still shows the Fable window above 95 percent, and confirm one
notification arrives per `reminderMinutes` instead of one per poll, with
`notification-state-v2.json` holding one row per window.
