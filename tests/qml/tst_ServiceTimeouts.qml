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

  // Quickshell 0.3.1: running = false is SIGTERM, so the child stays alive
  // until its own exit arrives. The mock reports that, or the corpse window
  // this harness has to reach would not exist.
  function processMock(id, outId, errId) {
    return [
      "  QtObject {",
      "    id: " + id,
      "    property bool alive: false",
      "    property bool running: false",
      "    property var command: []",
      "    property bool stdinEnabled: false",
      "    property string written: \"\"",
      "    signal started()",
      "    signal exited(int exitCode)",
      "    function write(data) { written += data }",
      "    function finish(code) { alive = false; running = false; exited(code) }",
      "    onRunningChanged: {",
      "      if (running && !alive) { alive = true; started() }",
      "      else if (!running && alive) running = true",
      "    }",
      "  }",
      "  QtObject { id: " + outId + "; property string text: \"\" }",
      "  QtObject { id: " + errId + "; property string text: \"\" }"
    ].join("\n")
  }

  function finishLane(s, name, exitCode, stdout, stderr) {
    var lane = s.lanes[name]
    lane.stdoutSource.text = stdout === undefined ? "" : stdout
    lane.stderrSource.text = stderr === undefined ? "" : stderr
    lane.process.finish(exitCode)
  }

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
        processMock("versionProbe", "versionOut", "versionErr"),
        processMock("statusProcess", "statusOut", "statusErr"),
        processMock("settingsReadProcess", "settingsReadOut", "settingsReadErr"),
        processMock("settingsBootstrapProcess", "settingsBootstrapOut", "settingsBootstrapErr"),
        processMock("settingsWriteProcess", "settingsWriteOut", "settingsWriteErr"),
        processMock("maintenanceCheckProcess", "maintenanceCheckOut", "maintenanceCheckErr"),
        processMock("maintenanceHandoffProcess", "maintenanceHandoffOut", "maintenanceHandoffErr"),
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
    service.applyVersionProbeResult({ ok: true, exitCode: 0, stdout: "10.3.17\n", stderr: "", timedOut: false })
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
    finishLane(s, "settingsBootstrap", 1)
    s.openSettings("monitor-a")
    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    s.setDisplayMetric("used")
    verify(s.saveSettings())
    compare(s.settingsState.phase, "saving")
    tryVerify(function () { return s.settingsState.phase === "dirty" }, 500)
    compare(s.settingsWriteBusy, false)
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
    compare(s.settingsWriteBusy, false)
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
    compare(s.maintenanceCheckBusy, false)
  }

  function test_maintenance_handoff_timeout_unblocks() {
    var s = createService()
    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
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

  function test_a_timed_out_bootstrap_holds_the_lane_until_its_corpse_reports() {
    var s = createService()
    tryCompare(s, "settingsBootstrapBusy", false, 500)
    s.kickSettingsBootstrap()
    compare(s.settingsBootstrapBusy, false)

    finishLane(s, "settingsBootstrap", 0, JSON.stringify(validSettings()))
    compare(s.appliedSettings, null)

    s.kickSettingsBootstrap()
    compare(s.settingsBootstrapBusy, true)
    finishLane(s, "settingsBootstrap", 0, JSON.stringify(validSettings()))
    verify(s.appliedSettings !== null)
  }

  function test_a_status_corpse_never_becomes_the_next_runs_result() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.beginCollection()
    compare(s.statusBusy, true)
    s.refreshAll(true)
    tryCompare(s.lanes.status, "stalled", true, 500)
    compare(s.statusBusy, false)
    verify(!Core.pendingIsEmpty(s.pendingForcedTargets),
           "the forced refresh waits for the killed run to report")

    finishLane(s, "status", 0, validEnvelope())

    compare(s.snapshot, null)
    tryVerify(function () { return Core.pendingIsEmpty(s.pendingForcedTargets) }, 500)
    compare(s.statusBusy, true)
    compare(s.refreshing, true)
  }

  function test_a_reaped_corpse_clears_only_its_own_lane() {
    var s = createService()
    s.beginCollection()
    s.openSettings("monitor-a")
    s.checkForUpdates()
    tryCompare(s, "runtimeHealth", "stalled", 500)
    compare(s.lanes.status.stalled, true)
    var completedBefore = s.completedCallbackCount

    finishLane(s, "status", 0, validEnvelope())

    compare(s.lanes.status.stalled, false)
    compare(s.lanes.settingsRead.stalled, true)
    compare(s.lanes.maintenanceCheck.stalled, true)
    compare(s.runtimeHealth, "stalled")
    compare(s.snapshot, null)
    compare(s.completedCallbackCount, completedBefore)

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
    compare(s.maintenanceHandoffBusy, false)
    compare(s.maintenanceUi.updateCommand,
        "omarchy plugin update othavi0.agent-bar && omarchy-restart-shell")
  }

  function test_handoff_waiting_on_status_starts_when_status_finishes() {
    var s = createService()
    bootstrapSettings(s)
    s.kickStatus()
    compare(s.statusBusy, true)

    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    compare(s.maintenanceHandoffBusy, false)

    finishLane(s, "status", 0, validEnvelope())
    compare(s.maintenanceHandoffBusy, true)
  }

  function test_handoff_waiting_on_a_failed_status_still_starts() {
    var s = createService()
    bootstrapSettings(s)
    s.kickStatus()
    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceHandoffBusy, false)
    finishLane(s, "status", 1, "", "boom")
    compare(s.maintenanceHandoffBusy, true)
  }

  function test_handoff_waiting_on_maintenance_check_starts_when_check_finishes() {
    var s = createService()
    bootstrapSettings(s)
    s.checkForUpdates()
    compare(s.maintenanceCheckBusy, true)

    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    compare(s.maintenanceHandoffBusy, false)

    finishLane(s, "maintenanceCheck", 0, availableCheck())
    compare(s.maintenanceHandoffBusy, true)
  }

  function test_handoff_waiting_on_settings_read_starts_when_read_finishes() {
    var s = createService()
    bootstrapSettings(s)
    s.kickSettingsRead()
    compare(s.settingsReadBusy, true)

    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    compare(s.maintenanceHandoffBusy, false)

    finishLane(s, "settingsRead", 1)
    compare(s.maintenanceHandoffBusy, true)
  }

  function test_handoff_waiting_on_settings_bootstrap_starts_when_bootstrap_finishes() {
    var s = createService()
    s.kickSettingsBootstrap()
    compare(s.settingsBootstrapBusy, true)

    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    compare(s.maintenanceHandoffBusy, false)

    finishLane(s, "settingsBootstrap", 1)
    compare(s.maintenanceHandoffBusy, true)
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
}
