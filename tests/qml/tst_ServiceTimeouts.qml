import QtQuick
import QtTest

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
      service = component.createObject(testCase)
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
      var processStart = source.indexOf("  // Processes (isolated lanes)")
      var processEnd = source.indexOf("  // Single completed handler", processStart)
      verify(processStart >= 0 && processEnd > processStart)
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
      service = Qt.createQmlObject(source, testCase, serviceUrl)
    }
    verify(service !== null, component.errorString())
    service.testMode = true
    service.helperPath = "/nonexistent"
    service.manifest = ({ version: "10.3.17", __sourceDir: "/nonexistent" })
    service.versionProbeTimeoutMs = 50
    service.statusTimeoutMs = 50
    service.settingsTimeoutMs = 50
    service.maintenanceCheckTimeoutMs = 50
    service.maintenanceHandoffTimeoutMs = 50
    service.collectionDelayMs = 10000
    service.applyVersionProbeResult("10.3.17\n", "", 0)
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
    s.applySettingsBootstrapResult("", 1)
    s.openSettings("monitor-a")
    var generation = s.activeSettingsReadGeneration
    s.applySettingsReadResult(generation, JSON.stringify(validSettings()), 0)
    s.setDisplayMetric("used")
    verify(s.saveSettings())
    compare(s.settingsState.phase, "saving")
    tryVerify(function () { return s.settingsState.phase === "dirty" }, 500)
    compare(s.settingsWriteBusy, false)
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

  function test_runtime_health_accumulates_and_real_callback_resets() {
    var s = createService()
    s.applySettingsBootstrapResult("", 1)
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
    s.applySettingsBootstrapResult("", 1)
    s.openSettings("monitor-a")
    tryVerify(function () { return s.settingsState.phase === "load_failed" }, 500)
    s.checkForUpdates()
    tryCompare(s, "runtimeHealth", "stalled", 500)
    compare(s.health("10.3.17"), "stalled")
  }
}
