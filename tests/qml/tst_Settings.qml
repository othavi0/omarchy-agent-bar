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

  // ---- Pure draft / validation ----

  function test_default_settings_valid() {
    var d = Service.defaultSettings()
    var v = Core.validateSettingsDraft(d)
    compare(v.ok, true)
  }

  function test_default_settings_enable_only_claude_and_codex() {
    // SET-027: a first run shows only the two providers nearly every user has
    // a CLI for. This table must stay identical to `default_enabled` on the
    // Rust side, which tests/servicecore_contract.rs enforces.
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

    d = Core.moveProvider(d, "grok", -1) // amp, grok swap near end
    // default: claude, codex, amp, grok, antigravity → move grok up → claude, codex, grok, amp, antigravity
    compare(d.providers[2].id, "grok")
    compare(d.providers[3].id, "amp")

    d = Core.moveProvider(d, "claude", -1) // already top — no-op
    compare(d.providers[0].id, "claude")
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

  function optionValues(options) {
    return options.map(function (o) { return o.value }).join(",")
  }

  function optionLabels(options) {
    return options.map(function (o) { return o.label }).join(",")
  }

  function test_refresh_interval_options() {
    var o = Core.refreshIntervalOptions(60)
    compare(optionValues(o), "30,60,120,300,600,900,1800,3600")
    compare(optionLabels(o), "30 s,1 min,2 min,5 min,10 min,15 min,30 min,1 h")
    // A saved value outside the list stays selectable, in order.
    var odd = Core.refreshIntervalOptions(45)
    compare(optionValues(odd), "30,45,60,120,300,600,900,1800,3600")
    compare(odd[1].label, "45 s")
    compare(Core.refreshIntervalOptions(90)[2].label, "90 s")
  }

  function test_reminder_options() {
    var o = Core.reminderOptions(120)
    compare(optionValues(o), "15,30,60,120,240,480,720,1440")
    compare(optionLabels(o), "15 min,30 min,1 h,2 h,4 h,8 h,12 h,24 h")
    var odd = Core.reminderOptions(90)
    compare(optionValues(odd), "15,30,60,90,120,240,480,720,1440")
    compare(odd[3].label, "90 min")
  }

  function test_settings_changes_against_snapshot() {
    var snap = Service.defaultSettings()
    compare(Core.settingsChanges(snap, snap).length, 0)
    compare(Core.unsavedChangesLabel(0), "")

    var d = Core.setProviderEnabled(snap, "grok", true)
    d = Core.setRefreshInterval(d, 300)
    var changes = Core.settingsChanges(snap, d)
    compare(changes.sort().join(","), "provider:grok,refreshIntervalSeconds")
    compare(Core.unsavedChangesLabel(changes.length), "2 unsaved changes")
    compare(Core.unsavedChangesLabel(1), "1 unsaved change")

    // A reorder counts once, and marks every provider that moved.
    var moved = Core.moveProvider(snap, "codex", -1)
    compare(Core.settingsChanges(snap, moved).join(","), "providers.order")
    compare(Core.providerChanged(snap, moved, "codex"), true)
    compare(Core.providerChanged(snap, moved, "claude"), true)
    compare(Core.providerChanged(snap, moved, "amp"), false)

    // An absent updates block equals the default, so it is not a change.
    var legacy = Service.defaultSettings()
    delete legacy.updates
    compare(Core.settingsChanges(legacy, Service.defaultSettings()).length, 0)
    compare(Core.settingsChanges(legacy, Core.setAutomaticUpdates(legacy, false)).join(","),
            "updates.automatic")
  }

  function test_automatic_updates_setting() {
    var d = Service.defaultSettings()
    compare(d.updates.automatic, true)
    compare(Service.automaticUpdatesEnabled(d), true)

    d = Core.setAutomaticUpdates(d, false)
    compare(d.updates.automatic, false)
    compare(Service.automaticUpdatesEnabled(d), false)
    compare(Core.validateSettingsDraft(d).ok, true)

    // A document from a helper that predates the block, or no settings at
    // all yet, means the product default: automatic.
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
    // Snapshot untouched
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
    compare(Core.settingsCanSave(state, state.draft), false) // clean
    state = Core.settingsMarkDirty(state)
    state.draft = Core.setRefreshInterval(state.draft, 5)
    compare(Core.settingsCanSave(state, state.draft), false) // invalid
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

  // ---- Source / UI contracts ----

  function test_settings_view_source_contracts() {
    var src = read("SettingsView.qml")
    verify(src.indexOf("Restore defaults") >= 0)
    verify(src.indexOf("Save changes") >= 0)
    verify(src.indexOf("Cancel") >= 0)
    // Settings layout C3 (2026-09-10 amendment): section headers, label-left
    // rows, interval menus, and a save tray that exists only while dirty.
    verify(src.indexOf("NumberField") < 0)
    verify(src.indexOf("Dropdown") >= 0)
    verify(src.indexOf("Settings.refreshIntervalOptions(") >= 0)
    verify(src.indexOf("Settings.reminderOptions(") >= 0)
    var headers = ['text: "Providers"', 'text: "Bar"', 'text: "Alerts"', 'text: "Updates"']
    for (var h = 0; h < headers.length; h++)
      verify(src.indexOf(headers[h]) >= 0, headers[h])
    verify(src.indexOf("PanelSectionHeader") >= 0)
    verify(src.indexOf("Settings.unsavedChangesLabel(") >= 0)
    verify(src.indexOf('visible: root.phase === "dirty" || root.saving') >= 0)
    verify(src.indexOf("Color.menu.selectedBackground") >= 0)
    verify(src.indexOf("PanelSeparator") < 0, "C3 separates with space, not lines")
    verify(src.indexOf("Remaining") >= 0)
    verify(src.indexOf("Used") >= 0)
    verify(src.indexOf("MaintenanceView") >= 0)
    // SET-026: the failed-load copy is rendered by the view itself.
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
    // No credentials / money / theme / cache editor
    verify(src.indexOf("credential") < 0 || src.toLowerCase().indexOf("no credential") >= 0)
    verify(src.indexOf("password") < 0)
    verify(src.indexOf("apiKey") < 0)
    verify(!View.containsMoneyCopy(src))
    verify(src.indexOf("Text.RichText") < 0)
    // Copy design §5.7. The old labels are banned by name so a revert fails
    // here rather than silently shipping.
    verify(src.indexOf("Bar shows") >= 0)
    verify(src.indexOf("Chip number") < 0)
    verify(src.indexOf("Refresh every") >= 0)
    verify(src.indexOf("Refresh interval (seconds)") < 0)
    verify(src.indexOf('"Warn me before a quota runs out"') >= 0)
    verify(src.indexOf("Usage threshold alerts") < 0)
    verify(src.indexOf('text: "Loading\\u2026"') >= 0)
    verify(src.indexOf("Loading settings") < 0)
    // The menus carry the unit in each option, so the sibling unit labels
    // the NumberField layout needed are gone.
    verify(src.indexOf('text: "seconds"') < 0)
    verify(src.indexOf("Remind me every") >= 0)
    verify(src.indexOf('text: "minutes"') < 0)
    verify(src.indexOf('"Install automatically"') >= 0)
  }

  function test_settings_row_has_icon_name_chevrons() {
    var src = read("components/SettingsProviderRow.qml")
    verify(src.indexOf("Image") >= 0)
    verify(src.indexOf("displayName") >= 0)
    verify(src.indexOf("󰅃") >= 0)
    verify(src.indexOf("󰅀") >= 0)
    verify(src.indexOf("enableToggled") >= 0)
    // The On/Off text button became the same switch every other row uses.
    verify(src.indexOf("SettingsSwitch") >= 0)
    verify(src.indexOf('"On"') < 0)
  }

  function test_settings_switch_is_keyboard_operable() {
    // The host ToggleSwitch takes no keyboard focus; the wrapper must.
    var src = read("components/SettingsSwitch.qml")
    verify(src.indexOf("activeFocusOnTab: true") >= 0)
    verify(src.indexOf("Keys.onSpacePressed") >= 0)
    verify(src.indexOf("Keys.onReturnPressed") >= 0)
    verify(src.indexOf("Accessible.role: Accessible.CheckBox") >= 0)
    verify(src.indexOf("Accessible.checked: root.checked") >= 0)
    verify(src.indexOf("hasCursor: root.activeFocus") >= 0)
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
    // Re-arm before each start so consecutive saves keep a writable stdin.
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

  // ---- Startup bootstrap (SET-023) ----
  // settings.json is the only product settings source (SET-001), yet the
  // service used to read it only when the Settings popup opened: every shell
  // restart rendered defaultSettings() while the disk held the user's
  // choices. The payloads here are the schema-pinned fixtures in
  // tests/fixtures/settings-v1/ — never inline a settings document.

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

  // SET-025: a helper newer than the loaded QML may list a provider the
  // QML does not know. That row must validate, survive in the draft, and
  // round-trip to config apply untouched — otherwise every catalog addition
  // wedges Settings in "Loading" until the shell is restarted.
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

  // SET-026: a failed dialog load is a visible terminal state, not an
  // endless locked "Loading".
  function test_failed_load_is_visible_and_locked() {
    var state = Core.settingsBeginLoad(4)
    state = Core.settingsFailLoad(state, 4)
    compare(state.phase, "load_failed")
    compare(state.busy, false)
    compare(Core.settingsControlsLocked(state), true)
    compare(Core.settingsCanSave(state, state.draft), false)
    // A stale generation never flips a newer load.
    var newer = Core.settingsBeginLoad(5)
    compare(Core.settingsFailLoad(newer, 4).phase, "loading")
    // Cancel has no snapshot to fall back to and must not fabricate one.
    compare(Core.settingsCancel(state).phase, "load_failed")
  }

  function test_bootstrap_never_clobbers_dialog_result() {
    // A dialog read/save that finished first is newer than the boot read.
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
