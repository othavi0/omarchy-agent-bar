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
  property int minContentHeight: Style.space(160)
  property int contentLineHeight: Style.font.body + Style.space(8)

  property bool editorActive: contentLoader.item && contentLoader.item.editorOwnsFocus
      ? !!contentLoader.item.editorOwnsFocus
      : false

  readonly property var resolvedSettings: agentService
      ? agentService.resolvedSettings
      : Service.defaultSettings()

  readonly property var visibleProviders: agentService
      ? agentService.visibleProviders
      : Core.visibleProviders(null, resolvedSettings)

  property string settingsTab: "providers"

  readonly property string selectedId: {
    if (!agentService)
      return ""
    if (agentService.popupOwner && agentService.popupOwner.providerId
        && String(agentService.popupOwner.providerId).length)
      return String(agentService.popupOwner.providerId)
    if (agentService.selectedProviderId && String(agentService.selectedProviderId).length)
      return String(agentService.selectedProviderId)
    if (visibleProviders.length)
      return String(visibleProviders[0].id)
    return ""
  }

  readonly property string view: Service.popupView(agentService ? agentService.popupOwner : null)

  readonly property bool isOpen: Service.popupOpenForOwner(
    agentService ? agentService.popupOwner : null,
    owner
  )

  // The countdowns and the pace tick read this clock. It ticks only while the
  // popup is open and resyncs on every open (onIsOpenChanged).
  property double nowMs: Date.now()
  property alias nowTickRunning: nowTimer.running

  readonly property var resetUi: agentService ? agentService.resetUi : null

  readonly property var overview: Core.overviewModel(
    agentService ? agentService.snapshot : null,
    resolvedSettings,
    nowMs,
    {
      id: selectedId,
      collapsed: !!(agentService && agentService.popupOwner && agentService.popupOwner.collapsed)
    },
    {
      refreshing: agentService ? !!agentService.refreshing : false,
      resetUi: resetUi,
      resetBusy: !!(agentService && agentService.resetBusy),
      dateFormat: Qt.locale().dateFormat(Locale.ShortFormat),
      timeFormat: Qt.locale().timeFormat(Locale.ShortFormat)
    }
  )

  // Rows that open, close, change kind or gain an action change the focus
  // targets; rebuilding on this signature keeps the order live.
  readonly property string focusShape: {
    var rows = overview.rows
    var parts = []
    for (var i = 0; i < rows.length; i++) {
      parts.push([rows[i].id, rows[i].kind, rows[i].open, !!rows[i].action,
                  rows[i].useReset.visible].join(":"))
    }
    return parts.join("|")
  }

  // With padding 0 the band and footers meet the border, so their corners
  // follow the card radius minus the border width.
  readonly property int innerRadius: Math.max(0, Style.cornerRadius - verticalContentInset / 2)

  readonly property int measuredBodyHeight: header.implicitHeight
      + contentFlick.contentHeight
      + footerArea.implicitHeight

  property bool pendingRowFocus: false

  open: isOpen
  padding: 0
  contentWidth: maxContentWidth
  // verticalContentInset (padding + borders), not padding alone: KeyboardPanel
  // subtracts the border from the inner area, so sizing without it left the
  // border as phantom overflow and enabled a few-pixel scroll.
  contentHeight: Scroll.fittedPopupContentHeight(
    measuredBodyHeight + verticalContentInset,
    minContentHeight,
    maxContentHeight
  )
  focusTarget: keyCatcher

  function close() {
    if (agentService && owner)
      agentService.closePopup(owner)
    else
      root.open = false
  }

  function selectProvider(providerId) {
    if (!agentService)
      return
    agentService.requestPopup(owner, providerId, "usage")
  }

  function toggleRow(providerId) {
    if (!agentService)
      return
    agentService.toggleProviderRow(owner, providerId)
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
    agentService.requestPopup(owner, root.selectedId, "usage")
    contentFlick.contentY = 0
  }

  function onRefresh(providerId) {
    if (!agentService)
      return
    agentService.refreshProvider(providerId, true)
  }

  function onAction(providerId, kind, target) {
    if (!agentService)
      return
    agentService.dispatchAction(providerId, {
      kind: kind,
      label: "",
      target: target
    })
  }

  function onResetRequested(providerId, resetId) {
    if (!agentService)
      return
    agentService.requestReset(providerId, resetId)
  }

  readonly property var resetConfirmRow: {
    if (!resetUi || !resetUi.confirmOpen)
      return null
    var provider = Core.findProvider(agentService.snapshot, resetUi.providerId)
    var rows = Core.resetRows(provider,
        Qt.locale().dateFormat(Locale.ShortFormat), Qt.locale().timeFormat(Locale.ShortFormat))
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].id === resetUi.resetId)
        return rows[i]
    }
    return null
  }

  readonly property var resetConfirmModel: {
    if (!resetConfirmRow)
      return { title: "", message: "", confirmText: "Use reset" }
    var provider = Core.findProvider(agentService.snapshot, resetUi.providerId)
    return Core.resetConfirmModel(provider, resetConfirmRow)
  }

  function providerIds() {
    var ids = []
    for (var i = 0; i < overview.rows.length; i++)
      ids.push(overview.rows[i].id)
    return ids
  }

  // Up/Down select and open the next row (A11Y-002, UX-078); the deferred
  // rebuild in onSelectedIdChanged then moves focus to its head.
  function stepProvider(delta) {
    var next = Scroll.routeProviderDelta(providerIds(), root.selectedId, delta)
    if (!next)
      return
    root.pendingRowFocus = true
    root.selectProvider(next)
  }

  function handleTextKey(text) {
    var route = Scroll.routePanelTextKey(text, keyCatcher.blocked, root.view)
    if (route.action === "openSettings") {
      root.openSettings()
      return
    }
    if (route.action === "backToUsage") {
      root.backToUsage()
      return
    }
    if (route.action === "refresh") {
      if (root.selectedId.length)
        root.onRefresh(root.selectedId)
      return
    }
    if (route.action === "providerDelta" && root.view !== "settings")
      root.stepProvider(route.delta)
  }

  FocusController {
    id: focusController
    objectName: "focusController"
    flickable: contentFlick
    lineHeight: root.contentLineHeight
    focusBlocked: root.editorActive
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
    focusPendingRow()
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

  onViewChanged: {
    if (contentFlick)
      contentFlick.contentY = 0
    scheduleFocusRebuild()
  }
  onFocusShapeChanged: scheduleFocusRebuild()
  onSelectedIdChanged: Qt.callLater(function () {
    if (focusController && typeof focusController.clampScroll === "function")
      focusController.clampScroll()
    if (typeof root.rebuildFocusTargets === "function")
      root.rebuildFocusTargets()
  })

  // After a keyboard step or an open, focus lands on the selected row's head
  // rather than on the first target.
  function focusPendingRow() {
    if (!pendingRowFocus || view === "settings" || !contentLoader.item
        || typeof contentLoader.item.rowHead !== "function")
      return
    if (!contentLoader.item.builtCount)
      return
    pendingRowFocus = false
    var head = contentLoader.item.rowHead(selectedId)
    if (head)
      focusController.focusItem(head)
  }
  onAgentServiceChanged: scheduleFocusRebuild()
  onIsOpenChanged: {
    if (!isOpen)
      return
    root.nowMs = Date.now()
    contentFlick.contentY = 0
    root.pendingRowFocus = true
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
    onMoveRequested: function (dx, dy) {
      if (dy !== 0 && root.view !== "settings")
        root.stepProvider(dy)
    }
    onTabRequested: function (direction) {
      focusController.move(direction)
    }
    onActivateRequested: focusController.activate()
    onTextKey: function (text) {
      root.handleTextKey(text)
    }

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

    // UX-075: banners, the band and the footers stay pinned; only the rows
    // (or the Settings body) scroll. Everything runs edge to edge and each
    // block carries its own text inset.
    Item {
      id: popupBody
      objectName: "popupBody"
      anchors.fill: parent

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
          width: parent.width
          visible: !!root.agentService && root.agentService.restartPending
              && root.view !== "settings" && !stalledMessage.visible
          version: root.agentService ? root.agentService.pendingVersion : ""
          foreground: Commons.Color.foreground
          fontFamily: Style.font.family
          onRestartRequested: {
            if (root.agentService)
              root.agentService.restartShell()
          }
          onVisibleChanged: root.scheduleFocusRebuild()
        }

        OverviewBand {
          id: overviewBand
          width: parent.width
          visible: root.view !== "settings"
          headline: root.overview.headline
          innerRadius: stalledMessage.visible || restartBanner.visible ? 0 : root.innerRadius
          foreground: Commons.Color.foreground
          fontFamily: Style.font.family
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
          foreground: Commons.Color.foreground
          fontFamily: Style.font.family
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
      id: resetConfirmDialog
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
      foreground: Commons.Color.foreground
      fontFamily: Style.font.family
      onToggleRequested: function (id) { root.toggleRow(id) }
      onRefreshRequested: function (id) { root.onRefresh(id) }
      onActionRequested: function (id, kind, target) { root.onAction(id, kind, target) }
      onResetRequested: function (id, resetId) { root.onResetRequested(id, resetId) }
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
