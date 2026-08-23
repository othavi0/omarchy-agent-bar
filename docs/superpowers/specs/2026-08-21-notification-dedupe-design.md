# Notification deduplication and reminder cadence

Date: 2026-08-21
Status: proposed
Area: `src/notifications`, `src/settings`, `SettingsView.qml`

## Problem

A live install emitted `Claude Fable is almost out` once every 60 seconds for
hours. The alert was not re-triggering: the deduplication state failed to
persist on every cycle, so the notifier never learned it had already spoken.

Reproduced 3/3 against the installed helper (10.3.10) with an isolated
`XDG_CACHE_HOME` and a `notify-send` shim:

```text
run 1 stderr: notification dispatch failed: duplicate notification key
run 2 stderr: notification dispatch failed: duplicate notification key
run 3 stderr: notification dispatch failed: duplicate notification key
→ 3 dispatches, 0 entries written
```

Removing the colliding entry from the state file dropped it to 1 dispatch
across 3 runs with clean stderr. The escalation algorithm itself is sound.

## Root cause

`NotificationState::validate` derives its uniqueness key by truncating the
reset timestamp to whole seconds (`state.rs:90`,
`entry.reset_at.map(|t| t.unix_timestamp())`), while `upsert`, `level_for`, and
`remove_key` compare the full `OffsetDateTime`, nanoseconds included
(`state.rs:124`, `state.rs:136`).

The Claude usage endpoint returns `resets_at` with sub-second jitter. Measured
on a live cache, the same logical reset of `weekly-model:fable`:

```text
11:59:59.711745Z    collected 10:31:56
11:59:59.707742Z    collected 10:37:56
11:59:59.854947Z    persisted
12:00:00.024238Z    persisted
```

Within a single envelope the three Claude windows carry `.776731`, `.776754`,
and `.777029`, so each `resets_at` is derived from its own `now` server-side.
**Two Claude collections never produce the same key.** Codex returns epoch
seconds and is stable; Amp reports no reset (canonical `null` key).

The failure sequence: the first dispatch persists `.854947`. The next live
collection observes `.707742` — same second, different nanoseconds. `upsert`
does not recognise it as the same key and appends instead of replacing;
`validate` truncates both to `11:59:59` and rejects the document. `save`
returns `Err`, `evaluate` aborts, the level is never recorded, and the next
poll 60 seconds later notifies again — indefinitely.

Four aggravating factors:

1. **`resetAt` is identity, not data.** Even with the key mismatch fixed, jitter
   changes the key on every live collection, so Claude re-notifies each TTL
   (300s) while above threshold. `NOTIFY-001`/`NOTIFY-005` assume a stable
   timestamp the provider does not supply.
2. **Writes are all-or-nothing.** One colliding Claude window blocks
   persistence for every provider in the document.
3. **No pruning.** The live file held Amp entries from 8 and 12 August — 13 and
   9 days stale — each a future collision candidate.
4. **Silent failure.** `coordinator.rs:215` prints to stderr and nothing else.
   The defect ran for days without a single signal; finding it required
   instrumenting `notify-send`.

No existing test covers this: every fixture in the suite uses round
timestamps, so the sub-second path is unreachable from the current tests.

## Goals

- One notification per window per severity, repeated on a user-controlled
  cadence rather than every poll.
- Deduplication that survives a provider whose reset timestamp is never
  byte-identical twice.
- Persistence failure that is structurally impossible for the duplicate-key
  reason, and visible when it happens for any other reason.

## Non-goals

- Per-provider notification settings.
- Changing the 90/95 thresholds or their parity with `CoreView.js`.
- Changing the published status schema v2, including the `resetsAt` value.
- Notification history or an in-popup alert log.

## Design

### Notification state v2

A new file, `$XDG_CACHE_HOME/agent-bar/notification-state-v2.json`, reusing the
existing `notification.lock`. No content migration: the state is ephemeral, and
losing it costs at most one repeated notification, which `NOTIFY-012` already
permits. `notification-state-v1.json` joins the doctor's legacy list next to
the v9 `notify-state.json`.

```json
{
  "schemaVersion": 2,
  "entries": [
    {
      "providerId": "claude",
      "windowId": "weekly-model:fable",
      "level": "critical",
      "resetAt": "2026-08-21T11:59:59.777029Z",
      "notifiedAt": "2026-08-21T10:31:56Z"
    }
  ]
}
```

- The key is `(providerId, windowId)`, unique per document.
- `resetAt` is the last observed reset, nullable, retained as evidence rather
  than identity.
- `notifiedAt` is the instant of the last successful dispatch, RFC3339.

### One key definition

`validate`, `upsert`, `level_for`, and `remove_key` all route through a single
key function. Four hand-written comparisons are what allowed the current
divergence; the fix is not to correct them in parallel but to leave one.

Consequence worth stating plainly: with a per-window key and an `upsert` that
removes by that same key, `DuplicateKey` becomes unreachable on write. The
failure mode that caused this incident stops depending on discipline.

### Window identity and rearm

`RESET_JITTER_TOLERANCE: Duration = 60s`.

```text
same_window(saved, observed):
  (None,    None)    -> true
  (Some,    None)    -> false      # NOTIFY-005, explicit
  (None,    Some)    -> false      # NOTIFY-005, explicit
  (Some(a), Some(b)) -> |a - b| <= RESET_JITTER_TOLERANCE
```

