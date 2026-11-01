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

  function focusNames() {
    var fc = one(popup, "focusController")
    return fc.liveTargets().map(function (t) { return String(t.Accessible.name) })
  }

  function shown(root, name) {
    return byName(root, name).filter(function (item) { return visibleIn(item, popup) })
  }

  function buttonIn(id, label) {
    var found = ViewHarness.buttonsWithText(rowById(id), [label])
    compare(found.length, 1, "one " + label + " button in " + id)
    return found[0]
  }

  function leftOf(item) {
    return Math.round(item.mapToItem(one(popup, "popupBody"), 0, 0).x)
  }

  function rightOf(item) {
    return Math.round(item.mapToItem(one(popup, "popupBody"), item.width, 0).x)
  }

  function grab(name) {
    waitForRendering(popup)
    var saved = null
    popup.grabToImage(function (result) {
      saved = result.saveToFile(repoRoot + "/target/v10-ui-evidence/" + name)
    })
    tryVerify(function () { return saved !== null }, 3000, "grabToImage finished for " + name)
  }

  function withPalette(mode, body) {
    var c = Commons.Color
    var saved = { foreground: String(c.foreground), background: String(c.background),
                  accent: String(c.accent), urgent: String(c.urgent), muted: String(c.muted),
                  popups: { background: String(c.popups.background), border: String(c.popups.border) } }
    var p = Palette.themePalette(mode)
    try {
      c.foreground = p.foreground; c.background = p.background; c.accent = p.accent
      c.urgent = p.urgent; c.muted = p.muted
      c.popups.background = p.popups.background; c.popups.border = p.popups.border
      body()
    } finally {
      c.foreground = saved.foreground; c.background = saved.background; c.accent = saved.accent
      c.urgent = saved.urgent; c.muted = saved.muted
      c.popups.background = saved.popups.background; c.popups.border = saved.popups.border
    }
  }

  function test_real_popup_loads_with_the_real_service() {
    var p = openRealPopup()
    compare(p.isOpen, true)
    compare(p.view, "usage")
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
    var row = rowById("claude")
    var labels = byName(row, "windowLabel").map(function (l) { return String(l.text) })
    compare(labels, ["Weekly", "Fable"])
    compare(shown(row, "windowMeter").length, 2)
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

  // Nothing folds: every group shows every window.
  function test_every_window_shows_without_an_accordion() {
    openRealPopup()
    compare(byName(popup, "rowChevron").length, 0, "no chevron")
    compare(byName(popup, "rowDetail").length, 0, "no drawer")
    compare(byName(popup, "drawerWell").length, 0, "no drawer well")
    var expected = { claude: 3, codex: 2, grok: 1, antigravity: 4 }
    for (var id in expected) {
      compare(shown(rowById(id), "windowMeter").length, expected[id], id + " shows every window")
      compare(shown(rowById(id), "windowPercent").length, expected[id])
    }
  }

  function test_monitor_move_keeps_every_window() {
    openRealPopup()
    var other = secondPopup("mon-b")
    service.requestPopup("mon-b", "codex", "usage")
    settle()
    compare(popup.isOpen, false)
    compare(other.isOpen, true)
    compare(shown(rowById("claude", other), "windowMeter").length, 3)
  }

  function test_focus_order() {
    openRealPopup()
    tryVerify(function () { return focusNames().length > 0 }, 1000)
    compare(JSON.stringify(focusNames()), JSON.stringify(["Use reset", "Refresh", "Settings"]),
            "only buttons take focus")
  }

  function test_focus_skips_a_disabled_use_reset() {
    var env = F.normal()
    env.providers[0].resets = [F.claudeReset(false)]
    openRealPopup(env)
    var reset = buttonIn("claude", "Use reset")
    compare(reset.visible, true, "Use reset shows when nothing is claimable")
    compare(reset.enabled, false)
    tryVerify(function () { return focusNames().length > 0 }, 1000)
    compare(focusNames().indexOf("Use reset"), -1)
  }

  function test_status_group_carries_its_actions() {
    openRealPopup(F.problems(), "used", "codex")
    var codex = rowById("codex")
    compare(codex.row.kind, "status")
    compare(buttonIn("codex", "Install guide").objectName, "groupAction")
    compare(buttonIn("codex", "Check again").objectName, "groupAction")
    tryVerify(function () { return focusNames().indexOf("Install guide") >= 0 }, 1000)
    compare(focusNames().indexOf("Check again"), focusNames().indexOf("Install guide") + 1)
    compare(ViewHarness.buttonsWithText(codex, ["Refresh"]).length, 0, "no per-provider Refresh")
    verify(visibleTexts(codex).indexOf("Codex CLI was not found.") >= 0, visibleTexts(codex))
  }

  function test_spent_reset_hides_the_reset_action() {
    var env = F.normal()
    var spent = F.claudeReset(false)
    spent.available = 0
    spent.expiresAt = null
    spent.cooldownUntil = F.at(60)
    env.providers[0].resets = [spent]
    openRealPopup(env)
    compare(ViewHarness.buttonsWithText(rowById("claude"), ["Use reset"]).length, 0,
            "no Use reset without a reset left")
    compare(visibleTexts(rowById("claude")).join("|").indexOf("reset left"), -1)
  }

  function test_long_reset_label_stays_out_of_the_group() {
    var env = F.normal()
    var reset = F.claudeReset(true)
    reset.label = "Claude Opus 5.5 launch: one usage-limit reset for Team members"
    env.providers[0].resets = [reset]
    openRealPopup(env)
    grab("long-reset-label.png")
    compare(JSON.stringify(overflowingTexts(popup)), "[]")
    compare(visibleTexts(rowById("claude")).join("|").indexOf("Team members"), -1,
            "the group shows the count and date; the label waits for the confirm dialog")
  }

  function test_long_window_label_elides_and_keeps_the_bars() {
    var env = F.normal()
    env.providers[0].windows[2].label = "Claude Opus 5.5 Extended Thinking Preview for Team members"
    openRealPopup(env)
    grab("long-window-label.png")
    var meters = shown(popup, "windowMeter")
    for (var i = 1; i < meters.length; i++)
      compare(meters[i].width, meters[0].width, "every bar keeps one width")
    var label = byName(rowById("claude"), "windowLabel")[2]
    verify(label.truncated, "the long label elides")
    var reset = byName(rowById("claude"), "windowReset")[2]
    verify(rightOf(label) < leftOf(reset), "the label stops before its reset")
    compare(JSON.stringify(overflowingTexts(popup)), "[]")
  }

  function test_antigravity_window_labels_stay_whole() {
    openRealPopup(F.normal(), "used", "antigravity")
    var labels = byName(rowById("antigravity"), "windowLabel")
    compare(labels.length, 4)
    for (var i = 0; i < labels.length; i++)
      verify(!labels[i].truncated, labels[i].text + " is not elided")
  }

  function test_names_and_state_copy_stay_whole_data() {
    return [{ tag: "normal", env: "normal" }, { tag: "problems", env: "problems" },
            { tag: "nopct", env: "nopct" }, { tag: "stale", env: "stale" }]
  }

  function test_names_and_state_copy_stay_whole(data) {
    openRealPopup(F[data.env]())
    var names = byName(popup, "rowName").filter(function (t) { return visibleIn(t, popup) })
    verify(names.length > 0)
    for (var i = 0; i < names.length; i++)
      verify(!names[i].truncated, names[i].text + " is not elided")
    var buttons = ViewHarness.findAll(popup, function (item) {
      return item.bordered !== undefined && visibleIn(item, popup) && String(item.text).length
          && item.objectName.indexOf("Action") > 0
    })
    for (var b = 0; b < buttons.length; b++)
      verify(buttons[b].width >= buttons[b].implicitWidth, buttons[b].text + " is not squeezed")
    compare(JSON.stringify(overflowingTexts(popup)), "[]")
  }

  function test_single_group_puts_the_footer_under_it() {
    openRealPopup(F.envelope([F.claudeReady(25, 103)]))
    var onlyClaude = F.settings("used")
    for (var i = 0; i < onlyClaude.providers.length; i++)
      onlyClaude.providers[i].enabled = onlyClaude.providers[i].id === "claude"
    service.appliedSettings = onlyClaude
    settle()
    compare(rows().length, 1, "one provider group")
    grab("single-group.png")
    var row = rowById("claude")
    var rowBottom = row.mapToItem(popup, 0, row.height).y
    var footer = one(popup, "popupFooter")
    var gap = footer.mapToItem(popup, 0, 0).y - rowBottom
    verify(gap <= 1, "the footer sits under the group, gap " + gap + " px")
  }

  function test_tick_keeps_row_delegates() {
    openRealPopup()
    var use = buttonIn("claude", "Use reset")
    use.forceActiveFocus()
    verify(use.activeFocus)
    popup.nowMs = popup.nowMs + 30000
    settle()
    compare(buttonIn("claude", "Use reset"), use, "the clock tick re-binds text without new delegates")
    verify(use.activeFocus, "focus survives the tick")
  }

  function test_no_close_control() {
    openRealPopup()
    var closers = ViewHarness.findAll(popup, function (item) {
      return String(item.Accessible.name) === "Close"
          || (item.text !== undefined && (String(item.text) === "×" || String(item.text) === "Close"))
    })
    compare(closers.length, 0)
  }

  function test_edges_reach_the_border() {
    openRealPopup()
    var body = one(popup, "popupBody")
    verify(body.width > 0)
    var rules = byName(popup, "edgeRule").concat(byName(popup, "rowBand"))
        .filter(function (r) { return visibleIn(r, popup) })
    compare(rules.length, 8, "three group bands and rims plus the footer's")
    for (var i = 0; i < rules.length; i++)
      assertFullBleed(rules[i], body, "rule " + i)
    assertFullBleed(one(popup, "popupFooter"), body, "the footer")
    var list = rows()
    for (var r = 0; r < list.length; r++)
      assertFullBleed(list[r], body, list[r].row.id + " group")
  }

  function test_only_rows_list_scrolls() {
    openRealPopup()
    var body = one(popup, "popupBody")
    var flick = one(popup, "contentFlick")
    var footer = one(popup, "popupFooter")
    popup.maxContentHeight = 200
    settle()
    verify(flick.interactive, "the groups overflow a short popup")
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

  // The popup grows with its groups up to maxContentHeight, then scrolls.
  function test_height_follows_the_content_up_to_the_cap() {
    openRealPopup()
    var flick = one(popup, "contentFlick")
    popup.maxContentHeight = 4000
    settle()
    compare(popup.contentHeight, popup.measuredBodyHeight + popup.verticalContentInset,
            "an uncapped popup is exactly as tall as its content")
    compare(flick.height, flick.contentHeight, "no scroll without overflow")
    popup.maxContentHeight = 300
    settle()
    compare(popup.contentHeight, 300)
    verify(flick.interactive)
    flick.contentY = flick.contentHeight - flick.height
    settle()
    popup.maxContentHeight = 4000
    settle()
    compare(flick.contentY, 0, "growing back resets the scroll")
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

  // One "Updated" line in the footer; a refresh in flight replaces it.
  function test_footer_shows_one_updated_line() {
    openRealPopup()
    var status = one(popup, "footerStatus")
    compare(status.text, "Updated 1m ago · % used")
    var all = visibleTexts(popup).filter(function (t) { return t.indexOf("Updated") >= 0 })
    compare(all.length, 1, "only the footer says Updated: " + all)
    popup.refreshAll()
    tryCompare(service, "refreshing", true, 1000)
    compare(status.text, "Refreshing… · % used")
  }

  // The unit prints once, in the footer, for every percentage above it.
  function test_unit_prints_once() {
    openRealPopup()
    compare(visibleTexts(popup).filter(function (t) { return /\bused\b/.test(t) }),
            ["Updated 1m ago · % used"])
    cleanup()
    openRealPopup(F.normal(), "remaining")
    compare(visibleTexts(popup).filter(function (t) {
      return /\b(used|left)\b/.test(t) && t.indexOf("reset") < 0
    }), ["Updated 1m ago · % left"])
  }

  function test_popup_starts_with_the_rows() {
    openRealPopup(F.critical())
    var body = one(popup, "popupBody")
    compare(byName(popup, "overviewBand").length, 0, "no headline band")
    var first = rows()[0]
    compare(first.row.id, "claude")
    compare(first.mapToItem(body, 0, 0).y, 0, "the first row meets the top border")
    var resets = byName(first, "windowReset").map(function (t) { return String(t.text) })
    verify(resets[0].indexOf("38m") === 0, "the fullest window reads its own reset: " + resets)
    var tight = ViewHarness.findAll(popup, function (item) {
      return /tightest/i.test(String(item.text === undefined ? "" : item.text))
          || /tightest/i.test(String(item.Accessible.name))
    })
    compare(tight.length, 0, "nothing names a tightest window")
  }

  function test_meters_carry_no_time_tick() {
    openRealPopup()
    compare(byName(popup, "paceTick").length, 0, "no meter draws a time tick")
    var texts = visibleTexts(popup)
    for (var i = 0; i < texts.length; i++)
      verify(!/At this pace|Too early to project|time passed|of the window has passed/.test(texts[i]),
             "no pace copy: " + texts[i])
    compare(String(rowById("claude").Accessible.description), "")
  }

  // A critical window turns its own bar and number urgent; no alert glyph
  // repeats the colour.
  function test_critical_window_turns_its_bar_and_number_urgent() {
    openRealPopup(F.envelope([
      F.provider("claude", "Claude", "ready", [F.win("session", "5-hour", 20, 300, 30)]),
      F.provider("codex", "Codex", "ready", [
        F.win("session", "5-hour", 10, 300, 200),
        F.win("weekly", "Weekly", 97, 10080, 600)
      ])
    ]))
    var meters = byName(rowById("codex"), "windowMeter")
    var numbers = byName(rowById("codex"), "windowPercent")
    verify(Qt.colorEqual(meters[0].fillColor, Commons.Color.accent))
    verify(Qt.colorEqual(meters[1].fillColor, Commons.Color.urgent))
    verify(!Qt.colorEqual(numbers[0].color, Commons.Color.urgent))
    verify(Qt.colorEqual(numbers[1].color, Commons.Color.urgent))
    compare(byName(popup, "rowAlert").length, 0)
    var glyphs = ViewHarness.findAll(popup, function (item) {
      return item.textFormat !== undefined && visibleIn(item, popup)
          && String(item.text) === Tokens.GLYPH_ALERT
    })
    compare(glyphs.length, 0, "no alert glyph in the popup")
  }

  function test_first_row_follows_the_card_corners() {
    var saved = Style.cornerRadius
    Style.cornerRadius = 12
    try {
      openRealPopup()
      verify(popup.innerRadius > 0)
      var plate = one(rows()[0], "rowPlate")
      compare(plate.topLeftRadius, popup.innerRadius, "the first group's fill stays inside the rounded border")
      compare(plate.topRightRadius, popup.innerRadius)
      compare(one(rows()[1], "rowPlate").topLeftRadius, 0, "only the first group meets the border")

      service.restartPendingVersion = "10.7.0"
      settle()
      verify(one(popup, "restartBanner").visible)
      compare(one(rows()[0], "rowPlate").topLeftRadius, 0, "the banner owns the corners")
    } finally {
      Style.cornerRadius = saved
    }
  }

  // Gaveta: groups are slabs split by a band thicker than any hairline.
  function test_groups_are_split_by_the_band() {
    openRealPopup()
    var body = one(popup, "popupBody")
    var list = rows()
    for (var r = 0; r < list.length - 1; r++) {
      var band = one(list[r], "rowBand")
      verify(visibleIn(band, popup), list[r].row.id + " ends in a band")
      assertFullBleed(band, body, list[r].row.id + " band")
      verify(band.height > one(list[r], "edgeRule").height, "the band outweighs the rim")
    }
    compare(visibleIn(one(list[list.length - 1], "rowBand"), popup), false,
            "the footer draws the last band")
    compare(byName(popup, "rowRail").length, 0, "no accent rail")
    compare(byName(popup, "rowFrameTop").length + byName(popup, "rowFrameBottom").length, 0,
            "no frame lines around the selected group")
  }

  function test_band_is_the_floor_in_every_theme_data() {
    return [{ tag: "dark", mode: "dark" }, { tag: "light", mode: "light" }, { tag: "white", mode: "white" }]
  }

  function test_band_is_the_floor_in_every_theme(data) {
    withPalette(data.mode, function () {
      openRealPopup()
      var slab = one(rowById("codex"), "rowPlate").color
      var band = one(rowById("claude"), "rowBand").color
      verify(luma(band) < luma(slab), data.tag + ": the band (" + band + ") sits below the slab (" + slab + ")")
    })
  }

  function luma(c) {
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
  }

  // Group actions and Settings are tonal: accent fill over the slab, accent
  // label at 4.5:1. Refresh is text alone.
  function test_group_actions_are_tonal_data() {
    return [{ tag: "dark", mode: "dark" }, { tag: "light", mode: "light" }, { tag: "white", mode: "white" }]
  }

  function test_group_actions_are_tonal(data) {
    withPalette(data.mode, function () {
      openRealPopup(F.problems(), "used", "claude")
      var plate = one(rowById("codex"), "rowPlate").color
      var actions = [buttonIn("codex", "Install guide"), buttonIn("codex", "Check again")]
      for (var i = 0; i < actions.length; i++) {
        var b = actions[i]
        compare(b.bordered, false)
        compare(b.height, Style.spacing.controlHeight)
        verify(Math.abs(centerY(b) - centerY(actions[0])) <= 1, "the actions share one line")
        verify(Qt.colorEqual(b.color, Tokens.mix(plate, Commons.Color.accent, Tokens.PRIMARY_REST)),
               data.tag + ": " + b.text + " rests on the accent at 16%")
        var ratio = contrast(b.foreground, b.color)
        verify(ratio >= 4.5, data.tag + ": " + b.text + " reads at " + ratio.toFixed(2))
        var hotRatio = contrast(b.foreground, Tokens.mix(plate, Commons.Color.accent, Tokens.PRIMARY_PRESS))
        verify(hotRatio >= 4.5, data.tag + ": and on its press fill at " + hotRatio.toFixed(2))
      }
      verify(leftOf(actions[1]) > rightOf(actions[0]), "the actions sit side by side")
      var refresh = ViewHarness.buttonsWithText(one(popup, "popupFooter"), ["Refresh"])[0]
      compare(refresh.color.a, 0, data.tag + ": Refresh has no fill")
      var textRatio = contrast(over(refresh.foreground, plate), plate)
      verify(textRatio >= 4.5, data.tag + ": the Refresh label reads at " + textRatio.toFixed(2))
    })
  }

  function test_action_buttons_show_hover_and_press_data() {
    return [{ tag: "useReset" }, { tag: "installGuide" }, { tag: "checkAgain" },
            { tag: "refresh" }, { tag: "settings" }]
  }

  // The tonal fills replace the host fill rule, so each button paints its
  // own rest, hover or focus, and press tones, and a press still clicks.
  function test_action_buttons_show_hover_and_press(data) {
    var button
    var clicks = { count: 0 }
    if (data.tag === "useReset") {
      openRealPopup()
      button = buttonIn("claude", "Use reset")
    } else if (data.tag === "refresh" || data.tag === "settings") {
      openRealPopup()
      button = ViewHarness.buttonsWithText(one(popup, "popupFooter"),
                                           [data.tag === "refresh" ? "Refresh" : "Settings"])[0]
    } else {
      openRealPopup(F.problems(), "used", "codex")
      button = buttonIn("codex", data.tag === "installGuide" ? "Install guide" : "Check again")
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

  function test_disabled_use_reset_stays_legible_data() {
    return [{ tag: "dark", mode: "dark" }, { tag: "light", mode: "light" }, { tag: "white", mode: "white" }]
  }

  function test_disabled_use_reset_stays_legible(data) {
    withPalette(data.mode, function () {
      var env = F.normal()
      env.providers[0].resets = [F.claudeReset(false)]
      openRealPopup(env)
      var use = buttonIn("claude", "Use reset")
      var plate = one(rowById("claude"), "rowPlate").color
      compare(use.enabled, false)
      verify(!Qt.colorEqual(use.color, plate), data.tag + ": the disabled fill still shows on the slab")
      var label = over(use.foreground, use.color)
      var ratio = contrast(label, use.color)
      verify(ratio >= 3, data.tag + ": the disabled label keeps 3:1 contrast (" + ratio.toFixed(2) + ")")
    })
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

  function assertFullBleed(item, body, what) {
    var at = item.mapToItem(body, 0, 0)
    compare(at.x, 0, what + " starts at the popup border")
    compare(item.width, body.width, what + " spans the popup width")
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
    compare(general.length, 4)
    compare(general[0], one(popup, "metricGroup"))
    compare(general[1], one(popup, "intervalField").field)
    compare(general[2], one(popup, "notificationsToggle"))
    compare(String(general[3].Accessible.name), "Restore defaults")
    compare(byName(popup, "reminderField").length, 0)

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
    one(popup, "settingsHeader").backRequested()
    settle()
    compare(popup.view, "usage")
    compare(JSON.stringify(service.settingsDraft), draft, "Back keeps the unsaved draft")
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
    var fc = one(popup, "focusController")
    tryVerify(function () { return focusNames().length === 3 }, 1000)
    keyClick(Qt.Key_Tab)
    settle()
    compare(currentName(), "Use reset")
    pressAndExpectTabWalk(4, Qt.Key_Tab)
    pressAndExpectTabWalk(4, Qt.Key_Backtab)
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

  function test_view_switch_focuses_back() {
    openRealPopup(F.normal(), "used", "grok")
    keyClick(Qt.Key_Backtab)
    settle()
    compare(currentName(), "Settings", "Backtab from the open popup reaches the last button")
    keyClick(Qt.Key_Return)
    ServiceHarness.finishLane(service, "settingsRead", 0, JSON.stringify(F.settings("used")))
    settle()
    compare(popup.view, "settings")
    tryVerify(function () { return currentName() === "Back to usage" }, 1000,
              "the footer opens Settings on Back, not on " + currentName())
    keyClick(Qt.Key_Return)
    settle()
    compare(popup.view, "usage")
    compare(one(popup, "focusController").current, null, "Back focuses no control")
    keyClick(Qt.Key_Escape)
    settle()
    compare(popup.isOpen, false, "Esc still reaches the popup after Back")
  }

  function centerY(item) {
    return item.mapToItem(one(popup, "popupBody"), 0, item.height / 2).y
  }

  // Compact layout: icon, name and plan read on one header line, with the
  // short state note and the actions on the right of that same line.
  function test_header_puts_name_and_plan_on_one_line() {
    openRealPopup()
    var list = rows()
    var withPlan = 0
    for (var r = 0; r < list.length; r++) {
      var name = one(list[r], "rowName")
      var plan = one(list[r], "rowPlan")
      if (!visibleIn(plan, popup))
        continue
      withPlan++
      verify(Math.abs(centerY(plan) - centerY(name)) <= 2,
             list[r].row.id + ": the plan sits on the name's line, not under it")
      verify(leftOf(plan) > rightOf(name), list[r].row.id + ": the plan follows the name")
    }
    verify(withPlan > 0, "the fixture shows at least one plan")
    cleanup()
    openRealPopup(F.problems(), "used", "claude")
    var codex = rowById("codex")
    var install = buttonIn("codex", "Install guide")
    verify(Math.abs(centerY(install) - centerY(one(codex, "rowName"))) <= 2,
           "the actions share the header line")
    compare(rightOf(buttonIn("codex", "Check again")),
            one(popup, "popupBody").width - Style.spacing.popupPadding,
            "the last action ends on the content edge")
    var note = one(codex, "groupNote")
    verify(visibleIn(note, popup))
    verify(Math.abs(centerY(note) - centerY(one(codex, "rowName"))) <= 2, "the note shares the header line")
    verify(rightOf(note) <= leftOf(install), "the note sits left of the actions")
    compare(shown(popup, "sideColumn").length, 0, "no side column")
  }

  // Each window is one line: label, bar, percentage and reset, in columns
  // shared by every group so the bars line up across the popup.
  function test_each_window_is_one_line_with_shared_columns() {
    openRealPopup()
    var lines = shown(popup, "windowLine")
    compare(lines.length, 10)
    var meters = shown(popup, "windowMeter")
    var numbers = shown(popup, "windowPercent")
    var labels = shown(popup, "windowLabel")
    var resets = shown(popup, "windowReset")
    compare(meters.length, 10)
    var edge = one(popup, "popupBody").width - Style.spacing.popupPadding
    for (var i = 0; i < meters.length; i++) {
      var mid = centerY(meters[i])
      verify(Math.abs(centerY(labels[i]) - mid) <= 2, "label " + i + " shares its bar's line")
      verify(Math.abs(centerY(numbers[i]) - mid) <= 2, "percentage " + i + " shares its bar's line")
      verify(Math.abs(centerY(resets[i]) - mid) <= 2, "reset " + i + " shares its bar's line")
      compare(leftOf(labels[i]), Style.spacing.popupPadding, "label " + i + " starts on the inset")
      compare(labels[i].width, labels[0].width, "label " + i + " sits in the shared column")
      compare(leftOf(meters[i]), leftOf(meters[0]), "bar " + i + " starts with the others")
      compare(meters[i].width, meters[0].width, "bar " + i + " keeps the shared width")
      verify(leftOf(meters[i]) >= rightOf(labels[i]), "bar " + i + " starts after its label")
      compare(rightOf(numbers[i]), rightOf(numbers[0]), "percentage " + i + " ends with the others")
      verify(leftOf(numbers[i]) >= rightOf(meters[i]), "percentage " + i + " follows its bar")
      compare(rightOf(resets[i]), edge, "reset " + i + " ends on the content edge")
      verify(leftOf(resets[i]) >= rightOf(numbers[i]), "reset " + i + " follows its percentage")
      verify(!labels[i].truncated, labels[i].text + " is not cut")
    }
  }

  function test_footer_has_buttons_not_keycaps() {
    openRealPopup()
    var footer = one(popup, "popupFooter")
    var texts = visibleTexts(footer)
    compare(texts.filter(function (t) { return t === "↑↓" || t === "r" || t === "s" }).length, 0,
            "no keycap: " + JSON.stringify(texts))
    compare(texts.filter(function (t) { return /provider|refresh ·|settings$/.test(t) }).length, 0,
            "no key hint label: " + JSON.stringify(texts))
    compare(one(footer, "footerStatus").text, "Updated 1m ago · % used")
    var refresh = ViewHarness.buttonsWithText(footer, ["Refresh"])
    var settings = ViewHarness.buttonsWithText(footer, ["Settings"])
    compare(refresh.length, 1, "one Refresh button")
    compare(settings.length, 1, "one Settings button")
    verify(leftOf(refresh[0]) < leftOf(settings[0]), "Refresh comes before Settings")
    verify(leftOf(refresh[0]) > rightOf(one(footer, "footerStatus")), "the buttons sit right of the status")
    compare(refresh[0].iconText, Tokens.GLYPH_REFRESH)
    compare(settings[0].iconText, Tokens.GLYPH_SETTINGS)
    compare(refresh[0].color.a, 0, "Refresh is text alone")
    verify(settings[0].color.a > 0, "Settings is tonal")
    mouseClick(refresh[0])
    tryCompare(service, "refreshing", true, 1000)
    compare(one(footer, "footerStatus").text, "Refreshing… · % used")
    compare(service.pendingForcedTargets.all === true
            || String(service.lanes.status.process.command).indexOf("provider") < 0, true,
            "Refresh forces every provider")
    mouseClick(settings[0])
    settle()
    compare(popup.view, "settings")
  }

  // What a group draws: every shown item, its fill and its outline.
  function drawn(root) {
    return ViewHarness.findAll(root, function (item) { return visibleIn(item, popup) })
        .map(function (item) {
          return item.objectName + "|" + (item.color === undefined ? "" : String(item.color))
              + "|" + (item.border === undefined ? "" : String(item.border.color) + "/" + item.border.width)
        })
  }

  function test_clicking_a_group_neither_selects_nor_outlines_it() {
    openRealPopup(F.problems(), "used", "claude")
    var grok = rowById("grok")
    var before = drawn(grok)
    mouseClick(one(grok, "rowName"))
    settle()
    compare(JSON.stringify(drawn(grok)), JSON.stringify(before), "a click changes nothing in the group")
    compare(String(one(rowById("claude"), "rowPlate").color), String(one(grok, "rowPlate").color),
            "every group rests on one slab")
    compare(byName(popup, "rowFocusRing").length + byName(popup, "rowHead").length, 0,
            "a group is no focus stop")
    compare(service.pendingForcedTargets.ids["grok"] === true, false, "a click runs no action")
    compare(popup.selectedId, undefined, "the popup keeps no selection")
  }

  function test_arrows_enter_and_letters_do_nothing_and_escape_closes() {
    openRealPopup()
    var fc = one(popup, "focusController")
    settle()
    compare(fc.current, null, "opening focuses no control")
    var keys = [Qt.Key_Down, Qt.Key_Up, Qt.Key_J, Qt.Key_K, Qt.Key_Return, Qt.Key_Enter,
                Qt.Key_Space, Qt.Key_R, Qt.Key_S]
    for (var k = 0; k < keys.length; k++) {
      keyClick(keys[k])
      settle()
      compare(popup.view, "usage", "key " + keys[k] + " keeps the usage view")
      verify(!service.resetUi || !service.resetUi.confirmOpen, "key " + keys[k] + " asks no reset")
      compare(service.refreshing, false, "key " + keys[k] + " starts no refresh")
      compare(fc.current, null, "key " + keys[k] + " moves no focus")
    }
    keyClick(Qt.Key_Tab)
    settle()
    compare(currentName(), "Use reset", "Tab reaches the first button")
    keyClick(Qt.Key_Escape)
    settle()
    compare(popup.isOpen, false, "Esc closes the popup")
  }
}
