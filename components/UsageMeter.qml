import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tokens.js" as Tokens

// One usage bar. percent is the displayed metric (-1 = none). Every bar in
// the popup has this one height and the accent fill; a critical window
// turns urgent.
Item {
  id: root

  property real percent: -1
  property bool critical: false
  property color foreground: Commons.Color.foreground

  readonly property color trackColor: Util.alpha(root.foreground, Tokens.TRACK)
  readonly property color fillColor: root.critical ? Commons.Color.urgent : Commons.Color.accent

  readonly property bool hasPercent: root.percent >= 0 && root.percent <= 100
  readonly property real fillRatio: root.hasPercent ? Math.max(0, Math.min(1, root.percent / 100)) : 0
  readonly property int barHeight: Style.space(6)

  implicitWidth: Style.space(48)
  implicitHeight: root.barHeight
  Accessible.ignored: true

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: root.barHeight
    radius: Style.cornerRadius
    color: root.trackColor

    Rectangle {
      objectName: "meterFill"
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(root.barHeight, parent.width * root.fillRatio)
      height: parent.height
      radius: parent.radius
      color: root.fillColor
      visible: root.hasPercent && root.fillRatio > 0
    }
  }
}
