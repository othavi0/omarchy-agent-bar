import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "CoreService.js" as Service
import "CoreView.js" as Core
import "CoreScroll.js" as Scroll
import "CoreSettings.js" as Settings
import "components"
import "components/Tokens.js" as Tokens

// Do NOT redeclare KeyboardPanel's required anchorItem/bar here. Redeclaring
// them as required on this derived type makes Loader/createObject treat the
// base required props as unset (createObject returns null; chip click is a
// no-op). Call sites pass anchorItem + bar like first-party model-usage.
KeyboardPanel {
  id: root

  property var owner: null
  property var agentService: null

  property int maxContentWidth: Style.space(520)
  property int maxContentHeight: Style.space(560)
  property int contentLineHeight: Style.font.body + Style.space(8)

  property bool editorActive: contentLoader.item && contentLoader.item.editorOwnsFocus
      ? !!contentLoader.item.editorOwnsFocus
      : false

  readonly property var resolvedSettings: agentService
      ? agentService.resolvedSettings
      : Service.defaultSettings()

  property string settingsTab: "providers"

  readonly property string view: Service.popupView(agentService ? agentService.popupOwner : null)

  readonly property bool isOpen: Service.popupOpenForOwner(
    agentService ? agentService.popupOwner : null,
    owner
  )

  // The countdowns read this clock. It ticks only while the popup is open
  // and resyncs on every open (onIsOpenChanged).
  property double nowMs: Date.now()
  property alias nowTickRunning: nowTimer.running

  readonly property var resetUi: agentService ? agentService.resetUi : null

  readonly property var overview: Core.overviewModel(
    agentService ? agentService.snapshot : null,
    resolvedSettings,
    nowMs,
    {
      refreshing: agentService ? !!agentService.refreshing : false,
      resetUi: resetUi,
      resetBusy: !!(agentService && agentService.resetBusy),
      dateFormat: dateFormat,
      timeFormat: timeFormat
    }
  )

  // Groups that change kind or gain, lose, enable or disable an action
  // change the focus targets; rebuilding on this signature keeps the order
  // live.
  readonly property string focusShape: {
    var rows = overview.rows
    var parts = []
    for (var i = 0; i < rows.length; i++) {
      var actions = rows[i].actions.map(function (a) { return a.id + (a.enabled ? "+" : "-") })
      parts.push([rows[i].id, rows[i].kind].concat(actions).join(":"))
    }
    return parts.join("|")
  }

  // With padding 0 the top block and footers meet the border, so their
  // corners follow the card radius minus the border width.
  readonly property int innerRadius: Math.max(0, Style.cornerRadius - verticalContentInset / 2)

  readonly property int measuredBodyHeight: header.implicitHeight
      + contentFlick.contentHeight
      + footerArea.implicitHeight

  open: isOpen
  padding: 0
  contentWidth: maxContentWidth
  // verticalContentInset (padding + borders), not padding alone: KeyboardPanel
  // subtracts the border from the inner area, so sizing without it left the
  // border as phantom overflow and enabled a few-pixel scroll.
  contentHeight: Scroll.fittedPopupContentHeight(
    measuredBodyHeight + verticalContentInset,
    maxContentHeight
  )
  focusTarget: keyCatcher

  function close() {
    if (agentService && owner)
      agentService.closePopup(owner)
    else
      root.open = false
  }

  function openSettings() {
    if (!agentService)
      return
    agentService.openSettings(owner)
    contentFlick.contentY = 0
  }

  function backToUsage() {
    if (!agentService)
      return
    agentService.requestPopup(owner, agentService.selectedProviderId || null, "usage")
    contentFlick.contentY = 0
  }

  function refreshAll() {
    if (agentService)
      agentService.refreshAll(true)
  }

  // One entry point for every group action button.
  function runAction(providerId, action) {
    if (!agentService || !action || !action.enabled)
      return
    if (action.kind === "use_reset") {
      var choices = Core.claimableResets(Core.findProvider(agentService.snapshot, providerId),
          root.dateFormat, root.timeFormat)
      if (choices.length === 1)
        agentService.requestReset(providerId, choices[0].id)
      else if (choices.length > 1)
        root.resetChoiceProviderId = providerId
      return
    }
    agentService.dispatchAction(providerId, {
      kind: action.kind,
      label: "",
      target: action.target
    })
  }

  readonly property string dateFormat: Qt.locale().dateFormat(Locale.ShortFormat)
  readonly property string timeFormat: Qt.locale().timeFormat(Locale.ShortFormat)

  // The provider whose "Use reset" asked which reset to use; "" when no
  // choice is open. A refresh that leaves fewer choices updates the list; one
  // that leaves none ends the choice, so a reset that comes back later does
  // not reopen it without a click.
  property string resetChoiceProviderId: ""

  readonly property var resetChoices: resetChoiceProviderId.length && agentService
      ? Core.claimableResets(Core.findProvider(agentService.snapshot, resetChoiceProviderId),
                             dateFormat, timeFormat)
      : []

  property Connections resetChoiceWatch: Connections {
    target: root.agentService
    ignoreUnknownSignals: true
    function onSnapshotChanged() {
      if (root.resetChoiceProviderId.length
          && !Core.claimableResets(Core.findProvider(root.agentService.snapshot,
                                                     root.resetChoiceProviderId),
                                   root.dateFormat, root.timeFormat).length)
        root.resetChoiceProviderId = ""
    }
  }

  function chooseReset(resetId) {
    var providerId = resetChoiceProviderId
    resetChoiceProviderId = ""
    if (agentService && providerId.length)
      agentService.requestReset(providerId, resetId)
  }

  readonly property var resetConfirmModel: {
    var model = resetUi && resetUi.confirmOpen
        ? Core.resetConfirmModel(Core.findProvider(agentService.snapshot, resetUi.providerId),
                                 resetUi.resetId, dateFormat, timeFormat)
        : null
    return model || { resetId: "", title: "", message: "", confirmText: "Use reset" }
  }

  FocusController {
    id: focusController
    objectName: "focusController"
    flickable: contentFlick
    lineHeight: root.contentLineHeight
    focusBlocked: root.editorActive
    autoFocusFirst: root.view === "settings"
  }

  function rebuildFocusTargets() {
    if (!focusController || typeof focusController.setTargets !== "function")
      return
    var list = []
    if (stalledMessage && typeof stalledMessage.collectFocusTargets === "function")
      list = list.concat(stalledMessage.collectFocusTargets())
    list = list.concat(restartBanner.collectFocusTargets())
    if (root.view === "settings")
      list = list.concat(settingsHeader.collectFocusTargets())
    if (contentLoader.item && typeof contentLoader.item.collectFocusTargets === "function")
      list = list.concat(contentLoader.item.collectFocusTargets())
    if (root.view !== "settings")
      list = list.concat(popupFooter.collectFocusTargets())
    if (settingsFooter.shown)
      list = list.concat(settingsFooter.collectFocusTargets())
    focusController.setTargets(list)
    if (focusController.index < 0 && !root.editorActive)
      keyCatcher.forceActiveFocus()
    if (root.view === "settings" && contentLoader.item
        && typeof contentLoader.item.anchoredFocusTarget === "function") {
      var anchored = contentLoader.item.anchoredFocusTarget()
      if (anchored)
        focusController.focusItem(anchored)
    }
  }

  // Deferred so the rows and the Loader finish building first. The popup
  // can be destroyed before the call runs (#83), so check the method is
  // still there instead of throwing from a dead object.
  function scheduleFocusRebuild() {
    Qt.callLater(function () {
      if (typeof root.rebuildFocusTargets === "function")
        root.rebuildFocusTargets()
    })
  }

  // The old view's targets are gone, so its index means nothing here: the
  // rebuild starts on Back in Settings and on no control in the usage view.
  onViewChanged: {
    if (contentFlick)
      contentFlick.contentY = 0
    focusController.index = -1
    scheduleFocusRebuild()
  }
  onFocusShapeChanged: scheduleFocusRebuild()
  onAgentServiceChanged: scheduleFocusRebuild()
  onIsOpenChanged: {
    if (!isOpen) {
      resetChoiceProviderId = ""
      return
    }
    root.nowMs = Date.now()
    contentFlick.contentY = 0
    focusController.index = -1
    scheduleFocusRebuild()
    settingsTab = agentService && (agentService.updateRunning || agentService.restartPending)
        ? "about" : "providers"
  }

  PanelKeyCatcher {
    id: keyCatcher
    objectName: "keyCatcher"
    anchors.fill: parent
    blocked: root.editorActive

    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      focusController.move(direction)
    }
    onActivateRequested: focusController.activate()

    // A11Y-023: page/home/end. Nested under an Item (not KeyboardPanel default
    // contentItem) because Shortcut is not a QQuickItem and live Quattro rejects
    // non-Item default children ("Cannot assign QQuickShortcut to contentItem").
    // The clock Timer sits here for the same reason.
    Item {
      id: scrollShortcuts
      width: 0
      height: 0
      Shortcut {
        sequences: ["PgDown", "Page Down"]
        enabled: root.isOpen && !keyCatcher.blocked
        onActivated: focusController.scrollPage(1)
      }
      Shortcut {
        sequences: ["PgUp", "Page Up"]
        enabled: root.isOpen && !keyCatcher.blocked
        onActivated: focusController.scrollPage(-1)
      }
      Shortcut {
        sequence: "Home"
        enabled: root.isOpen && !keyCatcher.blocked
        onActivated: focusController.scrollHome()
      }
      Shortcut {
        sequence: "End"
        enabled: root.isOpen && !keyCatcher.blocked
        onActivated: focusController.scrollEnd()
      }
      Timer {
        id: nowTimer
        objectName: "nowTimer"
        interval: 30000
        repeat: true
        running: root.isOpen
        onTriggered: root.nowMs = Date.now()
      }
    }

    // UX-075: banners and the footers stay pinned; only the rows
    // (or the Settings body) scroll. Everything runs edge to edge and each
    // block carries its own text inset.
    Item {
      id: popupBody
      objectName: "popupBody"
      anchors.fill: parent

      // The catcher stands down while a number field owns typing; Tab, Backtab
      // and Esc still leave the field.
      Keys.onPressed: function (event) {
        if (!root.editorActive)
          return
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          focusController.move(event.key === Qt.Key_Backtab
              || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        }
      }

      Column {
        id: header
        anchors.top: parent.top
        width: parent.width

        StateMessage {
          id: stalledMessage
          width: parent.width
          leftPadding: Style.spacing.popupPadding
          rightPadding: Style.spacing.popupPadding
          topPadding: Style.space(12)
          bottomPadding: Style.space(12)
          visible: root.agentService
              && root.agentService.runtimeHealth === "stalled"
          title: "Agent Bar lost contact with its helper"
          body: "Restart the shell to recover."
          actions: [{
            kind: "restart_shell",
            label: "Restart shell",
            target: null
          }]
          foreground: Commons.Color.foreground
          fontFamily: Style.font.family
          onActionActivated: function (kind, target) {
            if (kind === "restart_shell" && root.agentService)
              root.agentService.restartShell()
          }
          onVisibleChanged: root.scheduleFocusRebuild()
        }

        RestartBanner {
          id: restartBanner
          objectName: "restartBanner"
          width: parent.width
          visible: !!root.agentService && root.agentService.restartPending
              && root.view !== "settings" && !stalledMessage.visible
          version: root.agentService ? root.agentService.pendingVersion : ""
          innerRadius: root.innerRadius
          foreground: Commons.Color.foreground
          fontFamily: Style.font.family
          onRestartRequested: {
            if (root.agentService)
              root.agentService.restartShell()
          }
          onVisibleChanged: root.scheduleFocusRebuild()
        }

        SettingsHeader {
          id: settingsHeader
          objectName: "settingsHeader"
          width: parent.width
          visible: root.view === "settings"
          tab: root.settingsTab
          changes: root.agentService
              ? Settings.settingsChanges(
                  root.agentService.settingsState ? root.agentService.settingsState.snapshot : null,
                  root.agentService.settingsDraft)
              : null
          innerRadius: stalledMessage.visible ? 0 : root.innerRadius
          foreground: Commons.Color.foreground
          fontFamily: Style.font.family
          onBackRequested: root.backToUsage()
          onTabSelected: function (id) { root.settingsTab = id }
        }
      }

      Flickable {
        id: contentFlick
        objectName: "contentFlick"
        anchors.top: header.bottom
        anchors.bottom: footerArea.top
        anchors.left: parent.left
        anchors.right: parent.right
        contentWidth: width
        contentHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: Scroll.flickableInteractive(contentHeight, height)
        ScrollBar.vertical: ScrollBar {
          policy: contentFlick.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        onContentHeightChanged: {
          if (!Scroll.flickableInteractive(contentHeight, height))
            contentY = 0
          else if (focusController && typeof focusController.clampScroll === "function")
            focusController.clampScroll()
        }
        onHeightChanged: {
          if (!Scroll.flickableInteractive(contentHeight, height))
            contentY = 0
          else if (focusController && typeof focusController.clampScroll === "function")
            focusController.clampScroll()
        }

        // Both bodies run edge to edge and carry their own inset.
        Loader {
          id: contentLoader
          width: contentFlick.width
          sourceComponent: root.view === "settings" ? settingsContent : providerContent
          onLoaded: root.scheduleFocusRebuild()
        }

        Connections {
          target: contentLoader.item
          ignoreUnknownSignals: true
          function onFocusShapeChanged() {
            root.scheduleFocusRebuild()
          }
        }
      }

      Item {
        id: footerArea
        anchors.bottom: parent.bottom
        width: parent.width
        implicitHeight: root.view === "settings"
            ? settingsFooter.implicitHeight
            : popupFooter.implicitHeight
        height: implicitHeight

        PopupFooter {
          id: popupFooter
          anchors.bottom: parent.bottom
          width: parent.width
          visible: root.view !== "settings"
          innerRadius: root.innerRadius
          statusText: root.overview.statusText
          foreground: Commons.Color.foreground
          fontFamily: Style.font.family
          onRefreshRequested: root.refreshAll()
          onSettingsRequested: root.openSettings()
        }

        SettingsFooter {
          id: settingsFooter
          anchors.bottom: parent.bottom
          width: parent.width
          active: root.view === "settings"
          innerRadius: root.innerRadius
          agentService: root.agentService
          foreground: Commons.Color.foreground
          fontFamily: Style.font.family
          onShownChanged: root.scheduleFocusRebuild()
        }
      }
    }

    ConfirmDialog {
      id: resetChoiceDialog
      objectName: "resetChoiceDialog"
      opened: root.resetChoices.length > 0 && !(root.resetUi && root.resetUi.confirmOpen)
      title: "Which reset do you want to use?"
      confirmVisible: false
      foreground: Commons.Color.foreground
      fontFamily: Style.font.family
      onCanceled: root.resetChoiceProviderId = ""

      Repeater {
        model: root.resetChoices
        delegate: ActionButton {
          id: choiceButton
          objectName: "resetChoice"
          required property var modelData
          property string choiceId: modelData.id
          width: parent ? parent.width : 0
          height: choiceText.implicitHeight + Style.space(12)
          tonal: false
          bordered: true
          Accessible.name: modelData.accessibleName
          onActivated: root.chooseReset(choiceId)

          Column {
            id: choiceText
            x: Style.space(8)
            width: choiceButton.width - Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: choiceButton.modelData.dateText.length
                  ? choiceButton.modelData.kindLabel + " · " + choiceButton.modelData.dateText
                  : choiceButton.modelData.kindLabel
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }

            Text {
              width: parent.width
              visible: text.length > 0
              text: choiceButton.modelData.effectText
              color: Util.alpha(Commons.Color.foreground, Tokens.TEXT_SECONDARY)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
            }
          }
        }
      }
    }

    ConfirmDialog {
      id: resetConfirmDialog
      objectName: "resetConfirmDialog"
      opened: !!(root.resetUi && root.resetUi.confirmOpen)
      title: root.resetConfirmModel.title
      message: root.resetConfirmModel.message
      confirmText: root.resetConfirmModel.confirmText
      foreground: Commons.Color.foreground
      fontFamily: Style.font.family
      onCanceled: if (root.agentService) root.agentService.closeResetConfirm()
      onConfirmed: if (root.agentService) root.agentService.confirmReset()
    }
  }

  // Declared as properties (not default contentItem children): KeyboardPanel's
  // default property is a QQuickItem list and rejects QQmlComponent objects.
  property Component providerContent: Component {
    OverviewList {
      width: contentLoader.width
      overview: root.overview
      topRadius: stalledMessage.visible || restartBanner.visible ? 0 : root.innerRadius
      foreground: Commons.Color.foreground
      fontFamily: Style.font.family
      onActionRequested: function (id, action) { root.runAction(id, action) }
    }
  }

  property Component settingsContent: Component {
    SettingsView {
      width: contentLoader.width
      // A Binding element, unlike a plain binding, survives the view's own
      // assignment to `tab`.
      Binding on tab { value: root.settingsTab }
      onTabChanged: root.settingsTab = tab
      agentService: root.agentService
      foreground: Commons.Color.foreground
      fontFamily: Style.font.family
    }
  }
}
