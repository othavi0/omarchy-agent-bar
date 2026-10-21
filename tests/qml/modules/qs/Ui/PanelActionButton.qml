import QtQuick
import qs.Commons
import qs.Commons as Commons

// Test stand-in for the host icon button: same public surface, a plain
// glyph instead of the host BorderSurface.
Item {
  id: root

  property string iconText: ""
  property string tooltipText: ""
  property color foreground: Commons.Color.foreground
  property color hoverColor: foreground
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.icon
  property real size: Math.round(Math.max(Style.space(22), fontSize + Style.spacing.sm * 2)) | 1
  property bool focusable: false
  property bool hasCursor: false
  property bool bordered: false

  signal clicked()
  signal hovered(bool isHovered)

  implicitWidth: size
  implicitHeight: size
  activeFocusOnTab: focusable

  Text {
    anchors.centerIn: parent
    text: root.iconText
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.enabled
    onClicked: root.clicked()
  }
}
