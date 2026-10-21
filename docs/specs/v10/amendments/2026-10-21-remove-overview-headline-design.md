# Remove the overview headline

Date: 2026-10-21
Status: approved
Supersedes: UX-076, the tightest parts of UX-075, UX-077, UX-079,
UX-081, and A11Y-024, and the severity tag placement in UX-020C, all from
`2026-10-21-popup-overview-redesign-design.md`

## Context

- The popup overview redesign put a headline band above the rows. The band
  named the tightest window across providers (`Tightest: Claude session
  76% used · resets in 1h 32m`), and the row that held that window showed
  a `Tightest` tag in place of its reset text.
- The owner reviewed the live popup and found the band confusing: it
  restated one row's own numbers above that row, and the `Tightest` tag hid
  the reset time of exactly the window closest to its limit.
- The bar chip already carries the alert glyph (`UX-085`) for a provider
  with a critical window, so the glanceable "something is close" cue does
  not depend on the band.

## Decision

The popup starts directly with the provider rows. Each row talks only about
its own provider. There is no headline band, no `Tightest` tag, and no
election of a window across providers.

- The usage view holds, top to bottom, the banners, one row per enabled
  provider in settings order, and the footer. The first row meets the top
  border when no banner sits above it.
- The overview model carries `metric`, `unitText`, `rows`, `selectedId`,
  and `openId`. It has no `tightest` and no `headline`. A row has no
  `subTag`, and a window has no `isTightest`.
- A ready row's sub line is `{label} · resets in {X}`, or the label alone
  without a reset. A stale row keeps `{label} · Updated {age}` (`UX-028`).
- Every detail window shows `resets in {X}` (plus the local clock under 24
  hours), the window with the highest usage included.
- The pace line names its window (`{label} is ...`) whenever that window is
  not the row primary.
- The row head's accessible name is `{Provider}, {N%} {used|left}`, the
  severity word when present, and the sub line. It never says `tightest`.
- The first row's selection fill, hover fill, and focus ring take the
  popup's inner radius on their top corners when no stalled message or
  restart banner sits above them, as the restart banner already does.
- `components/OverviewBand.qml` and `components/HeaderTag.qml` are deleted.
  `HeaderTag` had no other user once the band and the `Tightest` tag went.
  `Tokens.URGENT_FILL`, used only by those two files, is deleted too.

### What the band carried

- `No quota data yet.`: the band showed it when no provider presented a
  reading. Each row already shows its own state (`Signed out`, `Not
  installed`, `Rate limited`, `Offline`, `Failed`, `No percentage`, or a
  loading row), so the popup shows no replacement line. With every
  provider disabled the popup holds only the footer, whose Settings button
  is the way to enable one.
- The `Critical` and `Low` severity tags: a critical window still shows the
  alert glyph before the row value and the urgent colour on its meter and
  value, and the row head's accessible name carries `critical`. A warning
  window (90 to 94 used) carries the word `low` in the row head's
  accessible name and has no visual tag. No severity level is colour only.

## Contract changes

| ID | Old text (summary) | Replacement |
| --- | --- | --- |
| `UX-075` | Banners, headline band, rows, footer; the band stays fixed. | Banners, rows, footer. The banners and the footer stay fixed. |
| `UX-076` | The headline band names the tightest window. | Superseded. There is no band and no cross-provider election. |
| `UX-077` | A ready row whose primary is the tightest shows a `Tightest` tag in place of its reset. | Every ready row shows `{label} · resets in {X}`, or the label alone. |
| `UX-079` | A detail window shows `resets in X`, or the `Tightest` tag. | A detail window always shows `resets in X`. |
| `UX-081` | The pace line names its window when it is neither the primary nor the tightest. | The pace line names its window when it is not the primary. |
| `UX-020C` | The headline band shows the `Critical` or `Low` tag. | No tag. Critical keeps the alert glyph, the urgent colour, and the word `critical` in the accessible name; warning keeps the word `low` in the accessible name. Thresholds and the chip cue rule are unchanged. |
| `A11Y-024` | The row head's accessible name ends with `tightest` when it applies. | The accessible name never says `tightest`. |

## Tests

- `tst_Overview.qml`: the overview model has exactly the keys `metric`,
  `openId`, `rows`, `selectedId`, and `unitText`, and its JSON never
  contains `tightest`, across every fixture and both metrics. The row that
  formerly held the tightest window reads `Session (5h) · resets in 1h 32m`,
  and a high side window shows its reset.
- `tst_PopupReal.qml`: the real popup has no `overviewBand`, its first row
  meets the top border, no rendered text or accessible name matches
  `tightest`, the focus order starts at the first row head, and the first
  row's fill, hover, and focus ring follow the card's top corners unless the
  restart banner owns them.
- `tst_Popup.qml`: the popup sources and `CoreView.js` name none of the
  deleted identifiers, and both deleted files stay deleted.

## Rejected alternatives

- Renaming the band to "Closest to limit". The wording changes; the
  problem stays: one row's numbers repeat above that row and the tag still
  hides its reset.
- Electing the headline by pace projection instead of by used percentage.
  It adds a second election that can disagree with each row's own pace
  line, and still talks about one provider above all of them.
- Showing the band only while some window is critical or low. The bar chip
  already carries that cue (`UX-085`), and a band that appears and
  disappears moves every row and the focus targets under the pointer.

## Consequences

- The popup is one band shorter, so more rows fit before the list scrolls.
- The user scans the rows to compare providers; nothing ranks them.
- The warning level has no visual word in the popup. If that turns out to
  matter, a per-row cue belongs in a later amendment, not a headline.
- `bundle.json` still lists the two deleted files until the next
  `release:` commit regenerates it.
