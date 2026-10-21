import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tokens.js" as Tokens

// UX-083: the Settings entry plus static key hints. Only the button takes
// focus; the hints are read-only. The footer is a slab under the same band of
// popup floor that separates the provider rows.
Rectangle {
  id: root
  objectName: "popupFooter"

  property int innerRadius: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  signal settingsRequested()

  readonly property color tertiary: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
  readonly property var tones: Tokens.surfaces(Commons.Color.popups.background, root.foreground)
  readonly property int bandHeight: band.height + rule.height
  readonly property var hints: [
    { key: "↑↓", label: "provider" },
    { key: "r", label: "refresh" },
    { key: "s", label: "settings" }
  ]

  function collectFocusTargets() {
    return root.visible ? [settingsButton] : []
  }

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(settingsButton.implicitHeight, hintRow.implicitHeight)
      + Style.space(16) + root.bandHeight
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

  Button {
    id: settingsButton
    x: Style.space(8)
    y: root.bandHeight + Math.round((root.height - root.bandHeight - height) / 2)
    text: "Settings"
    iconText: Tokens.GLYPH_SETTINGS
    focusable: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    Accessible.name: "Settings"
    function focusActivate() {
      root.settingsRequested()
    }
    Accessible.onPressAction: focusActivate()
    onClicked: focusActivate()
  }

  Row {
    id: hintRow
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.popupPadding
    y: root.bandHeight + Math.round((root.height - root.bandHeight - height) / 2)
    spacing: Style.space(4)
    Accessible.ignored: true

    Repeater {
      model: root.hints.length

      Row {
        id: hintItem
        required property int index
        readonly property var hint: root.hints[index]
        spacing: Style.space(4)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(Style.space(16), keyText.implicitWidth + Style.space(6))
          height: Math.max(Style.space(16), keyText.implicitHeight + Style.space(2))
          radius: Math.max(0, Style.cornerRadius - Style.space(2))
          color: "transparent"
          border.color: Style.normalBorderColor
          border.width: Style.spacing.hairline

          Text {
            id: keyText
            anchors.centerIn: parent
            text: hintItem.hint.key
            color: Util.alpha(root.foreground, Tokens.TEXT_SECONDARY)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: hintItem.hint.label + (hintItem.index < root.hints.length - 1 ? " ·" : "")
          color: root.tertiary
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }
    }
  }
}
