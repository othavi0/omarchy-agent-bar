# Popup overview redesign ("Ritmo")

Date: 2026-10-21
Status: approved; the headline band and the `Tightest` tag are superseded
by `2026-10-21-remove-overview-headline-design.md`; the row fills, the
detail layout, and the action line are amended by
`2026-10-21-popup-drawer-design.md`
Supersedes in part: UX-004, UX-006, UX-013, UX-014, UX-015, UX-016,
UX-017, UX-018, UX-019, UX-020B, UX-020D, UX-024, UX-025, UX-028
(placement only), UX-070, UX-071, UX-072, UX-073 (placement only),
A11Y-002, A11Y-006, PROD-020, PROD-023 (wording), the `07` screenshot
inventory

## Context

- The owner approved the "Ritmo" prototype (round 3, variant k) with the
  scope "everything at once".
- The rail and the single-provider pane show one provider at a time, and
  the pane repeats facts: the lead window, the header severity tag, and the
  update age all restate what the chip already says.
- Hairlines stopped short of the popup border. Icon sizes and alpha values
  were numeric literals spread across the QML files.
- A window carries no duration, and `CLAUDE.md` forbids QML from parsing
  labels. A pace projection needs the window length, so the helper gains a
  field instead of the popup guessing it from `id` or `label`.
- The 2026-09-10 Settings tabs amendment said a rail meter "would need
  `UX-013` amended". Removing the rail is that amendment.
