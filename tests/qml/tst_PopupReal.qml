import QtQuick
import QtTest
import "../../CoreView.js" as Core
import "ServiceHarness.js" as ServiceHarness
import "ViewHarness.js" as ViewHarness
import "OverviewFixtures.js" as F

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
      return item.textFormat !== undefined && String(item.text).indexOf("Session (5h)") >= 0
    })
    verify(texts.length > 0, "the real popup renders the session window label")
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
      "Claude, 76% used, Session (5h), tightest",
      "Use reset",
      "Refresh",
      "Codex, 2% used, Session (5h) · resets in 4h 10m",
      "Grok, 30% used, Monthly · resets in 13d 21h",
      "Antigravity, 0% used, Gemini · 5h",
      "Settings"
    ]))

    headOf("claude").focusActivate()
    settle()
    tryVerify(function () { return focusNames().length === 5 }, 1000,
              "a collapsed row contributes its head only: " + JSON.stringify(focusNames()))
    compare(focusNames()[0], "Claude, 76% used, Session (5h), tightest")
    compare(focusNames()[1], "Codex, 2% used, Session (5h) · resets in 4h 10m")
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
    var rules = byName(popup, "edgeRule").filter(function (r) { return visibleIn(r, popup) })
    verify(rules.length >= 6, "band, rows, detail lines and footer each draw a rule: " + rules.length)
    for (var i = 0; i < rules.length; i++)
      assertFullBleed(rules[i], body, "rule " + i)
    assertFullBleed(one(popup, "overviewBand"), body, "the band")
    assertFullBleed(one(popup, "popupFooter"), body, "the footer")
    var list = rows()
    for (var r = 0; r < list.length; r++)
      assertFullBleed(list[r], body, list[r].row.id + " row")
  }

  function test_only_rows_list_scrolls() {
    openRealPopup()
    var body = one(popup, "popupBody")
    var flick = one(popup, "contentFlick")
    var band = one(popup, "overviewBand")
    var footer = one(popup, "popupFooter")
    popup.maxContentHeight = 200
    settle()
    verify(flick.interactive, "the rows overflow a short popup")
    var bandY = band.mapToItem(body, 0, 0).y
    var footerY = footer.mapToItem(body, 0, 0).y
    flick.contentY = 40
    settle()
    compare(band.mapToItem(body, 0, 0).y, bandY)
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

  function test_headline_band_names_the_tightest_window() {
    openRealPopup(F.critical())
    var band = one(popup, "overviewBand")
    compare(band.Accessible.name, "Tightest: Claude session 96% used, critical, resets in 38m")
    var texts = ViewHarness.findAll(band, function (item) {
      return item.textFormat !== undefined && item.visible && String(item.text).length > 0
    }).map(function (t) { return String(t.text) })
    verify(texts.indexOf("Critical") >= 0, "the band carries the Critical tag: " + texts)
    compare(one(band, "edgeRule").visible, true)
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
}
