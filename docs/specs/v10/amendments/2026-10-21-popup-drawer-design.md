# Popup drawer design ("Gaveta")

Date: 2026-10-21
Status: approved
Amends: UX-020B, UX-077, UX-079, UX-082, UX-083, UX-086, all from
`2026-10-21-popup-overview-redesign-design.md`

## Context

- On the live popup, the owner could not tell where one provider ended and
  the next began: every boundary was the same hairline, inside a row and
  between rows.
- The open row was marked only by a `Style.normalFill` plate, which reads as
  hover on several themes.
- The owner called the action line "old and dull, with no symmetry". `Use
  reset` and `Refresh` were outlined buttons of different widths. The pace
  line, the window lines, the reset line, and the action line each used
  their own top padding, row gap, and label column, so their left and right
  edges did not line up.
- Round 4 of the prototypes offered four treatments: Cartoes (cards),
  Gaveta (drawer), Foco (focus), and Fichario (index tabs). The owner chose
  Gaveta and asked for the drawer sections to line up with each other in
  the same change.
- The prototype is a design reference, not acceptance evidence
  (`07-testing-and-acceptance.md`, "Screenshots must use real rendered
  QML").

## Decision

Each provider row is a slab. Rows are separated by a band of popup floor
that is thicker than any rule inside a row. The open row is a drawer pulled
out of its slab.

### Surfaces (UX-086 extended)

`components/Tokens.js` derives every surface from the popup background and
the foreground with `Tokens.surfaces(background, foreground)`. No tone mixes
toward a fixed black.

| Surface | Dark background | Light background |
| --- | --- | --- |
| Floor (bands between rows) | the popup background | foreground mixed 20 % into the background |
| Slab (rows, footer) | foreground mixed 6 % into the background | the background |
| Well (open drawer) | foreground mixed 1.5 % into the background | foreground mixed 7 % into the background |

Depth always reads darker: the floor sits below the well, and the well
sits below the slab.

### Row (UX-020B and UX-077 amended)

- `UX-020B` (amended): the slab is tinted with the accent, mixed 6 % under
  an open head and 4 % under a selected closed head. A closed head shows
  `Style.hoverFill` under the pointer. The open row is framed: a line above
  it and a line below its drawer, in the popup border's colour
  (`Color.popups.border`) and width. The popup border draws the sides, so
  no side line doubles it. When the open row meets the popup's top border
  (nothing above it), that border is its top line and the row draws none.
  The first row's tint, hover fill, and focus ring still follow the popup's
  inner radius.
- `UX-077` (amended): the head ends with a chevron in its own column. The
  chevron points right on a closed row and down on the open row, with no
  animation (`A11Y-013`). It is accent on the selected or open row and
  tertiary otherwise, and hidden on loading rows, which do not open. The
  chevron's right edge is the row's right edge: `Style.spacing.popupPadding`
  in from the popup border.
- Every row but the last ends with a 4-unit floor band and a rim hairline,
  with the foreground at 10 %. The footer starts with the same band.

### Drawer (UX-079 amended)

- `UX-079` (amended): the drawer is a well under the open head. It has up to
  four sections in the `UX-079` order: pace, windows, resets, and actions.
  - Every section starts at the provider name's x
    (`popupPadding + iconLarge × 1.2 + Style.space(12)`). Every section ends
    at the chevron's right edge. Every section has `Style.space(10)` above
    and below its content.
  - A full-bleed hairline with the foreground at 8 % separates a section
    from the visible section above it. The first visible section has no
    hairline.
  - Every row inside a section is at least `Style.spacing.controlHeight`
    tall, with its content centred vertically. Window rows stack with no gap
    between them.
  - Window labels and reset labels share one label column. The column is at
    least as wide as the head's name column (`Style.font.body × 8.5`), or as
    wide as the widest label. Labels are bold in the foreground. Meters and
    reset facts start at the same x, which is the head meter's x unless a
    label is wider than the name column.
  - A window value is secondary text, or urgent and bold with the alert
    glyph when critical. Reset times and reset facts are tertiary. The facts
    of one reset line are joined with ` · `.
  - The action line holds the clock glyph and `Updated {age}` in tertiary on
    the left, and `Use reset` and `Refresh` on the right. Both are host
    `Button`s with no border, `Style.spacing.controlHeight` tall, one
    `Style.space(8)` apart. Both have the same width: the widest label
    either can show (`Refresh`, `Refreshing`, the retry label, `Use reset`,
    `Using reset…`) plus the icon, the padding, and the widest border the
    host can paint on focus, hover, or selection. Neither changes width while
    refreshing. `Refresh` ends on the chevron's right edge. `Use reset`
    carries the bolt glyph (U+F140B).
  - Button fills are mixed into the well. `Refresh` uses the foreground,
    10 % at rest, 16 % under the pointer or with focus, and 24 % while
    pressed. A claimable `Use reset` uses the accent, 24 % at rest, 34 %
    under the pointer or with focus, and 46 % while pressed. A disabled
    `Use reset` rests on the foreground at 4 %, and its label and glyph are
    tertiary. The host focus border is unchanged.
  - Setting `color` on a host `Button` replaces its whole fill rule, press
    included, and its `MouseArea` is private. A passive `PointHandler` in an
    item above the host content sees the press without taking the click, and
    drives the press tone.

### Status rows (UX-082 amended)

- `UX-082` (amended): the head action (`Sign in` with the user glyph,
  `Install guide` with the external-link glyph) uses the same borderless
  accent fill as a claimable `Use reset`, mixed into the head's own tint
  instead of the well, with the same hover, focus, and press tones, and is
  `Style.spacing.controlHeight` tall.

### Footer (UX-083 amended)

- `UX-083` (amended): the footer is a slab under a floor band and a rim
  hairline, the same boundary that separates two rows. Its content and
  hints are unchanged.

## Contract changes

| ID | Old text (summary) | Replacement |
| --- | --- | --- |
| `UX-020B` | The selected or open row head uses `Style.normalFill`. | The slab is tinted with the accent: 6 % open, 4 % selected. Lines above and below the open row, in the popup border's colour and width, frame it with the popup's own sides. |
| `UX-077` | Icon, name, meter, value, plan, sub line. | The same, plus a chevron column that points down on the open row. |
| `UX-079` | The detail order and the action line content. | The same order and content in a recessed well, with one left column, one right edge, equal section padding, control-height rows, a shared label column, and tonal twin buttons. |
| `UX-082` | The head action is a bordered button. | The head action is a borderless accent-tinted button. |
| `UX-083` | Footer on `Style.normalFill` under a hairline. | Footer slab under the row band. |
| `UX-086` | Every alpha comes from `Tokens.js`. | Also every surface and button tone, through `Tokens.surfaces` and `Tokens.mix`. |

## Tests

- `tst_PopupReal.qml` renders the real popup against the stub host modules
  and asserts:
  - every row but the last ends in a full-bleed band, and the band is taller
    than the drawer hairlines;
  - a reading row's drawer draws three full-bleed hairlines for its four
    sections;
  - the chevron's rotation is 90 on the open row and 0 on a closed row, and
    it follows the accordion;
  - the pace glyph, the window labels, the reset label, and the clock glyph
    start at the provider name's x;
  - `Refresh`, the pace key, and every window reset text end at the
    chevron's right edge;
  - the reset facts start at the meters' x, window rows are at least one
    control tall, and they stack without a gap;
  - `Use reset` and `Refresh` are borderless, share one width and height,
    sit one `Style.space(8)` apart, keep their width while refreshing, and
    share a centre line with `Updated`;
  - the status row's head action is borderless;
  - in the dark, light, and white palettes, the well is darker than the slab
    and the band is no lighter than the well.
- The stub `qs.Ui` `Button` now has a `Rectangle` root with public `color`
  and `radius`, as the host `BorderSurface` does. Its icon gap is
  `Style.spacing.controlGap`, as on the host.

## Rejected alternatives

- **Cartoes (cards).** Each provider is a separate card with a gap around
  it. The margins break the edge-to-edge rule (`UX-075`), and four cards
  cost more height than the bands.
- **Foco (focus).** The open provider grows and dims the others. Dimming
  reads as disabled, and the closed rows lose contrast exactly when the
  user is comparing them.
- **Fichario (index tabs).** Index tabs along the edge name the providers.
  This is a rail under another name, and `UX-013` retired the rail.
- **An animated chevron and a sliding drawer**, as in the prototype.
  `A11Y-013` forbids plugin-authored animation, so the chevron snaps.
- **An inner shadow in the well.** The prototype's shadow darkens toward
  black, and on a dark theme a shade derived from the background alone is
  invisible. The frame lines and the well tone carry the depth.
- **A left accent rail and a thick accent lip on the open row**, shipped in
  10.7.2. The owner rejected them: the rail read as generic, and a 15 %
  accent head was too loud. A full outline drawn inside the row doubled the
  popup border on both sides, so the frame keeps only the top and bottom
  lines.
- **Bold button labels and an accent-only glyph on `Use reset`.** The host
  `Button` draws its label and icon in one colour and bolds them only for
  `selected`. Re-drawing the content would duplicate the host control, and
  setting `selected` would misstate the state.

## Consequences

- The popup boundary between providers is 4 units of floor plus a rim
  hairline instead of a single hairline, so a popup with four providers is
  about 12 units taller.
- Light themes get visibly grey bands between rows.
- `preview.png` stays outdated until it is captured again.
- On a pure black theme, the dark floor and the dark well are almost equal,
  and only the rim and the drawer hairlines separate them.
