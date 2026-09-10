import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// A section opens with its title and a rule running to the right edge, so
// sections separate without a full-width divider between them. The title is
// drawn here rather than with the host PanelSectionHeader, whose Qt.darker
// tint turns darker than body text on light themes.
Item {
  id: root

  property string text: ""
  property string count: ""
  property bool danger: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  width: parent ? parent.width : implicitWidth
  implicitHeight: row.implicitHeight

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(8)

    Text {
      text: root.text
      color: root.danger ? Color.urgent : Util.alpha(root.foreground, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      textFormat: Text.PlainText
      Accessible.role: Accessible.Heading
      Accessible.name: root.text
    }

    Text {
      visible: root.count.length > 0
      text: root.count
      color: Util.alpha(root.foreground, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }

    PanelSeparator {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      foreground: root.danger ? Color.urgent : root.foreground
    }
  }
}
