import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tokens.js" as Tokens

// UX-083: one status line on the left ("Updated 2m ago · % used"), then
// Refresh and Settings on the right. The footer is a slab under the same
// band of popup floor that separates the provider groups.
Rectangle {
  id: root
  objectName: "popupFooter"

  property int innerRadius: 0
  property string statusText: ""
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  signal refreshRequested()
  signal settingsRequested()

  readonly property var tones: Tokens.surfaces(Commons.Color.popups.background, root.foreground)
  readonly property int bandHeight: band.height + rule.height
  readonly property int inset: Style.spacing.popupPadding

  function collectFocusTargets() {
    return root.visible ? [refreshAction, settingsAction] : []
  }

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(settingsAction.height, status.implicitHeight) + Style.space(16) + root.bandHeight
  height: implicitHeight
  color: root.tones.slab
  bottomLeftRadius: root.innerRadius
  bottomRightRadius: root.innerRadius

  Rectangle {
    id: band
    objectName: "rowBand"
    width: parent.width
    height: Style.space(4)
    color: root.tones.floor
  }

  PanelSeparator {
    id: rule
    objectName: "edgeRule"
    y: band.height
    width: parent.width
    foreground: root.foreground
    strength: Tokens.RIM
  }

  Item {
    id: line
    x: root.inset
    y: root.bandHeight
    width: parent.width - root.inset * 2
    height: parent.height - root.bandHeight

    Text {
      id: status
      objectName: "footerStatus"
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, buttons.x - Style.space(8))
      text: root.statusText
      color: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      textFormat: Text.PlainText
      Accessible.role: Accessible.StaticText
      Accessible.name: root.statusText
    }

    Row {
      id: buttons
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      ActionButton {
        id: refreshAction
        objectName: "footerRefresh"
        tonal: false
        surface: root.color
        text: "Refresh"
        iconText: Tokens.GLYPH_REFRESH
        fontFamily: root.fontFamily
        onActivated: root.refreshRequested()
      }

      ActionButton {
        id: settingsAction
        objectName: "footerSettings"
        surface: root.color
        text: "Settings"
        iconText: Tokens.GLYPH_SETTINGS
        fontFamily: root.fontFamily
        onActivated: root.settingsRequested()
      }
    }
  }
}
