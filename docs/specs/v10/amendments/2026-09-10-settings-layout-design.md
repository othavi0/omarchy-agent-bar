# Settings layout: sections, label-left rows, interval menus

Date: 2026-09-10
Status: approved

## Context

The owner found the Settings view hard to read:

- `Remind me every` sat below the Notifications card and read as a separate
  setting.
- `Refresh every` floated between `Bar shows` and Notifications.
- Number fields carried labels above them, while toggles came as bordered
  cards with labels beside them, so the view mixed two patterns.
- `Update automatically` sat among the bar settings.
- `Restore defaults`, `Cancel`, and `Save changes` sat mid-page above
  Maintenance, which made them look like they saved immediate actions too.

The owner reviewed three directions and variations in the brainstorming
companion. They chose "C3": section headers, label-left rows, interval
menus, and a save tray that appears only while something changed, with no
separator lines around it.

## Decision

- Section headers: Providers, Bar, Alerts, Updates (host
  `PanelSectionHeader`). Each row puts its label on the left and its control
  on the right.
- Provider rows keep their icon, name, and chevrons, and swap the `On/Off`
  text button for the same switch every other row uses.
- `Refresh every` and `Remind me every` use the host `Dropdown` with fixed
  choices. A saved value outside the list shows up as one extra choice, so
  opening a menu never rewrites a setting.
- Switches wrap the host `ToggleSwitch`, which takes no keyboard focus, in a
  Tab-focusable control that toggles on Enter or Space and exposes checkbox
  semantics.
- The Updates section holds the automatic switch, the version row with
  `Check for updates`, the `Update to <version>` row, and `Uninstall Agent
  Bar` as the only red control, alone on the last row. The "Maintenance" and
  "Danger zone" headers and the separators go away.
- `Restore defaults` moves beside the title. `Cancel` and `Save changes`
  move to a tray on the host `Color.menu.selectedBackground` surface. The
  tray shows only while the draft differs from the snapshot or is saving,
  and names the change count. Each differing row gets an accent bar in its
  gutter.
- Control labels the spec already names stay: `Bar shows`, `Refresh every`,
  `Remind me every`, `Save changes`, `Check for updates`, `Update to
  <version>`, `Uninstall Agent Bar`. The notification row reads "Warn me
  before a quota runs out"; the automatic switch reads "Install
  automatically".

## Contract changes

- `UX-035` replaces the native numeric control with the interval menus and
  the focusable switch.
- `UX-035A` defines the save tray and the changed-row marker.
- `UX-044` pins the danger action to the last row of Updates.
- `A11Y-008` covers an open interval menu.
