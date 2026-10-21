import QtQuick
import qs.Commons
import qs.Commons as Commons

Rectangle {
  property color foreground: Commons.Color.foreground
  property real strength: 0.12

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: 1
  height: 1
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, strength)
}
