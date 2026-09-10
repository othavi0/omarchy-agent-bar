import QtQuick
import qs.Commons
import qs.Ui
import "CoreView.js" as Core
import "CoreSettings.js" as Settings
import "components"

// Race-safe Settings UI (SET-014..022, UX-033..039). Mutations go through Service.
// Layout C3 (2026-09-10 amendment): section headers, label-left rows, interval
// menus, and a save tray that exists only while the draft differs.
Item {
  id: root

  property var agentService: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property url iconBase: Qt.resolvedUrl("icons/")
  // A11Y-008: true while an interval menu is open.
  property bool editorOwnsFocus: (refreshDropdown ? !!refreshDropdown.popupOpen : false)
      || (reminderDropdown ? !!reminderDropdown.popupOpen : false)

  readonly property var state: agentService ? agentService.settingsState : null
  readonly property var draft: agentService ? agentService.settingsDraft : null
  readonly property var snapshot: state && state.snapshot ? state.snapshot : null
  readonly property string phase: state && state.phase ? String(state.phase) : "closed"
  readonly property bool locked: agentService
      ? agentService.settingsLocked()
      : true
  readonly property bool canSave: agentService ? agentService.canSaveSettings() : false
  readonly property bool loading: phase === "loading"
  readonly property bool loadFailed: phase === "load_failed"
  readonly property bool saving: phase === "saving"
  readonly property var changes: Settings.settingsChanges(snapshot, draft)

  readonly property var providers: {
    if (!draft || !Array.isArray(draft.providers))
      return []
    return draft.providers
  }

  readonly property string metric: {
    if (draft && draft.display && draft.display.metric === "used")
      return "used"
    return "remaining"
  }

  readonly property int intervalSec: {
    if (draft && isFinite(Number(draft.refreshIntervalSeconds)))
      return Number(draft.refreshIntervalSeconds)
    return 60
  }

  readonly property bool notificationsOn: {
    if (draft && draft.notifications)
      return !!draft.notifications.enabled
    return true
  }

  readonly property bool automaticUpdatesOn: {
    if (draft && draft.updates && typeof draft.updates.automatic === "boolean")
      return draft.updates.automatic
    return true
  }

  readonly property int reminderMinutes: {
    if (draft && draft.notifications
        && isFinite(Number(draft.notifications.reminderMinutes)))
      return Number(draft.notifications.reminderMinutes)
    return 120
  }

  width: parent ? parent.width : implicitWidth
  implicitHeight: col.implicitHeight

  function iconUrl(id) {
    var name = Core.iconFileName(id)
    if (!name.length)
      return ""
    return String(root.iconBase) + name
  }

  function changed(key) {
    return root.changes.indexOf(key) >= 0
  }

  function collectFocusTargets() {
    return root.loadFailed ? [restartShellButton] : []
  }

  Column {
    id: col
    width: parent.width
    spacing: Style.space(4)

    // Title with the draft-only reset beside it (SET-022).
    Item {
      width: parent.width
      height: Math.max(title.implicitHeight, restoreButton.implicitHeight)

      Text {
        id: title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Settings"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        textFormat: Text.PlainText
        Accessible.role: Accessible.Heading
      }

      Button {
        id: restoreButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.loading && !root.loadFailed
        text: "Restore defaults"
        focusable: true
        enabled: !root.locked
        foreground: Util.alpha(root.foreground, 0.72)
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        Accessible.name: "Restore defaults"
        onClicked: {
          if (root.agentService)
            root.agentService.restoreSettingsDefaults()
        }
      }
    }

    Text {
      visible: root.loading
      width: parent.width
      text: "Loading\u2026"
      color: Util.alpha(root.foreground, 0.72)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }

    // SET-026: a failed load names the recovery step instead of locking the
    // dialog behind "Loading" forever. Plain fixed copy; no helper output.
    Text {
      visible: root.loadFailed
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Settings could not be loaded. Restart the shell and try again."
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
      Accessible.role: Accessible.StaticText
      Accessible.name: text
    }

    Button {
      id: restartShellButton
      visible: root.loadFailed
      text: "Restart shell"
      bordered: true
      focusable: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      Accessible.name: "Restart shell"
      function focusActivate() {
        if (root.agentService)
          root.agentService.restartShell()
      }
      Accessible.onPressAction: focusActivate()
      onClicked: focusActivate()
    }

    Column {
      width: parent.width
      spacing: Style.space(2)
      visible: !root.loading && !root.loadFailed
      opacity: root.locked ? 0.55 : 1.0
      enabled: !root.locked

      PanelSectionHeader {
        width: parent.width
        topPadding: Style.space(8)
        text: "Providers"
        foreground: Util.alpha(root.foreground, 0.55)
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.providers

        SettingsProviderRow {
          required property var modelData
          required property int index
          width: parent.width
          providerId: String(modelData.id || "")
          displayName: Core.providerDisplayName(providerId)
          iconSource: root.iconUrl(providerId)
          enabled: !!modelData.enabled
          locked: root.locked
          changed: Settings.providerChanged(root.snapshot, root.draft, providerId)
          canMoveUp: index > 0
          canMoveDown: index < root.providers.length - 1
          foreground: root.foreground
          fontFamily: root.fontFamily
          onEnableToggled: {
            if (root.agentService)
              root.agentService.setProviderEnabled(providerId, !modelData.enabled)
          }
          onMoveUp: {
            if (root.agentService)
              root.agentService.moveProvider(providerId, -1)
          }
          onMoveDown: {
            if (root.agentService)
              root.agentService.moveProvider(providerId, 1)
          }
        }
      }

      PanelSectionHeader {
        width: parent.width
        topPadding: Style.space(14)
        text: "Bar"
        foreground: Util.alpha(root.foreground, 0.55)
        fontFamily: root.fontFamily
      }

      SettingsRow {
        label: "Bar shows"
        changed: root.changed("display.metric")
        foreground: root.foreground
        fontFamily: root.fontFamily

        Row {
          spacing: Style.space(4)

          Button {
            text: "Remaining"
            selected: root.metric === "remaining"
            bordered: true
            focusable: true
            enabled: !root.locked
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              if (root.agentService)
                root.agentService.setDisplayMetric("remaining")
            }
          }

          Button {
            text: "Used"
            selected: root.metric === "used"
            bordered: true
            focusable: true
            enabled: !root.locked
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              if (root.agentService)
                root.agentService.setDisplayMetric("used")
            }
          }
        }
      }

      SettingsRow {
        label: "Refresh every"
        changed: root.changed("refreshIntervalSeconds")
        foreground: root.foreground
        fontFamily: root.fontFamily

        Dropdown {
          id: refreshDropdown
          width: Style.space(120)
          showLabel: false
          label: "Refresh every"
          value: String(root.intervalSec)
          options: Settings.refreshIntervalOptions(root.intervalSec)
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.name: "Refresh every"
          onChanged: function (v) {
            if (root.agentService)
              root.agentService.setRefreshInterval(Number(v))
          }
        }
      }

      PanelSectionHeader {
        width: parent.width
        topPadding: Style.space(14)
        text: "Alerts"
        foreground: Util.alpha(root.foreground, 0.55)
        fontFamily: root.fontFamily
      }

      SettingsRow {
        label: "Warn me before a quota runs out"
        changed: root.changed("notifications.enabled")
        foreground: root.foreground
        fontFamily: root.fontFamily

        SettingsSwitch {
          accessibleName: "Warn me before a quota runs out"
          checked: root.notificationsOn
          locked: root.locked
          foreground: root.foreground
          onToggled: {
            if (root.agentService)
              root.agentService.setNotificationsEnabled(!root.notificationsOn)
          }
        }
      }

      SettingsRow {
        label: "Remind me every"
        subordinate: true
        opacity: root.notificationsOn ? 1.0 : 0.55
        changed: root.changed("notifications.reminderMinutes")
        foreground: root.foreground
        fontFamily: root.fontFamily

        Dropdown {
          id: reminderDropdown
          width: Style.space(120)
          showLabel: false
          label: "Remind me every"
          value: String(root.reminderMinutes)
          options: Settings.reminderOptions(root.reminderMinutes)
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.name: "Remind me every"
          onChanged: function (v) {
            if (root.agentService)
              root.agentService.setReminderMinutes(Number(v))
          }
        }
      }

      PanelSectionHeader {
        width: parent.width
        topPadding: Style.space(14)
        text: "Updates"
        foreground: Util.alpha(root.foreground, 0.55)
        fontFamily: root.fontFamily
      }

      SettingsRow {
        label: "Install automatically"
        changed: root.changed("updates.automatic")
        foreground: root.foreground
        fontFamily: root.fontFamily

        SettingsSwitch {
          accessibleName: "Install updates automatically"
          checked: root.automaticUpdatesOn
          locked: root.locked
          foreground: root.foreground
          onToggled: {
            if (root.agentService)
              root.agentService.setAutomaticUpdates(!root.automaticUpdatesOn)
          }
        }
      }
    }

    // Version, check, update, and uninstall act immediately, outside the
    // draft, so they stay enabled while the draft is locked.
    MaintenanceView {
      visible: !root.loading && !root.loadFailed
      width: parent.width
      agentService: root.agentService
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Item { width: 1; height: Style.space(6) }

    // Save tray (UX-036..038): exists only while the draft differs from the
    // saved settings, and names how many changes it holds.
    Rectangle {
      visible: root.phase === "dirty" || root.saving
      width: parent.width
      height: tray.implicitHeight + Style.space(16)
      color: Color.menu.selectedBackground

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: root.saving ? "Saving\u2026" : Settings.unsavedChangesLabel(root.changes.length)
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
        Accessible.role: Accessible.StaticText
        Accessible.name: text
      }

      Row {
        id: tray
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

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
          text: "Save changes"
          bordered: true
          focusable: true
          enabled: root.canSave
          foreground: Color.accent
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
}
