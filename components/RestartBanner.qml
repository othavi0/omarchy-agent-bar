import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../CoreMaintenance.js" as Maintenance

Rectangle {
  id: root

  property string version: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal restartRequested()

  function collectFocusTargets() {
    return root.visible ? [restartButton] : []
  }

  width: parent ? parent.width : implicitWidth
  implicitHeight: row.implicitHeight + Style.space(12)
  radius: Style.cornerRadius
  color: Style.selectedFillFor(root.foreground, Color.accent)
  border.width: 1
  border.color: Color.accent

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(9)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(8)

    Text {
      Layout.fillWidth: true
      text: Maintenance.restartPendingMessage(root.version)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      Accessible.role: Accessible.StaticText
      Accessible.name: text
    }

    Button {
      id: restartButton
      text: "Restart shell"
      bordered: true
      selected: true
      focusable: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      Accessible.name: "Restart shell"
      function focusActivate() {
        root.restartRequested()
      }
      Accessible.onPressAction: focusActivate()
      onClicked: focusActivate()
    }
  }
}
