import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons
import "CoreService.js" as Service
import "CoreView.js" as Core
import "CoreScroll.js" as Scroll
import "components"

// Do NOT redeclare KeyboardPanel's required anchorItem/bar here. Redeclaring
// them as required on this derived type makes Loader/createObject treat the
// base required props as unset (createObject returns null; chip click is a
// no-op). Call sites pass anchorItem + bar like first-party model-usage.
KeyboardPanel {
  id: root

  property var owner: null
  property var agentService: null

  property int maxContentWidth: Style.space(540)
  property int maxContentHeight: Style.space(560)
  property int minContentHeight: Style.space(160)
  property int contentLineHeight: Style.font.body + Style.space(8)
  property int contentMargins: Style.spacing.popupPadding

  property bool editorActive: contentLoader.item && contentLoader.item.editorOwnsFocus
      ? !!contentLoader.item.editorOwnsFocus
      : false

  readonly property var resolvedSettings: agentService
      ? agentService.resolvedSettings
      : Service.defaultSettings()

  readonly property var railProviders: agentService
      ? agentService.visibleProviders
      : Core.visibleProviders(null, resolvedSettings)

  readonly property string displayMetric: Core.displayMetric(resolvedSettings)
  property string settingsTab: "providers"

  readonly property string selectedId: {
    if (!agentService)
      return ""
    if (agentService.popupOwner && agentService.popupOwner.providerId
        && String(agentService.popupOwner.providerId).length)
      return String(agentService.popupOwner.providerId)
    if (agentService.selectedProviderId && String(agentService.selectedProviderId).length)
      return String(agentService.selectedProviderId)
    if (railProviders.length)
      return String(railProviders[0].id)
    return ""
  }

  readonly property var selectedProvider: Core.resolveSelectedProvider(
    agentService ? agentService.snapshot : null,
    selectedId,
    resolvedSettings
  )

  readonly property string view: Service.popupView(agentService ? agentService.popupOwner : null)

  readonly property bool isOpen: Service.popupOpenForOwner(
    agentService ? agentService.popupOwner : null,
    owner
  )

  readonly property int footerHeight: settingsFooter.shown
      ? settingsFooter.implicitHeight + Style.space(8)
      : 0

  readonly property int measuredBodyHeight: {
    var col = contentColumn ? contentColumn.implicitHeight : 0
    var margins = contentMargins * 2 + root.footerHeight
    var railMin = rail && rail.minStackHeight
        ? rail.minStackHeight + Style.space(8)
        : Style.space(160)
    return Math.max(col + margins, railMin)
  }

  open: isOpen
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
    contentFlick.contentY = 0
  }

  function openSettings() {
    if (!agentService)
      return
    agentService.openSettings(owner)
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

  readonly property var resetUi: agentService ? agentService.resetUi : null

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
    for (var i = 0; i < railProviders.length; i++) {
      if (railProviders[i] && railProviders[i].id)
        ids.push(String(railProviders[i].id))
    }
    return ids
  }

  function stepProvider(delta) {
    var next = Scroll.routeProviderDelta(providerIds(), root.selectedId, delta)
    if (next)
      root.selectProvider(next)
  }

  function handleTextKey(text) {
    var route = Scroll.routePanelTextKey(text, keyCatcher.blocked)
    if (route.action === "openSettings") {
      root.openSettings()
      return
    }
    if (route.action === "refresh") {
      if (root.selectedId.length)
        root.onRefresh(root.selectedId)
      return
    }
    if (route.action === "providerDelta")
      root.stepProvider(route.delta)
  }

  FocusController {
    id: focusController
    flickable: contentFlick
    lineHeight: root.contentLineHeight
    focusBlocked: root.editorActive
  }

  function rebuildFocusTargets() {
    if (!focusController || typeof focusController.setTargets !== "function")
      return
    var list = []
    if (rail && typeof rail.collectFocusTargets === "function")
      list = list.concat(rail.collectFocusTargets())
    if (stalledMessage && typeof stalledMessage.collectFocusTargets === "function")
      list = list.concat(stalledMessage.collectFocusTargets())
    list = list.concat(restartBanner.collectFocusTargets())
    if (contentLoader.item && typeof contentLoader.item.collectFocusTargets === "function")
      list = list.concat(contentLoader.item.collectFocusTargets())
    if (settingsFooter.shown)
      list = list.concat(settingsFooter.collectFocusTargets())
    focusController.setTargets(list)
  }

  // Deferred so the rail and the Loader finish building first. The popup
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
  onSelectedIdChanged: Qt.callLater(function () {
    if (focusController && typeof focusController.clampScroll === "function")
      focusController.clampScroll()
    if (typeof root.rebuildFocusTargets === "function")
      root.rebuildFocusTargets()
  })
  onAgentServiceChanged: scheduleFocusRebuild()
  onIsOpenChanged: {
    if (isOpen)
      settingsTab = agentService && (agentService.updateRunning || agentService.restartPending)
          ? "about" : "providers"
  }

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    blocked: root.editorActive

    onCloseRequested: root.close()
    onMoveRequested: function (dx, dy) {
      if (dy !== 0)
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
    }

    Row {
      id: panelBody
      anchors.fill: parent
      spacing: 0

      ProviderRail {
        id: rail
        width: rail.railWidth
        height: parent.height
        providers: root.railProviders
        selectedProviderId: root.selectedId
        settingsActive: root.view === "settings"
        displayMetric: root.displayMetric
        nowMs: root.owner && root.owner.nowMs !== undefined ? root.owner.nowMs : Date.now()
        foreground: Color.foreground
        fontFamily: Style.font.family
        onProviderSelected: function (id) { root.selectProvider(id) }
        onSettingsClicked: root.openSettings()
      }

      Item {
        id: railGutter
        width: root.padding
        height: parent.height

        PanelSeparator {
          anchors.right: parent.right
          width: 1
          height: parent.height
          foreground: Color.foreground
        }
      }

      Item {
        width: Math.max(0, parent.width - rail.width - railGutter.width)
        height: parent.height
        clip: true

        Flickable {
          id: contentFlick
          anchors.fill: parent
          anchors.leftMargin: root.contentMargins
          anchors.rightMargin: root.contentMargins
          anchors.topMargin: root.contentMargins
          anchors.bottomMargin: root.contentMargins + root.footerHeight
          contentWidth: width
          contentHeight: contentColumn.implicitHeight
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

          Column {
            id: contentColumn
            width: contentFlick.width
            spacing: Style.space(12)

            StateMessage {
              id: stalledMessage
              width: parent.width
              visible: root.agentService
                  && root.agentService.runtimeHealth === "stalled"
              title: "Agent Bar lost contact with its helper"
              body: "Restart the shell to recover."
              actions: [{
                kind: "restart_shell",
                label: "Restart shell",
                target: null
              }]
              foreground: Color.foreground
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
              foreground: Color.foreground
              fontFamily: Style.font.family
              onRestartRequested: {
                if (root.agentService)
                  root.agentService.restartShell()
              }
              onVisibleChanged: root.scheduleFocusRebuild()
            }

            Loader {
              id: contentLoader
              width: parent.width
              sourceComponent: root.view === "settings" ? settingsContent : providerContent
              onLoaded: root.scheduleFocusRebuild()
            }
          }
        }

        SettingsFooter {
          id: settingsFooter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: root.contentMargins
          anchors.rightMargin: root.contentMargins
          anchors.bottomMargin: root.contentMargins
          active: root.view === "settings"
          agentService: root.agentService
          foreground: Color.foreground
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
      foreground: Color.foreground
      fontFamily: Style.font.family
      onCanceled: if (root.agentService) root.agentService.closeResetConfirm()
      onConfirmed: if (root.agentService) root.agentService.confirmReset()
    }
  }

  // Declared as properties (not default contentItem children): KeyboardPanel's
  // default property is a QQuickItem list and rejects QQmlComponent objects.
  property Component providerContent: Component {
    ProviderView {
      width: contentColumn.width
      active: root.isOpen
      provider: root.selectedProvider
      displayMetric: root.displayMetric
      refreshing: agentService ? !!agentService.refreshing : false
      resetBusy: !!(root.agentService && root.agentService.resetBusy
          && root.resetUi && root.selectedProvider
          && String(root.resetUi.providerId) === String(root.selectedProvider.id))
      resetOutcomeText: {
        var ui = root.resetUi
        var sel = root.selectedProvider
        if (!ui || !ui.outcome || !sel || String(ui.providerId) !== String(sel.id))
          return ""
        return Core.resetOutcomeText(ui.outcome, Qt.locale().timeFormat(Locale.ShortFormat))
      }
      foreground: Color.foreground
      fontFamily: Style.font.family
      onRefreshRequested: function (id) { root.onRefresh(id) }
      onActionRequested: function (id, kind, target) { root.onAction(id, kind, target) }
      onResetRequested: function (id, resetId) { root.onResetRequested(id, resetId) }
    }
  }

  property Component settingsContent: Component {
    SettingsView {
      width: contentColumn.width
      // A Binding element, unlike a plain binding, survives the view's own
      // assignment to `tab` when a tab is clicked.
      Binding on tab { value: root.settingsTab }
      onTabChanged: root.settingsTab = tab
      agentService: root.agentService
      foreground: Color.foreground
      fontFamily: Style.font.family
    }
  }
}
