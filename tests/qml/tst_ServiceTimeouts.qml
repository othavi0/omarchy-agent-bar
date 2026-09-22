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

  // UX-042: a check only paints the status. Nothing installs until the
  // user confirms the update dialog; the fallback command sits in
  // ui.updateCommand for a terminal.
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
        "omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell")
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
    s.refreshProvider("codex", true)
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

  function startClaimWithPopupOpen() {
    var s = createService()
    s.beginCollection()
    finishLane(s, "status", 0, Harness.claudeResetEnvelope())
    s.requestPopup("monitor-a", "claude", "usage")
    s.requestReset("claude", Harness.CLAUDE_RESET_ID)
    s.confirmReset()
    compare(s.lanes.reset.busy, true)
    return s
  }

  function test_closing_during_a_reset_keeps_the_claim() {
    var s = startClaimWithPopupOpen()

    s.closePopup("monitor-a")
    compare(s.resetBusy, true, "the claim stays visible as busy after close")

    var statusRun = s.lanes.status.runId
    finishLane(s, "reset", 0, Harness.claudeResetResult("reset"))

    compare(s.lanes.status.runId, statusRun + 1, "the settled claim refreshes its provider")
    var argv = s.lanes.status.process.command
    compare(argv[argv.indexOf("provider") + 1], "claude")
    verify(argv.indexOf("bypass") >= 0)
    compare(s.resetUi.providerId, "claude")
    compare(s.resetUi.outcome.result, "reset")
    compare(s.resetBusy, false)
  }

  function test_dismissing_during_a_reset_keeps_the_claim() {
    var s = startClaimWithPopupOpen()

    s.dismissPopup()
    var statusRun = s.lanes.status.runId
    finishLane(s, "reset", 0, Harness.claudeResetResult("reset"))

    compare(s.lanes.status.runId, statusRun + 1)
    compare(s.resetUi.outcome.result, "reset")
  }

  function test_reopening_during_a_reset_keeps_the_claim_locked() {
    var s = startClaimWithPopupOpen()
    var resetRun = s.lanes.reset.runId
    s.closePopup("monitor-a")
    s.requestPopup("monitor-a", "claude", "usage")

    compare(s.resetBusy, true, "the Use reset button binds to this and stays disabled")
    compare(s.resetUi.providerId, "claude")
    s.requestReset("claude", Harness.CLAUDE_RESET_ID)
    compare(s.resetUi.confirmOpen, false, "no second confirm while the claim runs")
    s.confirmReset()
    compare(s.lanes.reset.runId, resetRun, "no second reset run")
  }

  function test_confirm_on_an_occupied_lane_closes_the_dialog() {
    var s = startClaimWithPopupOpen()
    var resetRun = s.lanes.reset.runId
    s.resetUi = Core.resetUiOpenConfirm("claude", Harness.CLAUDE_RESET_ID)

    s.confirmReset()

    compare(s.resetUi.confirmOpen, false)
    compare(s.resetBusy, true)
    compare(s.lanes.reset.runId, resetRun)
  }

  function test_the_refresh_a_reset_fires_keeps_its_caption() {
    var s = startClaimWithPopupOpen()
    finishLane(s, "reset", 0, Harness.claudeResetResult("reset"))
    verify(s.lanes.status.busy)

    finishLane(s, "status", 0, Harness.claudeResetEnvelope([]))
    verify(s.resetUi.outcome !== null, "the forced refresh must not erase the caption")
    compare(s.resetUi.outcome.result, "reset")

    s.kickStatus()
    finishLane(s, "status", 0, Harness.claudeResetEnvelope([]))
    compare(s.resetUi.outcome, null)
  }

  function test_a_poll_in_flight_at_settle_keeps_the_caption_until_after_the_forced_run() {
    var s = startClaimWithPopupOpen()
    s.kickStatus()
    var pollRun = s.lanes.status.runId
    finishLane(s, "reset", 0, Harness.claudeResetResult("reset"))
    compare(s.lanes.status.runId, pollRun, "the forced run queues behind the poll")

    finishLane(s, "status", 0, Harness.claudeResetEnvelope())
    verify(s.resetUi.outcome !== null, "the poll that predates the claim leaves the caption")
    compare(s.lanes.status.runId, pollRun + 1)
    verify(s.lanes.status.process.command.indexOf("bypass") >= 0)

    finishLane(s, "status", 0, Harness.claudeResetEnvelope([]))
    verify(s.resetUi.outcome !== null)

    s.kickStatus()
    finishLane(s, "status", 0, Harness.claudeResetEnvelope([]))
    compare(s.resetUi.outcome, null)
  }

  function test_closing_the_popup_clears_the_reset_caption() {
    var s = startClaimWithPopupOpen()
    finishLane(s, "reset", 0, Harness.claudeResetResult("reset"))
    finishLane(s, "status", 0, Harness.claudeResetEnvelope([]))
    s.closePopup("monitor-a")
    compare(s.resetUi.outcome, null)
  }

  function test_the_reset_deadline_outlasts_the_helper_serial_budget() {
    var s = createService()
    compare(s.lanes.reset.timeoutMs, 45000,
            "version probe, GET, and POST at 10 s each plus startup")
  }

  function test_a_timed_out_claim_reads_as_unconfirmed_and_refreshes() {
    var s = createService()
    s.resetTimeoutMs = 50
    s.beginCollection()
    finishLane(s, "status", 0, Harness.claudeResetEnvelope())
    s.requestReset("claude", Harness.CLAUDE_RESET_ID)
    var statusRun = s.lanes.status.runId
    s.confirmReset()

    tryVerify(function () { return s.resetUi.outcome !== null }, 500)
    compare(s.resetUi.outcome.result, "unconfirmed")
    compare(View.resetOutcomeText(s.resetUi.outcome, "hh:mm"),
            "Could not confirm the reset. Refreshing.")
    compare(s.lanes.status.runId, statusRun + 1)
    compare(s.resetBusy, true, "the killed claim holds the lane until it exits")
  }

  function test_a_claim_that_exits_without_output_reads_as_unconfirmed() {
    var s = startClaimWithPopupOpen()
    finishLane(s, "reset", 1, "", "connection reset")
    compare(s.resetUi.outcome.result, "unconfirmed")
  }

  function test_a_claim_with_unreadable_output_reads_as_rejected() {
    var s = startClaimWithPopupOpen()
    finishLane(s, "reset", 1, "{not-json")
    compare(s.resetUi.outcome.result, "provider_error")
  }

  readonly property string startedDoc:
      '{"schemaVersion":1,"operation":"update","result":"started","unit":"agent-bar-update-7.service"}\n'
  readonly property string runningDoc:
      '{"schemaVersion":1,"operation":"update","status":"running","startedAt":"2026-09-22T12:00:00Z","targetVersion":"10.3.18"}\n'
  readonly property string noneDoc: '{"schemaVersion":1,"operation":"update","status":"none"}\n'

  function finishedDoc(result, installed) {
    return JSON.stringify({
      schemaVersion: 1,
      operation: "update",
      status: "finished",
      result: result,
      fromVersion: "10.3.17",
      installedVersion: installed,
      restartRequired: result === "updated",
      finishedAt: "2026-09-22T12:01:00Z"
    }) + "\n"
  }

  function serviceWithUpdateOffer() {
    var s = createService()
    bootstrapSettings(s)
    s.beginCollection()
    finishLane(s, "status", 0, validEnvelope())
    s.checkForUpdates()
    finishLane(s, "maintenanceCheck", 0, availableCheck())
    compare(s.maintenanceUi.phase, "update_available")
    return s
  }

  function startUpdate() {
    var s = serviceWithUpdateOffer()
    s.openUpdateConfirm()
    verify(s.confirmUpdate())
    return s
  }

  function runUpdateToStatus(stdout, exitCode) {
    var s = startUpdate()
    finishLane(s, "update", 0, startedDoc)
    s.pollUpdateStatus()
    compare(JSON.stringify(s.lanes.update.process.command), '["/nonexistent","update","status"]')
    finishLane(s, "update", exitCode === undefined ? 0 : exitCode, stdout)
    return s
  }

  function test_update_confirm_dialog_opens_and_closes() {
    var s = serviceWithUpdateOffer()
    s.openUpdateConfirm()
    compare(s.maintenanceUi.updateConfirmOpen, true)
    s.closeUpdateConfirm()
    compare(s.maintenanceUi.updateConfirmOpen, false)
    compare(s.maintenanceUi.phase, "update_available")
    compare(s.confirmUpdate(), false)
    compare(s.lanes.update.busy, false)
  }

  function test_update_confirm_runs_the_apply_lane_with_argv_and_stdin() {
    var s = startUpdate()
    compare(s.maintenanceUi.phase, "updating")
    compare(s.maintenanceUi.updateConfirmOpen, false)
    compare(s.maintenanceUi.message, "Updating… this takes a few seconds.")
    compare(s.maintenanceState.blocked, false)
    compare(s.pollEnabled, true)
    compare(s.lanes.update.busy, true)
    compare(s.lanes.maintenanceHandoff.busy, false)
    compare(JSON.stringify(s.lanes.update.process.command),
            '["/nonexistent","update","apply"]')
    compare(s.lanes.update.process.written,
            '{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":"10.3.18"}\n')
    compare(s.lanes.update.process.stdinEnabled, false)
  }

  function test_update_starts_beside_a_busy_status_lane() {
    var s = serviceWithUpdateOffer()
    s.kickStatus()
    compare(s.lanes.status.busy, true)
    s.openUpdateConfirm()
    verify(s.confirmUpdate())
    compare(s.maintenanceState.blocked, false)
    compare(s.lanes.update.busy, true)
    finishLane(s, "status", 0, validEnvelope())
    compare(s.refresh("claude"), "ok")
    compare(s.lanes.status.busy, true)
  }

  function test_started_polls_update_status_every_two_seconds_until_finished() {
    var s = startUpdate()
    s.updateTimeoutMs = 5000
    finishLane(s, "update", 0, startedDoc)
    compare(s.maintenanceUi.phase, "updating")
    compare(s.updateRunning, true)
    compare(s.lanes.update.busy, false)
    compare(s.updatePollIntervalMs, 2000)
    s.updatePollIntervalMs = 20
    tryVerify(function () { return s.lanes.update.busy }, 1000)
    compare(JSON.stringify(s.lanes.update.process.command), '["/nonexistent","update","status"]')
    compare(s.lanes.update.process.stdinEnabled, false)
    finishLane(s, "update", 0, runningDoc)
    compare(s.maintenanceUi.phase, "updating")
    compare(s.restartPending, false)
    tryVerify(function () { return s.lanes.update.busy }, 1000)
    finishLane(s, "update", 0, finishedDoc("updated", "10.3.18"))
    compare(s.maintenanceUi.phase, "restart_required")
    compare(s.maintenanceUi.message, "10.3.18 installed. Restart the shell to load it.")
    compare(s.restartPending, true)
    compare(s.pendingVersion, "10.3.18")
    compare(s.updateRunning, false)
    wait(100)
    compare(s.lanes.update.busy, false, "polling stops after the result")
  }

  function test_already_running_polls_like_started() {
    var s = startUpdate()
    finishLane(s, "update", 0, '{"schemaVersion":1,"operation":"update","result":"already_running"}\n')
    compare(s.maintenanceUi.phase, "updating")
    compare(s.updateRunning, true)
    s.pollUpdateStatus()
    compare(JSON.stringify(s.lanes.update.process.command), '["/nonexistent","update","status"]')
  }

  function test_updated_sets_restart_pending_and_keeps_polling() {
    var s = runUpdateToStatus(finishedDoc("updated", "10.3.18"))
    compare(s.maintenanceUi.phase, "restart_required")
    compare(s.maintenanceUi.installedVersion, "10.3.17")
    compare(s.restartPending, true)
    compare(s.pendingVersion, "10.3.18")
    compare(s.maintenanceState.blocked, false)
    compare(s.pollEnabled, true)
    compare(s.refresh("claude"), "ok")
    compare(s.lanes.status.busy, true)
    compare(s.lanes.maintenanceHandoff.busy, false)
  }

  function test_up_to_date_result_returns_to_up_to_date() {
    var s = runUpdateToStatus(finishedDoc("up_to_date", "10.3.17"))
    compare(s.maintenanceUi.phase, "up_to_date")
    compare(s.maintenanceUi.message, "Agent Bar is up to date.")
    compare(s.restartPending, false)
    compare(s.updateRunning, false)
  }

  function test_each_failure_result_renders_its_line() {
    var table = [
      ["local_changes", "The plugin folder has local changes. Run git status in ~/.config/omarchy/plugins/othavi0.agent-bar."],
      ["fetch_failed", "Could not reach GitHub. Try again."],
      ["validation_failed", "The update failed validation and was rolled back. You are still on 10.3.17."],
      ["timed_out", "The update timed out. You are still on 10.3.17."],
      ["failed", "The update did not finish. You are still on 10.3.17."]
    ]
    for (var i = 0; i < table.length; i++) {
      var s = runUpdateToStatus(finishedDoc(table[i][0], "10.3.17"))
      compare(s.maintenanceUi.phase, "update_failed", table[i][0])
      compare(s.maintenanceUi.message, table[i][1])
      compare(s.maintenanceUi.targetVersion, "10.3.18")
      compare(s.maintenanceUi.updateCommand,
              "omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell")
      compare(s.restartPending, false)
      compare(s.updateRunning, false)
      cleanup()
    }
  }

  function test_a_refused_or_unreadable_apply_renders_as_failed() {
    var s = startUpdate()
    finishLane(s, "update", 2, startedDoc)
    compare(s.maintenanceUi.phase, "update_failed")
    compare(s.maintenanceUi.message, "The update did not finish. You are still on 10.3.17.")
    compare(s.updateRunning, false)
    cleanup()
    s = startUpdate()
    finishLane(s, "update", 0, "Updating plugin...\n")
    compare(s.maintenanceUi.message, "The update did not finish. You are still on 10.3.17.")
    compare(s.updateRunning, false)
  }

  function test_none_or_unreadable_while_polling_fails_at_once() {
    var replies = [
      [0, noneDoc, "none"],
      [0, '{"status":"running","targetVersion":"10.3.18"}\n', "no envelope"],
      [0, "not json\n", "not json"],
      [1, "", "helper failed"]
    ]
    for (var i = 0; i < replies.length; i++) {
      var s = runUpdateToStatus(replies[i][1], replies[i][0])
      compare(s.maintenanceUi.phase, "update_failed", replies[i][2])
      compare(s.maintenanceUi.message, "The update did not finish. You are still on 10.3.17.", replies[i][2])
      compare(s.maintenanceUi.updateResult, "failed", replies[i][2])
      compare(s.updateRunning, false, replies[i][2])
      compare(s.restartPending, false, replies[i][2])
      cleanup()
    }
  }

  function test_update_lane_timeout_renders_as_failed() {
    var s = startUpdate()
    tryVerify(function () { return s.maintenanceUi.phase === "update_failed" }, 2000)
    compare(s.maintenanceUi.message, "The update did not finish. You are still on 10.3.17.")
    compare(s.updateRunning, false)
  }

  function test_no_result_within_the_poll_window_renders_as_failed() {
    var s = startUpdate()
    compare(s.updatePollWindowMs, 180000)
    s.updatePollWindowMs = 150
    s.updatePollIntervalMs = 20
    finishLane(s, "update", 0, startedDoc)
    tryVerify(function () { return s.lanes.update.busy }, 1000)
    finishLane(s, "update", 0, runningDoc)
    tryVerify(function () { return s.maintenanceUi.phase === "update_failed" }, 2000)
    compare(s.maintenanceUi.message, "The update did not finish. You are still on 10.3.17.")
    compare(s.updateRunning, false)
  }

  function test_update_lane_deadline_is_30_seconds() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", serviceUrl, false)
    xhr.send()
    var src = String(xhr.responseText)
    verify(src.indexOf("property int updateTimeoutMs: 30000") >= 0)
  }

  function serviceAtStartup() {
    service = Harness.createService(serviceUrl, testCase, testCase, null)
    return service
  }

  function test_startup_reads_update_status_once_before_collecting() {
    var s = serviceAtStartup()
    compare(s.lanes.update.busy, true)
    compare(JSON.stringify(s.lanes.update.process.command), '["/nonexistent","update","status"]')
    compare(s.lanes.status.busy, false)
    compare(s.updateRunning, false, "reading the status is not an update")
    s.openUninstallConfirm()
    compare(s.maintenanceUi.uninstallConfirmOpen, true)
    s.closeUninstallConfirm()
    finishLane(s, "update", 0, noneDoc)
    compare(s.maintenanceUi.phase, "idle")
    compare(s.updateRunning, false)
    compare(s.restartPending, false)
    s.beginCollection()
    compare(s.lanes.status.busy, true)
    compare(s.lanes.update.busy, false)
  }

  function test_startup_running_then_finished_updated_asks_for_the_restart() {
    var s = serviceAtStartup()
    finishLane(s, "update", 0, runningDoc)
    compare(s.maintenanceUi.phase, "updating")
    compare(s.maintenanceUi.targetVersion, "10.3.18")
    compare(s.updateRunning, true)
    s.pollUpdateStatus()
    compare(JSON.stringify(s.lanes.update.process.command), '["/nonexistent","update","status"]')
    finishLane(s, "update", 0, finishedDoc("updated", "10.3.18"))
    compare(s.maintenanceUi.phase, "restart_required")
    compare(s.maintenanceUi.message, "10.3.18 installed. Restart the shell to load it.")
    compare(s.restartPending, true)
    compare(s.pendingVersion, "10.3.18")
    compare(s.updateRunning, false)
  }

  function test_startup_finished_updated_asks_for_the_restart() {
    var s = serviceAtStartup()
    finishLane(s, "update", 0, finishedDoc("updated", "10.3.18"))
    compare(s.maintenanceUi.phase, "restart_required")
    compare(s.restartPending, true)
    compare(s.pendingVersion, "10.3.18")
  }

  function test_startup_finished_failure_renders_its_line() {
    var s = serviceAtStartup()
    finishLane(s, "update", 0, finishedDoc("locked", "10.3.17"))
    compare(s.maintenanceUi.phase, "update_failed")
    compare(s.maintenanceUi.message, "Another maintenance task is running. Try again in a minute.")
    compare(s.restartPending, false)
    compare(s.updateRunning, false)
  }

  function test_startup_unreadable_status_does_nothing() {
    var s = serviceAtStartup()
    finishLane(s, "update", 1, "")
    compare(s.maintenanceUi.phase, "idle")
    compare(s.updateRunning, false)
  }

  function test_later_keeps_the_restart_flag_and_restart_shell_clears_it() {
    var s = runUpdateToStatus(finishedDoc("updated", "10.3.18"))
    s.openSettings("mon-a")
    s.dismissPopup()
    compare(s.popupOwner, null)
    compare(s.restartPending, true)
    compare(s.pendingVersion, "10.3.18")
    compare(s.maintenanceUi.phase, "restart_required")
    var before = s.restartShellRequestCount
    s.restartShell()
    compare(s.restartShellRequestCount, before + 1)
    compare(JSON.stringify(s.lastRestartShellArgv), '["omarchy-restart-shell"]')
    compare(s.restartPending, false)
    compare(s.pendingVersion, "")
    compare(JSON.stringify(s.maintenanceUi), JSON.stringify({
      phase: "idle",
      installedVersion: "10.3.17",
      targetVersion: "",
      releaseNotesUrl: "",
      updateCommand: "",
      purgeSettings: false,
      uninstallArmed: false,
      message: "",
      updateResult: "",
      uninstallConfirmOpen: false,
      updateConfirmOpen: false
    }), "the About tab leaves restart_required with the banner")
  }

  function test_restart_shell_without_a_pending_update_keeps_the_phase() {
    var s = runUpdateToStatus(finishedDoc("fetch_failed", "10.3.17"))
    compare(s.maintenanceUi.phase, "update_failed")
    s.restartShell()
    compare(s.restartShellRequestCount, 1)
    compare(s.maintenanceUi.phase, "update_failed")
    compare(s.maintenanceUi.message, "Could not reach GitHub. Try again.")
  }

  function test_uninstall_is_refused_while_an_update_runs() {
    var s = startUpdate()
    s.openUninstallConfirm()
    compare(s.maintenanceUi.uninstallConfirmOpen, false)
    compare(s.armOrConfirmUninstall(), false)
    compare(s.lanes.maintenanceHandoff.busy, false)
    compare(s.maintenanceUi.phase, "updating")
    finishLane(s, "update", 0, startedDoc)
    s.openUninstallConfirm()
    compare(s.maintenanceUi.uninstallConfirmOpen, false, "polling still counts as running")
  }

  function test_closing_and_reopening_during_the_update_keeps_the_phase() {
    var s = startUpdate()
    compare(s.updateRunning, true)
    s.openSettings("mon-a")
    compare(s.popupOwner.view, "settings")
    compare(s.lanes.settingsRead.busy, true)
    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    s.closePopup("mon-a")
    compare(s.popupOwner, null)
    compare(s.maintenanceUi.phase, "updating")
    s.openSettings("mon-b")
    compare(s.popupOwner.view, "settings")
    compare(s.maintenanceUi.phase, "updating")
    finishLane(s, "update", 0, startedDoc)
    s.pollUpdateStatus()
    finishLane(s, "update", 0, finishedDoc("updated", "10.3.18"))
    compare(s.updateRunning, false)
    s.dismissPopup()
    s.openSettings("mon-a")
    compare(s.popupOwner.view, "settings")
    compare(s.maintenanceUi.phase, "restart_required")
  }

  function test_uninstall_still_refuses_to_open_settings_while_blocked() {
    var s = createService()
    bootstrapSettings(s)
    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    s.openSettings("mon-a")
    compare(s.popupOwner, null)
  }
}
