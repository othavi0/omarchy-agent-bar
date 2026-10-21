import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import "../CoreView.js" as Core
import "Tokens.js" as Tokens

// Provider mark at a given size. Codex and Grok ship white masks that take
// the foreground through MultiEffect; the others are full-colour images.
Item {
  id: root

  property string providerId: ""
  property int size: Style.font.iconLarge
  property bool dimmed: false
  property color foreground: Commons.Color.foreground

  readonly property bool tinted: Core.iconTinted(root.providerId)
  readonly property int paintedSize: Math.round(root.size * Core.iconOpticalScale(root.providerId))
  readonly property url source: Core.iconUrl(root.providerId)

  implicitWidth: root.size
  implicitHeight: root.size
  width: root.size
  height: root.size
  opacity: root.dimmed ? Tokens.DIMMED : 1
  Accessible.ignored: true

  Image {
    source: root.tinted ? "" : root.source
    visible: !root.tinted && source.toString().length > 0
    anchors.centerIn: parent
    width: root.paintedSize
    height: root.paintedSize
    sourceSize.width: root.paintedSize
    sourceSize.height: root.paintedSize
    fillMode: Image.PreserveAspectFit
  }

  Image {
    id: tintSource
    source: root.tinted ? root.source : ""
    visible: false
    anchors.centerIn: parent
    width: root.paintedSize
    height: root.paintedSize
    sourceSize.width: root.paintedSize
    sourceSize.height: root.paintedSize
    fillMode: Image.PreserveAspectFit
  }

  MultiEffect {
    visible: root.tinted
    source: tintSource
    anchors.fill: tintSource
    colorization: 1.0
    colorizationColor: root.foreground
  }
}
