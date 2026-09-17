import QtQuick
import QtTest
import "../../CoreService.js" as Core
import "../../CoreView.js" as View
import "ServiceHarness.js" as Harness

TestCase {
  id: testCase
  name: "AgentBarServiceTimeouts"
  when: windowShown

  property string repoRoot: {
    var path = String(Qt.resolvedUrl(".")).replace("file://", "")
    if (path.endsWith("/"))
      path = path.slice(0, -1)
    var parts = path.split("/")
    parts.pop(); parts.pop()
    return parts.join("/")
  }
  property string serviceUrl: "file://" + repoRoot + "/Service.qml"
  property var service: null

  function finishLane(s, name, exitCode, stdout, stderr) {
    Harness.finishLane(s, name, exitCode, stdout, stderr)
  }

  function createService() {
    service = Harness.createService(serviceUrl, testCase, testCase)
    return service
  }

  function cleanup() {
    if (service) {
      service.destroy()
      service = null
    }
  }

  function validEnvelope() {
    return JSON.stringify({
      schemaVersion: 2,
      helperVersion: "10.3.17",
      generatedAt: "2026-08-26T12:00:00Z",
      request: { provider: null, cache: "use" },
      providers: []
    })
  }

  function validSettings() {
    return {
      schemaVersion: 1,
      providers: [
        { id: "claude", enabled: true },
        { id: "codex", enabled: true },
        { id: "amp", enabled: false },
        { id: "grok", enabled: false },
        { id: "antigravity", enabled: false }
      ],
      display: { metric: "remaining" },
      refreshIntervalSeconds: 60,
      notifications: { enabled: true, reminderMinutes: 120 }
    }
  }

  function test_settings_read_timeout_fails_load() {
    var s = createService()
    s.openSettings("monitor-a")
    tryVerify(function () { return s.settingsState.phase === "load_failed" }, 500)
    compare(s.lanes.settingsRead.busy, false)
  }

  function test_settings_bootstrap_timeout_keeps_defaults() {
    var s = createService()
    tryCompare(s.lanes.settingsBootstrap, "busy", false, 500)
    compare(s.appliedSettings, null)
  }

  function test_settings_write_timeout_returns_dirty() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    s.setDisplayMetric("used")
    verify(s.saveSettings())
    compare(s.settingsState.phase, "saving")
    tryVerify(function () { return s.settingsState.phase === "dirty" }, 500)
    compare(s.lanes.settingsWrite.busy, false)
  }

  function test_a_write_corpse_cannot_undo_the_next_save() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    compare(s.appliedSettings.display.metric, "remaining")
    s.setDisplayMetric("used")
    verify(s.saveSettings())
    var canonicalA = JSON.parse(JSON.stringify(s.settingsDraft))
    compare(canonicalA.display.metric, "used")
    tryVerify(function () { return s.settingsState.phase === "dirty" }, 500)
    compare(s.lanes.settingsWrite.busy, false)
    verify(!s.saveSettings(), "the killed run still owns the lane")

    finishLane(s, "settingsWrite", 0, JSON.stringify(canonicalA))

    compare(s.settingsState.phase, "dirty")
    compare(s.appliedSettings.display.metric, "remaining")
    compare(s.settingsSaveCount, 1)

    verify(s.saveSettings(), "the reaped lane accepts the next save")
    compare(s.settingsState.phase, "saving")
    verify(s.pendingSettingsPayload.indexOf('"metric":"used"') >= 0)
  }

  function test_update_check_timeout_enters_error() {
    var s = createService()
    s.checkForUpdates()
    tryVerify(function () { return s.maintenanceUi.phase === "error" }, 500)
    compare(s.lanes.maintenanceCheck.busy, false)
  }

  function test_maintenance_handoff_timeout_unblocks() {
    var s = createService()
    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    tryVerify(function () { return !s.maintenanceState.blocked }, 500)
    compare(s.lanes.maintenanceHandoff.busy, false)
  }

  function test_status_timeout_runs_in_test_mode() {
    var s = createService()
    s.beginCollection()
    compare(s.lanes.status.busy, true)
    tryCompare(s.lanes.status, "busy", false, 500)
  }

  function test_a_timed_out_bootstrap_holds_the_lane_until_its_corpse_reports() {
    var s = createService()
    tryCompare(s.lanes.settingsBootstrap, "busy", false, 500)
    s.kickSettingsBootstrap()
    compare(s.lanes.settingsBootstrap.busy, false)

    finishLane(s, "settingsBootstrap", 0, JSON.stringify(validSettings()))
    compare(s.appliedSettings, null)

    s.kickSettingsBootstrap()
    compare(s.lanes.settingsBootstrap.busy, true)
    finishLane(s, "settingsBootstrap", 0, JSON.stringify(validSettings()))
    verify(s.appliedSettings !== null)
  }

  function test_a_status_corpse_never_becomes_the_next_runs_result() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.beginCollection()
    compare(s.lanes.status.busy, true)
    s.refreshAll(true)
    tryCompare(s.lanes.status, "stalled", true, 500)
    compare(s.lanes.status.busy, false)
    verify(!Core.pendingIsEmpty(s.pendingForcedTargets),
           "the forced refresh waits for the killed run to report")

    finishLane(s, "status", 0, validEnvelope())

    compare(s.snapshot, null)
    tryVerify(function () { return Core.pendingIsEmpty(s.pendingForcedTargets) }, 500)
    compare(s.lanes.status.busy, true)
    compare(s.refreshing, true)
  }

  function test_a_reaped_corpse_clears_only_its_own_lane() {
    var s = createService()
    s.beginCollection()
    s.openSettings("monitor-a")
    s.checkForUpdates()
    tryCompare(s, "runtimeHealth", "stalled", 500)
    compare(s.lanes.status.stalled, true)

    finishLane(s, "status", 0, validEnvelope())

    compare(s.lanes.status.stalled, false)
    compare(s.lanes.settingsRead.stalled, true)
    compare(s.lanes.maintenanceCheck.stalled, true)
    compare(s.runtimeHealth, "stalled")
    compare(s.snapshot, null)

    s.kickStatus()
    finishLane(s, "status", 0, validEnvelope())
    compare(s.runtimeHealth, "ok")
    compare(s.lanes.settingsRead.stalled, false)
    verify(s.snapshot !== null)
  }

  function test_runtime_health_accumulates_and_real_callback_resets() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    tryVerify(function () { return s.settingsState.phase === "load_failed" }, 500)
    compare(s.runtimeHealth, "ok")
    s.checkForUpdates()
    tryCompare(s, "runtimeHealth", "stalled", 500)
    s.kickStatus()
    finishLane(s, "status", 0, validEnvelope())
    compare(s.runtimeHealth, "ok")
  }

  function test_health_reports_stalled_first() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    tryVerify(function () { return s.settingsState.phase === "load_failed" }, 500)
    s.checkForUpdates()
    tryCompare(s, "runtimeHealth", "stalled", 500)
    compare(s.health("10.3.17"), "stalled")
  }

  function availableCheck() {
    return JSON.stringify({
      schemaVersion: 1,
      current: { version: "10.3.17" },
      available: true,
      reinstallRequired: false,
      latestCompatible: { version: "10.3.18", releaseNotesUrl: "" }
    })
  }

  function bootstrapSettings(s) {
    finishLane(s, "settingsBootstrap", 0, JSON.stringify(validSettings()))
    verify(s.appliedSettings !== null)
  }

  // UX-042: a manual check only paints the read-only status; the plugin
  // never queues a handoff, touches pendingMaintenanceIntention, or runs
  // the command itself. The command sits in ui.updateCommand for the user
  // to copy into a terminal.
  function test_manual_check_finds_an_update_stays_read_only() {
    var s = createService()
    bootstrapSettings(s)
    s.checkForUpdates()
    finishLane(s, "maintenanceCheck", 0, availableCheck())
    compare(s.maintenanceUi.phase, "update_available")
    compare(s.pendingMaintenanceIntention, null)
    compare(s.maintenanceState.blocked, false)
    compare(s.lanes.maintenanceHandoff.busy, false)
    compare(s.maintenanceUi.updateCommand,
        "GIT_PAGER=cat omarchy plugin update othavi0.agent-bar && omarchy-restart-shell")
  }

  function test_handoff_waiting_on_status_starts_when_status_finishes() {
    var s = createService()
    bootstrapSettings(s)
    s.kickStatus()
    compare(s.lanes.status.busy, true)

    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    compare(s.lanes.maintenanceHandoff.busy, false)

    finishLane(s, "status", 0, validEnvelope())
    compare(s.lanes.maintenanceHandoff.busy, true)
  }

  function test_handoff_waiting_on_a_failed_status_still_starts() {
    var s = createService()
    bootstrapSettings(s)
    s.kickStatus()
    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.lanes.maintenanceHandoff.busy, false)
    finishLane(s, "status", 1, "", "boom")
    compare(s.lanes.maintenanceHandoff.busy, true)
  }

  function test_handoff_waiting_on_maintenance_check_starts_when_check_finishes() {
    var s = createService()
    bootstrapSettings(s)
    s.checkForUpdates()
    compare(s.lanes.maintenanceCheck.busy, true)

    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    compare(s.lanes.maintenanceHandoff.busy, false)

    finishLane(s, "maintenanceCheck", 0, availableCheck())
    compare(s.lanes.maintenanceHandoff.busy, true)
  }

  function test_handoff_waiting_on_settings_read_starts_when_read_finishes() {
    var s = createService()
    bootstrapSettings(s)
    s.kickSettingsRead()
    compare(s.lanes.settingsRead.busy, true)

    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    compare(s.lanes.maintenanceHandoff.busy, false)

    finishLane(s, "settingsRead", 1)
    compare(s.lanes.maintenanceHandoff.busy, true)
  }

  function test_handoff_waiting_on_settings_bootstrap_starts_when_bootstrap_finishes() {
    var s = createService()
    s.kickSettingsBootstrap()
    compare(s.lanes.settingsBootstrap.busy, true)

    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    compare(s.lanes.maintenanceHandoff.busy, false)

    finishLane(s, "settingsBootstrap", 1)
    compare(s.lanes.maintenanceHandoff.busy, true)
  }

  // SET-028: the About tab lost its whole Updates section (default-on
  // background updates were the exact behavior omacom/omarchy-plugin-marketplace#4979
  // blocked). updates.automatic still reads as a tolerated legacy block, but
  // nothing in the UI writes or offers it back.
  function test_settings_about_tab_has_no_updates_section() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "file://" + repoRoot + "/MaintenanceView.qml", false)
    xhr.send()
    var src = String(xhr.responseText)
    var updatesHeader = 'text: "' + "Update" + "s" + '"'
    var autoUpdateCopy = "Update" + " automatically"
    verify(src.indexOf(updatesHeader) < 0, "Updates section header must be gone")
    verify(src.indexOf(autoUpdateCopy) < 0, "Update automatically copy must be gone")
  }

  function test_manual_check_still_waits_for_a_click() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.checkForUpdates()
    finishLane(s, "maintenanceCheck", 0, availableCheck())
    compare(s.maintenanceUi.phase, "update_available")
    compare(s.pendingMaintenanceIntention, null)
  }

  // Omarchy 4.0.3 (basecamp/omarchy#9618) injects a public manifest copy
  // without the host-only __sourceDir; the plugin tree must still resolve.
  function test_helper_and_login_resolve_from_public_manifest() {
    var s = createService()
    s.helperPath = ""
    s.manifest = ({ id: "othavi0.agent-bar", version: "10.3.22" })
    compare(s.pluginRoot, repoRoot)
    compare(s.resolvedHelperPath(), repoRoot + "/bin/agent-bar")
    s.loginProvider("claude")
    compare(s.lastLoginArgv[0], repoRoot + "/scripts/agent-bar-open-terminal")
  }

  function test_restart_shell_records_exact_argv_without_execution_in_test_mode() {
    var s = createService()
    compare(s.restartShellRequestCount, 0)
    compare(s.lastRestartShellArgv, null)

    s.restartShell()

    compare(s.restartShellRequestCount, 1)
    compare(s.lastRestartShellArgv.length, 1)
    compare(s.lastRestartShellArgv[0], "omarchy-restart-shell")
  }

  function test_forced_targets_coalesce_while_the_status_lane_is_busy() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.beginCollection()
    compare(s.lanes.status.busy, true)
    s.refreshProvider("claude", true)
    s.refreshProvider("amp", true)
    compare(s.lanes.status.busy, true)
    verify(!Core.pendingIsEmpty(s.pendingForcedTargets))

    finishLane(s, "status", 0, validEnvelope())

    compare(s.lanes.status.busy, true)
    verify(Core.pendingIsEmpty(s.pendingForcedTargets))
    var argv = s.lanes.status.process.command
    compare(argv.indexOf("bypass") >= 0, true)
  }

  function test_a_forced_refresh_of_all_dominates_a_single_provider() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.beginCollection()
    s.refreshProvider("grok", true)
    s.refreshAll(true)
    s.refreshProvider("claude", true)
    compare(s.pendingForcedTargets.all, true)

    finishLane(s, "status", 0, validEnvelope())

    var argv = s.lanes.status.process.command
    compare(argv.indexOf("bypass") >= 0, true)
    compare(argv.indexOf("provider") < 0, true, "all is not a single-provider request")
  }

  function test_lanes_overlap_and_each_refuses_a_second_run() {
    var s = createService()
    s.beginCollection()
    s.openSettings("monitor-a")
    s.checkForUpdates()
    compare(s.lanes.status.busy, true)
    compare(s.lanes.settingsRead.busy, true)
    compare(s.lanes.settingsBootstrap.busy, true)
    compare(s.lanes.maintenanceCheck.busy, true)

    compare(s.lanes.status.start(["/nonexistent", "status"]), false)
    compare(s.lanes.settingsRead.start(["/nonexistent", "config"]), false)
    compare(s.lanes.settingsBootstrap.start(["/nonexistent", "config"]), false)
    compare(s.lanes.maintenanceCheck.start(["/nonexistent", "update"]), false)
    compare(s.lanes.status.runId, 1)
    compare(s.lanes.settingsRead.runId, 1)
  }

  function test_maintenance_blocks_new_status_and_saves_but_not_reads() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    s.setDisplayMetric("used")
    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()

    s.kickStatus()
    compare(s.lanes.status.busy, false)
    compare(s.saveSettings(), false)
    s.kickSettingsRead()
    compare(s.lanes.settingsRead.busy, true)
  }

  function test_closing_during_a_load_keeps_the_one_load_alive() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    compare(s.settingsState.phase, "loading")
    var generation = s.settingsState.generation

    s.closePopup("monitor-a")
    compare(s.settingsState.phase, "loading")
    s.openSettings("monitor-a")
    compare(s.settingsState.generation, generation)
    compare(s.lanes.settingsRead.runId, 1, "reopening never starts a second read")

    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    compare(s.settingsState.phase, "clean")
    compare(s.settingsDraft.display.metric, "remaining")
  }

  function test_a_loading_dialog_keeps_its_controls_locked() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    compare(s.settingsLocked(), true)
    s.setDisplayMetric("used")
    compare(s.settingsDraft, null)

    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))

    compare(s.settingsState.phase, "clean")
    compare(s.settingsLocked(), false)
  }

  function test_closing_during_a_save_keeps_the_save_running() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    s.setNotificationsEnabled(false)
    verify(s.saveSettings())
    var canonical = JSON.parse(s.pendingSettingsPayload)

    s.closePopup("monitor-a")
    compare(s.settingsState.phase, "saving")
    compare(s.settingsState.busy, true)

    finishLane(s, "settingsWrite", 0, JSON.stringify(canonical))
    compare(s.settingsState.phase, "clean")
    compare(s.appliedSettings.notifications.enabled, false)
  }

  function test_reopening_during_a_save_shows_the_save_not_a_new_load() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    s.setDisplayMetric("used")
    verify(s.saveSettings())
    var generation = s.settingsState.generation

    s.openSettings("monitor-a")

    compare(s.settingsState.generation, generation)
    compare(s.settingsState.phase, "saving")
    compare(s.popupOwner.view, "settings")
  }

  function test_a_second_save_is_rejected_while_the_first_is_in_flight() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    s.setRefreshInterval(120)
    verify(s.saveSettings())
    compare(s.settingsSaveCount, 1)
    compare(s.saveSettings(), false)
    compare(s.settingsSaveCount, 1)

    finishLane(s, "settingsWrite", 0, s.pendingSettingsPayload)
    compare(s.settingsState.phase, "clean")
  }

  function test_an_edit_during_a_save_cannot_change_the_in_flight_payload() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    s.setDisplayMetric("used")
    s.setReminderMinutes(240)
    verify(s.saveSettings())
    compare(JSON.parse(s.pendingSettingsPayload).display.metric, "used")
    compare(JSON.parse(s.pendingSettingsPayload).notifications.reminderMinutes, 240)

    s.setDisplayMetric("remaining")
    s.setReminderMinutes(60)

    compare(JSON.parse(s.pendingSettingsPayload).display.metric, "used")
    compare(JSON.parse(s.pendingSettingsPayload).notifications.reminderMinutes, 240)
    compare(s.settingsState.pendingPayload.display.metric, "used")
    compare(s.settingsState.pendingPayload.notifications.reminderMinutes, 240)
    compare(s.lanes.settingsWrite.stdinText.indexOf('"metric":"used"') >= 0, true)
  }

  function test_visible_providers_derives_from_snapshot_and_updates_on_change() {
    var s = createService()
    s.appliedSettings = validSettings()
    compare(s.visibleProviders.length, 2)
    compare(s.visibleProviders[0].id, "claude")
    compare(s.visibleProviders[0].state, "loading")
    compare(s.visibleProviders[1].id, "codex")

    s.snapshot = {
      schemaVersion: 2,
      helperVersion: "10.3.17",
      generatedAt: "2026-08-26T12:00:00Z",
      request: { provider: null, cache: "use" },
      providers: [
        { id: "claude", name: "Claude", state: "ready", source: "live", plan: null,
          windows: [], lastSuccessAt: "2026-08-26T12:00:00Z",
          error: null, action: null },
        { id: "codex", name: "Codex", state: "ready", source: "live", plan: null,
          windows: [], lastSuccessAt: "2026-08-26T12:00:00Z",
          error: null, action: null }
      ]
    }

    compare(s.visibleProviders.length, 2)
    compare(s.visibleProviders[0].state, "ready")
    compare(s.visibleProviders[0].source, "live")
    compare(JSON.stringify(s.visibleProviders),
        JSON.stringify(View.visibleProviders(s.snapshot, s.appliedSettings)))
  }
}
