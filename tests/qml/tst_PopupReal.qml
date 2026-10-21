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
      F.provider("claude", "Claude", "ready", [F.win("session", "Session (5h)", 98, 300, 30)]),
      F.provider("codex", "Codex", "ready", [
        F.win("session", "Session (5h)", 10, 300, 200),
        F.win("weekly", "Weekly (7d)", 97, 10080, 600)
      ])
    ]))
    compare(rowById("codex").row.open, false)
    var alert = one(rowById("codex"), "rowAlert")
    verify(visibleIn(alert, popup), "the collapsed row shows the alert glyph")
  }
}
