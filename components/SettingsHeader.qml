import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../CoreSettings.js" as Settings
import "Tokens.js" as Tokens

// UX-084: the pinned Settings header. Back returns to the usage view with
// the selection and the draft kept; the tab strip spans the popup width.
Column {
  id: root

  property string tab: "providers"
  property var changes: null
  property int innerRadius: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  signal backRequested()
  signal tabSelected(string id)

  width: parent ? parent.width : implicitWidth

  function collectFocusTargets() {
    if (!root.visible)
      return []
    var out = [backButton]
    for (var i = 0; i < tabRepeater.count; i++)
      out.push(tabRepeater.itemAt(i))
    return out
  }

  Rectangle {
    width: parent.width
    height: titleRow.implicitHeight + Style.space(16)
    color: Style.normalFill
    topLeftRadius: root.innerRadius
    topRightRadius: root.innerRadius

    Row {
      id: titleRow
      x: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Button {
        id: backButton
        iconText: Tokens.GLYPH_BACK
        focusable: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        Accessible.name: "Back to usage"
        function focusActivate() {
          root.backRequested()
        }
        Accessible.onPressAction: focusActivate()
        onClicked: focusActivate()
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Settings"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        textFormat: Text.PlainText
        Accessible.role: Accessible.Heading
        Accessible.name: text
      }
    }
  }

  PanelSeparator {
    objectName: "edgeRule"
    width: parent.width
    foreground: root.foreground
  }

  Item {
    width: parent.width
    height: tabRow.implicitHeight + Style.space(16)

    Row {
      id: tabRow
      x: Style.spacing.popupPadding
      width: parent.width - Style.spacing.popupPadding * 2
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.md

      Repeater {
        id: tabRepeater
        model: Settings.SETTINGS_TABS

        Button {
          required property var modelData
          readonly property bool pending: !!(root.changes && root.changes.tabs
              && root.changes.tabs[modelData.id] > 0)
          width: (tabRow.width - tabRow.spacing * (Settings.SETTINGS_TABS.length - 1))
              / Settings.SETTINGS_TABS.length
          text: modelData.label + (pending ? " •" : "")
          selected: root.tab === modelData.id
          bordered: true
          focusable: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.role: Accessible.PageTab
          Accessible.name: modelData.label
          Accessible.description: pending ? "Unsaved changes" : ""
          function focusActivate() {
            root.tabSelected(modelData.id)
          }
          Accessible.onPressAction: focusActivate()
          onClicked: focusActivate()
        }
      }
    }
  }

  PanelSeparator {
    objectName: "edgeRule"
    width: parent.width
    foreground: root.foreground
  }
}
