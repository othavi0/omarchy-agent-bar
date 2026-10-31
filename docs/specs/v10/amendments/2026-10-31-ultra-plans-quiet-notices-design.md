# Ultra plans and quiet notices

Date: 2026-10-31
Status: approved
Supersedes: `UX-081` from `2026-10-21-popup-overview-redesign-design.md`;
amends `NOTIFY-003`, `NOTIFY-014`, and the session window label in
`JSON-020A` examples; adds `CACHE-026`

## Context

- On 2026-10-30 Anthropic renamed its plans: Max 5x became Max and Max 20x
  became Ultra, at the same prices. The OAuth `rateLimitTier` string still
  reads `default_claude_max_20x`, so the popup kept showing `MAX 20X`.
- Verified Ultra accounts lost the 5-hour limit. The usage endpoint now
  answers `five_hour: null` and lists only weekly limits for them.
- Claude Code 2.1.312 calls the 5-hour window `5-hour limit`.
- The open row's pace line (`At this pace full in ~1h 6m`) projected a
  linear rate the owner did not trust, and it crowded the drawer.
- A window that stayed critical repeated its desktop alert every
  `reminderMinutes` (default 120), so the owner saw the same 95% alert
  again and again.
- A 429 from the Claude usage endpoint carried `Retry-After`, but the next
  poll asked again after the 300-second TTL.

## Decision

- Plan names come from one table keyed by a substring of `rateLimitTier`:
  `ultra` and `max_20x` read `Ultra`, `max_5x` reads `Max`. Any other tier
  drops the `default_claude_` prefix and underscores (`Team premium`). The
  plan `id` stays the raw tier.
- The 5-hour window label is `5-hour` for Claude and Codex. Its `id` stays
  `session`, so cache and notification keys do not move.
- The pace line is removed: no projection, no `Too early to project`, and no
  `= time passed` key. The pace tick on the meter (`UX-080`) stays.
- Each window alerts once at 90% and once at 95% used. The same level never
  repeats inside one window, and a dip back to warning does not rearm
  critical; a new window or a higher level speaks again (`NOTIFY-003`). The
  `Remind me every` setting is removed. A stored
  `notifications.reminderMinutes` in `15..=1440` still reads and the next
  explicit write drops it (`NOTIFY-014`).
- A Claude 429 with `Retry-After` holds the cache row until that instant,
  capped at one hour (`CACHE-026`). The hold lives in the cache row's
  `expiresAt`; status JSON does not change.

## Version skew

A shell that still runs the previous QML after the helper updates reads a
settings document without `reminderMinutes`. Its draft check rejects that
document, so the Settings dialog opens in the `load_failed` state
(`SET-026`), whose copy already says to restart the shell. The bar keeps
polling with the settings it read at startup. The update flow already asks
for `Restart shell`.
