import QtQuick
import qs.Commons
import qs.Commons as Commons

// Test stand-in for the host labelled toggle row.
Item {
  id: root

  property string label: ""
  property string description: ""
  property bool checked: false
  property bool hasCursor: false
  property bool rounded: Style.cornerRadius > 0
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property real titleSize: Style.font.subtitle
  property real descriptionSize: Style.font.caption

  signal clicked()
  signal hovered(bool isHovered)

  implicitWidth: column.implicitWidth
  implicitHeight: column.implicitHeight + Style.spacing.controlPaddingY * 2
  activeFocusOnTab: true
  Keys.onReturnPressed: root.clicked()
  Keys.onEnterPressed: root.clicked()
  Keys.onSpacePressed: root.clicked()

  Column {
    id: column
    anchors.verticalCenter: parent.verticalCenter

    Text {
      text: (root.checked ? "[x] " : "[ ] ") + root.label
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.titleSize
    }

    Text {
      visible: root.description.length > 0
      text: root.description
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.descriptionSize
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.clicked()
  }
}
