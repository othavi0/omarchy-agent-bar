import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "CoreMaintenance.js" as Core
import "components"

Item {
  id: root

  property var agentService: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool settingsLocked: true
  property bool automaticUpdatesOn: true

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
    spacing: Style.spacing.huge

    Column {
      width: parent.width
      spacing: Style.space(8)

      SectionHeader {
        text: "Version"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Column {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: "Agent Bar "
                + (ui.installedVersion && ui.installedVersion.length
                    ? ui.installedVersion
                    : "\u2014")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            Accessible.name: "Installed version " + (ui.installedVersion || "unknown")
          }

          Text {
            width: parent.width
            visible: ui.message && ui.message.length > 0
            text: ui.message
            color: ui.phase === "error" ? Color.urgent : Util.alpha(root.foreground, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
          }
        }

        Button {
          text: root.checking ? "Checking\u2026" : "Check for updates"
          bordered: true
          focusable: true
          enabled: !root.blocked && !root.checking && !root.applying
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.name: "Check for updates"
          onClicked: {
            if (root.agentService)
              root.agentService.checkForUpdates()
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(8)
        visible: updateButton.visible || notesButton.visible

        Button {
          id: updateButton
          visible: root.updateAvailable && ui.targetVersion && ui.targetVersion.length > 0
          text: "Update to " + ui.targetVersion
          bordered: true
          focusable: true
          enabled: !root.blocked && !root.applying
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.name: text
          onClicked: {
            if (root.agentService)
              root.agentService.openUpdateConfirm()
          }
        }

        Button {
          id: notesButton
          visible: ui.releaseNotesUrl && String(ui.releaseNotesUrl).indexOf("https://") === 0
          text: "Release notes"
          bordered: true
          focusable: true
          enabled: !root.applying
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.name: "Release notes"
          onClicked: {
            if (root.agentService)
              root.agentService.openReleaseNotes()
          }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(8)
      opacity: root.settingsLocked ? 0.55 : 1.0
      enabled: !root.settingsLocked

      SectionHeader {
        text: "Updates"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Toggle {
        width: parent.width
        label: "Update automatically"
        description: "Install new versions and reload the shell."
        checked: root.automaticUpdatesOn
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          if (root.agentService)
            root.agentService.setAutomaticUpdates(!root.automaticUpdatesOn)
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(8)

      SectionHeader {
        text: "Danger zone"
        foreground: Color.urgent
        fontFamily: root.fontFamily
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          Layout.fillWidth: true
          text: "Removes Agent Bar. Your settings stay."
          color: Util.alpha(root.foreground, 0.72)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
        }

        Button {
          text: "Uninstall Agent Bar"
          bordered: true
          focusable: true
          enabled: !root.blocked && !root.applying
          foreground: Color.urgent
          fontFamily: root.fontFamily
          Accessible.name: "Uninstall Agent Bar"
          onClicked: {
            if (root.agentService)
              root.agentService.openUninstallConfirm()
          }
        }
      }
    }
  }

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
