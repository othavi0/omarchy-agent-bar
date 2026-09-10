import QtQuick
import qs.Commons
import qs.Ui
import "CoreMaintenance.js" as Core
import "components"

// Updates section body: version, update check/apply, uninstall
// (UX-040..047). SettingsView owns the "Updates" header and the automatic
// switch above these rows; every action here is immediate, not drafted.
Item {
  id: root

  property var agentService: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var ui: agentService && agentService.maintenanceUi
      ? agentService.maintenanceUi
      : Core.maintenanceUiIdle("")

  readonly property bool blocked: agentService && agentService.maintenanceState
      ? !!agentService.maintenanceState.blocked
      : false

  readonly property bool checking: ui.phase === "checking"
  readonly property bool updateAvailable: ui.phase === "update_available"
  readonly property bool applying: ui.phase === "applying" || ui.phase === "uninstalling"

  width: parent ? parent.width : implicitWidth
  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: parent.width
    spacing: Style.space(2)

    // UX-040 installed version, with the explicit check beside it (UX-041).
    Item {
      width: parent.width
      height: Math.max(Style.space(32), checkButton.implicitHeight)

      Text {
        anchors.left: parent.left
        anchors.right: checkButton.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "Version "
            + (ui.installedVersion && ui.installedVersion.length
                ? ui.installedVersion
                : "—")
        color: Util.alpha(root.foreground, 0.72)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        textFormat: Text.PlainText
        Accessible.name: text
      }

      Button {
        id: checkButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.checking ? "Checking\u2026" : "Check for updates"
        focusable: true
        enabled: !root.blocked && !root.checking && !root.applying
        foreground: Util.alpha(root.foreground, 0.72)
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        Accessible.name: "Check for updates"
        onClicked: {
          if (root.agentService)
            root.agentService.checkForUpdates()
        }
      }
    }

    Text {
      width: parent.width
      visible: ui.message && ui.message.length > 0
      text: ui.message
      color: ui.phase === "error"
          ? Color.urgent
          : (root.updateAvailable ? Color.accent : Util.alpha(root.foreground, 0.55))
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
    }

    // UX-042 available update: notes link and the confirmed apply.
    Item {
      visible: root.updateAvailable && ui.targetVersion && ui.targetVersion.length > 0
      width: parent.width
      height: updateRow.implicitHeight

      Row {
        id: updateRow
        anchors.right: parent.right
        spacing: Style.space(8)

        Button {
          visible: ui.releaseNotesUrl && String(ui.releaseNotesUrl).indexOf("https://") === 0
          text: "Release notes"
          focusable: true
          enabled: !root.applying
          foreground: Util.alpha(root.foreground, 0.72)
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          Accessible.name: "Release notes"
          onClicked: {
            if (root.agentService)
              root.agentService.openReleaseNotes()
          }
        }

        Button {
          text: "Update to " + ui.targetVersion
          bordered: true
          focusable: true
          enabled: !root.blocked && !root.applying
          foreground: Color.accent
          fontFamily: root.fontFamily
          Accessible.name: text
          onClicked: {
            if (root.agentService)
              root.agentService.openUpdateConfirm()
          }
        }
      }
    }

    Item { width: 1; height: Style.space(6) }

    // UX-044 danger action: the only red control, alone on its row.
    Button {
      text: "Uninstall Agent Bar"
      leftAlign: true
      horizontalPadding: 0
      focusable: true
      enabled: !root.blocked && !root.applying
      foreground: Color.urgent
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      Accessible.name: "Uninstall Agent Bar"
      onClicked: {
        if (root.agentService)
          root.agentService.openUninstallConfirm()
      }
    }
  }

  // Update confirmation (UX-043)
  ConfirmDialog {
    opened: !!ui.updateConfirmOpen
    title: "Confirm update"
    message: Core.updateConfirmMessage(ui)
    cancelText: "Cancel"
    confirmText: "Update"
    destructive: false
    foreground: root.foreground
    fontFamily: root.fontFamily
    onCanceled: {
      if (root.agentService)
        root.agentService.closeUpdateConfirm()
    }
    onConfirmed: {
      if (root.agentService)
        root.agentService.confirmUpdateApply()
    }
  }

  // Uninstall confirmation (UX-045..047)
  ConfirmDialog {
    opened: !!ui.uninstallConfirmOpen
    title: "Uninstall Agent Bar"
    message: ui.uninstallArmed
        ? (ui.purgeSettings
            ? "Deletes Agent Bar, your settings and every backup."
            : "Deletes Agent Bar. Your settings stay.")
        : "Removes Agent Bar. Your settings stay."
    cancelText: "Cancel"
    confirmText: ui.uninstallArmed ? "Uninstall now" : "Uninstall"
    destructive: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    onCanceled: {
      if (root.agentService)
        root.agentService.closeUninstallConfirm()
    }
    onConfirmed: {
      if (root.agentService)
        root.agentService.armOrConfirmUninstall()
    }

    // UX-046: purge checkbox default unchecked
    Toggle {
      label: "Also delete saved settings and backups"
      description: "Unchecked by default. Standard uninstall preserves settings."
      checked: !!ui.purgeSettings
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: {
        if (root.agentService)
          root.agentService.setUninstallPurge(!ui.purgeSettings)
      }
    }
  }
}
