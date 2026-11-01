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

  function model(env, metric, uiExtra) {
    return Core.overviewModel(env, F.settings(metric), F.FIXED_NOW, ui(uiExtra))
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

  function actionIds(row) {
    return row.actions.map(function (a) { return a.id + (a.enabled ? "" : "-") })
  }

  function test_overview_shape_has_no_headline() {
    var fixtures = [F.normal(), F.critical(), F.stale(), F.problems(), F.providerError(),
                    F.nopct(), F.early(), F.full(), null]
    var metrics = ["used", "remaining"]
    for (var f = 0; f < fixtures.length; f++) {
      for (var m = 0; m < metrics.length; m++) {
        var om = model(fixtures[f], metrics[m])
        compare(JSON.stringify(Object.keys(om).sort()),
                JSON.stringify(["metric", "rows", "statusText"]),
                "fixture " + f + " " + metrics[m] + " carries no headline")
        compare(/tightest/i.test(JSON.stringify(om)), false,
                "fixture " + f + " " + metrics[m] + " names no tightest window")
      }
    }
  }

  // Nothing folds: a group lists every window, in the provider's order, and
  // no row or window carries accordion, tick, or per-row unit fields.
  function test_every_window_shows_without_accordion_or_tick() {
    var m = model(F.normal(), "used")
    var claude = rowOf(m, "claude")
    compare(claude.kind, "reading")
    compare(claude.windows.map(function (w) { return w.id }), ["session", "weekly", "weekly-model:fable"])
    compare(claude.windows.map(function (w) { return w.percentText }), ["76%", "37%", "45%"])
    compare(rowOf(m, "antigravity").windows.length, 4)
    var fixtures = [F.normal(), F.critical(), F.stale(), F.early(), F.full()]
    var dead = ["open", "openable", "primary", "valueText", "unitText", "subText", "tickDescription",
                "refreshLabel", "useReset", "resets", "alert", "statusGlyph", "updatedText",
                "selected", "notes"]
    for (var f = 0; f < fixtures.length; f++) {
      var rows = model(fixtures[f], "used").rows
      for (var r = 0; r < rows.length; r++) {
        for (var d = 0; d < dead.length; d++)
          verify(!(dead[d] in rows[r]), rows[r].id + " row has no " + dead[d])
        for (var w = 0; w < rows[r].windows.length; w++) {
          verify(!("tickPercent" in rows[r].windows[w]), rows[r].id + " window has no tick")
          verify(!("elapsed" in rows[r].windows[w]), rows[r].id + " window has no elapsed share")
        }
      }
    }
  }

  function test_window_reset_text_adds_the_clock_under_a_day() {
    var env = withProviders([
      F.provider("claude", "Claude", "ready", [
        F.win("session", "5-hour", 10, 300, 200),
        F.win("weekly", "Weekly", 20, 10080, 92)
      ])
    ])
    var weekly = windowOf(rowOf(model(env, "used"), "claude"), "weekly")
    var clock = Qt.formatTime(new Date(Date.parse(F.at(92))), timeFormat)
    compare(weekly.resetText, "1h 32m (" + clock + ")")
    compare(windowOf(rowOf(model(F.normal(), "used"), "claude"), "weekly").resetText, "2d 20h")
    compare(windowOf(rowOf(model(F.normal(), "used"), "antigravity"), "gemini-5h").resetText, "")
    var past = withProviders([
      F.provider("claude", "Claude", "ready", [F.win("session", "5-hour", 50, 300, -5)])
    ])
    compare(windowOf(rowOf(model(past, "used"), "claude"), "session").resetText, "now")
  }

  function test_group_accessible_name_reads_every_window() {
    var claude = rowOf(model(F.critical(), "used"), "claude")
    compare(claude.accessibleName, "Claude, Max, 1 reset left, until "
            + Qt.formatDate(new Date(Date.parse(F.at(2 * 1440))), "MM/dd/yyyy")
            + ", 5-hour, 96% used, critical, resets in 38m"
            + ", Weekly, 37% used, resets in 2d 20h"
            + ", Fable, 45% used, resets in 2d 20h")
    compare(rowOf(model(F.normal(), "remaining"), "codex").accessibleName,
            "Codex, Plus, 5-hour, 98% left, resets in 4h 10m, Weekly, 82% left, resets in 5d 2h")
  }

  function test_critical_marks_the_window_not_the_group() {
    var env = withProviders([
      F.provider("codex", "Codex", "ready", [
        F.win("session", "5-hour", 10, 300, 200),
        F.win("weekly", "Weekly", 97, 10080, 600),
        F.win("monthly", "Monthly", 91, null, 9000)
      ])
    ])
    var codex = rowOf(model(env, "used"), "codex")
    compare(codex.windows.map(function (w) { return w.critical }), [false, true, false])
    verify(codex.accessibleName.indexOf("Monthly, 91% used, low") >= 0, codex.accessibleName)
  }

  function test_stale_group_keeps_its_windows_and_states_its_age() {
    var codex = rowOf(model(F.stale(), "used"), "codex")
    compare(codex.kind, "reading")
    compare(codex.state, "stale")
    compare(codex.windows.length, 2)
    compare(codex.windows[0].critical, true)
    compare(codex.note, "Updated 14m ago")
    compare(codex.detail, "")
    compare(codex.dimIcon, false)
    compare(JSON.stringify(codex).indexOf("Offline"), -1)
  }

  function test_status_groups() {
    var m = model(F.problems(), "used")
    var codex = rowOf(m, "codex")
    compare(codex.kind, "status")
    compare(codex.windows, [])
    compare(codex.note, "Not installed")
    compare(codex.detail, "Codex CLI was not found.")
    compare(actionIds(codex), ["view_installation", "retry"])
    compare(codex.actions[0].label, "Install guide")
    compare(codex.actions[1].label, "Check again")
    compare(codex.dimIcon, true)
    compare(codex.accessibleName, "Codex, Not installed")

    var claude = rowOf(m, "claude")
    compare(claude.note, "Signed out")
    compare(claude.detail, "Signing in opens the official Claude CLI.")
    compare(actionIds(claude), ["login"])
    compare(claude.actions[0].label, "Sign in")

    var grok = rowOf(m, "grok")
    compare(grok.note, "Rate limited")
    compare(actionIds(grok), ["retry"])
    compare(rowOf(m, "antigravity").note, "Offline")
    compare(rowOf(model(F.providerError(), "used"), "claude").note, "Failed")

    var none = rowOf(model(F.nopct(), "used"), "claude")
    compare(none.kind, "status")
    compare(none.note, "No percentage")
    compare(none.detail, Core.emptyWindowsMessage())
    compare(none.windows, [])
    compare(none.actions, [])
    compare(none.dimIcon, false)
  }

  function test_loading_group() {
    var m = model(null, "used")
    compare(m.rows.length, 4)
    var claude = rowOf(m, "claude")
    compare(claude.kind, "loading")
    compare(claude.note, "Loading")
    compare(claude.windows, [])
    compare(claude.actions, [])
    compare(claude.accessibleName, "Claude, Loading")
    compare(m.statusText, "% used", "no reading, no Updated line")
  }

  // One list per provider feeds the group header's buttons.
  function test_actions_for_lists_real_actions() {
    var claude = rowOf(model(F.normal(), "used"), "claude")
    compare(actionIds(claude), ["use_reset"])
    compare(claude.actions[0].label, "Use reset")
    compare(claude.actions[0].target, "spring")
    compare(rowOf(model(F.normal(), "used"), "codex").actions, [])

    var spent = F.normal()
    spent.providers[0].resets[0].claimable = false
    var locked = rowOf(model(spent, "used"), "claude")
    compare(actionIds(locked), ["use_reset-"])

    var busy = rowOf(model(F.normal(), "used", { resetBusy: true }), "claude")
    compare(actionIds(busy), ["use_reset-"])
    compare(busy.actions[0].label, "Using reset…")

    var gone = F.normal()
    gone.providers[0].resets[0].available = 0
    compare(rowOf(model(gone, "used"), "claude").actions, [], "no reset left, no action")

    var kinds = {}
    var fixtures = [F.normal(), F.critical(), F.stale(), F.problems(), F.providerError(), F.nopct(), null]
    for (var f = 0; f < fixtures.length; f++) {
      var rows = model(fixtures[f], "used").rows
      for (var r = 0; r < rows.length; r++) {
        verify(!("primary" in (rows[r].actions[0] || {})), rows[r].id + " ranks no action first")
        for (var a = 0; a < rows[r].actions.length; a++)
          kinds[rows[r].actions[a].kind] = true
      }
    }
    compare(Object.keys(kinds).sort(), ["login", "retry", "use_reset", "view_installation"],
            "only kinds the service dispatches")
  }

  function test_reset_notes_and_outcome() {
    var dateText = "until " + Qt.formatDate(new Date(Date.parse(F.at(2 * 1440))), "MM/dd/yyyy")
    compare(rowOf(model(F.normal(), "used"), "claude").note, "1 reset left · " + dateText)
    var settled = model(F.normal(), "used",
                        { resetUi: { providerId: "claude", outcome: { result: "reset" } } })
    compare(rowOf(settled, "claude").note, "1 reset left · " + dateText + " · Reset applied.")
    compare(rowOf(settled, "codex").note, "")
  }

  // The footer status: one "Updated" phrase for the oldest live reading, or
  // the refresh in flight, then the unit every percentage shares.
  function test_footer_status_text() {
    compare(model(F.normal(), "used").statusText, "Updated 1m ago · % used")
    compare(model(F.normal(), "remaining").statusText, "Updated 1m ago · % left")
    var mixed = F.normal()
    mixed.providers[1].lastSuccessAt = F.at(-42)
    compare(model(mixed, "used").statusText, "Updated 42m ago · % used", "the oldest ready reading wins")
    compare(model(F.stale(), "used").statusText, "Updated 1m ago · % used", "a stale group keeps its own age")
    compare(model(F.problems(), "used").statusText, "% used")
    compare(model(F.normal(), "used", { refreshing: true }).statusText, "Refreshing… · % used")
  }

}
