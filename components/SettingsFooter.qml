import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../CoreSettings.js" as Settings
import "Tokens.js" as Tokens

// Pinned under the Settings scroll surface so Save stays reachable on every
// tab without scrolling. Full width like the usage footer (UX-084): the fill
// and the top rule meet the border, and the buttons carry their own inset.
Rectangle {
  id: root
  objectName: "settingsFooter"

  property var agentService: null
  property bool active: false
  property int innerRadius: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  readonly property var settingsState: agentService ? agentService.settingsState : null
  readonly property string phase: settingsState && settingsState.phase ? String(settingsState.phase) : "closed"
  readonly property bool shown: active
      && (phase === "clean" || phase === "dirty" || phase === "saving")
  readonly property bool locked: agentService ? agentService.settingsLocked() : true
  readonly property bool saving: phase === "saving"
  readonly property bool canSave: agentService ? agentService.canSaveSettings() : false
  readonly property int changeCount: Settings.settingsChanges(
    settingsState ? settingsState.snapshot : null,
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
  width: parent ? parent.width : implicitWidth
  implicitHeight: shown ? rule.height + buttons.implicitHeight + Style.space(16) : 0
  height: implicitHeight
  color: Style.normalFill
  bottomLeftRadius: root.innerRadius
  bottomRightRadius: root.innerRadius

  function collectFocusTargets() {
    return shown ? [restoreButton, cancelButton, saveButton] : []
  }

  PanelSeparator {
    id: rule
    objectName: "edgeRule"
    width: parent.width
    foreground: root.foreground
  }

  RowLayout {
    id: buttons
    x: Style.spacing.popupPadding
    y: rule.height + Style.space(8)
    width: parent.width - Style.spacing.popupPadding * 2
    spacing: Style.space(8)

    Button {
      id: restoreButton
      text: "Restore defaults"
      focusable: true
      enabled: !root.locked
      foreground: root.foreground
      fontFamily: root.fontFamily
      Accessible.name: "Restore defaults"
      function focusActivate() {
        if (root.agentService)
          root.agentService.restoreSettingsDefaults()
      }
      Accessible.onPressAction: focusActivate()
      onClicked: focusActivate()
    }

    Text {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignRight
      text: root.statusText
      color: Util.alpha(root.foreground, Tokens.TEXT_SECONDARY)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideLeft
      textFormat: Text.PlainText
      Accessible.role: Accessible.StaticText
      Accessible.name: text
    }

    Button {
      id: cancelButton
      text: "Cancel"
      bordered: true
      focusable: true
      enabled: !root.locked && root.phase === "dirty" && root.changeCount > 0
      foreground: root.foreground
      fontFamily: root.fontFamily
      Accessible.name: "Cancel"
      function focusActivate() {
        if (root.agentService)
          root.agentService.cancelSettings()
      }
      Accessible.onPressAction: focusActivate()
      onClicked: focusActivate()
    }

    Button {
      id: saveButton
      readonly property bool ready: root.canSave && root.changeCount > 0
      text: root.saving ? "Saving\u2026" : "Save changes"
      bordered: true
      selected: ready
      focusable: true
      enabled: ready
      foreground: root.foreground
      fontFamily: root.fontFamily
      Accessible.name: "Save changes"
      function focusActivate() {
        if (root.agentService)
          root.agentService.saveSettings()
      }
      Accessible.onPressAction: focusActivate()
      onClicked: focusActivate()
    }
  }
}
