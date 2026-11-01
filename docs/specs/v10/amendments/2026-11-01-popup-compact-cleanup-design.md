# Popup compact cleanup

Date: 2026-11-01
Status: approved
Supersedes: `UX-087` (side column) and `UX-088` (stacked notes) from
`2026-10-31-popup-grid-layout-design.md`, the group selection of
`UX-020B`, `A11Y-002`, `A11Y-005`, and `A11Y-006`; amends `UX-023`,
`UX-083`, `UX-089`, `A11Y-004`, `A11Y-008`, `A11Y-027`, `TEST-026`, and
the provider window labels in `02-target-architecture.md`

## Context

- The owner used the v11.0.4 grid live. The fixed left column left an empty
  block under each provider name, so short groups read as half blank.
- The footer taught keys (`↑↓`, `r`, `s`) in keycaps. The owner wants
  buttons, not shortcuts.
- A click on a group tinted it and a focused group drew a ring, though the
  group itself does nothing. The selection only existed for the arrow keys
  and for Enter running the first action.
- `Weekly (7d)` repeated the window length that the reset countdown
  already shows.
- The owner picked layout "B · Compact" with the footer "Buttons with
  text" from a prototype with four layouts and three footers.

## Decision

### Provider group (UX-090)

- `UX-090`: every enabled provider is a group on its own slab, split from
  the next by the band of popup floor. A group starts with one header
  line:
  - on the left, the icon, the name (the only weight-600 text in the
    popup), and the plan in tertiary text on the same line;
  - on the right, the group note in secondary text, then the group's
    action buttons.

  The plan yields room first and elides; the note wraps, right-aligned,
  before it pushes the buttons. There is no side column.
- Under the header, every window takes one line (`UX-091`). A provider
  without a reading shows its state body (the `UX-029` to `UX-032A` copy or
  the provider's error message) on a line in place of the windows.
- Nothing folds. The popup grows with its groups up to `maxContentHeight`
  and scrolls past it.

### Window line (UX-091)

- `UX-091`: a window line holds four columns: the label, the bar, the
  percentage, and the reset countdown in tertiary text. The columns are
  shared by every group, so every bar in the popup starts on one edge and
  has one width:
  - the label column fits the widest label, at least `Claude/GPT · 7d`
    and at most a third of the content width; a longer label elides;
  - the percentage column fits `100%` in tabular figures;
  - the reset column fits the widest countdown, right-aligned on the
    content edge, and takes no room when no window has a reset.
- A critical window turns its bar and its percentage urgent (`UX-020C`).

### Note (UX-088)

- `UX-088` (amended): the group note is one line on the header, its parts
  joined by ` · ` in this order: `Loading`, the status word shared with
  Settings, `Updated {age}` for a stale provider, `{n} reset left` and its
  date, and the reset outcome of `UX-073`.

### Actions (UX-089)

- `UX-089` (amended): `actionsFor(provider)` lists the group's actions as
  `{ id, kind, label, target, enabled }`. Nothing ranks first and no key
  fires an entry. Every group action is a tonal button: the accent mixed at
  16% over the slab, its label the accent walked toward the foreground
  until it reads at 4.5:1 on the press fill; hover mixes 24%, press 34%. A
  disabled `Use reset` keeps a foreground fill at 4%.

### Footer (UX-083)

- `UX-083` (amended): the footer holds the status on the left, `Updated
  {age} · % used` (or `% left`), and two buttons on the right:
  - `Refresh`, text alone with the refresh glyph, forces a refresh of every
    shown provider, like the chip's middle click;
  - `Settings`, tonal with the settings glyph, opens Settings.

  The age is the oldest `lastSuccessAt` among ready providers. While a
  refresh runs the status reads `Refreshing… · % used`. Without a ready
  provider it reads the unit alone. No key hint remains.

### Selection (UX-020B, UX-023)

- `UX-020B` (amended): the popup keeps no selected group. Every group rests
  on the same slab; a click on a group changes nothing, and no group draws
  a focus ring. Settings has no idle selected-looking border.
- `UX-023` (amended): moving the popup to another monitor preserves the
  service state.

### Keys and accessibility

- `A11Y-002` (superseded): Up/Down and `j`/`k` do nothing in the popup.
- `A11Y-004` (amended): Enter and Space activate the focused button. The
  usage view opens with no control focused, so Enter does nothing until Tab
  reaches a button. Settings opens with focus on Back.
- `A11Y-005` and `A11Y-006` (superseded): `r` and `s` do nothing. The
  `Refresh` and `Settings` buttons, the chip's middle click, and its right
  click remain.
- `A11Y-007`: Escape still closes the popup.
- `A11Y-008` (amended): no letter shortcut remains to suspend. While a field
  editor owns input, Tab, Shift+Tab, and Escape still leave it.
- `A11Y-027` (amended): a group is no focus stop. It is an accessible
  grouping whose name reads the provider, the plan, the note, and every
  window as `{label}, {N}% used|left, critical|low, resets in {X}`; the
  state body is its description. The usage focus order is the banner
  actions, each group's enabled actions, `Refresh`, then `Settings`. Each
  button shows its focus with the host focus border and its hover fill.

### Window labels

- Provider window labels drop the duration suffix that repeated the reset
  countdown: Claude, Codex, and Grok weekly windows read `Weekly`, and a
  Codex extra bucket with a 7-day window reads its bare name. Other Codex
  bucket durations keep their suffix (`Premium (5h)`). Window `id` values
  do not change.

## Contract changes

| ID | Before | After |
| --- | --- | --- |
| `UX-087` | Fixed left column with name, plan, notes, stacked actions. | `UX-090`: header line with name, plan, note, and actions. |
| `UX-088` | Notes as stacked lines in the left column. | One note line on the header, joined by ` · `. |
| `UX-089` | First action is a tonal primary that Enter fires; the rest are text. | Every group action is tonal; no key fires one. |
| `UX-083` | `Settings` button, `Updated` line, unit, key hints. | Status line, `Refresh` and `Settings` buttons. |
| `UX-020B` | Selected group tint and focus ring. | No selection; no group ring. |
| `A11Y-002` | Up/Down and `j`/`k` move the selection. | Superseded. |
| `A11Y-004` | Enter on a group runs its primary action. | Enter activates the focused button only. |
| `A11Y-005`, `A11Y-006` | `r` refreshes, `s` toggles Settings. | Superseded by the footer buttons. |
| `A11Y-027` | Each group is one focus stop. | Groups are read, not focused. |
| `TEST-026` | Covers `j`/`k`, arrows, `r`, `s`. | Covers Tab, Shift+Tab, Enter, Space, Escape, inert arrows and letters, and visible focus. |
| Labels | `Weekly (7d)`. | `Weekly`. |
