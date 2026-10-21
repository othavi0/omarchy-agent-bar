import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tokens.js" as Tokens

// UX-076: the pinned headline naming the tightest window. It is read-only
// and never takes focus.
Rectangle {
  id: root
  objectName: "overviewBand"

  property var headline: null
  property int innerRadius: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  readonly property bool critical: !!(root.headline && root.headline.critical)
  readonly property color tertiary: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(content.implicitHeight, Style.spacing.controlHeight)
      + Style.space(20) + rule.height
  height: implicitHeight
  color: root.critical ? Util.alpha(Commons.Color.urgent, Tokens.URGENT_FILL) : Style.normalFill
  topLeftRadius: root.innerRadius
  topRightRadius: root.innerRadius

  Accessible.role: Accessible.StaticText
  Accessible.name: root.headline ? root.headline.accessibleName : "No quota data yet."

  RowLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.popupPadding
    anchors.rightMargin: Style.space(8)
    y: Math.round((parent.height - rule.height - height) / 2)
    spacing: Style.space(10)

    Text {
      visible: root.critical
      text: Tokens.GLYPH_ALERT
      color: Commons.Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
      textFormat: Text.PlainText
      Accessible.ignored: true
    }

    ProviderIcon {
      visible: !!root.headline
      providerId: root.headline ? root.headline.providerId : ""
      size: Style.font.iconLarge
      foreground: root.foreground
    }

    Flow {
      Layout.fillWidth: true
      spacing: Style.space(6)

      Text {
        visible: !root.headline
        text: "No quota data yet."
        color: Util.alpha(root.foreground, Tokens.TEXT_SECONDARY)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
        Accessible.ignored: true
      }

      Text {
        visible: !!root.headline
        text: "Tightest:"
        color: root.tertiary
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
        Accessible.ignored: true
      }

      Row {
        visible: !!root.headline

        Text {
          text: root.headline
              ? root.headline.providerName + " " + root.headline.windowWord + " "
                + root.headline.percentText + " " + root.headline.unitText
              : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          textFormat: Text.PlainText
          Accessible.ignored: true
        }

        Text {
          visible: !!root.headline && root.headline.resetText.length > 0
          text: " ·"
          color: root.tertiary
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          textFormat: Text.PlainText
          Accessible.ignored: true
        }
      }

      Text {
        visible: !!root.headline && root.headline.resetText.length > 0
        text: root.headline ? root.headline.resetText : ""
        color: root.tertiary
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
        Accessible.ignored: true
      }
    }

    HeaderTag {
      label: root.headline ? root.headline.tagText : ""
      kind: root.critical ? "urgent" : "neutral"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }

  PanelSeparator {
    id: rule
    objectName: "edgeRule"
    y: parent.height - height
    width: parent.width
    foreground: root.critical ? Commons.Color.urgent : root.foreground

    Binding on strength {
      when: root.critical
      value: Tokens.URGENT_RULE
      restoreMode: Binding.RestoreBindingOrValue
    }
  }
}
