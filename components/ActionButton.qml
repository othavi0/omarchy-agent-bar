import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tokens.js" as Tokens

// The popup's one button look. Tonal: the accent at a low share over the
// surface, its label the accent pulled to readable contrast. Plain: text
// alone. Both paint their own hover, focus and press tones over `surface`,
// the colour the button sits on.
Button {
  id: root

  property bool tonal: true
  property color surface: Commons.Color.popups.background

  signal activated()

  readonly property color fillTo: root.tonal ? Commons.Color.accent : root.foreground
  readonly property color accentText: Tokens.readableAccent(
      Commons.Color.accent,
      Tokens.mix(root.surface, Commons.Color.accent, Tokens.PRIMARY_PRESS),
      Commons.Color.foreground)

  height: Style.spacing.controlHeight
  bordered: false
  focusable: true
  horizontalPadding: Style.space(8)
  fontSize: Style.font.bodySmall
  iconSize: Style.font.bodySmall
  foreground: !root.enabled ? Util.alpha(Commons.Color.foreground, Tokens.TEXT_TERTIARY)
      : (root.tonal ? root.accentText : Util.alpha(Commons.Color.foreground, Tokens.TEXT_SECONDARY))
  background: !root.tonal ? "transparent"
      : (root.enabled
          ? Tokens.mix(root.surface, Commons.Color.accent, Tokens.PRIMARY_REST)
          : Tokens.mix(root.surface, Commons.Color.foreground, Tokens.BUTTON_OFF))
  color: !root.enabled ? root.background
      : press.active
          ? Tokens.mix(root.surface, root.fillTo, root.tonal ? Tokens.PRIMARY_PRESS : Tokens.BUTTON_PRESS)
      : root.hot || root.activeFocus
          ? Tokens.mix(root.surface, root.fillTo, root.tonal ? Tokens.PRIMARY_HOT : Tokens.BUTTON_HOT)
          : root.background
  Accessible.name: text

  function focusActivate() {
    if (root.enabled)
      root.activated()
  }
  Accessible.onPressAction: focusActivate()
  onClicked: focusActivate()

  // Setting `color` replaces the host fill rule, press included, and the
  // host MouseArea is private. A passive handler above it sees the press
  // without taking the click.
  Item {
    anchors.fill: parent
    PointHandler { id: press; acceptedButtons: Qt.LeftButton }
  }
}
