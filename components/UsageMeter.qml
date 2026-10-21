import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tokens.js" as Tokens

// One usage bar. percent is the displayed metric (-1 = none); tickPercent
// marks how much of the window has passed (-1 = no tick, UX-080).
Item {
  id: root

  property real percent: -1
  property bool critical: false
  property bool thin: false
  property real tickPercent: -1
  property color foreground: Commons.Color.foreground

  readonly property color trackColor: Util.alpha(root.foreground, Tokens.TRACK)
  readonly property color fillColor: root.critical
      ? Commons.Color.urgent
      : (root.thin ? Util.alpha(Commons.Color.accent, Tokens.THIN_FILL) : Commons.Color.accent)

  readonly property bool hasPercent: root.percent >= 0 && root.percent <= 100
  readonly property real fillRatio: root.hasPercent ? Math.max(0, Math.min(1, root.percent / 100)) : 0
  readonly property int barHeight: Style.space(root.thin ? 4 : 8)

  implicitWidth: Style.space(50)
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
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(root.barHeight, parent.width * root.fillRatio)
      height: parent.height
      radius: parent.radius
      color: root.fillColor
      visible: root.hasPercent && root.fillRatio > 0
    }
  }

  Rectangle {
    objectName: "paceTick"
    visible: root.tickPercent >= 0
    width: Style.spacing.hairline
    height: root.barHeight + Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    x: Math.max(0, Math.min(parent.width - width,
                            Math.round(parent.width * root.tickPercent / 100 - width / 2)))
    color: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
  }
}
