import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tokens.js" as Tokens

// UX-084: a full-width row with its own inset and a rule to the popup edge.
// detailText carries the status, or the plan when there is none, so the
// plan prints once.
Item {
  id: root
  objectName: "settingsProviderRow"

  property string providerId: ""
  property string displayName: ""
  property string detailText: ""
  property bool enabled: true
  property bool locked: false
  property bool movable: true
  property bool canMoveUp: true
  property bool canMoveDown: true
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  signal enableToggled()
  signal moveUp()
  signal moveDown()

  readonly property int bodyHeight: Style.space(40)

  width: parent ? parent.width : implicitWidth
  implicitHeight: root.bodyHeight + rule.height
  height: implicitHeight

  function collectFocusTargets() {
    return root.movable ? [enableSwitch, upButton, downButton] : [enableSwitch]
  }

  function focusTarget(control) {
    if (control === "up")
      return upButton
    if (control === "down")
      return downButton
    return enableSwitch
  }

  RowLayout {
    x: Style.spacing.popupPadding
    width: root.width - Style.spacing.popupPadding * 2
    height: root.bodyHeight
    spacing: Style.space(8)

    ProviderIcon {
      Layout.alignment: Qt.AlignVCenter
      providerId: root.providerId
      size: Style.font.iconLarge
      dimmed: !root.enabled
      foreground: root.foreground
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      text: root.displayName
      color: root.enabled ? root.foreground : Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
      textFormat: Text.PlainText
      Accessible.name: root.displayName
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      Layout.fillWidth: true
      text: root.detailText
      color: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      textFormat: Text.PlainText
    }

    // The host switch has no focus handling of its own; the row supplies
    // the Tab stop, the keys, and the cursor ring through hasCursor.
    ToggleSwitch {
      id: enableSwitch
      Layout.alignment: Qt.AlignVCenter
      checked: root.enabled
      interactive: !root.locked
      hasCursor: activeFocus
      activeFocusOnTab: !root.locked
      foreground: root.foreground
      function focusActivate() {
        if (!root.locked)
          root.enableToggled()
      }
      onToggled: focusActivate()
      Keys.onSpacePressed: focusActivate()
      Keys.onReturnPressed: focusActivate()
      Keys.onEnterPressed: focusActivate()
      Accessible.role: Accessible.CheckBox
      Accessible.name: root.displayName + " on the bar"
      Accessible.checked: root.enabled
      Accessible.onPressAction: focusActivate()
      Accessible.onToggleAction: focusActivate()
    }

    PanelActionButton {
      id: upButton
      visible: root.movable
      Layout.alignment: Qt.AlignVCenter
      iconText: Tokens.GLYPH_UP
      tooltipText: "Move up"
      foreground: root.foreground
      enabled: !root.locked && root.canMoveUp
      focusable: true
      Accessible.name: "Move " + root.displayName + " up"
      function focusActivate() {
        root.moveUp()
      }
      Accessible.onPressAction: focusActivate()
      onClicked: focusActivate()
    }

    PanelActionButton {
      id: downButton
      visible: root.movable
      Layout.alignment: Qt.AlignVCenter
      iconText: Tokens.GLYPH_DOWN
      tooltipText: "Move down"
      foreground: root.foreground
      enabled: !root.locked && root.canMoveDown
      focusable: true
      Accessible.name: "Move " + root.displayName + " down"
      function focusActivate() {
        root.moveDown()
      }
      Accessible.onPressAction: focusActivate()
      onClicked: focusActivate()
    }

    // Keeps hidden rows' switches in the same column as the rows above,
    // which carry two chevrons in this space.
    Item {
      visible: !root.movable
      Layout.preferredWidth: upButton.implicitWidth + downButton.implicitWidth + Style.space(8)
      Layout.preferredHeight: Style.spacing.hairline
    }
  }

  PanelSeparator {
    id: rule
    objectName: "edgeRule"
    y: root.bodyHeight
    width: root.width
    foreground: root.foreground
  }
}
