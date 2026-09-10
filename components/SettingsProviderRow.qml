import QtQuick
import qs.Commons
import qs.Ui

// One provider row: icon, English name, up/down order, enable switch.
Item {
  id: root

  property string providerId: ""
  property string displayName: ""
  property url iconSource: ""
  property bool enabled: true
  property bool locked: false
  property bool canMoveUp: true
  property bool canMoveDown: true
  // Differs from the saved settings (switch flipped or row moved).
  property bool changed: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal enableToggled()
  signal moveUp()
  signal moveDown()

  width: parent ? parent.width : implicitWidth
  implicitHeight: Style.space(36)
  height: implicitHeight

  Rectangle {
    visible: root.changed
    x: -Style.space(8)
    width: 2
    height: parent.height - Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    color: Color.accent
  }

  Image {
    id: icon
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    source: root.iconSource
    width: 16
    height: 16
    sourceSize.width: 16
    sourceSize.height: 16
    fillMode: Image.PreserveAspectFit
    opacity: root.enabled ? 1.0 : 0.45
  }

  Text {
    anchors.left: icon.right
    anchors.leftMargin: Style.space(8)
    anchors.right: controls.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.displayName
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    textFormat: Text.PlainText
    Accessible.name: root.displayName
  }

  Row {
    id: controls
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    // UX-034 native chevrons (Quattro dropdown uses 󰅀 down; 󰅃 up)
    PanelActionButton {
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅃"
      tooltipText: "Move up"
      foreground: root.foreground
      enabled: !root.locked && root.canMoveUp
      focusable: true
      Accessible.name: "Move " + root.displayName + " up"
      onClicked: root.moveUp()
    }

    PanelActionButton {
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅀"
      tooltipText: "Move down"
      foreground: root.foreground
      enabled: !root.locked && root.canMoveDown
      focusable: true
      Accessible.name: "Move " + root.displayName + " down"
      onClicked: root.moveDown()
    }

    Item { width: Style.space(4); height: 1 }

    SettingsSwitch {
      anchors.verticalCenter: parent.verticalCenter
      accessibleName: root.displayName
      checked: root.enabled
      locked: root.locked
      foreground: root.foreground
      onToggled: root.enableToggled()
    }
  }
}
