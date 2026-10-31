import QtQuick
import QtTest
import "../../CoreView.js" as Core
import "../../components/Tokens.js" as Tokens
import "OverviewFixtures.js" as F

TestCase {
  id: testCase
  name: "AgentBarOverview"

  readonly property string timeFormat: "hh:mm"

  function ui(extra) {
    var out = { refreshing: false, resetUi: null, resetBusy: false,
                dateFormat: "MM/dd/yyyy", timeFormat: timeFormat }
    for (var k in (extra || {}))
      out[k] = extra[k]
    return out
  }

  function model(env, metric, selection, uiExtra) {
    return Core.overviewModel(env, F.settings(metric), F.FIXED_NOW,
                              selection || { id: "claude", collapsed: false },
                              ui(uiExtra))
  }

  function rowOf(m, id) {
    for (var i = 0; i < m.rows.length; i++) {
      if (m.rows[i].id === id)
        return m.rows[i]
    }
    fail("no row " + id)
    return null
  }

  function windowOf(row, id) {
    for (var i = 0; i < row.windows.length; i++) {
      if (row.windows[i].id === id)
        return row.windows[i]
    }
    fail("no window " + id + " in " + row.id)
    return null
  }

  function withProviders(providers) {
    return F.envelope(providers)
  }

  function test_overview_elects_no_tightest_window() {
    var fixtures = [F.normal(), F.critical(), F.stale(), F.problems(), F.providerError(),
                    F.nopct(), F.early(), F.full(), null]
    var metrics = ["used", "remaining"]
    for (var f = 0; f < fixtures.length; f++) {
      for (var m = 0; m < metrics.length; m++) {
        var om = model(fixtures[f], metrics[m])
        compare(JSON.stringify(Object.keys(om).sort()),
                JSON.stringify(["metric", "openId", "rows", "selectedId", "unitText"]),
                "fixture " + f + " " + metrics[m] + " carries no headline")
        compare(/tightest/i.test(JSON.stringify(om)), false,
                "fixture " + f + " " + metrics[m] + " names no tightest window")
      }
    }
  }

  function test_row_primary_matches_chip() {
    var fixtures = [F.normal(), F.critical(), F.stale(), F.problems(), F.providerError(),
                    F.nopct(), F.early(), F.full(), null]
    var metrics = ["used", "remaining"]
    for (var f = 0; f < fixtures.length; f++) {
      for (var m = 0; m < metrics.length; m++) {
        var settings = F.settings(metrics[m])
        var providers = Core.visibleProviders(fixtures[f], settings)
        var om = Core.overviewModel(fixtures[f], settings, F.FIXED_NOW,
                                    { id: "claude", collapsed: false }, ui())
        compare(om.rows.length, providers.length)
        for (var i = 0; i < providers.length; i++) {
          compare(om.rows[i].id, String(providers[i].id))
          compare(om.rows[i].valueText,
                  Core.chipNumeralText(providers[i], metrics[m], F.FIXED_NOW),
                  "fixture " + f + " " + metrics[m] + " " + providers[i].id)
        }
      }
    }
  }

  function test_no_repeat_rule() {
    var m = model(F.normal(), "used")
    var claude = rowOf(m, "claude")
    compare(claude.kind, "reading")
    compare(claude.primary.id, "session")
    compare(claude.subText, "5-hour · resets in 1h 32m")
    compare(claude.windows.map(function (w) { return w.id }), ["weekly", "weekly-model:fable"])
    compare(claude.accessibleName, "Claude, 76% used, 5-hour · resets in 1h 32m")

    var codex = rowOf(m, "codex")
    compare(codex.subText, "5-hour · resets in 4h 10m")
    compare(codex.accessibleName, "Codex, 2% used, 5-hour · resets in 4h 10m")

    var hot = rowOf(model(F.critical(), "used"), "claude")
    compare(hot.accessibleName, "Claude, 96% used, critical, 5-hour · resets in 38m")

    var weeklyHighest = withProviders([
      F.provider("claude", "Claude", "ready", [
        F.win("session", "5-hour", 76, 300, 92),
        F.win("weekly", "Weekly (7d)", 97, 10080, 4080)
      ])
    ])
    var row = rowOf(model(weeklyHighest, "used"), "claude")
    compare(row.primary.id, "session")
    compare(row.subText, "5-hour · resets in 1h 32m")
    compare(windowOf(row, "weekly").resetCellText, "resets in 2d 20h",
            "the fullest window shows its reset like any other window")
  }

  function test_reset_cell_clock_only_under_a_day() {
    var env = withProviders([
      F.provider("claude", "Claude", "ready", [
        F.win("session", "5-hour", 10, 300, 200),
        F.win("weekly", "Weekly (7d)", 20, 10080, 92)
      ]),
      F.provider("codex", "Codex", "ready", [F.win("session", "5-hour", 50, 300, 250)])
    ])
    var weekly = windowOf(rowOf(model(env, "used"), "claude"), "weekly")
    var clock = Qt.formatTime(new Date(Date.parse(F.at(92))), timeFormat)
    compare(weekly.resetCellText, "resets in 1h 32m (" + clock + ")")

    var far = windowOf(rowOf(model(F.normal(), "used"), "claude"), "weekly")
    compare(far.resetCellText, "resets in 2d 20h")
  }

  function test_stale_row_reads_like_ready() {
    var codex = rowOf(model(F.stale(), "used"), "codex")
    compare(codex.kind, "reading")
    compare(codex.state, "stale")
    compare(codex.critical, true)
    compare(codex.valueText, "96%")
    compare(codex.subText, "5-hour · Updated 14m ago")
    compare(codex.updatedText, "", "the subline already shows the age, so the open detail does not repeat it")
    compare(codex.statusWord, "")
    compare(codex.dimIcon, false)
    compare(JSON.stringify(codex).indexOf("Offline"), -1)
    compare(codex.primary.tickPercent, -1)
    for (var i = 0; i < codex.windows.length; i++)
      compare(codex.windows[i].tickPercent, -1)
    compare(codex.tickDescription, "")
  }

  function test_tick_fraction() {
    var used = rowOf(model(F.normal(), "used"), "claude")
    compare(used.primary.tickPercent, 69)
    compare(used.tickDescription, "69% of the window has passed.")
    compare(rowOf(model(F.normal(), "remaining"), "claude").primary.tickPercent, 31)

    compare(rowOf(model(F.early(), "used"), "claude").primary.tickPercent, -1)
    compare(rowOf(model(F.early(), "used"), "claude").tickDescription, "")
    compare(rowOf(model(F.normal(), "used"), "grok").primary.tickPercent, -1)
    compare(rowOf(model(F.normal(), "used"), "antigravity").primary.tickPercent, -1)

    var past = withProviders([
      F.provider("claude", "Claude", "ready", [F.win("session", "5-hour", 50, 300, -5)])
    ])
    compare(rowOf(model(past, "used"), "claude").primary.tickPercent, 100)
  }

  function test_rows_carry_no_pace_projection() {
    var fixtures = [F.normal(), F.critical(), F.early(), F.full()]
    for (var i = 0; i < fixtures.length; i++) {
      var rows = model(fixtures[i], "used").rows
      for (var r = 0; r < rows.length; r++)
        verify(!("pace" in rows[r]), rows[r].id + " row has no pace model")
    }
  }

  function test_status_rows() {
    var m = model(F.problems(), "used", null, { refreshing: true })
    var codex = rowOf(m, "codex")
    compare(codex.kind, "status")
    compare(codex.statusWord, "Not installed")
    compare(codex.statusGlyph, Tokens.GLYPH_PLUG)
    compare(codex.action.kind, "view_installation")
    compare(codex.action.label, "Install guide")
    compare(codex.refreshLabel, "Check again")
    compare(codex.dimIcon, true)
    compare(codex.valueText, "—")
    compare(codex.unitText, "")
    compare(codex.openable, true)
    compare(codex.refreshing, true)
    compare(codex.accessibleName, "Codex, Not installed")

    var claude = rowOf(m, "claude")
    compare(claude.statusWord, "Signed out")
    compare(claude.statusGlyph, Tokens.GLYPH_USER)
    compare(claude.action.label, "Sign in")
    compare(claude.refreshLabel, "Refresh")
    compare(claude.statusBody, "Signing in opens the official Claude CLI.")

    var grok = rowOf(m, "grok")
    compare(grok.statusWord, "Rate limited")
    compare(grok.statusGlyph, Tokens.GLYPH_CLOCK)
    compare(grok.action, null)
    compare(grok.refreshLabel, "Retry")

    var antigravity = rowOf(m, "antigravity")
    compare(antigravity.statusWord, "Offline")
    compare(antigravity.statusGlyph, Tokens.GLYPH_WIFI_OFF)

    var failed = rowOf(model(F.providerError(), "used"), "claude")
    compare(failed.statusWord, "Failed")
    compare(failed.statusGlyph, Tokens.GLYPH_ALERT)

    var none = rowOf(model(F.nopct(), "used"), "claude")
    compare(none.kind, "status")
    compare(none.statusWord, "No percentage")
    compare(none.statusGlyph, "")
    compare(none.statusBody, Core.emptyWindowsMessage())
    compare(none.valueText, "—")
    compare(none.dimIcon, false)
    compare(none.primary, null)
  }

  function test_loading_row_not_openable() {
    var m = model(null, "used", { id: "claude", collapsed: false })
    compare(m.rows.length, 4)
    var claude = rowOf(m, "claude")
    compare(claude.kind, "loading")
    compare(claude.valueText, "···")
    compare(claude.unitText, "")
    compare(claude.openable, false)
    compare(claude.open, false)
    compare(claude.selected, true)
    compare(claude.accessibleName, "Claude, loading")
    compare(m.selectedId, "claude")
    compare(m.openId, "")
  }

  function test_open_and_collapse() {
    var m = model(F.normal(), "used", { id: "codex", collapsed: false })
    compare(m.selectedId, "codex")
    compare(m.openId, "codex")
    compare(rowOf(m, "codex").open, true)
    compare(rowOf(m, "codex").selected, true)
    compare(rowOf(m, "claude").open, false)
    compare(rowOf(m, "claude").selected, false)

    var collapsed = model(F.normal(), "used", { id: "codex", collapsed: true })
    compare(collapsed.selectedId, "codex")
    compare(collapsed.openId, "")
    compare(rowOf(collapsed, "codex").open, false)
    compare(rowOf(collapsed, "codex").selected, true)

    var unknown = model(F.normal(), "used", { id: "zzz", collapsed: false })
    compare(unknown.selectedId, "claude")
    compare(unknown.openId, "claude")

    var nothing = Core.overviewModel(F.normal(), { providers: [] }, F.FIXED_NOW,
                                     { id: "claude", collapsed: false }, ui())
    compare(nothing.rows.length, 0)
    compare(nothing.selectedId, "")
    compare(nothing.openId, "")
    compare(model(F.normal(), "used").metric, "used")
    compare(model(F.normal(), "used").unitText, "used")
    compare(model(F.normal(), "remaining").unitText, "left")
  }

  function test_use_reset_disabled_not_hidden() {
    var claude = rowOf(model(F.normal(), "used"), "claude")
    compare(claude.useReset.visible, true)
    compare(claude.useReset.enabled, true)
    compare(claude.useReset.resetId, "spring")
    compare(claude.useReset.text, "Use reset")
    compare(claude.resets.length, 1)
    compare(claude.resets[0].label, "Usage reset")
    compare(claude.resets[0].facts, [
      "1 of 1 available",
      "clears 5-hour and weekly",
      "until " + Qt.formatDate(new Date(Date.parse(F.at(2 * 1440))), "MM/dd/yyyy")
    ])

    var spent = F.normal()
    spent.providers[0].resets[0].claimable = false
    var locked = rowOf(model(spent, "used"), "claude")
    compare(locked.useReset.visible, true)
    compare(locked.useReset.enabled, false)
    compare(locked.useReset.resetId, null)

    var busy = rowOf(model(F.normal(), "used", null, { resetBusy: true }), "claude")
    compare(busy.useReset.enabled, false)
    compare(busy.useReset.text, "Using reset…")

    compare(rowOf(model(F.normal(), "used"), "codex").useReset.visible, false)

    var settled = model(F.normal(), "used", null,
                        { resetUi: { providerId: "claude", outcome: { result: "reset" } } })
    compare(rowOf(settled, "claude").outcomeText, "Reset applied.")
    compare(rowOf(settled, "codex").outcomeText, "")
  }

  function test_window_minutes_of() {
    compare(Core.windowMinutesOf({ windowMinutes: 0 }), null)
    compare(Core.windowMinutesOf({ windowMinutes: "x" }), null)
    compare(Core.windowMinutesOf({ windowMinutes: -5 }), null)
    compare(Core.windowMinutesOf({ windowMinutes: null }), null)
    compare(Core.windowMinutesOf({}), null)
    compare(Core.windowMinutesOf(null), null)
    compare(Core.windowMinutesOf({ windowMinutes: 300 }), 300)
    var lines = Core.windowDisplayLines(F.claudeReady(76, 92), "used", F.FIXED_NOW)
    compare(lines[0].windowMinutes, 300)
    compare(Core.windowDisplayLines(F.grokReady(), "used", F.FIXED_NOW)[0].windowMinutes, null)
  }

  function test_critical_side_window_raises_the_row_alert() {
    var env = withProviders([
      F.provider("claude", "Claude", "ready", [F.win("session", "5-hour", 98, 300, 30)]),
      F.provider("codex", "Codex", "ready", [
        F.win("session", "5-hour", 10, 300, 200),
        F.win("weekly", "Weekly (7d)", 97, 10080, 600)
      ])
    ])
    var codex = rowOf(model(env, "used"), "codex")
    compare(codex.valueText, "10%")
    compare(codex.critical, false, "the value keeps the main window's colour")
    compare(codex.alert, true, "a critical side window still flags the row")
    compare(rowOf(model(F.normal(), "used"), "codex").alert, false)
    compare(rowOf(model(F.critical(), "used"), "claude").alert, true)
  }
}
