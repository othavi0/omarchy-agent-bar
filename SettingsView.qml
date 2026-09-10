import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "CoreView.js" as Core
import "CoreSettings.js" as Settings
import "components"

Item {
  id: root

  property var agentService: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property url iconBase: Qt.resolvedUrl("icons/")
  property string tab: "providers"
  property bool editorOwnsFocus: (intervalField && intervalField.field
        ? !!intervalField.field.activeFocus
        : false)
      || (reminderField && reminderField.field
        ? !!reminderField.field.activeFocus
        : false)

  readonly property var state: agentService ? agentService.settingsState : null
  readonly property var draft: agentService ? agentService.settingsDraft : null
  readonly property var snapshot: agentService ? agentService.snapshot : null
  readonly property string phase: state && state.phase ? String(state.phase) : "closed"
  readonly property bool locked: agentService
      ? agentService.settingsLocked()
      : true
  readonly property bool loading: phase === "loading"
  readonly property bool loadFailed: phase === "load_failed"

  readonly property var sections: Settings.providerSections(draft)
  readonly property var changes: Settings.settingsChanges(state ? state.snapshot : null, draft)

  readonly property var tabOptions: {
    var out = []
    for (var i = 0; i < Settings.SETTINGS_TABS.length; i++) {
      var t = Settings.SETTINGS_TABS[i]
      out.push({
        value: t.id,
        label: t.label + (root.changes.tabs[t.id] > 0 ? " •" : "")
      })
    }
    return out
  }

  readonly property string metric: {
    if (draft && draft.display && draft.display.metric === "used")
      return "used"
    return "remaining"
  }

  readonly property var previewProvider: {
    for (var i = 0; i < sections.shown.length; i++) {
      var p = Core.findProvider(snapshot, sections.shown[i].id)
      if (p && Core.presentsReading(p.state) && p.windows && p.windows.length)
        return p
    }
    return null
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

  function providerStatus(id) {
    return Core.settingsProviderStatus(Core.findProvider(root.snapshot, id))
  }

  function collectFocusTargets() {
    return root.loadFailed ? [restartShellButton] : []
  }

  Column {
    id: col
    width: parent.width
    spacing: Style.spacing.huge

    Column {
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: "Settings"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        textFormat: Text.PlainText
        Accessible.role: Accessible.Heading
      }

      ButtonGroup {
        options: root.tabOptions
        value: root.tab
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function (value) { root.tab = value }
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
    }

    Column {
      visible: root.tab === "providers"
      width: parent.width
      spacing: Style.spacing.huge
      opacity: root.locked ? 0.55 : 1.0
      enabled: !root.locked

      Column {
        width: parent.width
        spacing: Style.space(2)

        SectionHeader {
          text: "On the bar"
          count: String(root.sections.shown.length)
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          bottomPadding: Style.space(4)
          text: "The bar shows them in this order."
          color: Util.alpha(root.foreground, 0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }

        Repeater {
          model: root.sections.shown

          SettingsProviderRow {
            required property var modelData
            width: parent.width
            providerId: modelData.id
            displayName: Core.providerDisplayName(modelData.id)
            statusText: root.providerStatus(modelData.id)
            iconSource: root.iconUrl(modelData.id)
            enabled: true
            locked: root.locked
            canMoveUp: modelData.canMoveUp
            canMoveDown: modelData.canMoveDown
            foreground: root.foreground
            fontFamily: root.fontFamily
            onEnableToggled: {
              if (root.agentService)
                root.agentService.setProviderEnabled(providerId, false)
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
      }

      Column {
        visible: root.sections.hidden.length > 0
        width: parent.width
        spacing: Style.space(2)

        SectionHeader {
          text: "Hidden"
          count: String(root.sections.hidden.length)
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          model: root.sections.hidden

          SettingsProviderRow {
            required property var modelData
            width: parent.width
            providerId: modelData.id
            displayName: Core.providerDisplayName(modelData.id)
            statusText: root.providerStatus(modelData.id)
            iconSource: root.iconUrl(modelData.id)
            enabled: false
            locked: root.locked
            movable: false
            foreground: root.foreground
            fontFamily: root.fontFamily
            onEnableToggled: {
              if (root.agentService)
                root.agentService.setProviderEnabled(providerId, true)
            }
          }
        }
      }
    }

    Column {
      visible: root.tab === "general"
      width: parent.width
      spacing: Style.spacing.huge
      opacity: root.locked ? 0.55 : 1.0
      enabled: !root.locked

      Column {
        width: parent.width
        spacing: Style.space(8)

        SectionHeader {
          text: "Bar shows"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          ButtonGroup {
            options: [
              { value: "remaining", label: "Remaining" },
              { value: "used", label: "Used" }
            ]
            value: root.metric
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function (value) {
              if (root.agentService)
                root.agentService.setDisplayMetric(value)
            }
          }

          Item { Layout.fillWidth: true }

          Text {
            visible: root.previewProvider !== null
            text: "Bar reads"
            color: Util.alpha(root.foreground, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }

          Rectangle {
            visible: root.previewProvider !== null
            implicitWidth: previewRow.implicitWidth + Style.spacing.controlPaddingX
            implicitHeight: Style.space(24)
            radius: Style.cornerRadius
            color: Style.hoverFill

            Row {
              id: previewRow
              anchors.centerIn: parent
              spacing: Style.spacing.sm

              Image {
                anchors.verticalCenter: parent.verticalCenter
                source: root.previewProvider ? root.iconUrl(root.previewProvider.id) : ""
                width: 14
                height: 14
                sourceSize.width: 14
                sourceSize.height: 14
                fillMode: Image.PreserveAspectFit
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.previewProvider
                    ? Core.chipPercentText(root.previewProvider, root.metric)
                    : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                textFormat: Text.PlainText
              }
            }

            Accessible.role: Accessible.StaticText
            Accessible.name: root.previewProvider
                ? "Bar reads " + Core.chipAccessibleLabel(root.previewProvider, root.metric)
                : ""
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(8)

        SectionHeader {
          text: "Refresh and alerts"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: "Refresh every"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }

          NumberField {
            id: intervalField
            fieldWidth: Style.space(88)
            value: root.intervalSec
            from: 30
            to: 3600
            stepSize: 5
            foreground: root.foreground
            fontFamily: root.fontFamily
            Accessible.name: "Refresh every, in seconds"
            onModified: function (v) {
              if (root.agentService)
                root.agentService.setRefreshInterval(v)
            }
          }

          Text {
            Layout.preferredWidth: Style.space(52)
            text: "seconds"
            color: Util.alpha(root.foreground, 0.72)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
            Accessible.ignored: true
          }
        }

        Toggle {
          width: parent.width
          label: "Notifications"
          description: "Warn me before a quota runs out."
          checked: root.notificationsOn
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: {
            if (root.agentService)
              root.agentService.setNotificationsEnabled(!root.notificationsOn)
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)
          enabled: root.notificationsOn
          opacity: root.notificationsOn ? 1.0 : 0.55

          Text {
            Layout.fillWidth: true
            text: "Remind me every"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }

          NumberField {
            id: reminderField
            fieldWidth: Style.space(88)
            value: root.reminderMinutes
            from: 15
            to: 1440
            stepSize: 15
            foreground: root.foreground
            fontFamily: root.fontFamily
            Accessible.name: "Remind me every, in minutes"
            onModified: function (v) {
              if (root.agentService)
                root.agentService.setReminderMinutes(v)
            }
          }

          Text {
            Layout.preferredWidth: Style.space(52)
            text: "minutes"
            color: Util.alpha(root.foreground, 0.72)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
            Accessible.ignored: true
          }
        }
      }
    }

    MaintenanceView {
      visible: root.tab === "about"
      width: parent.width
      agentService: root.agentService
      settingsLocked: root.locked
      automaticUpdatesOn: root.automaticUpdatesOn
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }
}
