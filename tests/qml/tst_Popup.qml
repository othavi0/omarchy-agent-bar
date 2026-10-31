import QtQuick
import QtTest
import "../../CoreView.js" as Core
import "../../CoreService.js" as Service
import "ViewHarness.js" as ViewHarness

TestCase {
  id: testCase
  name: "AgentBarPopup"
  when: windowShown
  visible: true

  property string repoRoot: {
    var u = Qt.resolvedUrl(".")
    var path = String(u).replace("file://", "")
    if (path.endsWith("/"))
      path = path.slice(0, -1)
    var parts = path.split("/")
    parts.pop(); parts.pop()
    return parts.join("/")
  }

  function read(rel) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "file://" + repoRoot + "/" + rel, false)
    xhr.send()
    return String(xhr.responseText || "")
  }

  function blockEnd(src, start) {
    var open = src.indexOf("{", start)
    var depth = 0
    for (var i = open; i < src.length; i++) {
      if (src[i] === "{")
        depth++
      else if (src[i] === "}" && --depth === 0)
        return i
    }
    return -1
  }

  function test_restart_banner_is_one_line_with_a_restart_button() {
    var banner = ViewHarness.createView(repoRoot, "components/RestartBanner.qml", testCase, testCase,
                                        { width: 420, version: "10.6.2" })
    var lines = ViewHarness.findAll(banner, function (item) {
      return item.textFormat !== undefined && item.text !== undefined && item.bordered === undefined
    })
    compare(lines.length, 1)
    compare(lines[0].text, "10.6.2 installed. Restart the shell to load it.")
    compare(lines[0].textFormat, Text.PlainText)
    var buttons = ViewHarness.buttonsWithText(banner, ["Restart shell"])
    compare(buttons.length, 1)
    compare(buttons[0].visible, true)
    compare(banner.collectFocusTargets().length, 1)
    compare(banner.collectFocusTargets()[0], buttons[0])
    var requested = 0
    banner.restartRequested.connect(function () { requested++ })
    buttons[0].clicked()
    compare(requested, 1)
    buttons[0].focusActivate()
    compare(requested, 2)
    banner.visible = false
    compare(banner.collectFocusTargets().length, 0)
    banner.destroy()
  }

  function test_popup_shows_the_restart_banner_on_the_status_view_only() {
    var src = read("Popup.qml")
    var start = src.indexOf("RestartBanner {")
    verify(start > src.indexOf("id: stalledMessage"), "the banner sits under the stalled message")
    verify(start < src.indexOf("id: contentLoader"), "the banner sits above the provider content")
    var block = src.substring(start, blockEnd(src, start))
    verify(block.indexOf("root.agentService.restartPending") >= 0)
    verify(block.indexOf('root.view !== "settings"') >= 0)
    verify(block.indexOf("!stalledMessage.visible") >= 0)
    verify(block.indexOf("version: root.agentService ? root.agentService.pendingVersion") >= 0)
    verify(block.indexOf("root.agentService.restartShell()") >= 0)
    verify(src.indexOf("list.concat(restartBanner.collectFocusTargets())") >= 0)
  }

  function test_state_message_restart_action_emits_typed_signal() {
    var source = read("components/StateMessage.qml")
    verify(source.indexOf("Keys.onReturnPressed") < 0,
           "StateMessage must rely on the host Button key mapping")
    source = source.replace("import qs.Commons\n", "")
    source = source.replace("import qs.Ui\n", "")
    source = source.replace("  id: root\n",
                            "  id: root\n  property alias actionRepeaterForTest: actionRepeater\n")
    source = source.replace(/Style\.space\((\d+)\)/g, "$1")
    source = source.replace(/Style\.cornerRadius/g, "4")
    source = source.replace(/Style\.selectedFill/g, '"#333333"')
    source = source.replace(/Style\.hoverFill/g, '"#444444"')
    source = source.replace(/Style\.font\.body/g, "14")
    source = source.replace(/Style\.font\.caption/g, "12")
    source = source.replace(/Color\.foreground/g, '"#ffffff"')
    source = source.replace(/Style\.font\.family/g, '"sans"')
    source = source.replace('import "Tokens.js" as Tokens\n', "")
    source = source.replace(/Util\.alpha\(root\.foreground, Tokens\.TEXT_SECONDARY\)/g,
                            "root.foreground")
    source = source.replace(/          text: modelData[^\n]*\n/, "")
    source = source.replace(/          foreground: root\.foreground\n/, "")
    source = source.replace(/          fontFamily: root\.fontFamily\n/, "")
    source = source.replace(/          bordered: true\n/, "")
    source = source.replace(/          focusable: true\n/, "")
    source = source.replace(/          leftAlign: true\n/, "")
    source = source.replace(
      "        Button {",
      "        Rectangle {\n"
        + "          property string text: modelData && modelData.label"
        + " ? String(modelData.label) : \"\"\n"
        + "          property color foreground: root.foreground\n"
        + "          property string fontFamily: root.fontFamily\n"
        + "          property bool bordered: true\n"
        + "          property bool focusable: true\n"
        + "          property bool leftAlign: true\n"
        + "          signal clicked()"
    )
    var message = Qt.createQmlObject(source, testCase,
                                     "StateMessageHarness.qml")
    verify(message !== null)
    message.width = 320
    message.title = "Agent Bar lost contact with its helper"
    message.body = "Restart the shell to recover."
    message.actions = [{
      kind: "restart_shell",
      label: "Restart shell",
      target: null
    }]
    wait(1)
    var receivedKind = ""
    var activationCount = 0
    message.actionActivated.connect(function (kind, target) {
      receivedKind = kind
      activationCount += 1
    })
    compare(message.actionRepeaterForTest.count, 1)
    var action = message.actionRepeaterForTest.itemAt(0)
    action.clicked()
    compare(receivedKind, "restart_shell")
    compare(activationCount, 1)
    action.focusActivate()
    compare(activationCount, 2)

    message.visible = false
    compare(message.collectFocusTargets().length, 0)
    message.visible = true
    message.skeleton = true
    compare(message.collectFocusTargets().length, 0)
    message.destroy()
  }

  function test_popup_uses_keyboard_panel_and_overview() {
    var src = read("Popup.qml")
    verify(src.indexOf("KeyboardPanel") >= 0)
    verify(src.indexOf("PanelKeyCatcher") >= 0)
    verify(src.indexOf("OverviewList {") >= 0)
    verify(src.indexOf("PopupFooter {") >= 0)
    verify(src.indexOf("SettingsHeader {") >= 0)
    verify(src.indexOf("ProviderRail") < 0)
    verify(src.indexOf("ProviderView") < 0)
    verify(src.indexOf("maxContentWidth: Style.space(520)") >= 0)
    verify(src.indexOf('objectName: "popupBody"') >= 0)
    verify(src.indexOf("Core.overviewModel(") >= 0)
  }

  function test_stalled_banner_is_conditional_and_actionable() {
    var src = read("Popup.qml")
    var banner = src.indexOf("id: stalledMessage")
    verify(banner >= 0)
    var loader = src.indexOf("id: contentLoader")
    verify(loader > banner, "the stalled banner must render above the active view")
    var body = src.substring(banner, loader)
    verify(body.indexOf('runtimeHealth === "stalled"') >= 0)
    verify(body.indexOf('title: "Agent Bar lost contact with its helper"') >= 0)
    verify(body.indexOf('body: "Restart the shell to recover."') >= 0)
    verify(body.indexOf('label: "Restart shell"') >= 0)
    verify(body.indexOf("root.agentService.restartShell()") >= 0)
    verify(src.indexOf("stalledMessage.collectFocusTargets()") >= 0)
  }

  function test_no_meta_footer() {
    var files = ["components/ProviderRow.qml"]
    for (var i = 0; i < files.length; i++) {
      var src = read(files[i])
      verify(src.length > 0, files[i] + " exists")
      verify(src.indexOf("connection") < 0, files[i])
      verify(src.indexOf('"Cache"') < 0, files[i])
      verify(src.indexOf('"Live"') < 0, files[i])
    }
  }

  // UX-028: a stale row reads like a ready one. The age is neutral copy from
  // the model; no offline wording, no error text, no stale-only glyph.
  function test_stale_age_line_is_neutral() {
    var core = read("CoreView.js")
    verify(core.indexOf("formatAgoText(provider.lastSuccessAt, nowMs)") >= 0)
    verify(core.indexOf('"Updated " + ago') >= 0)
    var files = ["components/ProviderRow.qml"]
    for (var i = 0; i < files.length; i++) {
      var src = read(files[i])
      verify(src.length > 0, files[i] + " exists")
      verify(src.indexOf("󰅐") < 0, files[i])
      verify(src.indexOf("⌛") < 0, files[i])
      verify(src.indexOf('"Last data "') < 0, files[i])
      verify(src.indexOf("Offline") < 0, files[i])
      verify(src.indexOf("GLYPH_WIFI_OFF") < 0, files[i])
      verify(src.indexOf("errorMessage") < 0, files[i])
      verify(src.indexOf('+ " ago"') < 0, files[i])
    }
    verify(read("components/ProviderRow.qml").indexOf("root.row.notes") >= 0)
  }

  function test_stale_windows_are_not_dimmed() {
    var files = ["components/ProviderRow.qml", "components/UsageMeter.qml"]
    for (var i = 0; i < files.length; i++) {
      var src = read(files[i])
      verify(src.length > 0, files[i] + " exists")
      verify(src.indexOf("isStale") < 0, files[i])
      verify(src.indexOf('"stale"') < 0, files[i] + " must not branch on the stale state")
    }
    verify(read("components/UsageMeter.qml").indexOf("property bool dimmed") < 0)
  }

  function popupSourceFiles() {
    return [
      "Popup.qml",
      "components/OverviewList.qml",
      "components/ProviderRow.qml",
      "components/UsageMeter.qml",
      "components/ProviderIcon.qml",
      "components/PopupFooter.qml",
      "components/SettingsHeader.qml",
      "components/StateMessage.qml",
      "components/RestartBanner.qml"
    ]
  }

  function test_plain_text_only_no_rich_text() {
    var files = popupSourceFiles()
    for (var i = 0; i < files.length; i++) {
      var src = read(files[i])
      verify(src.length > 0, files[i] + " exists")
      verify(src.indexOf("Text.RichText") < 0, files[i])
      verify(src.indexOf("RichText") < 0, files[i])
      verify(src.indexOf("innerHTML") < 0, files[i])
      if (src.indexOf("textFormat:") >= 0)
        verify(src.indexOf("Text.PlainText") >= 0, files[i] + " should use PlainText")
    }
  }

  function test_no_money_copy_in_popup_sources() {
    var files = popupSourceFiles()
    for (var i = 0; i < files.length; i++) {
      var src = read(files[i])
      verify(src.length > 0, files[i] + " exists")
      verify(!Core.containsMoneyCopy(src), files[i] + " has money copy")
    }
  }

  function test_card_height_accounts_for_border_inset() {
    // KeyboardPanel subtracts verticalContentInset (padding + top/bottom
    // border) from the inner area; sizing the card with padding alone leaves
    // the border as phantom overflow that enables a few-pixel scroll.
    var src = read("Popup.qml")
    verify(src.indexOf("verticalContentInset") >= 0)
    verify(src.indexOf("padding * 2") < 0)
  }

  function test_popup_open_owner_gate() {
    var ownerA = { id: "a" }
    var ownerB = { id: "b" }
    verify(!Service.popupOpenForOwner(null, ownerA))
    verify(Service.popupOpenForOwner({ owner: ownerA, providerId: "claude", view: "usage" }, ownerA))
    verify(!Service.popupOpenForOwner({ owner: ownerA, providerId: "claude", view: "usage" }, ownerB))
  }

  function test_bar_widget_hosts_popup() {
    var src = read("BarWidget.qml")
    verify(src.indexOf("Popup") >= 0)
    verify(src.indexOf("agentService") >= 0)
  }

  function test_actions_are_allowlisted_kinds_only() {
    var p = {
      id: "claude",
      name: "Claude",
      state: "cli_missing",
      windows: [],
      action: {
        kind: "view_installation",
        label: "Install guide",
        target: "https://example.com/install"
      }
    }
    var acts = Core.stateActions(p)
    for (var i = 0; i < acts.length; i++) {
      verify(Core.mapActionKind(acts[i].kind) !== null)
    }
    compare(Core.mapActionKind("rm -rf"), null)
    compare(Core.mapActionKind("bash"), null)
  }

  function test_critical_meter_uses_the_urgent_token() {
    var meter = read("components/UsageMeter.qml")
    verify(meter.length > 0, "UsageMeter.qml exists")
    verify(meter.indexOf("Color.urgent") >= 0)
    verify(meter.indexOf("root.critical") >= 0)
    verify(meter.indexOf("Qt.rgba(") < 0)
    var fill = meter.slice(meter.indexOf("readonly property color fillColor"))
    fill = fill.slice(0, fill.indexOf("\n"))
    verify(fill.indexOf("root.critical ? Commons.Color.urgent : Commons.Color.accent") >= 0,
           "the fill is the accent, or urgent when critical: " + fill)
  }

  // The three QML gates never compile a file that imports qs.*, so a dangling
  // reference to a deleted function is invisible to them. These guards ban the
  // exact dead identifiers by name.
  function test_primary_window_allowlist_is_gone() {
    var files = [
      "BarWidget.qml",
      "components/ConfirmDialog.qml",
      "components/FocusController.qml",
      "components/ProviderChip.qml",
      "components/OverviewList.qml",
      "components/ProviderRow.qml",
      "components/UsageMeter.qml",
      "components/ProviderIcon.qml",
      "components/PopupFooter.qml",
      "components/SettingsHeader.qml",
      "components/SettingsProviderRow.qml",
      "components/SettingsFooter.qml",
      "components/SectionHeader.qml",
      "components/StateMessage.qml",
      "CoreMaintenance.js",
      "CoreScroll.js",
      "CoreService.js",
      "CoreSettings.js",
      "CoreView.js",
      "MaintenanceView.qml",
      "Popup.qml",
      "Service.qml",
      "SettingsView.qml"
    ]
    for (var i = 0; i < files.length; i++) {
      var source = read(files[i])
      verify(source.length > 0, files[i] + " exists")
      verify(source.indexOf("primaryWindow") < 0,
             files[i] + " still references the deleted lead selector")
    }

    var core = read("CoreView.js")
    verify(core.indexOf("PRIMARY_WINDOW_IDS") < 0,
           "the id allowlist must be deleted, not left dormant")
    verify(core.indexOf("windowGroups") < 0,
           "windowGroups is replaced by windowLayout")
    verify(core.indexOf("function electLeadIndex") >= 0)
  }

  // The rail and single-provider pane are gone with their files; their
  // helpers must not linger in CoreView.js.
  function test_rail_and_pane_helpers_are_gone() {
    var core = read("CoreView.js")
    var dead = ["railProviderSelected", "railTooltipText", "resolveSelectedProvider",
                "headerModel", "contentMode"]
    for (var i = 0; i < dead.length; i++)
      verify(core.indexOf("function " + dead[i] + "(") < 0, dead[i] + " is dead code")
    var gone = ["ProviderRail.qml", "ProviderView.qml", "components/ProviderHeader.qml",
                "components/UsageWindow.qml", "components/ResetsSection.qml"]
    for (var g = 0; g < gone.length; g++)
      compare(read(gone[g]), "", gone[g] + " is deleted")
  }

  // The headline band and the Tightest tag are gone; no row names another
  // provider's window.
  function test_headline_and_tightest_tag_are_gone() {
    var files = popupSourceFiles().concat(["CoreView.js"])
    var dead = ["OverviewBand", "HeaderTag", "headline", "subTag", "isTightest",
                "electTightest", "severityTagText", "Tightest"]
    for (var i = 0; i < files.length; i++) {
      var source = read(files[i])
      verify(source.length > 0, files[i] + " exists")
      for (var d = 0; d < dead.length; d++)
        verify(source.indexOf(dead[d]) < 0, files[i] + " still references " + dead[d])
    }
    compare(read("components/OverviewBand.qml"), "", "OverviewBand.qml is deleted")
    compare(read("components/HeaderTag.qml"), "", "HeaderTag.qml is deleted")
  }

  // The accordion, its drawer, the time tick and the per-provider Refresh
  // are gone with their file; no source keeps their identifiers alive.
  function test_accordion_and_tick_are_gone() {
    var files = popupSourceFiles().concat(["CoreView.js", "CoreService.js", "Service.qml",
                                           "components/Tokens.js"])
    var dead = ["RowDetail", "rowChevron", "drawerWell", "togglePopupRow", "toggleProviderRow",
                "collapsed", "openable", "paceTick", "tickPercent", "TICK_MIN_ELAPSED",
                "tickDescription", "windowMinutesOf", "refreshButton", "refreshLabel",
                "GLYPH_CHEVRON", "rowAlert"]
    for (var i = 0; i < files.length; i++) {
      var source = read(files[i])
      verify(source.length > 0, files[i] + " exists")
      for (var d = 0; d < dead.length; d++)
        verify(source.indexOf(dead[d]) < 0, files[i] + " still references " + dead[d])
    }
    compare(read("components/RowDetail.qml"), "", "RowDetail.qml is deleted")
  }

  function test_absolute_clock_humaniser_is_gone() {
    var core = read("CoreView.js")
    verify(core.indexOf("formatResetText") < 0)
    verify(core.indexOf("WEEKDAYS") < 0)
    verify(core.indexOf("Qt.formatDateTime") < 0)
    verify(core.indexOf("function resetCountdownText") >= 0)
  }

  function test_lead_reset_clock_is_locale_formatted() {
    var core = read("CoreView.js")
    verify(core.indexOf("function resetClockText(") >= 0)
    verify(core.indexOf('"hh:mm"') < 0)
    verify(core.indexOf('"HH:mm"') < 0)
    var h24 = Core.resetClockText("2026-08-02T02:00:00Z", "HH:mm")
    verify(/^\(\d{2}:\d{2}\)$/.test(h24), "got: " + h24)
    var h12 = Core.resetClockText("2026-08-02T02:00:00Z", "h:mm AP")
    verify(/^\(\d{1,2}:\d{2} (AM|PM)\)$/.test(h12), "got: " + h12)
    compare(Core.resetClockText("not-a-date", "HH:mm"), "")
    compare(Core.resetClockText("2026-08-02T02:00:00Z", ""), "")
  }

  function test_reset_argv_is_typed_array() {
    compare(JSON.stringify(Service.resetArgv("/bin/agent-bar", "claude", "juniper-tide")),
            JSON.stringify(["/bin/agent-bar", "reset", "claude", "juniper-tide"]))
  }

  function test_parse_reset_outcome_accepts_the_documented_shape() {
    var stdout = JSON.stringify({
      schemaVersion: 1,
      operation: "reset",
      provider: "claude",
      resetId: "cedar-ember:opus55-launch-promax-20260921",
      result: "reset",
      resetsLeft: 0,
      cooldownUntil: null,
      clears: ["session", "weekly"]
    })
    var parsed = Service.parseResetOutcome(stdout)
    verify(parsed.ok)
    compare(parsed.outcome.result, "reset")
    compare(parsed.outcome.resetsLeft, 0)
    compare(JSON.stringify(parsed.outcome.clears), JSON.stringify(["session", "weekly"]))
  }

  function test_parse_reset_outcome_rejects_unknown_result_and_garbage() {
    verify(!Service.parseResetOutcome("not json").ok)
    verify(!Service.parseResetOutcome("").ok)
    verify(!Service.parseResetOutcome(JSON.stringify({
      schemaVersion: 1, operation: "reset", provider: "claude", resetId: "x",
      result: "explodes", resetsLeft: null, cooldownUntil: null, clears: []
    })).ok)
  }

  function test_validate_provider_requires_resets_array() {
    var base = { id: "claude", name: "Claude", state: "ready", windows: [], action: null }
    verify(Service.validateProvider(base) !== null)
    var withEmpty = { id: "claude", name: "Claude", state: "ready", windows: [],
                       resets: [], action: null }
    compare(Service.validateProvider(withEmpty), null)
    var withMalformed = { id: "claude", name: "Claude", state: "ready", windows: [],
                           resets: [{ id: "x", label: "X", available: -1, total: null,
                                      clears: [], expiresAt: null, refillsAt: null,
                                      cooldownUntil: null, claimable: true }],
                           action: null }
    verify(Service.validateProvider(withMalformed) !== null)
  }

  // Every group action comes from one model list: the left column draws it
  // and Enter fires its first entry. No per-provider Refresh survives.
  function test_group_actions_come_from_one_model() {
    var row = read("components/ProviderRow.qml")
    verify(row.indexOf("root.row.actions") >= 0)
    verify(row.indexOf("Core.primaryAction(root.actions)") >= 0)
    verify(row.indexOf("refreshButton") < 0)
    verify(row.indexOf("useResetButton") < 0)
    var popup = read("Popup.qml")
    verify(popup.indexOf("function runAction(providerId, action)") >= 0)
    verify(popup.indexOf('action.kind === "use_reset"') >= 0)
  }

  function test_service_owns_a_dedicated_reset_lane() {
    var src = read("Service.qml")
    verify(src.indexOf("id: resetLane") >= 0)
    verify(src.indexOf("id: resetProcess") >= 0)
    verify(src.indexOf("function useReset") >= 0 || src.indexOf("function confirmReset") >= 0)
    verify(src.indexOf("function requestReset(providerId, resetId)") >= 0)
  }

  function test_reset_confirm_dialog_is_single_confirm_no_arming() {
    var src = read("Popup.qml")
    verify(src.indexOf("id: resetConfirmDialog") >= 0)
    verify(src.indexOf('title: "Use reset?"') < 0)
    verify(src.indexOf("root.resetConfirmModel.title") >= 0)
    verify(src.indexOf("root.agentService.confirmReset()") >= 0)
  }

  // #83: a deferred rebuild can run after the popup was destroyed, where an
  // unguarded root.rebuildFocusTargets() throws on every open/close cycle.
  function test_deferred_focus_rebuild_survives_popup_destruction() {
    var src = read("Popup.qml")
    verify(src.indexOf("Qt.callLater(root.rebuildFocusTargets)") < 0)
    var re = /root\.rebuildFocusTargets\(\)/g
    var m
    while ((m = re.exec(src)) !== null) {
      var before = src.slice(Math.max(0, m.index - 80), m.index)
      verify(before.indexOf('typeof root.rebuildFocusTargets === "function"') >= 0,
             "unguarded rebuildFocusTargets() at offset " + m.index)
    }
    verify(src.indexOf("function scheduleFocusRebuild()") >= 0)
    compare(src.split("Qt.callLater(").length - 1, 2,
            "only scheduleFocusRebuild and onSelectedIdChanged defer")
  }
}
