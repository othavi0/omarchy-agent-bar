# Popup grid layout

Date: 2026-10-31
Status: approved
Supersedes: `UX-077`, `UX-078`, `UX-079`, `UX-080`, `UX-082`, `A11Y-024`,
and `A11Y-025` from `2026-10-21-popup-overview-redesign-design.md`; the
row frame, chevron, and drawer of `2026-10-21-popup-drawer-design.md`;
amends `UX-020A`, `UX-020B`, `UX-020C`, `UX-020D`, `UX-028`, `UX-083`,
`A11Y-002`, `A11Y-004`, and `A11Y-026`

## Context

- The accordion showed one window per provider and hid the rest behind a
  chevron. Comparing Claude's weekly window with Codex's took two clicks.
- The pace tick on the meter marked time passed. The owner read it as a
  second fill and asked for it to go.
- Every percentage repeated its unit word (`used`), and every open drawer
  repeated `Updated 1m ago` and a `Refresh` button that the `r` key and the
  middle click already cover.
- The owner picked layout "2 · side column" with "tonal" buttons and the
  Omarchy theme palette from a prototype with four layouts, four button
  styles, and six palettes.

## Decision

### Provider group (UX-087)

- `UX-087`: every enabled provider is a group on its own slab. Groups are
  split by the existing band of popup floor (the Gaveta band); there is no
  accent rail, no card margin, and no outline against the popup border.
  A group has two columns:
  - The left column has a fixed width of `Style.space(118)`: the icon and
    the name (the only weight-600 text in the popup), the plan in tertiary
    text, the short notes, then the actions stacked.
  - The right column stacks every window in the provider's order. A window
    is a label line, with the reset countdown right-aligned in tertiary
    text, over a full-width bar with the percentage in a fixed column on
    the right. The countdown adds the local clock time when the reset is
    under 24 hours away. Every bar in the popup has one width and one
    height.
  - A provider without a reading puts its state body (the `UX-029` to
    `UX-032A` copy or the provider's error message) in the right column.

  Nothing folds: no chevron, no drawer, no collapsed flag. The popup grows
  with its groups up to `maxContentHeight` and scrolls past it.

### Notes (UX-088)

- `UX-088`: a group's notes are short lines in the left column, in this
  order: `Loading` while the first collection runs; the status word shared
  with Settings (`Signed out`, `Not installed`, `Rate limited`, `Offline`,
  `Failed`, `No percentage`); `Updated {age}` for a stale provider
  (`UX-028`); `{n} reset left` and its date when the provider has resets;
  and the reset outcome of `UX-073`.

### Actions (UX-089)

- `UX-089`: one model list, `actionsFor(provider)`, holds every action a
  group offers, as `{ id, kind, label, target, enabled, primary }`. The
  left column draws it, and Enter fires its first entry. The list is the
  provider's state actions (`Sign in`, `Install guide`, `Check again`,
  `Retry`), then `Use reset` when the provider has a reset left. `Use
  reset` stays listed but disabled when nothing is claimable or the reset
  lane is busy. The first entry is the primary.
  - The primary is tonal: the accent mixed at 16% over the slab, with its
    label the accent walked toward the theme foreground until it reads at
    4.5:1 on the press fill. Hover mixes 24% and press 34%.
  - Every other action is text alone in the secondary text colour, with a
    foreground hover and press fill.
  - Both keep the host focus ring.
- The per-provider `Refresh` button is removed. `r` refreshes the
  selected provider and the bar chip's middle click refreshes all.

### Meter (UX-020A, UX-080)

- `UX-020A` (amended): every window shows a bar filled by the displayed
  metric, in the accent colour, or the urgent colour when the window is
  critical.
- `UX-080` (superseded): the pace tick is removed with its accessible
  description. The model no longer reads `windowMinutes`.

### Severity (UX-020C, A11Y-026)

- `UX-020C` and `A11Y-026` (amended): a critical window turns its own bar
  and number urgent. The popup draws no alert glyph; the window's
  accessible name carries `critical` or `low`. The bar chip keeps its
  alert glyph (`UX-085`).

### Selection (UX-020B, UX-020D)

- `UX-020B` (amended): the selected group's slab takes a 6% accent tint.
  The focused group draws the accent focus ring inset by `Style.space(4)`,
  so it never doubles the popup border.
- `UX-020D` (amended): the lead window election still feeds the bar chip.
  The popup shows every window and elects none.

### Footer (UX-083)

- `UX-083` (amended): the footer holds `Settings` on the left and, on the
  right, one `Updated {age}` line, the unit (`% used` or `% left`) that
  every percentage above shares, and the key hints. The age is the oldest
  `lastSuccessAt` among ready providers, so the footer never claims fresher
  data than the popup shows. While a refresh runs the line reads
  `Refreshing…`. Without a ready provider the line is empty.

### Keys and accessibility (A11Y-002, A11Y-004, A11Y-027)

- `A11Y-002` (amended): Up/Down and `j`/`k` move the selection and the
  focus to the next group.
- `A11Y-004` (amended): Enter and Space on a group run its primary action
  when it is enabled; a click on a group selects it.
- `A11Y-027`: each group is one focus stop, a button whose accessible name
  reads the provider, the plan, the notes, and every window as `{label},
  {N}% used|left, critical|low, resets in {X}`. The state body is its
  accessible description. The usage focus order is the banner actions,
  then each group followed by its enabled actions, then `Settings`.

## Contract changes

| ID | Before | After |
| --- | --- | --- |
| `UX-077` | Row with one primary meter, value over unit, sub line. | `UX-087`: group with every window. |
| `UX-078` | Accordion; one open row. | Superseded; nothing folds. |
| `UX-079` | Drawer with windows, reset facts, `Updated`, `Use reset`, `Refresh`. | `UX-087` windows, `UX-088` notes, `UX-089` actions, `UX-083` footer. |
| `UX-080` | Pace tick on the meter. | Removed. |
| `UX-082` | Status row with glyph, word, body, first action. | `UX-087` and `UX-088`: word in the notes, body in the right column, actions from `UX-089`. |
| `A11Y-024` | Expandable row head with the tick description. | `A11Y-027`. |
| `A11Y-025` | Head, row action, open row's `Use reset` and `Refresh`. | `A11Y-027`. |