- The prototype is a design reference, not acceptance evidence
  (`07-testing-and-acceptance.md`, "Screenshots must use real rendered
  QML").

## Decision

### Status JSON: windowMinutes (JSON-020A, CACHE-001B)

- `JSON-020A`: every window carries `windowMinutes`, a positive integer of
  whole minutes or `null`. The key is always present and follows
  `resetsAt`. Providers fill it from data they already have:
  - Codex: the wire `windowDurationMins`. A missing or non-positive value
    is `null`. The `workspace-limit` window is `null`.
  - Claude: 300 for the session window; 10080 for the weekly window, for
    model windows whose kind starts with `seven_day` or `weekly`, and for
    the legacy Opus and Sonnet windows. Any other scoped kind is `null`.
  - Antigravity: 300 for the `-5h` windows, 10080 for the `-weekly`
    windows.
  - Grok: 10080 only for an explicit `USAGE_PERIOD_TYPE_WEEKLY` period. An
    absent period and the monthly window are `null`.
  - Anything else is `null`. QML reads the key only for the pace tick and
    the pace line, and never derives a duration from `id` or `label`.
- `CACHE-001B`: a cache document written before `windowMinutes` still
  loads. The missing key reads as `null`. The cache schema version stays 2.
  A value of 0 is corrupt and follows `CACHE-018`.

The status schema adds `windowMinutes` to the required window keys as
`null` or an integer with minimum 1, and keeps `additionalProperties:
false`.

### Popup layout (UX-075 to UX-079)

```text
+--------------------------------------------------+
| ! [C] Tightest: Claude session 96% used ·        |
|       resets in 38m                   [Critical] |
+--------------------------------------------------+
| [C] Claude      [==========|====]   96%          |
|     Max         Session (5h) [Tightest]   used   |
|   ! At this pace full in ~11m, 27m before reset  |
|     Weekly (7d) [====      ]  37%  resets in 2d  |
|     Updated 1m ago          [Use reset] [Refresh]|
+--------------------------------------------------+
| [X] Codex       [=         ]    2%               |
|     Plus        Session (5h) · resets in 4h 10m  |
+--------------------------------------------------+
| [S] Settings              [↑↓] provider · [r] ...|
+--------------------------------------------------+
```

`[C]`, `[X]`, and `[S]` stand for the provider icons and the settings
glyph; `!` stands for the alert glyph. The letters are not literal UI.

- `UX-075` (band removed by `2026-10-21-remove-overview-headline-design.md`): the usage view holds, top to bottom, the banners, the headline
  band, one row per enabled provider in settings order, and a footer. Every
  band, rule, row fill, and footer runs edge to edge, and text carries its
  own indent. There is no close control: Escape and an outside click close
  the popup. The width intention is `Style.space(520)`. Only the rows list
  scrolls; the banners, the band, and the footer stay fixed. The popup
  resizes to fit an expanded row with no animation (`UX-020`, `A11Y-013`).
- `UX-076` (superseded by `2026-10-21-remove-overview-headline-design.md`): the headline band names the tightest window: the highest
  `usedPercent` across ready and stale providers, ties going to settings
  order and then to delivered window order. This election is separate from
  the per-row primary of `UX-020D`.
  - Copy: `Tightest: {Provider} {session|weekly|label} {N%} {used|left} ·
    resets in {X}`. The window word is `session` or `weekly` when the window
    id is `session` or `weekly`; otherwise the label renders verbatim as
    plain text. The reset part is omitted when `resetsAt` is null.
  - Critical (95 or more used): urgent fill, urgent rule, the alert glyph,
    and a `Critical` tag.
  - Warning (90 to 94 used): a `Low` tag.
  - No reading anywhere: `No quota data yet.`
  - The band is not focusable. Its accessible name spells out the same
    facts.
- `UX-077`: each row shows the provider icon, the name, the primary meter,
  and the value over its unit word (`used` or `left`), with the plan and a
  sub line under them. The primary window follows the `UX-020D` election,
  so `UX-002` holds and the chip numeral equals the row value. The sub line
  follows the no-repeat rule (the `Tightest` tag is superseded by
  `2026-10-21-remove-overview-headline-design.md`):
  - a ready row whose primary is the tightest shows the window label and a
    `Tightest` tag in place of its reset text;
  - any other ready row shows `{label} · resets in {X}`, or the label alone
    without a reset;
  - a stale row shows `{label} · Updated {age}` (`UX-028`) and no tag.

  The detail lists only the other windows; the primary never repeats there.
  A critical window anywhere in the row puts the alert glyph before the
  value, as the bar chip cue does (`UX-085`). The value turns urgent only
  when the primary itself is critical.
- `UX-078`: the rows form an accordion.
  - At most one row is open: the selected one, unless the user collapsed
    it.
  - A click, Enter, or Space on a row head opens a closed row or collapses
    the open one.
  - Up/Down and `j`/`k` move the selection and open the new row.
  - A chip click opens the popup with that provider's row open, and a click
    on another chip while the popup is open opens that row instead
    (replaces `UX-004` and `UX-006`). A click on the same chip still closes
    the popup (`UX-005`), collapsed or not.
  - The selection and the collapsed flag live in the service popup owner,
    so a monitor move keeps them (`UX-023`).
  - Selection and scroll position persist while the popup stays open; a new
    open scrolls to the top and keeps the selected row (replaces `UX-024`
    and `UX-025`).
  - Loading rows do not open.
- `UX-079`: an open row's detail holds, in order:
  1. the pace line (`UX-081`);
  2. the other windows, each with a thin meter, its value, and `resets in
     X` (plus the local clock time when the reset is under 24 hours away,
     never a day name), or the `Tightest` tag when that window is the
     tightest (the tag is superseded by
     `2026-10-21-remove-overview-headline-design.md`);
  3. the reset fact lines (the `UX-071` facts: label, count, which windows
     it clears, and one date, with no button), then the result caption of
     `UX-073`;
  4. one action line: `Updated {age}` on the left, `[Use reset] [Refresh]`
     on the right, with Refresh always rightmost and always enabled.

  The popup ignores a reset entry with no reset left (`available` 0): it
  draws no fact line for it, and a provider whose entries are all spent
  shows no `Use reset`.
  `Use reset` shows whenever the provider has resets and is enabled only
  when one entry is claimable and the reset lane is idle. It targets the
  first claimable entry of the open row's provider and keeps the
  `ConfirmDialog` flow of `UX-072`. This re-homes `UX-070` to `UX-072`
  from the former "Resets" section.

### Pace (UX-080, UX-081)

Pace uses only `windowMinutes`, `resetsAt`, and `usedPercent`. A window
has an elapsed fraction only when it has both a length and a parseable
reset: `elapsed = clamp(1 - (resetsAt - now) / windowMinutes, 0, 1)`.

- `UX-080`: the pace tick is a hairline in the tertiary text colour on the
  meter. It shows only for ready providers whose window has `elapsed` of at
  least 0.1, placed at the time passed (used metric) or the time left
  (remaining metric). Stale rows have no tick, because their fill is frozen
  at `lastSuccessAt`. The row head's accessible description reads
  `{N}% of the window has passed.`
- `UX-081`: the pace line applies only to ready rows. Candidates are the
  windows that show a tick and whose reset is still ahead; a window past its
  reset holds the old period's reading. The projection is linear (`projected = used /
  elapsed`) and is labelled `At this pace`. Durations use the countdown
  format of "resets in" (`1h 6m`, `26m`). `full` reads `empty` under the
  remaining metric. The line names its window (`{label} is ...`) only when
  that window is neither the row primary nor the tightest (the tightest
  exception is superseded by `2026-10-21-remove-overview-headline-design.md`).

  | Case | When | Copy |
  | --- | --- | --- |
  | Full now | a candidate is at 100 % used | alert glyph, `Full now` or `{label} is full now` |
  | Runs out | a candidate projects to 100 % or more | alert glyph, `At this pace full in ~{X}, {Y} before reset`, for the soonest to fill; `, at reset` when {Y} rounds under a minute |
  | Lasts | every candidate projects under 100 % | check glyph, `Lasts to reset, {label} ends near {N}% used` (or `{N}% left`), for the highest projection |
  | Too early | no candidate, but some window has an elapsed fraction | clock glyph, `Too early to project, under 10% of the window has passed.` |
  | None | no window has both a length and a reset | no line |

  Every case except Too early ends with a key: a tick sample and `= time
  passed` (used metric) or `= time left` (remaining metric).

### Status rows (UX-082)

- `UX-082`: a provider without a reading renders a status row. Error states
  dim the icon; a ready row with no percentage keeps its icon at full
  opacity (`PROD-031`). The row shows a glyph and the status word shared
  with Settings (`Not installed`, `Signed out`, `Rate limited`, `Offline`,
  `Failed`, `No percentage`) in the meter cell, the state body text in the
  sub line, and the first non-retry action (`Sign in`, `Install guide`) in
  the value cell, or `—` when there is none. The open row's action line
  carries the retry label (`Check again` for a missing CLI, `Retry`) or
  `Refresh`. The `UX-029` to `UX-032A` copy is unchanged.

### Footer and keys (UX-083, A11Y-002 and A11Y-006 amended)

- `UX-083`: the footer holds the `Settings` button with the settings glyph
  on the left and static hints on the right, with each key in a bordered
  box: `↑↓ provider · r refresh · s settings`. The hints are not focusable.
- `A11Y-002` (amended): Up/Down and `j`/`k` move the row selection and open
  the row. They do nothing in Settings.
- `A11Y-006` (amended): `s` opens Settings from the usage view and returns
  to the usage view from Settings.

### Settings (UX-084)

- `UX-084`: Settings keeps its three tabs and the 2026-09-10 behavior, with
  these changes:
  - A band holds Back (accessible name `Back to usage`) and the title
    `Settings`. Back and `s` return to the usage view and keep the
    selection and the unsaved draft.
  - The tab strip spans the full width.
  - Section rules run edge to edge.
  - Each provider row prints its plan or its state once.
  - The footer runs edge to edge: `Restore defaults` quiet on the left,
    the status text, `Cancel`, and `Save changes` on the right. The status
    text reads `No changes` while the draft is clean; "unsaved" appears
    only when there are changes.
  - Every body control is in the Tab order: Back, the tabs, the current tab
    body, then the footer.

### Bar chip cue (UX-085)

- `UX-085`: the bar chip cue renders as the alert glyph (U+F0026) instead
  of `!`, under the existing `UX-020C` rule: every error state, plus a
  ready or stale provider with a critical window. The accessible name is
  unchanged. Vertical bars still hide the cue.

### Tokens (UX-086)

- `UX-086`: plugin QML takes every alpha and opacity fraction from
  `components/Tokens.js`, and every size from `Style` or a `Tokens` ratio
  over `Style`. No numeric alpha, opacity, or size literal above 1 remains
  in plugin QML. `Tokens.js` also names the Nerd Font glyphs the popup
  uses.

### Accessibility (A11Y-024 to A11Y-026)

- `A11Y-024`: the row head is a button with `Accessible.expandable`,
  `Accessible.expanded`, and an accessible name that spells out the
  provider, the value and unit, the severity word, the sub line, and
  `tightest` when it applies (the `tightest` word is superseded by
  `2026-10-21-remove-overview-headline-design.md`). The tick's meaning goes in
  `Accessible.description`.
- `A11Y-025`: the usage focus order is the banner actions, then for each
  row its head (not for loading rows), its row action when present, and for
  the open row `Use reset` (skipped while disabled) and Refresh, then the
  footer `Settings`. Collapsed rows contribute only the head and the row
  action.
- `A11Y-026`: pace and severity cues are never colour only. The alert,
  check, and clock glyphs, the words, and the accessible names carry them.

## Contract changes

| ID | Old text (summary) | Replacement |
| --- | --- | --- |
| `UX-004` | Left click opens the clicked provider. | `UX-078`: a chip click opens the popup with that row open. |
| `UX-006` | Another chip switches content without closing. | `UX-078`: another chip opens its row without closing. |
| `UX-013` | The left rail uses provider icons only. | Retired. There is no rail; `UX-075` lists every provider as a row. |
| `UX-014` | Rail slot tooltips, `!` slot cue, rail hairline. | Retired with the rail. Row accessible names follow `A11Y-024`. |
| `UX-015` | Settings is the last control in the rail. | `UX-083`: Settings is the footer button. |
| `UX-016`, `UX-017` | Provider header with name, plan, severity, refresh. | The header is removed. `UX-076` carries severity, `UX-077` the name and plan, `UX-079` the refresh. |
| `UX-018` | One provider's content at a time. | `UX-075`, `UX-078`: every provider is a row; one row's detail is open. |
| `UX-019` | Full-width provider sections; Settings rules to the right edge. | Every band, rule, row fill, and footer runs edge to edge, Settings included. |
| `UX-020A` | Every window row shows a usage track. | Unchanged, and the meter carries the pace tick (`UX-080`). |
| `UX-020B` | Rail plate for the slot that owns the content. | The selected or open row head uses `Style.normalFill`. Amended by `2026-10-21-popup-drawer-design.md`: an accent tint and a frame of top and bottom lines. |
| `UX-020C` | The header shows the `Critical` or `Low` tag. | The severity tag moves to the band (`UX-076`). Thresholds and the chip cue rule are unchanged. Superseded by `2026-10-21-remove-overview-headline-design.md`: no tag. |
| `UX-020D` | One lead window; the rest are compact rows. | The lead becomes the row primary (`UX-077`); the rest move to the detail (`UX-079`). The election is unchanged. |
| `UX-024`, `UX-025` | Selection and scroll persist; a new open resets to the top. | `UX-078`. |
| `UX-028` | `Updated <age>` caption in the pane; header refresh. | `Updated <age>` lives in the stale sub line, and in the action line only for rows that are not stale, so it never shows twice; Refresh lives in the action line. The stale rendering rule itself stays: no cue, no error text, same severity colour, no "Offline" wording. |
| `UX-070` to `UX-072` | A "Resets" section in `ProviderView` with its own `Use reset`. | `UX-079`: reset fact lines in the detail, `Use reset` in the action line. |
| `UX-073` | Result caption under the section. | The caption follows the reset fact lines (`UX-079`). The copy is unchanged. |
| `A11Y-002` | Up/Down and `j`/`k` switch rail entries. | Move the row selection and open the row. |
| `A11Y-006` | `s` opens Settings. | `s` toggles between usage and Settings. |
| `PROD-020`, `PROD-023` | "provider rail". | "popup rows". |
| `07` screenshot inventory | 15 names. | The 17 names `scripts/verify-v10-ui` requires, adding `ready-white.png` and `critical-dark.png`. |

## Tests

- `TEST-043`: screenshots render the real `Popup.qml` with the real
  `Service.qml` against the stub host modules in `tests/qml/modules`, from
  deterministic fixtures. A missing output directory or a failed save
  fails the run.
- `TEST-044`: the fixed scan lists in `tst_Accessibility.qml` and
  `tst_Tokens.qml` equal the QML files on disk, minus declared exemptions.

The QML test command gains `-import tests/qml/modules`, so the stub
`qs.Commons` and `qs.Ui` modules resolve before the host shell directory.

## Rejected alternatives

- Parsing the window duration from `id` or `label` in QML. It breaks the
  rule that QML never parses provider text, and a label such as `Workspace
  limit` has no duration to find.
- The prototype's stale treatment (`Offline · last data {age}`, a wifi-off
  glyph, a grey meter). It contradicts `UX-028`, whose rationale is a
  measured false alarm after suspend; it contradicts the chip and the
  notifications, which still treat a stale critical window as urgent; and
  "Offline" is false when the cause is a rate limit or an expired token.
- A popup-local "closed row" flag. The collapsed flag rides the service
  popup owner, so a monitor move and `UX-005` keep working.
- A cache schema bump for `windowMinutes`. It would reject every existing
  cache document and lose stale retention (`CACHE-022`) for one cycle.

## Not changing

`UX-001` to `UX-003`, `UX-005`, `UX-007` to `UX-012`, `UX-020`,
`UX-020A`, the `UX-020C` thresholds (95 and 90), `UX-021` to `UX-023`,
`UX-026`, `UX-027`, `UX-029` to `UX-032A`, `UX-033` to `UX-058`,
`UX-043A` to `UX-043D`, `UX-074`, `A11Y-005`, and the notifications.

## Consequences

- The status JSON gains one required key per window. External readers of
  the closed schema need it.
- The popup is 20 units narrower.
- The screenshot evidence becomes real renders of the real popup.
- `preview.png` stays outdated until it is captured again.
- Pace appears on a live install only after the `release:` commit rebuilds
  `bin/agent-bar`. Until then, and for cache rows written before the
  field, rows show no tick and no pace line.
