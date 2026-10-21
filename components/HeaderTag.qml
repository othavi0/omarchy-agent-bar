import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tokens.js" as Tokens

// kind: "neutral" (outline), "accent" (selected accent fill) or "urgent"
// (urgent text and border on the urgent fill).
Rectangle {
  id: root

  property string label: ""
  property string kind: "neutral"
  property string accessibleName: ""
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  readonly property color toneColor: root.kind === "urgent"
      ? Commons.Color.urgent
      : (root.kind === "accent"
          ? Commons.Color.accent
          : Util.alpha(root.foreground, Tokens.TEXT_SECONDARY))

  visible: root.label.length > 0
  implicitWidth: tagText.implicitWidth + Style.space(10)
  implicitHeight: tagText.implicitHeight + Style.space(4)
  width: implicitWidth
  height: implicitHeight
  radius: Style.cornerRadius
  color: root.kind === "urgent"
      ? Util.alpha(Commons.Color.urgent, Tokens.URGENT_FILL)
      : (root.kind === "accent" ? Style.selectedAccentFill : "transparent")
  border.width: Style.spacing.hairline
  border.color: root.kind === "neutral" ? Style.normalBorderColor : root.toneColor

  Text {
    id: tagText
    anchors.centerIn: parent
    text: root.label
    color: root.toneColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.5
    textFormat: Text.PlainText
    Accessible.name: root.accessibleName.length > 0 ? root.accessibleName : root.label
    Accessible.role: Accessible.StaticText
  }
}
