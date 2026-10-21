import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "CoreView.js" as Core
import "CoreSettings.js" as Settings
import "components"
import "components/Tokens.js" as Tokens

Item {
  id: root

  property var agentService: null
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property string tab: "providers"
  property bool editorOwnsFocus: (intervalField && intervalField.field
        ? !!intervalField.field.activeFocus
        : false)
      || (reminderField && reminderField.field
        ? !!reminderField.field.activeFocus
        : false)
      || maintenanceView.editorOwnsFocus

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

  readonly property int reminderMinutes: {
    if (draft && draft.notifications
        && isFinite(Number(draft.notifications.reminderMinutes)))
      return Number(draft.notifications.reminderMinutes)
    return 120
  }

  // UX-084: the view spans the popup; text and controls carry this inset and
  // the rows and section rules run to the border.
  readonly property int inset: Style.spacing.popupPadding
  readonly property int edgeGap: Style.space(12)

  // A change here rebuilds the popup focus order: the tab, the provider
  // rows (the Repeaters rebuild their delegates on every draft change), the
  // reminder field and the About buttons.
  readonly property string focusShape: [
    root.tab, root.phase, root.loadFailed, root.locked, root.notificationsOn,
    root.sectionIds(root.sections.shown), root.sectionIds(root.sections.hidden),
    maintenanceView.ui.phase, maintenanceView.notesAvailable
  ].join("|")

  // The row control the keyboard last acted on. A move or a toggle rebuilds
  // the rows, so focus returns to that control on the moved row.
  property var focusAnchor: null

  width: parent ? parent.width : implicitWidth
  implicitHeight: col.implicitHeight + root.edgeGap * 2

  function sectionIds(list) {
    var ids = []
    for (var i = 0; i < list.length; i++)
      ids.push(list[i].id)
    return ids.join(",")
  }

  function providerDetail(id) {
    var provider = Core.findProvider(root.snapshot, id)
    var status = Core.settingsProviderStatus(provider)
    if (status.length)
      return status
    return Core.plainText(Core.planBadge(provider))
  }

  function rowsOf(repeater) {
    var out = []
    for (var i = 0; i < repeater.count; i++) {
      var row = repeater.itemAt(i)
      if (row)
        out.push(row)
    }
    return out
  }

  function anchorRow(providerId, control) {
    root.focusAnchor = { id: String(providerId), control: control }
  }

  // Returns the anchored control on its rebuilt row, once.
  function anchoredFocusTarget() {
    var anchor = root.focusAnchor
    root.focusAnchor = null
    if (!anchor || root.tab !== "providers")
      return null
    var rows = rowsOf(shownRepeater).concat(rowsOf(hiddenRepeater))
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].providerId !== anchor.id)
        continue
      // A row moved to an end loses that chevron; the other one is nearest.
      var order = [anchor.control, anchor.control === "up" ? "down" : "up", "switch"]
      for (var j = 0; j < order.length; j++) {
        var target = rows[i].focusTarget(order[j])
        if (target.visible && target.enabled)
          return target
      }
      return null
    }
    return null
  }

  function collectFocusTargets() {
    var out = []
    if (root.loadFailed)
      out.push(restartShellButton)
    if (root.tab === "providers") {
      var rows = rowsOf(shownRepeater).concat(rowsOf(hiddenRepeater))
      for (var i = 0; i < rows.length; i++)
        out = out.concat(rows[i].collectFocusTargets())
    } else if (root.tab === "general") {
      out.push(metricGroup, intervalField.field, notificationsToggle)
      if (root.notificationsOn)
        out.push(reminderField.field)
    } else if (root.tab === "about") {
      out = out.concat(maintenanceView.collectFocusTargets())
    }
    return out
  }

  Column {
    id: col
    y: root.edgeGap
    width: parent.width
    spacing: Style.spacing.huge

    Column {
      visible: root.loading || root.loadFailed
      x: root.inset
      width: parent.width - root.inset * 2
      spacing: Style.space(8)

      Text {
        visible: root.loading
        width: parent.width
        text: "Loading\u2026"
        color: Util.alpha(root.foreground, Tokens.TEXT_SECONDARY)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      Text {
        visible: root.loadFailed
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Settings could not be loaded. Restart the shell and try again."
        color: Commons.Color.urgent
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

    // A hidden tab is disabled too: Qt keeps focus on an invisible item, and
    // a spin box left focused on another tab would take the arrow keys.
    Column {
      visible: root.tab === "providers"
      width: parent.width
      spacing: Style.spacing.huge
      opacity: root.locked ? Tokens.LOCKED : 1.0
      enabled: !root.locked && visible

      Column {
        width: parent.width

        SectionHeader {
          x: root.inset
          width: parent.width - root.inset * 2
          bleed: root.inset
          text: "On the bar"
          count: String(root.sections.shown.length)
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          x: root.inset
          topPadding: Style.space(6)
          bottomPadding: Style.space(2)
          text: "The bar shows them in this order."
          color: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }

        Repeater {
          id: shownRepeater
          model: root.sections.shown

          SettingsProviderRow {
            required property var modelData
            width: parent.width
            providerId: modelData.id
            displayName: Core.providerDisplayName(modelData.id)
            detailText: root.providerDetail(modelData.id)
            enabled: true
            locked: root.locked
            canMoveUp: modelData.canMoveUp
            canMoveDown: modelData.canMoveDown
            foreground: root.foreground
            fontFamily: root.fontFamily
            onEnableToggled: {
              root.anchorRow(providerId, "switch")
              if (root.agentService)
                root.agentService.setProviderEnabled(providerId, false)
            }
            onMoveUp: {
              root.anchorRow(providerId, "up")
              if (root.agentService)
                root.agentService.moveProvider(providerId, -1)
            }
            onMoveDown: {
              root.anchorRow(providerId, "down")
              if (root.agentService)
                root.agentService.moveProvider(providerId, 1)
            }
          }
        }
      }

      Column {
        visible: root.sections.hidden.length > 0
        width: parent.width

        SectionHeader {
          x: root.inset
          width: parent.width - root.inset * 2
          bleed: root.inset
          text: "Hidden"
          count: String(root.sections.hidden.length)
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          id: hiddenRepeater
          model: root.sections.hidden

          SettingsProviderRow {
            required property var modelData
            width: parent.width
            providerId: modelData.id
            displayName: Core.providerDisplayName(modelData.id)
            detailText: root.providerDetail(modelData.id)
            enabled: false
            locked: root.locked
            movable: false
            foreground: root.foreground
            fontFamily: root.fontFamily
            onEnableToggled: {
              root.anchorRow(providerId, "switch")
              if (root.agentService)
                root.agentService.setProviderEnabled(providerId, true)
            }
          }
        }
      }
    }

    Column {
      visible: root.tab === "general"
      x: root.inset
      width: parent.width - root.inset * 2
      spacing: Style.spacing.huge
      opacity: root.locked ? Tokens.LOCKED : 1.0
      enabled: !root.locked && visible

      Column {
        width: parent.width
        spacing: Style.space(8)

        SectionHeader {
          bleed: root.inset
          text: "Bar shows"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          ButtonGroup {
            id: metricGroup
            objectName: "metricGroup"
            Accessible.name: "Bar shows"
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
            color: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
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
                source: root.previewProvider ? Core.iconUrl(root.previewProvider.id) : ""
                width: Style.bar.iconSize
                height: Style.bar.iconSize
                sourceSize.width: Style.bar.iconSize
                sourceSize.height: Style.bar.iconSize
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
          bleed: root.inset
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
            objectName: "intervalField"
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
            color: Util.alpha(root.foreground, Tokens.TEXT_SECONDARY)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
            Accessible.ignored: true
          }
        }

        Toggle {
          id: notificationsToggle
          objectName: "notificationsToggle"
          width: parent.width
          label: "Notifications"
          Accessible.name: "Notifications"
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
          opacity: root.notificationsOn ? 1.0 : Tokens.LOCKED

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
            objectName: "reminderField"
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
            color: Util.alpha(root.foreground, Tokens.TEXT_SECONDARY)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
            Accessible.ignored: true
          }
        }
      }
    }

    MaintenanceView {
      id: maintenanceView
      visible: root.tab === "about"
      enabled: visible
      x: root.inset
      width: parent.width - root.inset * 2
      edgeBleed: root.inset
      agentService: root.agentService
      settingsLocked: root.locked
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }
}
