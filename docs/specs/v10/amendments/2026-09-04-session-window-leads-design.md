# Session window leads the chip and popup

Date: 2026-09-04
Status: approved

## Context

The bar chip and the popup show one number: the percentage of the elected
lead window (`UX-002`). `UX-020D` elected that window in four steps: a
critical window first, then a plan window, then the window whose reset comes
soonest, then the first delivered window. A window whose reset already
elapsed, or that has no reset, did not compete in the third step.

On a Claude account this produced a wrong chip every morning. Cached status
from 2026-09-03 20:42 BRT carried three windows: `session` at 21 % used
resetting `2026-09-04T03:10Z`, `weekly` at 64 % resetting
`2026-09-04T12:00Z`, and `weekly-model:fable` at 79 % resetting at the same
instant. Replaying that document through `CoreView.js` at two clocks gave:

```
2026-09-03T23:45Z  lead=session  chip=21%
2026-09-04T10:00Z  lead=weekly   chip=64%
```

Overnight the session reset elapsed, the third step skipped the session, and
the weekly window took the number. Two more paths reach the same outcome:
a session opened after ~07:00Z on this account resets after the 12:00Z
weekly reset and loses the "soonest reset" comparison while active; and a
weekly or per-model window at or above 95 % used wins the first step
outright.

The owner decided on 2026-09-04: the chip always shows the five-hour window
when there is one. A weekly window running out is reported through colour
and the `!` cue, and in the popup, never by taking the chip number.

## Decision

A session window leads whenever one is delivered. The existing election
applies only when no session window exists.

Session windows are identified by id. The Rust mappers author these ids as
typed schema data: `session` for Claude and Codex, `gemini-5h` for
Antigravity. This is the same contract the `plan-` prefix already relies on
in `UX-020D`. The rule only promotes ids it knows; it never demotes an id it
does not know, which is the defect the pre-2026-08-07 allowlist had.

## Design

- `CoreView.js` `electLeadIndex` gains a step 0 before the critical step:
  the first delivered line whose id is in `SESSION_WINDOW_IDS`
  (`["session", "gemini-5h"]`) leads. Steps 1 to 4 are unchanged.
- Chip and popup share the election, so both change together (`UX-002`).
- `chipSeverityUrgent` and `chipStateCue` are unchanged. They derive from
  `providerSeverity`, which scans every window, so a weekly window at or
  above the critical threshold still paints the numeral urgent and shows
  `!` while the numeral itself stays the session percentage.
- Per provider: Claude, Codex, and Antigravity now lead with their session
  window. Grok delivers only `weekly` and Amp leads with `plan-` windows, so
  neither changes.

## Not changing

- Severity thresholds, notification levels, and their parity test.
- Stale retention: a retained session window leads exactly like a fresh one,
  which is the "last known value" the owner asked for after hours idle.
- The status JSON schema and the Rust mappers.

## Tests

`tests/qml/tst_ProviderStates.qml`:

- `test_session_window_leads_over_sooner_weekly_reset` replays the
  2026-09-03 data at 10:00Z and the active-session-after-weekly-reset case.
- `test_session_window_leads_over_critical_weekly` proves a critical
  per-model window keeps the urgent tint and the `!` cue without taking the
  number.
- `test_gemini_5h_window_leads_like_session` covers the Antigravity id.
- `test_lead_election_critical_beats_nearest_reset` and
  `test_unknown_window_id_can_lead` previously used `session` as the losing
  window; they now use non-session ids so they keep proving the steps they
  are named after.

## Spec amendment

`UX-002` reads: the chip shows the used or remaining percentage of the
elected lead window (per `UX-020D`), so chip and popup always name the same
number.

`UX-020D` reads: the popup renders exactly one lead window, elected
deterministically. A session window (id `session` or `gemini-5h`) leads
whenever present, the first delivered one if several. Otherwise a critical
window wins, and among criticals the one with the lowest remaining
percentage; otherwise a plan window (id starting `plan-`) wins, and among
plan windows the one with the lowest remaining percentage; otherwise the
window whose reset comes soonest; ties keep the delivered order; when no
window has a future reset the first delivered window leads. Every other
window renders as a compact row in delivered order.
