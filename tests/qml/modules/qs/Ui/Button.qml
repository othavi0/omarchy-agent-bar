import QtQuick
import qs.Commons
import qs.Commons as Commons

// Test stand-in for the host Button: same public surface, icon and label
// drawn as plain text without the host BorderSurface states. Like the host,
// the root is the filled surface, so `color` and `radius` are public.
Rectangle {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property bool selected: false
  property bool active: false
  property bool hasCursor: false
  property bool focusable: false
  property bool bordered: false
  property color foreground: Commons.Color.foreground
  property color background: "transparent"
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real iconSize: Style.font.icon
  property real iconRotation: 0
  property bool iconSpinning: false
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY
  property bool leftAlign: false
  property color tooltipBackground: Commons.Color.tooltip.background
  property color tooltipForeground: Commons.Color.tooltip.text
  property color tooltipBorder: Commons.Color.tooltip.border

  readonly property bool hot: mouseArea.containsMouse || hasCursor

  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  implicitWidth: row.implicitWidth + horizontalPadding * 2
  implicitHeight: Math.max(label.implicitHeight, iconGlyph.implicitHeight) + verticalPadding * 2
  color: root.background
  radius: Style.cornerRadius
  border.width: root.bordered ? Style.normalBorderWidth : 0
  border.color: Style.normalBorderFor(root.foreground, root.accent)
  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    x: root.leftAlign ? root.horizontalPadding : Math.max(0, (root.width - implicitWidth) / 2)
    spacing: Style.spacing.controlGap

    Text {
      id: iconGlyph
      visible: root.iconText.length > 0
      text: root.iconText
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      rotation: root.iconRotation
    }

    Text {
      id: label
      visible: root.text.length > 0
      text: root.text
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function (mouse) {
      if (mouse.button === Qt.RightButton)
        root.rightClicked()
      else
        root.clicked()
    }
  }
}
