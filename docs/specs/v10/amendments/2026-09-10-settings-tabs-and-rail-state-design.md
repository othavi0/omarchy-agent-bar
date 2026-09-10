# Settings tabs and rail state

Date: 2026-09-10
Status: approved

## Context

The owner compared throwaway prototypes of the popup rail and the Settings
view and picked a direction. Measured in the prototype, the single-column
Settings view ran about 787 px of content in a 542 px viewport, so
`Save changes` sat below the fold when Settings opened. Full-width separators
between sections read as heavy, and `Remind me every` stayed editable with
notifications off.

Reading the code turned up two rail defects. With Settings open, the rail
kept the soft plate on the provider that had been selected, while the
Settings slot showed nothing, so two places disagreed about what owned the
content. Provider slots had no tooltip, although `UX-014` promises the name
through tooltips.

## Decision

1. The rail plate follows the open view. In the usage view the selected
   provider carries it; in the settings view the Settings slot carries it and
   no provider does.
2. Every provider slot carries a tooltip and accessible name built from the
   chip's accessible label: the name, the displayed percentage when a reading
   exists, the plain-language state qualifier when it does not, and
   `critical` when a critical window drives severity.
3. A provider slot shows the chip's `!` cue in its corner under the same
   rule as the bar chip: every error state, and a ready provider with a
   critical window. The critical cue uses the urgent theme colour.
4. A hairline separates the rail from the content, and another sits above
   the Settings slot.
5. Settings splits into three tabs, `Providers`, `General`, and `About`,
   switched by the native `ButtonGroup`. A tab whose fields differ from the
   saved settings shows `•` after its label.
6. Each section opens with its title and a rule running to the right edge.
   Sections never use a full-width separator between them.
7. `Providers` lists the providers on the bar under `On the bar` with their
   count, and the rest under `Hidden`. Each row uses the native
   `ToggleSwitch` and shows the provider's state in words when it has no
   reading or no percentage. The up and down chevrons appear on the bar
   section only, and a move swaps with the nearest provider in the same
   section.
8. `General` holds `Bar shows`, with a preview of the first ready provider's
   chip number, and `Refresh and alerts`. `Remind me every` is disabled while
   notifications are off.
9. `About` holds the installed version with `Check for updates`, the
   `Update automatically` toggle, and the danger zone with
   `Uninstall Agent Bar`.
10. `Restore defaults`, the unsaved-change count, `Cancel`, and
    `Save changes` sit in a footer pinned under the scroll surface, visible on
    every tab once settings have loaded.

## Contract changes

- `UX-014` holds for provider slots through the tooltip in decision 2.
- `UX-020B` now says the Settings slot carries the plate while Settings owns
  the content.
- The Settings list and `UX-033` and `UX-034` in `04` describe the tabs,
  the two provider sections, and section-scoped ordering.
- `UX-036` to `UX-038` are unchanged; the draft, save, and cancel flow stays
  as it was.

## Rejected alternatives

- A rail with a per-provider usage meter. It repeats the number the bar
  chips already show above the popup and would need `UX-013` amended.
- No rail at all. It would widen the content by 48 px, but the popup would
  lose its own provider list.
- Saving each change as it is made. It breaks `UX-036` to `UX-038`.
- Showing the footer only while changes are pending. The popup would change
  height on the first edit, and `A11Y-013` rules out an animation to soften
  that.
