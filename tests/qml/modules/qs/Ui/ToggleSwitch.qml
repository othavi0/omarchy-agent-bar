import QtQuick
import qs.Commons
import qs.Commons as Commons

// Test stand-in for the host switch: same public surface and track size.
Item {
  id: root

  property bool checked: false
  property bool busy: false
  readonly property bool mirrored: LayoutMirroring.enabled
  property bool interactive: true
  property bool hasCursor: false
  property bool cursorRing: interactive
  property int cursorPad: Style.space(6)
  property bool rounded: Style.cornerRadius > 0
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property int trackHeight: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))
  property int trackWidth: Math.round(trackHeight * 1.9)

  readonly property alias containsMouse: mouse.containsMouse
  readonly property bool hot: hasCursor || mouse.containsMouse

  signal toggled()
  signal hovered(bool isHovered)

  implicitWidth: trackWidth + (cursorRing ? cursorPad * 2 : 0)
  implicitHeight: trackHeight + (cursorRing ? cursorPad * 2 : 0)

  Rectangle {
    anchors.centerIn: parent
    width: root.trackWidth
    height: root.trackHeight
    radius: root.rounded ? height / 2 : 0
    color: root.checked ? root.accent : "transparent"
    border.width: 1
    border.color: root.foreground
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    onClicked: root.toggled()
  }
}
