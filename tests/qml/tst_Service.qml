import QtQuick
import QtTest
import "../../CoreService.js" as Core
import "ServiceHarness.js" as Harness

TestCase {
  id: testCase
  name: "AgentBarService"
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
  property string serviceUrl: "file://" + repoRoot + "/Service.qml"
  property string manifestPath: repoRoot + "/manifest.json"
  property var service: null

  function createService() {
    service = Harness.createService(serviceUrl, testCase, testCase)
    return service
  }

  function finishLane(s, name, exitCode, stdout, stderr) {
    Harness.finishLane(s, name, exitCode, stdout, stderr)
  }

  function cleanup() {
    if (service) {
      service.destroy()
      service = null
    }
  }

  function validEnvelope(version) {
    return JSON.stringify({
      schemaVersion: 2,
      helperVersion: version || "10.3.17",
      generatedAt: "2026-07-26T18:42:00Z",
      request: { provider: null, cache: "use" },
      providers: [{
        id: "claude",
        name: "Claude",
        state: "ready",
        source: "live",
        plan: null,
        account: null,
        windows: [{
          id: "session",
          label: "Session",
          usedPercent: 10,
          remainingPercent: 90,
          resetsAt: null
        }],
        lastSuccessAt: "2026-07-26T18:42:00Z",
        error: null,
        action: null
      }]
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

  function loadManifest() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "file://" + manifestPath, false)
    xhr.send()
    compare(xhr.status === 200 || xhr.status === 0, true)
    return JSON.parse(xhr.responseText)
  }

  function test_manifest_shape() {
    var m = loadManifest()
    compare(m.id, "othavi0.agent-bar")
    verify(m.kinds.indexOf("service") >= 0)
    verify(m.kinds.indexOf("bar-widget") >= 0)
    compare(m.barWidget.schema.length, 0)
    verify(!("activation" in m))
  }

  function test_plugin_root_from_url() {
    compare(Core.pluginRootFromUrl("file:///home/u/.config/omarchy/plugins/othavi0.agent-bar/"),
            "/home/u/.config/omarchy/plugins/othavi0.agent-bar")
    compare(Core.pluginRootFromUrl("file:///home/a%20b/%C3%A7/plugin/"), "/home/a b/" + String.fromCharCode(0xE7) + "/plugin")
    compare(Core.pluginRootFromUrl("qrc:/plugin/"), "")
    compare(Core.pluginRootFromUrl(""), "")
  }

  function test_version_and_health() {
    var s = createService()
    compare(s.health("10.3.17"), "ok")
    compare(s.health("9.0.0"), "unknown")
    compare(s.collectionStarted, false)
    s.beginCollection()
    compare(s.collectionStarted, true)
    compare(s.lanes.status.busy, true)
  }

  function test_refresh_closed_providers() {
    var s = createService()
    compare(s.refresh("claude"), "ok")
    compare(s.refresh("nope"), "unknown")
    compare(s.refreshRequestCount, 1)
  }

  function test_status_argv_shape_cache_use() {
    var s = createService()
    s.beginCollection()
    var argv = s.lanes.status.process.command
    verify(argv.indexOf("status") >= 0)
    verify(argv.indexOf("format") >= 0)
    verify(argv.indexOf("json") >= 0)
    verify(argv.indexOf("cache") >= 0)
    verify(argv.indexOf("use") >= 0 || argv.indexOf("bypass") >= 0)
    verify(argv.indexOf("notifications") >= 0)
    verify(argv.indexOf("evaluate") >= 0)
  }

  function test_force_refresh_uses_bypass() {
    var s = createService()
    s.beginCollection()
    finishLane(s, "status", 0, validEnvelope())
    var startsBefore = s.lanes.status.runId
    s.refreshAll(true)
    compare(s.lanes.status.runId, startsBefore + 1)
    verify(s.lanes.status.process.command.indexOf("bypass") >= 0)
  }

  function test_immutable_snapshot_replacement() {
    var s = createService()
    s.beginCollection()
    finishLane(s, "status", 0, validEnvelope())
    verify(s.snapshot !== null)
    compare(s.snapshot.schemaVersion, 2)
    compare(s.snapshot.providers[0].id, "claude")
    var first = s.snapshot
    s.kickStatus()
    finishLane(s, "status", 0, validEnvelope())
    verify(s.snapshot !== first)
    compare(s.snapshot.providers[0].id, "claude")
  }

  function test_malformed_envelope_retains_snapshot() {
    var s = createService()
    s.beginCollection()
    finishLane(s, "status", 0, validEnvelope())
    var kept = s.snapshot
    s.kickStatus()
    finishLane(s, "status", 0, "{not-json")
    compare(s.snapshot, kept)
  }

  function test_one_status_lane_no_reentry() {
    var s = createService()
    s.beginCollection()
    var runId = s.lanes.status.runId
    s.kickStatus()
    compare(s.lanes.status.runId, runId)
  }

  function test_pending_forced_union_all_dominates() {
    var p = Core.emptyPending()
    p = Core.unionForced(p, "claude")
    p = Core.unionForced(p, "amp")
    p = Core.unionForced(p, "all")
    compare(p.all, true)
    p = Core.unionForced(p, "grok")
    compare(p.all, true)
  }

  function test_status_argv_single_provider_force() {
    var argv = Core.statusArgv("/h", { all: false, ids: { "claude": true } })
    verify(argv.indexOf("provider") >= 0)
    verify(argv.indexOf("claude") >= 0)
    verify(argv.indexOf("bypass") >= 0)
  }

  function test_popup_same_owner_close() {
    var s = createService()
    s.requestPopup("mon-a", "claude", "usage")
    compare(s.popupOwner.owner, "mon-a")
    compare(s.selectedProviderId, "claude")
    s.closePopup("mon-b")
    verify(s.popupOwner !== null)
    s.closePopup("mon-a")
    compare(s.popupOwner, null)
  }

  function test_popup_dismiss_clears_any_owner() {
    var s = createService()
    s.requestPopup("mon-a", "claude", "usage")
    verify(s.popupOwner !== null)
    s.closePopup("mon-b")
    verify(s.popupOwner !== null)
    s.dismissPopup()
    compare(s.popupOwner, null)
    verify(Core.foreignPopupOpen({ owner: "mon-a" }, "mon-b"))
    verify(!Core.foreignPopupOpen({ owner: "mon-a" }, "mon-a"))
    verify(!Core.foreignPopupOpen(null, "mon-b"))
  }

  function test_popup_cross_monitor_transfer() {
    var s = createService()
    s.requestPopup("mon-a", "claude", "usage")
    s.requestPopup("mon-b", "grok", "usage")
    compare(s.popupOwner.owner, "mon-b")
    compare(s.popupOwner.providerId, "grok")
    compare(s.selectedProviderId, "grok")
  }

  function test_settings_open_captures_snapshot() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.beginCollection()
    finishLane(s, "status", 0, validEnvelope())
    s.openSettings("mon-a")
    finishLane(s, "settingsRead", 0, JSON.stringify(validSettings()))
    compare(s.settingsState.phase, "clean")
    verify(s.settingsState.snapshot !== null)
    verify(s.settingsDraft !== null)
    compare(s.popupOwner.view, "settings")
  }

  function test_maintenance_blocks_poll_and_waits_drain() {
    var s = createService()
    finishLane(s, "settingsBootstrap", 1)
    s.beginCollection()
    compare(s.lanes.status.busy, true)
    s.pendingMaintenanceIntention = ({ kind: "uninstall", purge: false })
    s.beginMaintenanceHandoff()
    compare(s.maintenanceState.blocked, true)
    compare(s.pollEnabled, false)
    compare(s.lanes.maintenanceHandoff.busy, false)
    finishLane(s, "status", 0, validEnvelope())
    compare(s.lanes.maintenanceHandoff.busy, true)
  }

  function test_service_qml_declares_seven_process_lanes() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", serviceUrl, false)
    xhr.send()
    var src = String(xhr.responseText)
    verify(src.indexOf("id: versionProbe") >= 0)
    verify(src.indexOf("id: statusProcess") >= 0)
    verify(src.indexOf("id: settingsReadProcess") >= 0)
    verify(src.indexOf("id: settingsBootstrapProcess") >= 0)
    verify(src.indexOf("id: settingsWriteProcess") >= 0)
    verify(src.indexOf("id: maintenanceCheckProcess") >= 0)
    verify(src.indexOf("id: maintenanceHandoffProcess") >= 0)
    verify(src.indexOf("id: pollTimer") >= 0)
    verify(src.indexOf('target: "othavi0.agent-bar"') >= 0)
  }

  function test_service_qml_declares_a_lane_per_process_and_destruction() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", serviceUrl, false)
    xhr.send()
    var src = String(xhr.responseText)
    verify(src.indexOf("id: versionProbeLane") >= 0)
    verify(src.indexOf("id: statusLane") >= 0)
    verify(src.indexOf("id: settingsReadLane") >= 0)
    verify(src.indexOf("id: settingsBootstrapLane") >= 0)
    verify(src.indexOf("id: settingsWriteLane") >= 0)
    verify(src.indexOf("id: maintenanceCheckLane") >= 0)
    verify(src.indexOf("id: maintenanceHandoffLane") >= 0)
    verify(src.indexOf("Component.onDestruction") >= 0)
  }

  function test_runtime_health() {
    compare(Core.runtimeHealth(0), "ok")
    compare(Core.runtimeHealth(1), "ok")
    compare(Core.runtimeHealth(2), "stalled")
    compare(Core.runtimeHealth(7), "stalled")
  }

  // Live Quattro: duplicate Component.onCompleted → "Property value set multiple times"
  // and the service never loads (bar chips disappear).
  function test_service_qml_has_single_component_on_completed() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", serviceUrl, false)
    xhr.send()
    var src = String(xhr.responseText)
    var re = /Component\.onCompleted/g
    var count = 0
    while (re.exec(src) !== null)
      count++
    compare(count, 1)
    verify(src.indexOf("startVersionProbe") >= 0)
    verify(src.indexOf("syncMaintenanceVersion") >= 0)
  }

  // Quickshell StdioCollector.text is read-only; assigning throws TypeError and
  // aborts the version probe before Process.running is set (live bar stuck loading).
  function test_service_qml_does_not_assign_stdio_collector_text() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", serviceUrl, false)
    xhr.send()
    var src = String(xhr.responseText)
    verify(src.indexOf("versionOut.text =") < 0)
    verify(src.indexOf("versionErr.text =") < 0)
    verify(src.indexOf("statusOut.text =") < 0)
    verify(src.indexOf("statusErr.text =") < 0)
  }

  // Live Quattro createObject sets manifest after construction completes.
  function test_service_qml_defers_probe_until_helper_path() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", serviceUrl, false)
    xhr.send()
    var src = String(xhr.responseText)
    verify(src.indexOf("function tryStartProduction") >= 0)
    verify(src.indexOf("onManifestChanged") >= 0)
    verify(src.indexOf("onHelperPathChanged") >= 0)
    verify(src.indexOf("tryStartProduction()") >= 0)
    // The host strips __sourceDir from third-party manifests (Omarchy 4.0.3).
    verify(src.indexOf("__sourceDir") < 0)
    var emptyBranch = src.indexOf("if (!helper.length)")
    verify(emptyBranch >= 0)
    var nextFail = src.indexOf("finishVersionProbeFailure", emptyBranch)
    var nextReturn = src.indexOf("return", emptyBranch)
    verify(nextReturn >= 0)
    if (nextFail >= 0)
      verify(nextReturn < nextFail)
  }
}
