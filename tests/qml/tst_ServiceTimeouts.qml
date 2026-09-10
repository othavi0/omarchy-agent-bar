import QtQuick
import QtTest
import "../../CoreService.js" as Core

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

  function createService() {
    var component = Qt.createComponent(serviceUrl)
    if (component.status === Component.Ready) {
      service = component.createObject(testCase, { testMode: true, helperPath: "/nonexistent" })
    } else {
      // Arch packages Quickshell's QML plugins into the quickshell executable,
      // so qmltestrunner cannot load Process/IpcHandler. Keep Service.qml's
      // production logic intact and replace only those native test seams.
      var xhr = new XMLHttpRequest()
      xhr.open("GET", serviceUrl, false)
      xhr.send()
      var source = String(xhr.responseText)
      source = source.replace("import Quickshell\n", "")
      source = source.replace("import Quickshell.Io\n", "")
      var processStart = source.indexOf("\n  Process {") + 1
      var processEnd = source.indexOf("\n  Timer {", processStart) + 1
      verify(processStart > 0 && processEnd > processStart)
      verify(source.indexOf("\n  Process {", processEnd) < 0, "every Process block sits before the first Timer")
      var processMocks = [
        "  QtObject { id: versionProbe; property bool running: false; property var command: [] }",
        "  QtObject { id: statusProcess; property bool running: false; property var command: [] }",
        "  QtObject { id: settingsReadProcess; property bool running: false; property var command: [] }",
        "  QtObject { id: settingsBootstrapProcess; property bool running: false; property var command: [] }",
        "  QtObject { id: settingsWriteProcess; property bool running: false; property bool stdinEnabled: true; property var command: [] }",
        "  QtObject { id: maintenanceCheckProcess; property bool running: false; property var command: [] }",
        "  QtObject { id: maintenanceHandoffProcess; property bool running: false; property bool stdinEnabled: false; property var command: [] }",
        ""
      ].join("\n")
      source = source.slice(0, processStart) + processMocks + source.slice(processEnd)
      source = source.replace(/  IpcHandler \{[\s\S]*?\n  \}\n\n  onHelperPathChanged:/,
                              "  QtObject { }\n\n  onHelperPathChanged:")
      source = source.replace("property bool testMode: false", "property bool testMode: true")
      service = Qt.createQmlObject(source, testCase, serviceUrl)
    }
    verify(service !== null, component.errorString())
    service.testMode = true
    service.helperPath = "/nonexistent"
    service.manifest = ({ version: "10.3.17" })
    service.versionProbeTimeoutMs = 50
    service.statusTimeoutMs = 50
    service.settingsTimeoutMs = 50
    service.maintenanceCheckTimeoutMs = 50
    service.maintenanceHandoffTimeoutMs = 50
    service.collectionDelayMs = 10000
    service.applyVersionProbeResult(service.activeVersionProbeGeneration, "10.3.17\n", "", 0)
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
    compare(s.settingsReadBusy, false)
  }

  function test_settings_bootstrap_timeout_keeps_defaults() {
    var s = createService()
    tryCompare(s, "settingsBootstrapBusy", false, 500)
    compare(s.appliedSettings, null)
  }

  function test_settings_write_timeout_returns_dirty() {
    var s = createService()
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, "", 1)
    s.openSettings("monitor-a")
    var generation = s.activeSettingsReadGeneration
    s.applySettingsReadResult(generation, JSON.stringify(validSettings()), 0)
    s.setDisplayMetric("used")
    verify(s.saveSettings())
    compare(s.settingsState.phase, "saving")
    tryVerify(function () { return s.settingsState.phase === "dirty" }, 500)
    compare(s.settingsWriteBusy, false)
  }

  function test_late_timed_out_write_cannot_adopt_old_canonical() {
    var s = createService()
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, "", 1)
    s.openSettings("monitor-a")
    s.applySettingsReadResult(
      s.activeSettingsReadGeneration,
      JSON.stringify(validSettings()),
      0
    )
    s.setDisplayMetric("used")
    verify(s.saveSettings())
    var generationA = s.activeSettingsWriteGeneration
    var canonicalA = JSON.parse(JSON.stringify(s.settingsDraft))
    tryVerify(function () { return s.settingsState.phase === "dirty" }, 500)

    s.setDisplayMetric("remaining")
    verify(s.saveSettings())
    var generationB = s.activeSettingsWriteGeneration
    verify(generationB !== generationA)
    compare(s.settingsState.phase, "saving")
    compare(s.settingsDraft.display.metric, "remaining")
    verify(s.pendingSettingsPayload.indexOf('"metric":"remaining"') >= 0)

    s.settingsWriteExited(0, generationA, JSON.stringify(canonicalA))

    compare(s.settingsState.phase, "saving")
    compare(s.settingsDraft.display.metric, "remaining")
    compare(s.settingsState.snapshot.display.metric, "remaining")
    compare(s.appliedSettings.display.metric, "remaining")
    verify(s.pendingSettingsPayload.indexOf('"metric":"remaining"') >= 0)
    compare(Object.keys(s.timedOutLanes).length, 0)
  }

  function test_native_write_exit_keeps_new_save_intact() {
    var s = createService()
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, "", 1)
    s.openSettings("monitor-a")
    s.applySettingsReadResult(
      s.activeSettingsReadGeneration,
      JSON.stringify(validSettings()),
      0
    )
    s.setDisplayMetric("used")
    verify(s.saveSettings())
    var generationA = s.activeSettingsWriteGeneration
    tryVerify(function () { return s.settingsState.phase === "dirty" }, 500)

    s.setDisplayMetric("remaining")
    verify(s.saveSettings())
    var generationB = s.activeSettingsWriteGeneration
    verify(generationB !== generationA)
    s.settingsWriteStartedGeneration = generationA
    var completedBefore = s.completedCallbackCount

    s.settingsWriteExited(0)

    compare(s.activeSettingsWriteGeneration, generationB)
    compare(s.settingsWriteBusy, true)
    compare(s.settingsState.phase, "saving")
    compare(s.settingsDraft.display.metric, "remaining")
    compare(s.settingsState.snapshot.display.metric, "remaining")
    verify(s.pendingSettingsPayload.indexOf('"metric":"remaining"') >= 0)
    compare(s.pendingSettingsPayloadGeneration, generationB)
    compare(s.completedCallbackCount, completedBefore)
    verify(!s.timedOutLanes.settingsWrite)
  }

  function test_update_check_timeout_enters_error() {
    var s = createService()
    s.checkForUpdates()
    tryVerify(function () { return s.maintenanceUi.phase === "error" }, 500)
    compare(s.maintenanceCheckBusy, false)
  }

  function test_maintenance_handoff_timeout_unblocks() {
    var s = createService()
    s.pendingMaintenanceIntention = ({ kind: "update_apply", version: "10.3.18" })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    tryVerify(function () { return !s.maintenanceState.blocked }, 500)
    compare(s.maintenanceHandoffBusy, false)
  }

  function test_status_timeout_runs_in_test_mode() {
    var s = createService()
    s.beginCollection()
    compare(s.statusBusy, true)
    tryCompare(s, "statusBusy", false, 500)
  }

  function test_late_timed_out_status_cannot_replace_new_request() {
    var s = createService()
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, "", 1)
    s.beginCollection()
    var generationA = s.activeStatusGeneration
    tryCompare(s, "statusBusy", false, 500)
    s.kickStatus()
    var generationB = s.activeStatusGeneration
    verify(generationB !== generationA)

    s.statusExited(0, generationA, validEnvelope(), "")

    compare(s.activeStatusGeneration, generationB)
    compare(s.statusBusy, true)
    compare(s.snapshot, null)
    compare(Object.keys(s.timedOutLanes).length, 0)
  }

  function test_native_status_exit_keeps_new_request_intact() {
    var s = createService()
    s.beginCollection()
    var generationA = s.activeStatusGeneration
    tryCompare(s, "statusBusy", false, 500)
    s.kickStatus()
    var generationB = s.activeStatusGeneration
    verify(generationB !== generationA)
    s.statusStartedGeneration = generationA
    var completedBefore = s.completedCallbackCount

    s.statusExited(0)

    compare(s.activeStatusGeneration, generationB)
    compare(s.statusBusy, true)
    compare(s.refreshing, true)
    compare(s.snapshot, null)
    compare(s.completedCallbackCount, completedBefore)
    verify(!s.timedOutLanes.status)
  }

  function test_late_timed_out_bootstrap_cannot_replace_new_request() {
    var s = createService()
    var generationA = s.activeSettingsBootstrapGeneration
    tryCompare(s, "settingsBootstrapBusy", false, 500)
    s.kickSettingsBootstrap()
    var generationB = s.activeSettingsBootstrapGeneration
    verify(generationB !== generationA)

    s.settingsBootstrapExited(0, generationA, JSON.stringify(validSettings()))

    compare(s.activeSettingsBootstrapGeneration, generationB)
    compare(s.settingsBootstrapBusy, true)
    compare(s.appliedSettings, null)
    compare(Object.keys(s.timedOutLanes).length, 0)
  }

  function test_settled_exit_is_ignored_completely() {
    var s = createService()
    s.beginCollection()
    var generationA = s.activeStatusGeneration
    s.statusBusy = false
    s.kickStatus()
    var generationB = s.activeStatusGeneration
    var completedBefore = s.completedCallbackCount
    s.recordLaneTimeout("settingsRead")
    s.recordLaneTimeout("status", generationA)

    s.statusExited(0, generationA, validEnvelope(), "")

    compare(s.activeStatusGeneration, generationB)
    compare(s.statusBusy, true)
    compare(s.snapshot, null)
    compare(s.completedCallbackCount, completedBefore)
    verify(s.timedOutLanes.settingsRead)
    verify(!s.timedOutLanes.status)
  }

  function test_reap_clears_only_its_own_timed_out_lane() {
    var s = createService()
    s.recordLaneTimeout("status", 4)
    s.recordLaneTimeout("settingsRead", 9)
    s.recordLaneTimeout("maintenanceCheck", 12)
    compare(s.runtimeHealth, "stalled")
    var completedBefore = s.completedCallbackCount

    s.statusExited(0, 4, validEnvelope(), "")

    verify(!s.timedOutLanes.status)
    verify(s.timedOutLanes.settingsRead)
    compare(s.runtimeHealth, "stalled")
    compare(s.completedCallbackCount, completedBefore)
    verify(!Core.isLaneSettled(s.settledLanes, "status", 4))
    verify(Core.isLaneSettled(s.settledLanes, "settingsRead", 9))
    verify(Core.isLaneSettled(s.settledLanes, "maintenanceCheck", 12))

    s.applySettingsReadResult(s.activeSettingsReadGeneration, "", 1)
    compare(Object.keys(s.timedOutLanes).length, 0)
    verify(!Core.isLaneSettled(s.settledLanes, "settingsRead", 9))
  }

  function test_runtime_health_accumulates_and_real_callback_resets() {
    var s = createService()
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, "", 1)
    s.openSettings("monitor-a")
    tryVerify(function () { return s.settingsState.phase === "load_failed" }, 500)
    compare(s.runtimeHealth, "ok")
    s.checkForUpdates()
    tryCompare(s, "runtimeHealth", "stalled", 500)
    var generation = s.activeStatusGeneration
    if (!s.statusBusy) {
      s.kickStatus()
      generation = s.activeStatusGeneration
    }
    s.applyStatusResult(generation, validEnvelope(), "", 0)
    compare(s.runtimeHealth, "ok")
  }

  function test_health_reports_stalled_first() {
    var s = createService()
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, "", 1)
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

  function test_version_ready_schedules_the_first_automatic_check() {
    var s = createService()
    verify(s.autoUpdateScheduled)
    compare(s.autoUpdateDelayMs, s.autoUpdateFirstDelayMs)
    compare(s.autoUpdateFirstDelayMs, 120000)
    compare(s.autoUpdateIntervalMs, 21600000)
  }

  function bootstrapSettings(s) {
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, JSON.stringify(validSettings()), 0)
    verify(s.appliedSettings !== null)
  }

  function test_automatic_update_skips_until_settings_load() {
    var s = createService()
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, "", 1)
    compare(s.appliedSettings, null)
    compare(s.automaticUpdateTick(), false)
    compare(s.maintenanceCheckBusy, false)
  }

  function test_manual_click_takes_over_an_automatic_check() {
    var s = createService()
    bootstrapSettings(s)
    verify(s.automaticUpdateTick())
    s.checkForUpdates()
    compare(s.maintenanceUi.phase, "checking")
    s.applyUpdateCheckResult(s.activeMaintenanceCheckGeneration, "", 1)
    compare(s.maintenanceUi.phase, "error")
  }

  function test_automatic_result_never_overwrites_a_handoff() {
    var s = createService()
    bootstrapSettings(s)
    verify(s.automaticUpdateTick())
    s.pendingMaintenanceIntention = ({ kind: "update_apply", version: "10.3.18" })
    s.beginMaintenanceHandoff()
    var before = s.maintenanceUi.phase
    s.applyUpdateCheckResult(s.activeMaintenanceCheckGeneration, availableCheck(), 0)
    compare(s.maintenanceUi.phase, before)
  }

  function test_started_update_says_the_shell_reloads_later() {
    var s = createService()
    bootstrapSettings(s)
    s.checkForUpdates()
    s.applyUpdateCheckResult(s.activeMaintenanceCheckGeneration, availableCheck(), 0)
    verify(s.confirmUpdateApply())
    s.applyMaintenanceHandoffDone(s.activeMaintenanceHandoffGeneration, 0)
    compare(s.maintenanceUi.message, "Update started. The shell reloads when it finishes.")
  }

  function test_handoff_waiting_on_status_starts_when_status_finishes() {
    var s = createService()
    bootstrapSettings(s)
    verify(s.automaticUpdateTick())
    s.kickStatus()
    compare(s.statusBusy, true)
    var statusGeneration = s.activeStatusGeneration

    s.applyUpdateCheckResult(s.activeMaintenanceCheckGeneration, availableCheck(), 0)
    compare(s.maintenanceState.blocked, true)
    compare(s.maintenanceHandoffBusy, false)

    s.applyStatusResult(statusGeneration, validEnvelope(), "", 0)
    compare(s.maintenanceHandoffBusy, true)
  }

  function test_handoff_waiting_on_a_failed_status_still_starts() {
    var s = createService()
    bootstrapSettings(s)
    s.kickStatus()
    var statusGeneration = s.activeStatusGeneration
    s.pendingMaintenanceIntention = ({ kind: "update_apply", version: "10.3.18" })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceHandoffBusy, false)
    s.applyStatusResult(statusGeneration, "", "boom", 1)
    compare(s.maintenanceHandoffBusy, true)
  }

  function test_automatic_update_checks_then_applies_without_a_click() {
    var s = createService()
    bootstrapSettings(s)
    compare(s.automaticUpdateTick(), true)
    compare(s.maintenanceCheckBusy, true)
    compare(s.maintenanceUi.phase, "idle")
    compare(s.autoUpdateDelayMs, s.autoUpdateIntervalMs)
    verify(s.autoUpdateScheduled)

    s.applyUpdateCheckResult(s.activeMaintenanceCheckGeneration, availableCheck(), 0)

    compare(s.pendingMaintenanceIntention.kind, "update_apply")
    compare(s.pendingMaintenanceIntention.version, "10.3.18")
    compare(s.maintenanceState.blocked, true)
    compare(s.maintenanceUi.phase, "applying")
    compare(s.maintenanceHandoffBusy, true)
  }

  function test_automatic_update_respects_the_setting() {
    var s = createService()
    var settings = validSettings()
    settings.updates = { automatic: false }
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, JSON.stringify(settings), 0)
    compare(s.automaticUpdateTick(), false)
    compare(s.maintenanceCheckBusy, false)
    verify(s.autoUpdateScheduled)
  }

  function test_automatic_update_waits_while_the_popup_is_open() {
    var s = createService()
    bootstrapSettings(s)
    s.popupOwner = ({ owner: "monitor-a", providerId: "", view: "provider" })
    compare(s.automaticUpdateTick(), false)
    compare(s.maintenanceCheckBusy, false)
  }

  function test_automatic_check_failure_stays_silent() {
    var s = createService()
    bootstrapSettings(s)
    verify(s.automaticUpdateTick())
    s.applyUpdateCheckResult(s.activeMaintenanceCheckGeneration, "", 1)
    compare(s.maintenanceUi.phase, "idle")
    compare(s.pendingMaintenanceIntention, null)
    compare(s.maintenanceState.blocked, false)
  }

  function test_automatic_updates_toggle_saves_with_the_draft() {
    var s = createService()
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, "", 1)
    s.openSettings("monitor-a")
    s.applySettingsReadResult(s.activeSettingsReadGeneration, JSON.stringify(validSettings()), 0)
    s.setAutomaticUpdates(false)
    compare(s.settingsDraft.updates.automatic, false)
    compare(s.settingsState.phase, "dirty")
    verify(s.saveSettings())
    verify(s.pendingSettingsPayload.indexOf('"updates":{"automatic":false}') >= 0)
  }

  function test_settings_view_offers_the_automatic_updates_toggle() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "file://" + repoRoot + "/SettingsView.qml", false)
    xhr.send()
    var src = String(xhr.responseText)
    verify(src.indexOf("label: \"Update automatically\"") >= 0)
    verify(src.indexOf("setAutomaticUpdates(!root.automaticUpdatesOn)") >= 0)
  }

  function test_manual_check_still_waits_for_a_click() {
    var s = createService()
    s.applySettingsBootstrapResult(s.activeSettingsBootstrapGeneration, "", 1)
    s.checkForUpdates()
    s.applyUpdateCheckResult(s.activeMaintenanceCheckGeneration, availableCheck(), 0)
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
}
