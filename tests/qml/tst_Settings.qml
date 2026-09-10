import QtQuick
import QtTest
import "../../CoreSettings.js" as Core
import "../../CoreService.js" as Service
import "../../CoreView.js" as View

TestCase {
  id: testCase
  name: "AgentBarSettings"
  when: windowShown

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

  function test_default_settings_valid() {
    var d = Service.defaultSettings()
    var v = Core.validateSettingsDraft(d)
    compare(v.ok, true)
  }

  function test_default_settings_enable_only_claude_and_codex() {
    var expected = {
      claude: true,
      codex: true,
      amp: false,
      grok: false,
      antigravity: false
    }
    var d = Service.defaultSettings()
    var seen = 0
    for (var i = 0; i < d.providers.length; i++) {
      var row = d.providers[i]
      verify(expected[row.id] !== undefined)
      compare(row.enabled, expected[row.id], row.id)
      seen += 1
    }
    compare(seen, 5)
  }

  function test_provider_toggle_and_order() {
    var d = Service.defaultSettings()
    d = Core.setProviderEnabled(d, "codex", false)
    compare(d.providers[1].id, "codex")
    compare(d.providers[1].enabled, false)

    d = Core.moveProvider(d, "grok", -1)
    compare(d.providers[2].id, "grok")
    compare(d.providers[3].id, "amp")

    d = Core.moveProvider(d, "claude", -1)
    compare(d.providers[0].id, "claude")
  }

  function ids(draft) {
    var out = []
    for (var i = 0; i < draft.providers.length; i++)
      out.push(draft.providers[i].id)
    return out.join(",")
  }

  function test_move_provider_stays_within_its_section() {
    var d = Service.defaultSettings()
    d = Core.setProviderEnabled(d, "grok", true)
    d = Core.moveProvider(d, "grok", -1)
    compare(ids(d), "claude,grok,amp,codex,antigravity")
    compare(ids(Core.moveProvider(d, "claude", -1)), "claude,grok,amp,codex,antigravity")
    compare(ids(Core.moveProvider(d, "codex", 1)), "claude,grok,amp,codex,antigravity")
    compare(ids(Core.moveProvider(d, "amp", 1)), "claude,grok,antigravity,codex,amp")
  }

  function test_provider_sections_split_by_enabled() {
    var s = Core.providerSections(Service.defaultSettings())
    compare(s.shown.length, 2)
    compare(s.shown[0].id, "claude")
    compare(s.shown[0].canMoveUp, false)
    compare(s.shown[0].canMoveDown, true)
    compare(s.shown[1].id, "codex")
    compare(s.shown[1].canMoveDown, false)
    compare(s.hidden.length, 3)
    compare(s.hidden[0].id, "amp")
    compare(s.hidden[2].id, "antigravity")
    compare(Core.providerSections(null).shown.length, 0)
  }

  function test_settings_changes_count_per_tab() {
    var snap = Service.defaultSettings()
    var none = Core.settingsChanges(snap, Core.cloneDraft(snap))
    compare(none.count, 0)
    compare(none.tabs.providers + none.tabs.general + none.tabs.about, 0)

    var d = Core.setProviderEnabled(snap, "grok", true)
    d = Core.moveProvider(d, "grok", -1)
    d = Core.setDisplayMetric(d, "used")
    d = Core.setAutomaticUpdates(d, false)
    var c = Core.settingsChanges(snap, d)
    compare(c.tabs.providers, 2)
    compare(c.tabs.general, 1)
    compare(c.tabs.about, 1)
    compare(c.count, 4)

    compare(Core.settingsChanges(null, d).count, 0)
    var legacy = Core.cloneDraft(snap)
    delete legacy.updates
    compare(Core.settingsChanges(legacy, Core.cloneDraft(snap)).count, 0)
  }

  function test_settings_tabs_table() {
    var tabs = []
    for (var i = 0; i < Core.SETTINGS_TABS.length; i++)
      tabs.push(Core.SETTINGS_TABS[i].id + ":" + Core.SETTINGS_TABS[i].label)
    compare(tabs.join(","), "providers:Providers,general:General,about:About")
  }

  function test_rail_selection_follows_the_open_view() {
    compare(View.railProviderSelected("usage", "claude", "claude"), true)
    compare(View.railProviderSelected("settings", "claude", "claude"), false)
    compare(View.railProviderSelected("usage", "codex", "claude"), false)
    compare(View.railProviderSelected("usage", "", ""), false)
  }

  function test_rail_tooltip_names_provider_and_state() {
    var nowMs = Date.parse("2026-09-10T12:00:00Z")
    var missing = { id: "antigravity", name: "Antigravity", state: "cli_missing", windows: [] }
    compare(View.railTooltipText(missing, "remaining", nowMs), "Antigravity · no CLI")
    var grok = { id: "grok", name: "Grok", state: "ready",
                 windows: [{ id: "session", usedPercent: 96, remainingPercent: 4 }] }
    compare(View.railTooltipText(grok, "remaining", nowMs), "Grok · 4% · critical")
    var claude = { id: "claude", name: "Claude", state: "ready",
                   windows: [{ id: "session", usedPercent: 62, remainingPercent: 38 }] }
    compare(View.railTooltipText(claude, "used", nowMs), "Claude · 62%")
  }

  function test_settings_provider_status_words() {
    compare(View.settingsProviderStatus({ state: "cli_missing" }), "Not installed")
    compare(View.settingsProviderStatus({ state: "unauthenticated" }), "Signed out")
    compare(View.settingsProviderStatus({ state: "network_error" }), "Offline")
    compare(View.settingsProviderStatus({ state: "ready", windows: [] }), "No percentage")
    compare(View.settingsProviderStatus({ state: "ready",
                                          windows: [{ id: "session", usedPercent: 1 }] }), "")
    compare(View.settingsProviderStatus({ state: "loading" }), "")
    compare(View.settingsProviderStatus(null), "")
  }

  function test_display_metric_and_interval_bounds() {
    var d = Service.defaultSettings()
    d = Core.setDisplayMetric(d, "used")
    compare(d.display.metric, "used")
    d = Core.setDisplayMetric(d, "remaining")
    compare(d.display.metric, "remaining")

    d = Core.setRefreshInterval(d, 30)
    compare(d.refreshIntervalSeconds, 30)
    d = Core.setRefreshInterval(d, 3600)
    compare(d.refreshIntervalSeconds, 3600)

    var bad = Core.setRefreshInterval(d, 10)
    compare(Core.validateSettingsDraft(bad).ok, false)
    bad = Core.setRefreshInterval(d, 9999)
    compare(Core.validateSettingsDraft(bad).ok, false)
  }

  function test_reminder_minutes_bounds() {
    var d = Service.defaultSettings()
    compare(d.notifications.reminderMinutes, 120)
    compare(Core.validateSettingsDraft(d).ok, true)

    d = Core.setReminderMinutes(d, 15)
    compare(d.notifications.reminderMinutes, 15)
    d = Core.setReminderMinutes(d, 1440)
    compare(d.notifications.reminderMinutes, 1440)

    var bad = Core.setReminderMinutes(d, 5)
    compare(Core.validateSettingsDraft(bad).ok, false)
    bad = Core.setReminderMinutes(d, 2000)
    compare(Core.validateSettingsDraft(bad).ok, false)
  }

  function test_automatic_updates_setting() {
    var d = Service.defaultSettings()
    compare(d.updates.automatic, true)
    compare(Service.automaticUpdatesEnabled(d), true)

    d = Core.setAutomaticUpdates(d, false)
    compare(d.updates.automatic, false)
    compare(Service.automaticUpdatesEnabled(d), false)
    compare(Core.validateSettingsDraft(d).ok, true)

    var legacy = Service.defaultSettings()
    delete legacy.updates
    compare(Core.validateSettingsDraft(legacy).ok, true)
    compare(Service.automaticUpdatesEnabled(legacy), true)
    compare(Service.automaticUpdatesEnabled(null), true)

    var bad = Service.defaultSettings()
    bad.updates = { automatic: "yes" }
    compare(Core.validateSettingsDraft(bad).ok, false)
  }

  function test_notifications_toggle() {
    var d = Service.defaultSettings()
    d = Core.setNotificationsEnabled(d, false)
    compare(d.notifications.enabled, false)
    d = Core.setNotificationsEnabled(d, true)
    compare(d.notifications.enabled, true)
  }

  function test_restore_defaults_draft_only() {
    var state = Core.settingsOpen(null, Service.defaultSettings(), 1)
    state = Core.settingsMarkDirty(state)
    state.draft = Core.setProviderEnabled(state.draft, "claude", false)
    state = Core.settingsRestoreDefaults(state)
    compare(state.phase, "dirty")
    compare(state.draft.providers[0].enabled, true)
    compare(state.snapshot.providers[0].enabled, true)
  }

  function test_restore_defaults_does_not_enable_antigravity() {
    var state = Core.settingsOpen(null, Service.defaultSettings(), 1)
    state = Core.settingsMarkDirty(state)
    state.draft = Core.setProviderEnabled(state.draft, "antigravity", true)
    state = Core.settingsRestoreDefaults(state)
    var found = null
    for (var i = 0; i < state.draft.providers.length; i++) {
      if (state.draft.providers[i].id === "antigravity")
        found = state.draft.providers[i]
    }
    verify(found !== null)
    compare(found.enabled, false)
  }

  function test_cancel_restores_snapshot() {
    var snap = Service.defaultSettings()
    var state = Core.settingsOpen(null, snap, 2)
    state.draft = Core.setDisplayMetric(state.draft, "used")
    state = Core.settingsMarkDirty(state)
    compare(state.phase, "dirty")
    state = Core.settingsCancel(state)
    compare(state.phase, "clean")
    compare(state.draft.display.metric, "remaining")
  }

  function test_invalid_save_disabled() {
    var state = Core.settingsOpen(null, Service.defaultSettings(), 3)
    compare(Core.settingsCanSave(state, state.draft), false)
    state = Core.settingsMarkDirty(state)
    state.draft = Core.setRefreshInterval(state.draft, 5)
    compare(Core.settingsCanSave(state, state.draft), false)
    state.draft = Core.setRefreshInterval(state.draft, 60)
    compare(Core.settingsCanSave(state, state.draft), true)
  }

  function test_loading_locks_controls() {
    var state = Core.settingsBeginLoad(1)
    compare(state.phase, "loading")
    compare(Core.settingsControlsLocked(state), true)
    state = Core.settingsFinishLoad(state, 1, Service.defaultSettings())
    compare(state.phase, "clean")
    compare(Core.settingsControlsLocked(state), false)
  }

  function test_save_begin_captures_payload() {
    var state = Core.settingsOpen(null, Service.defaultSettings(), 5)
    state = Core.settingsMarkDirty(state)
    var payload = Core.cloneDraft(state.draft)
    payload = Core.setDisplayMetric(payload, "used")
    state = Core.settingsBeginSave(state, 6, payload)
    compare(state.phase, "saving")
    compare(state.generation, 6)
    compare(state.busy, true)
    compare(state.pendingPayload.display.metric, "used")
  }

  function test_settings_view_source_contracts() {
    var src = read("SettingsView.qml")
    var footer = read("components/SettingsFooter.qml")
    verify(footer.indexOf("Restore defaults") >= 0)
    verify(footer.indexOf("Save changes") >= 0)
    verify(footer.indexOf("Cancel") >= 0)
    verify(footer.indexOf("settingsChanges(") >= 0)
    verify(src.indexOf("NumberField") >= 0)
    verify(src.indexOf("Notifications") >= 0)
    verify(src.indexOf("Remaining") >= 0)
    verify(src.indexOf("Used") >= 0)
    verify(src.indexOf("MaintenanceView") >= 0)
    verify(src.indexOf("Settings could not be loaded") >= 0)
    verify(src.indexOf("load_failed") >= 0)
    verify(src.indexOf('text: "Restart shell"') >= 0)
    verify(src.indexOf("visible: root.loadFailed") >= 0)
    verify(src.indexOf('Accessible.name: "Restart shell"') >= 0)
    verify(src.indexOf("root.agentService.restartShell()") >= 0)
    verify(src.indexOf("function collectFocusTargets()") >= 0)
    verify(src.indexOf("return root.loadFailed ? [restartShellButton] : []") >= 0)
    verify(src.indexOf("Keys.onReturnPressed") < 0,
           "Settings must rely on the host Button key mapping")
    verify(src.indexOf("credential") < 0 || src.toLowerCase().indexOf("no credential") >= 0)
    verify(src.indexOf("password") < 0)
    verify(src.indexOf("apiKey") < 0)
    verify(!View.containsMoneyCopy(src))
    verify(src.indexOf("Text.RichText") < 0)
    verify(src.indexOf("Bar shows") >= 0)
    verify(src.indexOf("Chip number") < 0)
    verify(src.indexOf("Refresh every") >= 0)
    verify(src.indexOf("Refresh interval (seconds)") < 0)
    verify(src.indexOf("Warn me before a quota runs out.") >= 0)
    verify(src.indexOf("Usage threshold alerts") < 0)
    verify(src.indexOf('text: "Loading\\u2026"') >= 0)
    verify(src.indexOf("Loading settings") < 0)
    verify(src.indexOf('text: "seconds"') >= 0)
    verify(src.indexOf("Remind me every") >= 0)
    verify(src.indexOf('text: "minutes"') >= 0)
  }

  function test_settings_view_is_tabbed_with_line_headers() {
    var src = read("SettingsView.qml")
    verify(src.indexOf("ButtonGroup") >= 0)
    verify(src.indexOf("Settings.SETTINGS_TABS") >= 0)
    verify(src.indexOf("SectionHeader") >= 0)
    verify(src.indexOf('"On the bar"') >= 0)
    verify(src.indexOf('"Hidden"') >= 0)
    verify(src.indexOf("providerSections(") >= 0)
    verify(src.indexOf("PanelSeparator") < 0,
           "sections open with a titled line, never a full-width separator")
    var maint = read("MaintenanceView.qml")
    verify(maint.indexOf("SectionHeader") >= 0)
    verify(maint.indexOf("PanelSeparator") < 0)
    var header = read("components/SectionHeader.qml")
    verify(header.indexOf("PanelSectionHeader") >= 0)
    verify(header.indexOf("Layout.fillWidth: true") >= 0)
  }

  function test_popup_pins_the_settings_footer_outside_the_scroll() {
    var src = read("Popup.qml")
    var loader = src.indexOf("id: contentLoader")
    var footer = src.indexOf("id: settingsFooter")
    verify(loader > 0)
    verify(footer > loader, "the footer is a sibling after the scroll surface, not scrolled content")
    verify(src.indexOf("anchors.bottomMargin: root.contentMargins + root.footerHeight") >= 0,
           "the scroll surface stops above the footer")
    verify(src.indexOf("+ root.footerHeight") > 0, "the popup height budgets the footer")
  }

  function test_rail_state_follows_view_with_tooltips() {
    var rail = read("ProviderRail.qml")
    verify(rail.indexOf("property bool settingsActive") >= 0)
    verify(rail.indexOf("Core.railProviderSelected(") >= 0)
    verify(rail.indexOf("Core.railTooltipText(") >= 0)
    verify(rail.indexOf("Core.chipStateCue(") >= 0)
    var tooltips = rail.split("PanelToolTip {").length - 1
    compare(tooltips, 2, "every rail slot, provider and Settings, carries a tooltip")
    var popup = read("Popup.qml")
    verify(popup.indexOf('settingsActive: root.view === "settings"') >= 0)
  }

  function test_settings_row_has_icon_name_chevrons() {
    var src = read("components/SettingsProviderRow.qml")
    verify(src.indexOf("Image") >= 0)
    verify(src.indexOf("displayName") >= 0)
    verify(src.indexOf("󰅃") >= 0)
    verify(src.indexOf("󰅀") >= 0)
    verify(src.indexOf("enableToggled") >= 0)
  }

  function test_service_settings_argv_shapes() {
    var show = Core.settingsArgvShow("/tmp/agent-bar")
    compare(show[0], "/tmp/agent-bar")
    compare(show[1], "config")
    compare(show[2], "show")
    var apply = Core.settingsArgvApplyStdin("/tmp/agent-bar")
    compare(apply[3], "stdin")
  }

  function test_service_qml_has_settings_methods() {
    var src = read("Service.qml")
    verify(src.indexOf("function saveSettings") >= 0)
    verify(src.indexOf("function cancelSettings") >= 0)
    verify(src.indexOf("function restoreSettingsDefaults") >= 0)
    verify(src.indexOf("pendingSettingsPayload") >= 0)
    verify(src.indexOf("stdinEnabled: true") >= 0)
    verify(src.indexOf("config\", \"apply\", \"stdin\"") >= 0 || src.indexOf("settingsArgvApplyStdin") >= 0)
  }

  // Settings write mirrors the maintenance handoff EOF pattern: `config apply
  // stdin` reads until EOF, so write() must be followed by stdinEnabled=false
  // or the helper hangs forever and the save never lands.
  function test_service_settings_stdin_closes_after_write() {
    var src = read("Service.qml")
    var proc = src.indexOf("id: settingsWriteProcess")
    verify(proc >= 0)
    var onStarted = src.indexOf("onStarted:", proc)
    verify(onStarted >= 0)
    var onExited = src.indexOf("onExited:", onStarted)
    verify(onExited > onStarted)
    var body = src.substring(onStarted, onExited)
    verify(body.indexOf("write(") >= 0)
    var writeAt = body.indexOf("write(")
    var closeAt = body.indexOf("stdinEnabled = false", writeAt)
    verify(closeAt > writeAt, "stdinEnabled=false must follow write for EOF")
    var kick = src.indexOf("function kickSettingsWrite")
    verify(kick >= 0)
    var kickEnd = src.indexOf("function applySettingsWriteResult", kick)
    verify(kickEnd > kick)
    var kickBody = src.substring(kick, kickEnd)
    verify(kickBody.indexOf("stdinEnabled = true") >= 0,
           "kickSettingsWrite must re-arm stdin before start")
  }

  function test_popup_hosts_settings_view() {
    var src = read("Popup.qml")
    verify(src.indexOf("SettingsView") >= 0)
    verify(src.indexOf("settingsStub") < 0)
  }

  function test_bootstrap_applies_persisted_settings() {
    var stdout = read("tests/fixtures/settings-v1/valid-used-metric.json")
    var applied = Core.settingsBootstrapResult(null, stdout, 0)
    verify(applied !== null)
    compare(applied.display.metric, "used")
    compare(applied.providers[0].id, "claude")
    compare(applied.providers[0].enabled, false)
    compare(applied.refreshIntervalSeconds, 30)
  }

  function test_bootstrap_failure_keeps_defaults() {
    var stdout = read("tests/fixtures/settings-v1/valid-used-metric.json")
    compare(Core.settingsBootstrapResult(null, stdout, 1), null)
    compare(Core.settingsBootstrapResult(null, "", 0), null)
    compare(Core.settingsBootstrapResult(null, "not json", 0), null)
    var invalid = read("tests/fixtures/settings-v1/invalid-metric.json")
    compare(Core.settingsBootstrapResult(null, invalid, 0), null)
  }

  function test_unknown_provider_from_newer_helper_validates_and_round_trips() {
    var doc = Service.defaultSettings()
    doc.providers.push({ id: "future-provider", enabled: true })
    compare(Core.validateSettingsDraft(doc).ok, true)
    var applied = Core.settingsBootstrapResult(null, JSON.stringify(doc), 0)
    verify(applied !== null)
    compare(applied.providers.length, doc.providers.length)
    compare(applied.providers[applied.providers.length - 1].id, "future-provider")
    var state = Core.settingsOpen(null, applied, 7)
    state = Core.settingsMarkDirty(state)
    var payload = JSON.parse(JSON.stringify(state.draft))
    compare(Core.validateSettingsDraft(payload).ok, true)
    compare(payload.providers[payload.providers.length - 1].id, "future-provider")
    compare(payload.providers[payload.providers.length - 1].enabled, true)
  }

  function test_unknown_provider_still_needs_valid_shape() {
    var doc = Service.defaultSettings()
    doc.providers.push({ id: "future-provider", enabled: "yes" })
    compare(Core.validateSettingsDraft(doc).ok, false)
    doc = Service.defaultSettings()
    doc.providers.push({ id: "claude", enabled: true })
    compare(Core.validateSettingsDraft(doc).reason, "duplicate provider")
    doc = Service.defaultSettings()
    doc.providers.pop()
    compare(Core.validateSettingsDraft(doc).reason, "missing provider")
  }

  function test_failed_load_is_visible_and_locked() {
    var state = Core.settingsBeginLoad(4)
    state = Core.settingsFailLoad(state, 4)
    compare(state.phase, "load_failed")
    compare(state.busy, false)
    compare(Core.settingsControlsLocked(state), true)
    compare(Core.settingsCanSave(state, state.draft), false)
    var newer = Core.settingsBeginLoad(5)
    compare(Core.settingsFailLoad(newer, 4).phase, "loading")
    compare(Core.settingsCancel(state).phase, "load_failed")
  }

  function test_bootstrap_never_clobbers_dialog_result() {
    var winner = { schemaVersion: 1 }
    var stdout = read("tests/fixtures/settings-v1/valid-used-metric.json")
    compare(Core.settingsBootstrapResult(winner, stdout, 0), winner)
  }

  function test_poll_interval_follows_applied_settings() {
    compare(Service.pollIntervalMs(null), 60000)
    var doc = JSON.parse(read("tests/fixtures/settings-v1/valid-used-metric.json"))
    compare(Service.pollIntervalMs(doc), 30000)
  }

  // Wiring lives in plugin QML the runner cannot compile (imports qs.*), so
  // the contract is asserted on source text, the repo's standing mitigation.
  function test_service_bootstraps_settings_at_startup() {
    var src = read("Service.qml")
    verify(src.indexOf("id: settingsBootstrapProcess") >= 0)
    var probe = src.indexOf("function finishVersionProbeSuccess(")
    verify(probe >= 0)
    var probeEnd = src.indexOf("function finishVersionProbeFailure(", probe)
    verify(probeEnd > probe)
    verify(src.substring(probe, probeEnd).indexOf("kickSettingsBootstrap()") >= 0,
           "the boot read must start once the helper is proven alive")
    var apply = src.indexOf("function applySettingsBootstrapResult(")
    verify(apply >= 0)
    var applyEnd = src.indexOf("function ", apply + 10)
    verify(applyEnd > apply)
    var applyBody = src.substring(apply, applyEnd)
    verify(applyBody.indexOf("settingsState") < 0,
           "bootstrap only feeds appliedSettings; the dialog owns its snapshot")
    verify(applyBody.indexOf("settingsDraft") < 0)
    verify(src.indexOf("pollIntervalMs: Core.pollIntervalMs(") >= 0,
           "the poll timer must follow applied settings")
    verify(src.indexOf("pollIntervalMs: 60000") < 0,
           "the hardcoded interval must not come back")
  }
}
