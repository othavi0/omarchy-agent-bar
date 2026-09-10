import QtQuick
import qs.Commons

Rectangle {
  id: root

  property string label: ""
  property bool urgent: false
  property string accessibleName: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  visible: root.label.length > 0
  implicitWidth: tagText.implicitWidth + Style.space(10)
  implicitHeight: tagText.implicitHeight + Style.space(4)
  width: implicitWidth
  height: implicitHeight
  radius: Style.cornerRadius
  color: "transparent"
  border.width: 1
  border.color: root.urgent ? Color.urgent : Style.normalBorderColor

  Text {
    id: tagText
    anchors.centerIn: parent
    text: root.label
    color: root.urgent ? Color.urgent : Util.alpha(root.foreground, 0.72)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.5
    textFormat: Text.PlainText
    Accessible.name: root.accessibleName.length > 0 ? root.accessibleName : root.label
    Accessible.role: Accessible.StaticText
  }
}
