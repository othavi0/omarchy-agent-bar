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

  readonly property var ui: agentService && agentService.maintenanceUi
      ? agentService.maintenanceUi
      : Core.maintenanceUiIdle("")

  readonly property bool blocked: agentService && agentService.maintenanceState
      ? !!agentService.maintenanceState.blocked
      : false

  readonly property bool checking: ui.phase === "checking"
  readonly property bool updateAvailable: ui.phase === "update_available"
      && !!ui.targetVersion && String(ui.targetVersion).length > 0
  readonly property bool notesAvailable: !!ui.releaseNotesUrl
      && String(ui.releaseNotesUrl).indexOf("https://") === 0
  readonly property bool maintenanceBusy: ui.phase === "uninstalling"

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

          TextEdit {
            width: parent.width
            visible: !!ui.updateCommand && String(ui.updateCommand).length > 0
            text: ui.updateCommand || ""
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            color: root.foreground
            font.family: "monospace"
            font.pixelSize: Style.font.caption
            textFormat: TextEdit.PlainText
            Accessible.name: "Update command"
          }
        }

        Button {
          text: root.checking ? "Checking\u2026" : "Check for updates"
          bordered: true
          focusable: true
          enabled: !root.blocked && !root.checking && !root.maintenanceBusy
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
        // Derived from state, not from the children: a child of a hidden
        // item reads visible=false, so the old child-based binding latched
        // the row closed when the view opened on an available update.
        visible: root.updateAvailable || root.notesAvailable

        Button {
          id: marketplaceButton
          visible: root.updateAvailable
          text: "Marketplace page"
          bordered: true
          focusable: true
          enabled: !root.blocked && !root.maintenanceBusy
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.name: "Marketplace page"
          onClicked: {
            if (root.agentService)
              root.agentService.openMarketplacePage()
          }
        }

        Button {
          id: notesButton
          visible: root.notesAvailable
          text: "Release notes"
          bordered: true
          focusable: true
          enabled: !root.maintenanceBusy
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

      SectionHeader {
        text: "Danger zone"
        danger: true
        foreground: root.foreground
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
          enabled: !root.blocked && !root.maintenanceBusy
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
