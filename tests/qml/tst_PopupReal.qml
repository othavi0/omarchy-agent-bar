import QtQuick
import QtTest
import qs.Commons
import qs.Commons as Commons
import "../../CoreView.js" as Core
import "ServiceHarness.js" as ServiceHarness
import "ViewHarness.js" as ViewHarness
import "OverviewFixtures.js" as F
import "TestPalette.js" as Palette
import "../../components/Tokens.js" as Tokens

TestCase {
  id: testCase
  name: "AgentBarPopupReal"
  when: windowShown
  visible: true
  width: 600
  height: 900

  property string repoRoot: {
    var path = String(Qt.resolvedUrl(".")).replace("file://", "")
    if (path.endsWith("/"))
      path = path.slice(0, -1)
    var parts = path.split("/")
    parts.pop(); parts.pop()
    return parts.join("/")
  }
  property var service: null
  property var popup: null
  property var extraPopups: []

  function openRealPopup(env, metric, providerId) {
    service = ServiceHarness.createService("file://" + repoRoot + "/Service.qml", testCase, testCase)
    service.appliedSettings = F.settings(metric || "used")
    service.snapshot = env || F.normal()
    popup = ViewHarness.createReal(repoRoot, "Popup.qml", testCase, testCase,
                                   { agentService: service, owner: "mon-a" })
    service.requestPopup("mon-a", providerId || "claude", "usage")
    if (popup.nowMs !== undefined)
      popup.nowMs = F.FIXED_NOW
    settle()
    return popup
  }

  function secondPopup(owner) {
    var p = ViewHarness.createReal(repoRoot, "Popup.qml", testCase, testCase,
                                   { agentService: service, owner: owner })
    if (p.nowMs !== undefined)
      p.nowMs = F.FIXED_NOW
    extraPopups.push(p)
    return p
  }

  function settle() {
    wait(20)
  }

  function cleanup() {
    for (var i = 0; i < extraPopups.length; i++)
      extraPopups[i].destroy()
    extraPopups = []
    if (popup) {
      popup.destroy()
      popup = null
    }
    if (service) {
      service.destroy()
      service = null
    }
  }

  function byName(root, name) {
    return ViewHarness.findAll(root, function (item) {
      return item.objectName === name
    })
  }

  function one(root, name) {
    var found = byName(root, name)
    compare(found.length, 1, "exactly one " + name)
    return found[0]
  }

  function visibleIn(item, root) {
    for (var cur = item; cur && cur !== root; cur = cur.parent) {
      if (cur.visible === false)
        return false
    }
    return true
  }

  function rows(p) {
    return byName(p || popup, "providerRow").filter(function (r) {
      return r.visible && r.row
    }).sort(function (a, b) {
      return a.mapToItem(null, 0, 0).y - b.mapToItem(null, 0, 0).y
    })
  }

  function rowById(id, p) {
    var list = rows(p)
    for (var i = 0; i < list.length; i++) {
      if (list[i].row.id === id)
        return list[i]
    }
    fail("no row " + id)
    return null
  }

  function headOf(id, p) {
    return one(rowById(id, p), "rowHead")
  }

  function detailOf(id, p) {
    return one(rowById(id, p), "rowDetail")
  }

  function focusNames() {
    var fc = one(popup, "focusController")
    return fc.liveTargets().map(function (t) { return String(t.Accessible.name) })
  }

  function test_real_popup_loads_with_the_real_service() {
    var p = openRealPopup()
    compare(p.isOpen, true)
    compare(p.view, "usage")
    compare(p.selectedId, "claude")
    verify(p.width > 0 && p.height > 0, "the panel stub sizes the popup from its content")
    var texts = ViewHarness.findAll(p, function (item) {
      return item.textFormat !== undefined && String(item.text).indexOf("5-hour") >= 0
    })
    verify(texts.length > 0, "the real popup renders the session window label")
  }

  function test_claude_without_session_window_renders() {
    failOnWarning(/TypeError|ReferenceError|Unable to assign|Cannot read|undefined|NaN/)
    var env = F.normal()
    env.providers[0] = F.claudeUltraNoSession()
    compare(Core.chipPercentText(env.providers[0], "used"), "29%")
    openRealPopup(env, "used", "claude")
    var head = headOf("claude")
    verify(head.visible)
    var detail = detailOf("claude")
    var labels = byName(detail, "windowLabel").map(function (l) { return String(l.text) })
    verify(labels.indexOf("Fable") >= 0, "Fable window renders: " + labels)
    verify(byName(detail, "windowMeter").length > 0, "detail keeps its meters")
    var row = rowById("claude")
    var sessionTexts = ViewHarness.findAll(row, function (item) {
      return item.textFormat !== undefined && visibleIn(item, row)
          && /5h|5-hour/.test(String(item.text))
    })
    compare(sessionTexts.length, 0, "no 5-hour copy for a provider without that window")
  }

  function test_real_popup_grabs_to_an_image() {
    var p = openRealPopup()
    wait(50)
    var path = repoRoot + "/target/popup-real-smoke.png"
    var saved = null
    p.grabToImage(function (result) {
      saved = result.saveToFile(path)
    })
    tryVerify(function () { return saved !== null }, 2000, "grabToImage finished")
    verify(saved, "cannot write " + path + "; create target/ first")
  }

  function test_one_row_per_enabled_provider() {
    openRealPopup()
    compare(rows().map(function (r) { return r.row.id }).join(","),
            "claude,codex,grok,antigravity")
    var settings = F.settings("used")
    settings.providers[2].enabled = false
    service.appliedSettings = settings
    settle()
    compare(rows().map(function (r) { return r.row.id }).join(","), "claude,codex,antigravity")
  }

  function test_accordion() {
    openRealPopup()
    compare(rowById("claude").row.open, true)
    verify(visibleIn(detailOf("claude"), popup), "the open row shows its detail")
    compare(visibleIn(detailOf("codex"), popup), false)

    headOf("claude").focusActivate()
    settle()
    compare(rowById("claude").row.open, false)
    compare(visibleIn(detailOf("claude"), popup), false, "a second activation collapses the row")
    compare(popup.selectedId, "claude")

    headOf("codex").focusActivate()
    settle()
    compare(rowById("codex").row.open, true)
    compare(rowById("claude").row.open, false)
    compare(popup.selectedId, "codex")
    compare(Core.routeChipClick(1, "mon-a", "codex", service.popupOwner).action, "closePopup",
            "the same chip still closes the popup (UX-005)")
  }

  function test_monitor_move_opens_row() {
    openRealPopup()
    headOf("claude").focusActivate()
    settle()
    compare(service.popupOwner.collapsed, true)
    var other = secondPopup("mon-b")
    service.requestPopup("mon-b", "claude", "usage")
    settle()
    compare(service.popupOwner.collapsed, false)
    compare(popup.isOpen, false)
    compare(other.isOpen, true)
    compare(rowById("claude", other).row.open, true)
  }

  function test_keyboard_moves_and_opens() {
    openRealPopup()
    var keys = one(popup, "keyCatcher")
    keys.moveRequested(0, 1)
    settle()
    compare(popup.selectedId, "codex")
    compare(rowById("codex").row.open, true)
    compare(rowById("claude").row.open, false)
    tryVerify(function () { return headOf("codex").activeFocus }, 1000,
              "focus follows the selection to the new head")

    popup.handleTextKey("s")
    settle()
    compare(popup.view, "settings")
    keys.moveRequested(0, 1)
    settle()
    compare(popup.selectedId, "codex", "arrows do not switch providers in Settings")
    popup.handleTextKey("s")
    settle()
    compare(popup.view, "usage")
    compare(popup.selectedId, "codex")
    compare(rowById("codex").row.open, true)

    popup.handleTextKey("r")
    var command = service.lanes.status.process.command
    var argv = command ? Array.prototype.slice.call(command) : []
    verify(service.pendingForcedTargets.ids["codex"] === true
           || argv.join(" ").indexOf("provider codex") >= 0,
           "r forces a refresh of the selected provider: " + JSON.stringify(argv))
  }

  function test_open_focuses_the_selected_row() {
    openRealPopup(F.normal(), "used", "codex")
    tryVerify(function () { return headOf("codex").activeFocus }, 1000,
              "the popup opens with focus on the selected row, not the first one")
    compare(headOf("claude").activeFocus, false)
  }

  function test_keys_suspended_while_editor_owns_input() {
    openRealPopup()
    var keys = one(popup, "keyCatcher")
    keys.blocked = true
    popup.handleTextKey("s")
    settle()
    compare(popup.view, "usage")
  }

  function test_focus_order() {
    openRealPopup()
    tryVerify(function () { return focusNames().length > 0 }, 1000)
    compare(JSON.stringify(focusNames()), JSON.stringify([
      "Claude, 76% used, 5-hour · resets in 1h 32m",
      "Use reset",
      "Refresh",
      "Codex, 2% used, 5-hour · resets in 4h 10m",
      "Grok, 30% used, Monthly · resets in 13d 21h",
      "Antigravity, 0% used, Gemini · 5h",
      "Settings"
    ]))

    headOf("claude").focusActivate()
    settle()
    tryVerify(function () { return focusNames().length === 5 }, 1000,
              "a collapsed row contributes its head only: " + JSON.stringify(focusNames()))
    compare(focusNames()[0], "Claude, 76% used, 5-hour · resets in 1h 32m")
    compare(focusNames()[1], "Codex, 2% used, 5-hour · resets in 4h 10m")
  }

  function test_focus_skips_a_disabled_use_reset() {
    var env = F.normal()
    env.providers[0].resets = [F.claudeReset(false)]
    openRealPopup(env)
    var reset = ViewHarness.buttonsWithText(detailOf("claude"), ["Use reset"])
    compare(reset.length, 1)
    compare(reset[0].visible, true, "Use reset shows when nothing is claimable")
    compare(reset[0].enabled, false)
    tryVerify(function () { return focusNames().length > 0 }, 1000)
    compare(focusNames().indexOf("Use reset"), -1)
    compare(focusNames()[1], "Refresh")
  }

  function test_long_reset_label_keeps_the_drawer_readable() {
    var env = F.normal()
    var reset = F.claudeReset(true)
    reset.label = "Claude Opus 5.5 launch: one usage-limit reset for Team members"
    env.providers[0].resets = [reset]
    openRealPopup(env)
    var detail = detailOf("claude")
    waitForRendering(popup)
    var saved = null
    popup.grabToImage(function (result) {
      saved = result.saveToFile(repoRoot + "/target/v10-ui-evidence/long-reset-label.png")
    })
    tryVerify(function () { return saved !== null }, 3000, "grabToImage finished")
    var meters = byName(detail, "windowMeter")
    compare(meters.length, 2)
    for (var i = 0; i < meters.length; i++)
      verify(meters[i].width >= detail.contentWidth / 3,
             "window meter keeps its width, got " + meters[i].width + " of " + detail.contentWidth)
    var label = one(detail, "resetLabel")
    verify(label.mapToItem(detail, label.width, 0).x <= detail.width,
           "the reset label stays inside the drawer")
    var facts = one(detail, "resetFacts")
    verify(facts.width >= detail.contentWidth / 2,
           "reset facts get a readable width, got " + facts.width + " of " + detail.contentWidth)
    verify(facts.lineCount <= 2, "reset facts wrap at most once, got " + facts.lineCount + " lines")
  }

  function test_long_window_label_keeps_the_meters() {
    var env = F.normal()
    env.providers[0].windows[2].label = "Claude Opus 5.5 Extended Thinking Preview for Team members"
    openRealPopup(env)
    var detail = detailOf("claude")
    waitForRendering(popup)
    var saved = null
    popup.grabToImage(function (result) {
      saved = result.saveToFile(repoRoot + "/target/v10-ui-evidence/long-window-label.png")
    })
    tryVerify(function () { return saved !== null }, 3000, "grabToImage finished")
    var meters = byName(detail, "windowMeter")
    compare(meters.length, 2)
    for (var i = 0; i < meters.length; i++)
      verify(meters[i].width >= detail.contentWidth / 4,
             "window meter keeps its width, got " + meters[i].width + " of " + detail.contentWidth)
  }

  function test_antigravity_window_labels_stay_whole() {
    openRealPopup(F.normal(), "used", "antigravity")
    var detail = detailOf("antigravity")
    var labels = byName(detail, "windowLabel")
    verify(labels.length > 0)
    for (var i = 0; i < labels.length; i++)
      verify(!labels[i].truncated, labels[i].text + " is not elided")
  }

  function overflowingTexts(root) {
    return ViewHarness.findAll(root, function (item) {
      if (item.textFormat === undefined || !item.text || !visibleIn(item, root))
        return false
      var left = item.mapToItem(root, 0, 0).x
      return left < 0 || left + Math.max(item.width, item.contentWidth) > root.width + 1
    }).map(function (item) { return String(item.text) })
  }

  function test_long_provider_copy_never_leaves_the_popup() {
    var long = "Claude Opus 5.5 Extended Thinking Preview for Enterprise Team members"
    var env = F.normal()
    for (var p = 0; p < env.providers.length; p++) {
      var provider = env.providers[p]
      provider.plan = { id: "enterprise", label: long }
      for (var w = 0; w < provider.windows.length; w++)
        provider.windows[w].label = long + " " + w
    }
    var reset = F.claudeReset(true)
    reset.label = long
    env.providers[0].resets = [reset]
    for (var o = 0; o < env.providers.length; o++) {
      openRealPopup(env, "used", env.providers[o].id)
      waitForRendering(popup)
      var saved = null
      popup.grabToImage(function (result) {
        saved = result.saveToFile(repoRoot + "/target/v10-ui-evidence/long-copy-"
                                  + env.providers[o].id + ".png")
      })
      tryVerify(function () { return saved !== null }, 3000, "grabToImage finished")
      compare(JSON.stringify(overflowingTexts(popup)), "[]",
              env.providers[o].id + " drawer keeps every text inside the popup")
      cleanup()
    }
  }

  function test_single_collapsed_row_puts_the_footer_under_it() {
    openRealPopup(F.envelope([F.claudeReady(25, 103)]))
    var onlyClaude = F.settings("used")
    for (var i = 0; i < onlyClaude.providers.length; i++)
      onlyClaude.providers[i].enabled = onlyClaude.providers[i].id === "claude"
    service.appliedSettings = onlyClaude
    settle()
    compare(rows().length, 1, "one provider row")
    headOf("claude").focusActivate()
    settle()
    compare(rowById("claude").row.open, false, "the only row is collapsed")
    waitForRendering(popup)
    var saved = null
    popup.grabToImage(function (result) {
      saved = result.saveToFile(repoRoot + "/target/v10-ui-evidence/single-collapsed-row.png")
    })
    tryVerify(function () { return saved !== null }, 3000, "grabToImage finished")
    var row = rowById("claude")
    var rowBottom = row.mapToItem(popup, 0, row.height).y
    var footer = one(popup, "popupFooter")
    var gap = footer.mapToItem(popup, 0, 0).y - rowBottom
    verify(gap <= 1, "the footer sits under the row, gap " + gap + " px")
  }

  function test_spent_reset_hides_the_reset_section() {
    var env = F.normal()
    var spent = F.claudeReset(false)
    spent.available = 0
    spent.expiresAt = null
    spent.cooldownUntil = F.at(60)
    env.providers[0].resets = [spent]
    openRealPopup(env)
    var detail = detailOf("claude")
    compare(byName(detail, "resetLabel").length, 0, "no reset line without a reset left")
    compare(ViewHarness.buttonsWithText(detail, ["Use reset"])[0].visible, false,
            "Use reset hides without a reset left")
  }

  function test_status_row_carries_its_action() {
    openRealPopup(F.problems(), "used", "codex")
    var codex = rowById("codex")
    compare(codex.row.kind, "status")
    var install = ViewHarness.buttonsWithText(codex, ["Install guide"])
    compare(install.length, 1)
    tryVerify(function () { return focusNames().indexOf("Install guide") >= 0 }, 1000)
    compare(focusNames().indexOf("Install guide"), focusNames().indexOf("Codex, Not installed") + 1)
    var refresh = one(detailOf("codex"), "refreshButton")
    compare(refresh.text, "Check again")
  }

  function test_tick_keeps_row_delegates() {
    openRealPopup()
    var head = headOf("claude")
    head.forceActiveFocus()
    verify(head.activeFocus)
    popup.nowMs = popup.nowMs + 30000
    settle()
    compare(headOf("claude"), head, "the clock tick re-binds text without new delegates")
    verify(head.activeFocus, "focus survives the tick")
  }

  function test_no_close_control() {
    openRealPopup()
    var closers = ViewHarness.findAll(popup, function (item) {
      return String(item.Accessible.name) === "Close"
          || (item.text !== undefined && (String(item.text) === "×" || String(item.text) === "Close"))
    })
    compare(closers.length, 0)
  }

  function assertFullBleed(item, body, what) {
    var at = item.mapToItem(body, 0, 0)
    compare(at.x, 0, what + " starts at the popup border")
    compare(item.width, body.width, what + " spans the popup width")
  }

  function test_edges_reach_the_border() {
    openRealPopup()
    var body = one(popup, "popupBody")
    verify(body.width > 0)
    var rules = byName(popup, "edgeRule").concat(byName(popup, "drawerRule"), byName(popup, "rowBand"))
        .filter(function (r) { return visibleIn(r, popup) })
    verify(rules.length >= 5, "bands, rims, drawer hairlines and the footer each run edge to edge: " + rules.length)
    for (var i = 0; i < rules.length; i++)
      assertFullBleed(rules[i], body, "rule " + i)
    assertFullBleed(one(popup, "popupFooter"), body, "the footer")
    var list = rows()
    for (var r = 0; r < list.length; r++)
      assertFullBleed(list[r], body, list[r].row.id + " row")
  }

  function test_only_rows_list_scrolls() {
    openRealPopup()
    var body = one(popup, "popupBody")
    var flick = one(popup, "contentFlick")
    var footer = one(popup, "popupFooter")
    popup.maxContentHeight = 200
    settle()
    verify(flick.interactive, "the rows overflow a short popup")
    var footerY = footer.mapToItem(body, 0, 0).y
    flick.contentY = 40
    settle()
    compare(footer.mapToItem(body, 0, 0).y, footerY)
    compare(footerY + footer.height, body.height, "the footer is pinned to the bottom")

    popup.maxContentHeight = 4000
    settle()
    compare(flick.interactive, false)
    compare(flick.contentY, 0)
  }

  function test_expand_reclamps_content_y() {
    openRealPopup()
    var flick = one(popup, "contentFlick")
    popup.maxContentHeight = 220
    settle()
    verify(flick.interactive)
    flick.contentY = flick.contentHeight - flick.height
    settle()
    headOf("claude").focusActivate()
    settle()
    verify(flick.contentY <= Math.max(0, flick.contentHeight - flick.height),
           "collapse re-clamps contentY: " + flick.contentY + " of " + flick.contentHeight
           + " in " + flick.height)
  }

  function test_clock_resyncs_on_open() {
    openRealPopup()
    compare(popup.nowTickRunning, true)
    service.closePopup("mon-a")
    settle()
    compare(popup.nowTickRunning, false, "the clock stops while the popup is closed")
    popup.nowMs = 0
    service.requestPopup("mon-a", "claude", "usage")
    settle()
    verify(popup.nowMs > 0, "opening resyncs the clock")
    compare(popup.nowTickRunning, popup.isOpen)
  }

  function test_footer_focus_keeps_the_scroll() {
    openRealPopup()
    var flick = one(popup, "contentFlick")
    popup.maxContentHeight = 220
    settle()
    verify(flick.interactive)
    flick.contentY = 0
    var fc = one(popup, "focusController")
    var settingsButton = fc.liveTargets()[fc.liveTargets().length - 1]
    compare(String(settingsButton.Accessible.name), "Settings")
    verify(fc.focusItem(settingsButton))
    compare(flick.contentY, 0, "a pinned footer target never scrolls the rows")
  }

  function test_refresh_busy_state() {
    openRealPopup()
    var refresh = one(detailOf("claude"), "refreshButton")
    compare(refresh.text, "Refresh")
    compare(refresh.iconSpinning, false)
    popup.onRefresh("claude")
    tryCompare(service, "refreshing", true, 1000)
    compare(refresh.text, "Refreshing")
    compare(refresh.iconSpinning, true)
    compare(refresh.enabled, true, "Refresh stays enabled")
  }

  function test_popup_starts_with_the_rows() {
    openRealPopup(F.critical())
    var body = one(popup, "popupBody")
    compare(byName(popup, "overviewBand").length, 0, "no headline band")
    var first = rows()[0]
    compare(first.row.id, "claude")
    compare(first.mapToItem(body, 0, 0).y, 0, "the first row meets the top border")
    var texts = ViewHarness.findAll(popup, function (item) {
      return item.textFormat !== undefined && visibleIn(item, popup) && String(item.text).length > 0
    }).map(function (t) { return String(t.text) })
    verify(texts.indexOf("5-hour · resets in 38m") >= 0,
           "the fullest row reads its own reset: " + texts)
    var tight = ViewHarness.findAll(popup, function (item) {
      return /tightest/i.test(String(item.text === undefined ? "" : item.text))
          || /tightest/i.test(String(item.Accessible.name))
    })
    compare(tight.length, 0, "nothing names a tightest window")
  }

  function test_pace_line_renders_the_projection() {
    openRealPopup()
    var detail = detailOf("claude")
    var texts = ViewHarness.findAll(detail, function (item) {
      return item.textFormat !== undefined && visibleIn(item, popup) && String(item.text).length > 0
    }).map(function (t) { return String(t.text) })
    verify(texts.indexOf("full in ~1h 6m") >= 0, "pace strong text: " + texts)
    verify(texts.indexOf(", 26m before reset") >= 0)
    verify(texts.indexOf("= time passed") >= 0)
    var ticks = byName(rowById("claude"), "paceTick").filter(function (t) {
      return visibleIn(t, popup)
    })
    verify(ticks.length >= 1, "the primary meter carries the pace tick")
  }
  function openSettingsView(env) {
    openRealPopup(env)
    popup.openSettings()
    ServiceHarness.finishLane(service, "settingsRead", 0, JSON.stringify(F.settings("used")))
    settle()
    compare(popup.view, "settings")
    compare(service.settingsState.phase, "clean")
    return popup
  }

  function settingsRowFor(id) {
    var found = byName(popup, "settingsProviderRow").filter(function (r) {
      return r.providerId === id && visibleIn(r, popup)
    })
    compare(found.length, 1, "exactly one Settings row for " + id)
    return found[0]
  }

  function visibleTexts(root) {
    return ViewHarness.findAll(root, function (item) {
      return item.textFormat !== undefined && visibleIn(item, popup) && String(item.text).length > 0
    }).map(function (t) { return String(t.text) })
  }

  function liveFocusNamesAfterRebuild(expectedFirst) {
    tryVerify(function () {
      var names = focusNames()
      return names.length > 0 && names[0] === expectedFirst
    }, 1000, "the focus order rebuilt: " + JSON.stringify(focusNames()))
    return focusNames()
  }

  function test_settings_focus_order() {
    openSettingsView()
    var tabs = ["Back to usage", "Providers", "General", "About"]
    tryVerify(function () { return focusNames().length > tabs.length }, 1000,
              "the Providers body joins the focus order: " + JSON.stringify(focusNames()))
    compare(JSON.stringify(focusNames()), JSON.stringify(tabs.concat([
      "Claude on the bar", "Move Claude down",
      "Codex on the bar", "Move Codex up", "Move Codex down",
      "Grok on the bar", "Move Grok up", "Move Grok down",
      "Antigravity on the bar", "Move Antigravity up",
      "Restore defaults"
    ])))

    popup.settingsTab = "general"
    var fc = one(popup, "focusController")
    tryVerify(function () { return fc.liveTargets().indexOf(one(popup, "metricGroup")) >= 0 }, 1000,
              "the General body joins the focus order")
    var general = fc.liveTargets().slice(tabs.length)
    compare(general.length, 5)
    compare(general[0], one(popup, "metricGroup"))
    compare(general[1], one(popup, "intervalField").field)
    compare(general[2], one(popup, "notificationsToggle"))
    compare(general[3], one(popup, "reminderField").field)
    compare(String(general[4].Accessible.name), "Restore defaults")

    service.setNotificationsEnabled(false)
    tryVerify(function () { return fc.liveTargets().indexOf(one(popup, "reminderField").field) < 0 },
              1000, "the reminder field leaves the order while notifications are off")

    popup.settingsTab = "about"
    tryVerify(function () { return focusNames().indexOf("Check for updates") >= 0 }, 1000,
              "the About body joins the focus order: " + JSON.stringify(focusNames()))
    var about = focusNames()
    compare(JSON.stringify(about.slice(0, tabs.length)), JSON.stringify(tabs))
    compare(about[tabs.length], "Check for updates")
    compare(about[tabs.length + 1], "Uninstall Agent Bar")
  }

  function test_settings_focus_follows_a_moved_row() {
    openSettingsView()
    tryVerify(function () { return focusNames().indexOf("Move Codex up") >= 0 }, 1000)
    var fc = one(popup, "focusController")
    var up = fc.liveTargets()[focusNames().indexOf("Move Codex up")]
    verify(fc.focusItem(up))
    fc.activate()
    tryVerify(function () {
      return fc.current && String(fc.current.Accessible.name) === "Move Codex down"
    }, 1000, "focus stays on the moved row: " + (fc.current ? fc.current.Accessible.name : "none"))
    verify(fc.current.activeFocus)
    compare(service.settingsDraft.providers[0].id, "codex")
  }

  function test_settings_edges() {
    openSettingsView()
    settingsRowFor("antigravity").enableToggled()
    settle()
    var body = one(popup, "popupBody")
    var tabs = ["providers", "general", "about"]
    for (var t = 0; t < tabs.length; t++) {
      popup.settingsTab = tabs[t]
      settle()
      var rules = byName(popup, "edgeRule").filter(function (r) { return visibleIn(r, popup) })
      verify(rules.length >= 4, tabs[t] + ": header, sections and footer draw rules: " + rules.length)
      for (var i = 0; i < rules.length; i++)
        assertFullBleed(rules[i], body, tabs[t] + " rule " + i)
      assertFullBleed(one(popup, "settingsFooter"), body, tabs[t] + " footer")
    }
    popup.settingsTab = "providers"
    settle()
    var settingsRows = byName(popup, "settingsProviderRow").filter(function (r) {
      return visibleIn(r, popup)
    })
    compare(settingsRows.length, 4)
    for (var r = 0; r < settingsRows.length; r++)
      assertFullBleed(settingsRows[r], body, settingsRows[r].providerId + " Settings row")
    var footer = one(popup, "settingsFooter")
    compare(footer.mapToItem(body, 0, 0).y + footer.height, body.height,
            "the Settings footer meets the bottom border")
  }

  function test_settings_plan_once_and_status() {
    var env = F.problems()
    env.providers[0] = F.claudeReady(76, 92)
    env.providers[1].plan = { id: "plus", label: "Plus" }
    openSettingsView(env)
    var claude = visibleTexts(settingsRowFor("claude")).join(" ")
    compare(claude.split("Max").length - 1, 1, "the plan prints once: " + claude)
    var codex = visibleTexts(settingsRowFor("codex")).join(" ")
    verify(codex.indexOf("Not installed") >= 0, codex)
    compare(codex.indexOf("Plus"), -1, "a status replaces the plan: " + codex)

    var footer = one(popup, "settingsFooter")
    verify(visibleTexts(footer).indexOf("No changes") >= 0, visibleTexts(footer))
    service.setDisplayMetric("remaining")
    settle()
    verify(visibleTexts(footer).indexOf("1 unsaved change") >= 0, visibleTexts(footer))
  }

  function test_settings_back_without_rail() {
    openSettingsView(F.normal())
    settingsRowFor("grok").enableToggled()
    settle()
    var draft = JSON.stringify(service.settingsDraft)
    var selected = popup.selectedId
    one(popup, "settingsHeader").backRequested()
    settle()
    compare(popup.view, "usage")
    compare(popup.selectedId, selected)
    compare(JSON.stringify(service.settingsDraft), draft, "Back keeps the unsaved draft")
    compare(rowById(selected).row.open, true, "Back reopens the selected row")
  }

  // Real key presses reach the catcher only when the focused control leaves
  // them alone, so these tests press keys instead of emitting its signals.
  function pressAndExpectTabWalk(steps, key) {
    var fc = one(popup, "focusController")
    var live = fc.liveTargets()
    var at = live.indexOf(fc.current)
    verify(at >= 0, "the walk starts on a live target")
    var direction = key === Qt.Key_Backtab ? -1 : 1
    for (var i = 1; i <= steps; i++) {
      keyClick(key)
      settle()
      var want = live[((at + direction * i) % live.length + live.length) % live.length]
      compare(fc.current, want, "step " + i + " lands on " + want.Accessible.name
              + ", not " + (fc.current ? fc.current.Accessible.name : "none"))
      verify(want.activeFocus, "step " + i + ": " + want.Accessible.name
             + " holds focus, not " + testCase.Window.activeFocusItem)
    }
  }

  function test_tab_keys_walk_the_usage_order() {
    openRealPopup()
    tryVerify(function () { return headOf("claude").activeFocus }, 1000)
    var count = focusNames().length
    compare(count, 7)
    pressAndExpectTabWalk(count + 1, Qt.Key_Tab)
    pressAndExpectTabWalk(count + 1, Qt.Key_Backtab)
  }

  function test_tab_keys_walk_the_general_tab() {
    openSettingsView()
    popup.settingsTab = "general"
    var fc = one(popup, "focusController")
    var group = one(popup, "metricGroup")
    tryVerify(function () { return fc.liveTargets().indexOf(group) >= 0 }, 1000)
    verify(fc.focusItem(group))
    pressAndExpectTabWalk(fc.liveTargets().length + 1, Qt.Key_Tab)
    pressAndExpectTabWalk(3, Qt.Key_Backtab)
  }

  function test_escape_closes_from_a_number_field() {
    openSettingsView()
    popup.settingsTab = "general"
    var fc = one(popup, "focusController")
    var field = one(popup, "intervalField").field
    tryVerify(function () { return fc.liveTargets().indexOf(field) >= 0 }, 1000)
    verify(fc.focusItem(field))
    verify(popup.editorActive, "the field owns typing")
    keyClick(Qt.Key_Escape)
    settle()
    compare(popup.isOpen, false, "Esc closes the popup from the field")
  }

  function currentName() {
    var fc = one(popup, "focusController")
    return fc.current && fc.current.activeFocus ? String(fc.current.Accessible.name) : "none"
  }

  function test_view_switch_focuses_back_and_the_selected_row() {
    openRealPopup(F.normal(), "used", "grok")
    tryVerify(function () { return headOf("grok").activeFocus }, 1000)
    keyClick(Qt.Key_S)
    ServiceHarness.finishLane(service, "settingsRead", 0, JSON.stringify(F.settings("used")))
    settle()
    compare(popup.view, "settings")
    tryVerify(function () { return currentName() === "Back to usage" }, 1000,
              "s opens Settings on Back, not on " + currentName())

    keyClick(Qt.Key_S)
    settle()
    compare(popup.view, "usage")
    tryVerify(function () { return headOf("grok").activeFocus }, 1000,
              "Back lands on the selected row, not on " + currentName())

    var fc = one(popup, "focusController")
    var live = fc.liveTargets()
    verify(fc.focusItem(live[live.length - 1]))
    compare(currentName(), "Settings")
    keyClick(Qt.Key_Return)
    settle()
    compare(popup.view, "settings")
    tryVerify(function () { return currentName() === "Back to usage" }, 1000,
              "the footer opens Settings on Back, not on " + currentName())
  }

  function test_hidden_selection_moves_to_the_shown_row() {
    openRealPopup(F.normal(), "used", "grok")
    var settings = F.settings("used")
    for (var i = 0; i < settings.providers.length; i++) {
      if (settings.providers[i].id === "grok")
        settings.providers[i].enabled = false
    }
    service.appliedSettings = settings
    settle()
    compare(popup.overview.selectedId, "claude")
    compare(popup.selectedId, popup.overview.selectedId,
            "the popup and the overview agree on the selected row")
    tryVerify(function () { return headOf("claude").activeFocus }, 1000,
              "focus follows the selection to the shown row")

    headOf("claude").focusActivate()
    settle()
    compare(rowById("claude").row.open, false, "the first press closes the open row")

    keyClick(Qt.Key_Down)
    settle()
    compare(popup.selectedId, "codex", "Down steps from the shown row")
    compare(rowById("codex").row.open, true)
  }

  function test_collapsed_row_shows_a_critical_side_window() {
    openRealPopup(F.envelope([
      F.provider("claude", "Claude", "ready", [F.win("session", "5-hour", 98, 300, 30)]),
      F.provider("codex", "Codex", "ready", [
        F.win("session", "5-hour", 10, 300, 200),
        F.win("weekly", "Weekly (7d)", 97, 10080, 600)
      ])
    ]))
    compare(rowById("codex").row.open, false)
    var alert = one(rowById("codex"), "rowAlert")
    verify(visibleIn(alert, popup), "the collapsed row shows the alert glyph")
  }

  function test_restart_banner_follows_the_card_corners() {
    var saved = Style.cornerRadius
    Style.cornerRadius = 12
    try {
      openRealPopup()
      service.restartPendingVersion = "10.7.0"
      settle()
      var banner = one(popup, "restartBanner")
      verify(banner.visible)
      verify(popup.innerRadius > 0)
      compare(banner.topLeftRadius, popup.innerRadius, "the banner fill stays inside the rounded border")
      compare(banner.topRightRadius, popup.innerRadius)
    } finally {
      Style.cornerRadius = saved
    }
  }

  function test_first_row_follows_the_card_corners() {
    var saved = Style.cornerRadius
    Style.cornerRadius = 12
    try {
      openRealPopup()
      verify(popup.innerRadius > 0)
      var plate = one(rows()[0], "rowPlate")
      compare(plate.topLeftRadius, popup.innerRadius, "the open row fill stays inside the rounded border")
      compare(plate.topRightRadius, popup.innerRadius)
      compare(one(rows()[0], "rowHover").topLeftRadius, popup.innerRadius)
      compare(one(rows()[0], "rowFocusRing").topRightRadius, popup.innerRadius,
              "the focus ring of the first row follows the border too")
      compare(one(rows()[1], "rowPlate").topLeftRadius, 0, "only the first row meets the border")

      service.restartPendingVersion = "10.7.0"
      settle()
      verify(one(popup, "restartBanner").visible)
      compare(one(rows()[0], "rowPlate").topLeftRadius, 0, "the banner owns the corners")
    } finally {
      Style.cornerRadius = saved
    }
  }

  // Gaveta: rows are slabs split by a band thicker than any rule inside the
  // open drawer, and the drawer's sections are split by full-bleed hairlines.
  function test_drawer_band_outweighs_the_hairlines() {
    openRealPopup()
    var body = one(popup, "popupBody")
    var list = rows()
    for (var r = 0; r < list.length - 1; r++) {
      var band = one(list[r], "rowBand")
      verify(visibleIn(band, popup), list[r].row.id + " ends in a band")
      assertFullBleed(band, body, list[r].row.id + " band")
    }
    compare(visibleIn(one(list[list.length - 1], "rowBand"), popup), false,
            "the footer draws the last band")
    var rules = byName(detailOf("claude"), "drawerRule").filter(function (r) { return visibleIn(r, popup) })
    compare(rules.length, 3, "pace, windows, reset and actions are four sections with three rules")
    for (var i = 0; i < rules.length; i++) {
      assertFullBleed(rules[i], body, "drawer rule " + i)
      verify(one(list[0], "rowBand").height > rules[i].height,
             "the band (" + one(list[0], "rowBand").height + ") outweighs a hairline (" + rules[i].height + ")")
    }
  }

  function test_chevron_follows_the_open_row() {
    openRealPopup()
    tryCompare(one(rowById("claude"), "rowChevron"), "rotation", 90, 1000, "the open row points down")
    compare(one(rowById("codex"), "rowChevron").rotation, 0, "a closed row points right")
    verify(visibleIn(one(rowById("codex"), "rowChevron"), popup))
    headOf("codex").focusActivate()
    settle()
    tryCompare(one(rowById("codex"), "rowChevron"), "rotation", 90, 1000)
    tryCompare(one(rowById("claude"), "rowChevron"), "rotation", 0, 1000)
  }

  function leftOf(item) {
    return Math.round(item.mapToItem(one(popup, "popupBody"), 0, 0).x)
  }

  function rightOf(item) {
    return Math.round(item.mapToItem(one(popup, "popupBody"), item.width, 0).x)
  }

  function test_drawer_sections_share_one_column_and_one_edge() {
    openRealPopup()
    var row = rowById("claude")
    var detail = detailOf("claude")
    var column = leftOf(one(row, "rowName"))
    var starts = [one(detail, "paceGlyph"), one(detail, "resetLabel"), one(detail, "updatedClock")]
        .concat(byName(detail, "windowLabel"))
    compare(byName(detail, "windowLabel").length, 2)
    for (var i = 0; i < starts.length; i++)
      compare(leftOf(starts[i]), column, starts[i].objectName + " starts under the provider name")

    var edge = rightOf(one(row, "rowChevron"))
    var ends = [one(detail, "refreshButton"), one(detail, "paceKey")].concat(byName(detail, "windowReset"))
    for (var e = 0; e < ends.length; e++)
      compare(rightOf(ends[e]), edge, ends[e].objectName + " ends on the chevron's edge")

    var labels = byName(detail, "windowLabel")
    var metersStart = leftOf(byName(detail, "windowMeter")[0])
    compare(leftOf(one(detail, "resetFacts")), metersStart, "the reset facts start where the meters start")
    for (var w = 0; w < labels.length; w++)
      verify(labels[w].height >= Style.spacing.controlHeight, "a window row is one control tall")
    compare(labels[1].mapToItem(detail, 0, 0).y - labels[0].mapToItem(detail, 0, 0).y, labels[0].height,
            "window rows stack with no gap")
  }

  function test_action_buttons_are_tonal_twins() {
    openRealPopup()
    var detail = detailOf("claude")
    var use = one(detail, "useResetButton")
    var refresh = one(detail, "refreshButton")
    compare(use.bordered, false, "Use reset has no outline")
    compare(refresh.bordered, false, "Refresh has no outline")
    compare(use.width, refresh.width, "both buttons share one width")
    compare(use.height, refresh.height)
    compare(refresh.height, Style.spacing.controlHeight)
    compare(Math.round(use.mapToItem(detail, use.width, 0).x) + Style.space(8),
            Math.round(refresh.mapToItem(detail, 0, 0).x), "one gap between the twins")
    verify(!Qt.colorEqual(use.color, refresh.color), "the claimable reset is the tinted primary")
    verify(Qt.colorEqual(refresh.color, refresh.background), "Refresh rests on its tonal fill")
    var width = refresh.width
    popup.onRefresh("claude")
    tryCompare(service, "refreshing", true, 1000)
    compare(refresh.text, "Refreshing")
    compare(refresh.width, width, "Refreshing does not resize the button")
    var clock = one(detail, "updatedClock")
    compare(Math.round(clock.mapToItem(detail, 0, clock.height / 2).y),
            Math.round(refresh.mapToItem(detail, 0, refresh.height / 2).y),
            "Updated sits on the buttons' centre line")
  }

  function test_status_row_action_is_tonal() {
    openRealPopup(F.problems(), "used", "codex")
    var install = ViewHarness.buttonsWithText(rowById("codex"), ["Install guide"])
    compare(install.length, 1)
    compare(install[0].bordered, false, "the head action drops the outline too")
    var head = one(rowById("codex"), "rowPlate").color
    verify(!Qt.colorEqual(install[0].color, head), "the head action rests on a tint, not the bare head")
    compare(install[0].height, Style.spacing.controlHeight, "the layout keeps the head action at the control height")
  }

  function luma(c) {
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
  }

  function test_well_is_recessed_in_every_theme_data() {
    return [{ tag: "dark", mode: "dark" }, { tag: "light", mode: "light" }, { tag: "white", mode: "white" }]
  }

  function test_well_is_recessed_in_every_theme(data) {
    var c = Commons.Color
    var saved = { foreground: String(c.foreground), background: String(c.background),
                  accent: String(c.accent), urgent: String(c.urgent), muted: String(c.muted),
                  popups: { background: String(c.popups.background), border: String(c.popups.border) } }
    var p = Palette.themePalette(data.mode)
    try {
      c.foreground = p.foreground; c.background = p.background; c.accent = p.accent
      c.urgent = p.urgent; c.muted = p.muted
      c.popups.background = p.popups.background; c.popups.border = p.popups.border
      openRealPopup()
      var well = one(rowById("claude"), "drawerWell").color
      var slab = one(rowById("codex"), "rowPlate").color
      var band = one(rowById("claude"), "rowBand").color
      verify(luma(well) < luma(slab), data.tag + ": the well (" + well + ") sits below the slab (" + slab + ")")
      verify(luma(band) <= luma(well), data.tag + ": the band (" + band + ") is the floor under the well (" + well + ")")
    } finally {
      c.foreground = saved.foreground; c.background = saved.background; c.accent = saved.accent
      c.urgent = saved.urgent; c.muted = saved.muted
      c.popups.background = saved.popups.background; c.popups.border = saved.popups.border
    }
  }

  function test_action_buttons_show_hover_and_press_data() {
    return [{ tag: "useReset" }, { tag: "refresh" }, { tag: "headAction" }]
  }

  // The tonal fills replace the host fill rule, so each button paints its
  // own rest, hover or focus, and press tones, and a press still clicks.
  function test_action_buttons_show_hover_and_press(data) {
    var button
    var clicks = { count: 0 }
    if (data.tag === "headAction") {
      openRealPopup(F.problems(), "used", "codex")
      button = ViewHarness.buttonsWithText(rowById("codex"), ["Install guide"])[0]
    } else {
      openRealPopup()
      button = one(detailOf("claude"), data.tag === "useReset" ? "useResetButton" : "refreshButton")
    }
    verify(button.enabled, data.tag + " is enabled")
    button.clicked.connect(function () { clicks.count++ })
    var rest = String(button.color)
    button.hasCursor = true
    var hot = String(button.color)
    button.hasCursor = false
    verify(hot !== rest, data.tag + ": hover (" + hot + ") differs from rest (" + rest + ")")
    button.forceActiveFocus()
    tryVerify(function () { return button.activeFocus }, 1000, data.tag + " takes focus")
    compare(String(button.color), hot, data.tag + ": focus takes the hover tone")
    mousePress(button, button.width / 2, button.height / 2, Qt.LeftButton)
    var pressed = String(button.color)
    verify(pressed !== hot && pressed !== rest,
           data.tag + ": press (" + pressed + ") differs from hover (" + hot + ") and rest (" + rest + ")")
    mouseRelease(button, button.width / 2, button.height / 2, Qt.LeftButton)
    verify(String(button.color) !== pressed, data.tag + ": release drops the press tone")
    compare(clicks.count, 1, data.tag + ": the press still clicks")
  }

  function frameWidth() {
    return popup.verticalContentInset / 2
  }

  function test_open_block_is_framed_without_doubled_sides() {
    openRealPopup()
    compare(byName(popup, "rowRail").length, 0, "no accent rail on the left of the open row")
    compare(byName(popup, "rowLip").length, 0, "no thick accent lip under the open head")
    var claude = rowById("claude")
    var top = one(claude, "rowFrameTop")
    var bottom = one(claude, "rowFrameBottom")
    compare(top.visible, false, "the popup border already closes the first row's top")
    verify(bottom.visible, "the open block closes with a bottom line")
    compare(bottom.x, 0)
    compare(bottom.width, claude.width, "the line spans the row; the popup border draws the sides")
    compare(bottom.height, frameWidth(), "the line matches the popup border width")
    verify(Qt.colorEqual(bottom.color, Commons.Color.popups.border), "the line uses the popup border colour")
    compare(bottom.y + bottom.height, one(claude, "drawerWell").y + one(claude, "drawerWell").height,
            "the bottom line closes the well, above the band to the next provider")

    cleanup()
    openRealPopup(F.normal(), "used", "grok")
    var grok = rowById("grok")
    verify(one(grok, "rowFrameTop").visible, "an open row below another provider gets a top line")
    compare(one(grok, "rowFrameTop").y, 0)
    compare(one(rowById("claude"), "rowFrameBottom").visible, false, "a closed row draws no frame")
  }

  function test_open_head_keeps_a_light_accent() {
    openRealPopup()
    var plate = one(rowById("claude"), "rowPlate").color
    var slab = Tokens.surfaces(Commons.Color.popups.background, Commons.Color.foreground).slab
    verify(Qt.colorEqual(plate, Tokens.mix(slab, Commons.Color.accent, 0.06)),
           "the open head carries 6% accent, got " + plate)
  }

  function test_action_buttons_reserve_the_host_focus_border() {
    openRealPopup()
    var thin = one(detailOf("claude"), "refreshButton").width
    cleanup()
    var saved = Style.styleOverrides
    Style.styleOverrides = { "focus-border-width": 3 }
    try {
      openRealPopup()
      compare(Style.focusBorderWidth, 3)
      var detail = detailOf("claude")
      compare(one(detail, "refreshButton").width, thin + (3 - Style.spacing.hairline) * 2,
              "a 3 px focus border widens the buttons by the extra border on each side")
      compare(one(detail, "useResetButton").width, one(detail, "refreshButton").width)
    } finally {
      Style.styleOverrides = saved
    }
  }

  function test_drawer_meters_start_under_the_head_meter() {
    openRealPopup()
    var head = one(rowById("claude"), "rowMeter")
    var meters = byName(detailOf("claude"), "windowMeter")
    verify(meters.length > 0)
    for (var i = 0; i < meters.length; i++)
      compare(leftOf(meters[i]), leftOf(head), "drawer meter " + i + " starts under the head meter")
    compare(leftOf(one(detailOf("claude"), "resetFacts")), leftOf(head), "the reset facts too")
  }

  function contrast(a, b) {
    function lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    function lum(c) { return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) }
    var la = lum(a), lb = lum(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  function over(top, base) {
    return Qt.rgba(top.r * top.a + base.r * (1 - top.a), top.g * top.a + base.g * (1 - top.a),
                   top.b * top.a + base.b * (1 - top.a), 1)
  }

  function test_disabled_use_reset_stays_legible_data() {
    return [{ tag: "dark", mode: "dark" }, { tag: "light", mode: "light" }, { tag: "white", mode: "white" }]
  }

  function test_disabled_use_reset_stays_legible(data) {
    var c = Commons.Color
    var saved = { foreground: String(c.foreground), background: String(c.background),
                  accent: String(c.accent), popups: { background: String(c.popups.background) } }
    var p = Palette.themePalette(data.mode)
    try {
      c.foreground = p.foreground; c.background = p.background; c.accent = p.accent
      c.popups.background = p.popups.background
      var env = F.normal()
      env.providers[0].resets = [F.claudeReset(false)]
      openRealPopup(env)
      var use = one(detailOf("claude"), "useResetButton")
      var well = one(rowById("claude"), "drawerWell").color
      compare(use.enabled, false)
      verify(!Qt.colorEqual(use.color, well), data.tag + ": the disabled fill still shows on the well")
      var label = over(use.foreground, use.color)
      var ratio = contrast(label, use.color)
      verify(ratio >= 3, data.tag + ": the disabled label keeps 3:1 contrast (" + ratio.toFixed(2) + ")")
    } finally {
      c.foreground = saved.foreground; c.background = saved.background; c.accent = saved.accent
      c.popups.background = saved.popups.background
    }
  }
}
