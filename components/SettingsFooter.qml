import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../CoreSettings.js" as Settings

// Pinned under the Settings scroll surface so Save stays reachable on every
// tab without scrolling.
Item {
  id: root

  property var agentService: null
  property bool active: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var state: agentService ? agentService.settingsState : null
  readonly property string phase: state && state.phase ? String(state.phase) : "closed"
  readonly property bool shown: active
      && (phase === "clean" || phase === "dirty" || phase === "saving")
  readonly property bool locked: agentService ? agentService.settingsLocked() : true
  readonly property bool saving: phase === "saving"
  readonly property bool canSave: agentService ? agentService.canSaveSettings() : false
  readonly property int changeCount: Settings.settingsChanges(
    state ? state.snapshot : null,
    agentService ? agentService.settingsDraft : null
  ).count

  readonly property string statusText: {
    if (saving)
      return "Saving\u2026"
    if (changeCount === 1)
      return "1 unsaved change"
    if (changeCount > 1)
      return changeCount + " unsaved changes"
    return "No changes"
  }

  visible: shown
  implicitHeight: shown ? body.implicitHeight : 0

  Column {
    id: body
    width: parent.width
    spacing: Style.space(8)

    PanelSeparator {
      width: parent.width
      foreground: root.foreground
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      Button {
        text: "Restore defaults"
        focusable: true
        enabled: !root.locked
        foreground: root.foreground
        fontFamily: root.fontFamily
        Accessible.name: "Restore defaults"
        onClicked: {
          if (root.agentService)
            root.agentService.restoreSettingsDefaults()
        }
      }

      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        text: root.statusText
        color: Util.alpha(root.foreground, 0.72)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideLeft
        textFormat: Text.PlainText
        Accessible.role: Accessible.StaticText
        Accessible.name: text
      }

      Button {
        text: "Cancel"
        bordered: true
        focusable: true
        enabled: !root.locked && root.phase === "dirty"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Accessible.name: "Cancel"
        onClicked: {
          if (root.agentService)
            root.agentService.cancelSettings()
        }
      }

      Button {
        text: root.saving ? "Saving\u2026" : "Save changes"
        bordered: true
        selected: root.canSave
        focusable: true
        enabled: root.canSave
        foreground: root.foreground
        fontFamily: root.fontFamily
        Accessible.name: "Save changes"
        onClicked: {
          if (root.agentService)
            root.agentService.saveSettings()
        }
      }
    }
  }
}