60 seconds swallows millisecond jitter with four orders of magnitude to spare
and stays negligible against any real window (5h / 7d). The comparison is
absolute so a reset that moves backwards also rearms.

### Emission decision

Per window of a `Ready` provider, with `level = from_used_percent(used)`:

```text
level is None                                  -> remove entry, no dispatch
saved is None                                  -> dispatch
!same_window(saved.resetAt, observed)          -> dispatch (window advanced)
level > saved.level                            -> dispatch (escalation)
level == saved.level
  && now - saved.notifiedAt >= reminder        -> dispatch (reminder)
otherwise                                      -> skip
```

`level < saved.level` never dispatches, preserving `NOTIFY-002`. A successful
dispatch replaces the entry with the observed reset, the new level, and
`notifiedAt = now`.

### Reminder cadence

`settings.notifications.reminderMinutes`, integer, `15..=1440`, default `120`.

The default is two hours because the owner judged hourly too frequent. It is a
default, not a floor: the field exists so it can be tuned without a rebuild.

The field is optional on read with a serde default, so existing `settings.json`
files stay valid and are never rewritten (`SET-007`); it is written on every
explicit apply, so the canonical document gains it on first save.

There is deliberately no "never" value: notify-once is no longer reachable,
and users who want silence use the existing toggle. This is a product decision,
flagged under Open decisions below.

### Pruning

Inside `evaluate`, before persisting:

Both rules apply only to providers in `Ready`, so a provider in error or serving
stale data keeps its deduplication and does not notify again on recovery.

- Entries whose `resetAt` is in the past are dropped — an elapsed reset means
  the window restarted, so rearming is correct.
- Entries for windows absent from the envelope are dropped.

Restricting elapsed-reset pruning to `Ready` matters: pruning on stale data
would rearm against a reading the provider has not confirmed, producing a
notification about a window that may already have reset.

The file is also naturally bounded now: at most one row per live window.

### Observability

- Persistence failure becomes a structured `log::warn!` naming the provider and
  window, replacing the bare `eprintln!` at `coordinator.rs:215`. Provider and
  window IDs are catalog constants, not user data.
- `doctor` parses the v2 state, reports it unreadable or non-unique, and lists
  the v1 file as removable legacy.

## Spec amendments

`docs/specs/v10/05-settings-cache-and-notifications.md`:

- `NOTIFY-001` — key becomes provider ID and window ID. The reset timestamp is
  recorded as an observation, not as identity.
- `NOTIFY-003` — the same severity repeats at most once per
  `reminderMinutes` while the window stays above its threshold, instead of once
  per key.
- `NOTIFY-005` — rearm on recovery below 90, on a `null`/timestamp transition,
  or on a reset moving by more than the jitter tolerance.
- New `NOTIFY-013` — the 60s jitter tolerance and the provider behaviour that
  motivates it.
- New `NOTIFY-014` — `reminderMinutes`, its range, and its default of 120.
- Cache file list gains `notification-state-v2.json`.
- `SET-*` — the new settings key, optional on read, canonical on write.

`REQUIREMENTS_MATRIX.md`, `docs/guide/runtime.md` (paths), and `CHANGELOG.md`
follow.

## Surface

| File | Change |
| --- | --- |
| `src/notifications/state.rs` | v2 schema, single key function, tolerance, path |
| `src/notifications/mod.rs` | emission decision, reminder, pruning |
| `src/status/coordinator.rs` | structured warn on persistence failure |
| `src/settings/schema.rs` | `reminderMinutes` field, allowed key, range validation |
| `src/settings/migration.rs` | v9 migration emits the default (120) |
| `schemas/settings-v1.schema.json` | optional integer property |
| `src/plugin/doctor.rs` | v2 state check, v1 legacy entry |
| `CoreSettings.js` | draft validation and setter |
| `SettingsView.qml` | `NumberField` "Remind me every / minutes" |
| `Service.qml` | settings write path for the new field |

## Testing

Written first, each confirmed failing before implementation.

Rust:

- sub-second jitter across consecutive cycles dispatches once;
- a real window advance (+7d) dispatches again;
- `null` to timestamp and back rearms;
- N jittered cycles leave exactly one entry;
- direct regression: the live v1 document that produced
  `duplicate notification key` no longer blocks persistence;
- reminder fires at the boundary and not before;
- pruning drops elapsed resets and absent `Ready` windows, and keeps entries
  for stale providers;
- settings: missing `reminderMinutes` defaults to 120, out-of-range is rejected,
  apply returns it in the canonical document.

Fixtures gain sub-second timestamps, which the suite currently has nowhere.

QML: `tst_Settings` and `tst_SettingsRaces` cover the new control, including
the draft state machine under an in-flight save.

## Verification

`cargo fmt --check`, `cargo test`, `cargo clippy --all-targets -D warnings`,
`git diff --check`; Qt6 `qmllint`, `omarchy plugin validate .`, and Qt6
`qmltestrunner` per CLAUDE.md; ShellCheck if any script changes.

Live QA on the authorized gate: with Fable above 95%, confirm exactly one
notification per `reminderMinutes`, a state file holding one row per window,
and empty stderr across consecutive polls.

## Open decisions

1. **No "never" reminder value.** Range starts at 15 minutes, so notify-once
   is no longer reachable. Confirm this is intended, or the range gains `0`
   with "once only" semantics.
2. **Reminder applies to both severities.** Warning and critical repeat on the
   same cadence. A split (critical hourly, warning less often) is possible but
   adds a second number to the contract.
