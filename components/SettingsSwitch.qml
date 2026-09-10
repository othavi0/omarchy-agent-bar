import QtQuick
import qs.Commons
import qs.Ui

// Keyboard-operable switch for Settings rows. The host ToggleSwitch takes
// no focus, so this wrapper owns Tab focus, Enter/Space, and the accessible
// checkbox semantics; the host switch only draws.
Item {
  id: root

  property string accessibleName: ""
  property bool checked: false
  property bool locked: false
  property color foreground: Color.foreground

  signal toggled()

  implicitWidth: track.implicitWidth
  implicitHeight: track.implicitHeight
  activeFocusOnTab: true

  Accessible.role: Accessible.CheckBox
  Accessible.name: root.accessibleName
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.onToggleAction: root.activate()
  Accessible.onPressAction: root.activate()

  function activate() {
    if (!root.locked)
      root.toggled()
  }

  Keys.onReturnPressed: root.activate()
  Keys.onEnterPressed: root.activate()
  Keys.onSpacePressed: root.activate()

  ToggleSwitch {
    id: track
    anchors.centerIn: parent
    checked: root.checked
    interactive: !root.locked
    hasCursor: root.activeFocus
    foreground: root.foreground
    onToggled: root.activate()
  }
}
