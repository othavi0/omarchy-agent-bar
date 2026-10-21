import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tokens.js" as Tokens

// A section opens with its title over a rule. The header sits inside the
// inset content; `bleed` widens the rule past that inset so it meets the
// popup border (UX-084). The title is drawn here rather than with the host
// PanelSectionHeader, whose Qt.darker tint turns darker than body text on
// light themes.
Item {
  id: root

  property string text: ""
  property string count: ""
  property bool danger: false
  property int bleed: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  width: parent ? parent.width : implicitWidth
  implicitHeight: row.implicitHeight + Style.space(6) + rule.height

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(8)

    Text {
      text: root.text
      color: root.danger ? Commons.Color.urgent : Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      textFormat: Text.PlainText
      Accessible.role: Accessible.Heading
      Accessible.name: root.text
    }

    Text {
      Layout.fillWidth: true
      visible: root.count.length > 0
      text: root.count
      color: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }
  }

  PanelSeparator {
    id: rule
    objectName: "edgeRule"
    x: -root.bleed
    y: row.implicitHeight + Style.space(6)
    width: root.width + 2 * root.bleed
    foreground: root.danger ? Commons.Color.urgent : root.foreground
  }
}
