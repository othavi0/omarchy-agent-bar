import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  property string providerId: ""
  property string displayName: ""
  property string statusText: ""
  property url iconSource: ""
  property bool enabled: true
  property bool locked: false
  property bool movable: true
  property bool canMoveUp: true
  property bool canMoveDown: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal enableToggled()
  signal moveUp()
  signal moveDown()

  width: parent ? parent.width : implicitWidth
  implicitHeight: Style.space(36)
  height: implicitHeight

  RowLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    Image {
      Layout.alignment: Qt.AlignVCenter
      source: root.iconSource
      Layout.preferredWidth: 16
      Layout.preferredHeight: 16
      sourceSize.width: 16
      sourceSize.height: 16
      fillMode: Image.PreserveAspectFit
      opacity: root.enabled ? 1.0 : 0.45
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      text: root.displayName
      color: root.enabled ? root.foreground : Util.alpha(root.foreground, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      textFormat: Text.PlainText
      Accessible.name: root.displayName
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      Layout.fillWidth: true
      text: root.statusText
      color: Util.alpha(root.foreground, 0.55)
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
      iconText: "󰅃"
      tooltipText: "Move up"
      foreground: root.foreground
      enabled: !root.locked && root.canMoveUp
      focusable: true
      Accessible.name: "Move " + root.displayName + " up"
      onClicked: root.moveUp()
    }

    PanelActionButton {
      id: downButton
      visible: root.movable
      Layout.alignment: Qt.AlignVCenter
      iconText: "󰅀"
      tooltipText: "Move down"
      foreground: root.foreground
      enabled: !root.locked && root.canMoveDown
      focusable: true
      Accessible.name: "Move " + root.displayName + " down"
      onClicked: root.moveDown()
    }

    // Keeps hidden rows' switches in the same column as the rows above,
    // which carry two chevrons in this space.
    Item {
      visible: !root.movable
      Layout.preferredWidth: upButton.implicitWidth + downButton.implicitWidth + Style.space(8)
      Layout.preferredHeight: 1
    }
  }
}
