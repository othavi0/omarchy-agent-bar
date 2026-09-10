import QtQuick
import qs.Commons
import qs.Ui

// One Settings row: label on the left, its control on the right, and an
// accent bar in the gutter while the row differs from the saved settings.
Item {
  id: root

  property string label: ""
  property bool changed: false
  // Subordinate rows (a reminder under its alert) use the supporting tone.
  property bool subordinate: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  default property alias control: slot.data

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(Style.space(32), slot.childrenRect.height)

  Rectangle {
    visible: root.changed
    x: -Style.space(8)
    width: 2
    height: parent.height - Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    color: Color.accent
  }

  Text {
    anchors.left: parent.left
    anchors.right: slot.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: root.subordinate ? Util.alpha(root.foreground, 0.72) : root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    textFormat: Text.PlainText
    Accessible.ignored: true
  }

  Item {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }
}
