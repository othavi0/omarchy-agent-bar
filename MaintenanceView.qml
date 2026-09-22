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
  readonly property bool canUpdate: Core.maintenanceUiCanUpdate(ui)
  readonly property bool updating: ui.phase === "updating"
  readonly property bool restartRequired: ui.phase === "restart_required"
  readonly property bool updateFlow: root.canUpdate || root.updating || root.restartRequired
  readonly property bool failed: ui.phase === "error" || ui.phase === "update_failed"
  readonly property bool notesAvailable: !!ui.releaseNotesUrl
      && String(ui.releaseNotesUrl).indexOf("https://") === 0
  readonly property bool maintenanceBusy: ui.phase === "uninstalling" || root.updating
  readonly property var updateConfirm: Core.updateConfirmModel(ui.targetVersion)
  // Selecting the command line takes keyboard focus; the popup's key catcher
  // must stand down for it like it does for the settings editors.
  readonly property bool editorOwnsFocus: commandField.activeFocus

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
            visible: !root.restartRequired && ui.message && ui.message.length > 0
            text: ui.message
            color: root.failed ? Color.urgent : Util.alpha(root.foreground, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }
        }

        Button {
          visible: !root.updateFlow
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

      Rectangle {
        id: restartBanner
        visible: root.restartRequired
        width: parent.width
        height: bannerText.implicitHeight + Style.space(14)
        radius: Style.cornerRadius
        color: Style.selectedFillFor(root.foreground, Color.accent)
        border.width: 1
        border.color: Color.accent

        Text {
          id: bannerText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(9)
          anchors.rightMargin: Style.space(9)
          text: ui.message
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          Accessible.role: Accessible.StaticText
          Accessible.name: text
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(8)
        // Derived from state, not from the children: a child of a hidden
        // item reads visible=false, so the old child-based binding latched
        // the row closed when the view opened on an available update.
        visible: root.updateFlow || root.notesAvailable
        opacity: root.updating ? 0.55 : 1.0

        Button {
          id: updateButton
          visible: root.canUpdate || root.updating
          text: root.updating ? "Updating\u2026" : "Update to " + ui.targetVersion
          bordered: true
          selected: true
          focusable: true
          enabled: root.canUpdate && !root.blocked
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.name: "Update to " + ui.targetVersion
          onClicked: {
            if (root.agentService)
              root.agentService.openUpdateConfirm()
          }
        }

        Button {
          id: restartButton
          visible: root.restartRequired
          text: "Restart shell"
          bordered: true
          selected: true
          focusable: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.name: "Restart shell"
          onClicked: {
            if (root.agentService)
              root.agentService.restartShell()
          }
        }

        Button {
          id: laterButton
          visible: root.restartRequired
          text: "Later"
          bordered: true
          focusable: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          Accessible.name: "Later"
          onClicked: {
            if (root.agentService)
              root.agentService.dismissPopup()
          }
        }

        Button {
          id: notesButton
          visible: root.notesAvailable && !root.restartRequired
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

        Button {
          id: marketplaceButton
          visible: root.canUpdate || root.updating
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
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: !!ui.updateCommand && String(ui.updateCommand).length > 0

        Text {
          width: parent.width
          text: "Or run this in a terminal:"
          color: Util.alpha(root.foreground, 0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }

        TextEdit {
          id: commandField
          width: parent.width
          text: ui.updateCommand || ""
          readOnly: true
          selectByMouse: true
          cursorVisible: false
          wrapMode: TextEdit.Wrap
          color: root.foreground
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          textFormat: TextEdit.PlainText
          Accessible.name: "Update command"
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
          id: uninstallButton
          text: "Uninstall Agent Bar"
          bordered: true
          focusable: true
          enabled: !root.blocked && !root.maintenanceBusy
          opacity: uninstallButton.enabled ? 1.0 : 0.55
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
    id: updateConfirmDialog
    opened: !!ui.updateConfirmOpen
    title: root.updateConfirm.title
    message: root.updateConfirm.message
    cancelText: root.updateConfirm.cancelText
    confirmText: root.updateConfirm.confirmText
    destructive: false
    foreground: root.foreground
    fontFamily: root.fontFamily
    onCanceled: {
      if (root.agentService)
        root.agentService.closeUpdateConfirm()
    }
    onConfirmed: {
      if (root.agentService)
        root.agentService.confirmUpdate()
    }
  }

  ConfirmDialog {
    id: uninstallConfirmDialog
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
