.pragma library

// Quickshell 0.3.1: running = false is SIGTERM, so the child stays alive
// until its own exit arrives. The mock reports that, or the corpse window
// tests have to reach would not exist.
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

// Boots the real Service.qml against a helper that never runs. Arch packages
// Quickshell's QML plugins into the quickshell executable, so qmltestrunner
// cannot load Process/IpcHandler; when that happens this splices QtObject
// mocks in place of the native Process blocks, keeping Service.qml's
// production logic intact and replacing only those native test seams.
function createService(serviceUrl, parent, testCase) {
  var component = Qt.createComponent(serviceUrl)
  var service = null
  if (component.status === 1 /* Component.Ready: unavailable to a .pragma library JS module */) {
    service = component.createObject(parent, { testMode: true, helperPath: "/nonexistent" })
  } else {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", serviceUrl, false)
    xhr.send()
    var source = String(xhr.responseText)
    source = source.replace("import Quickshell\n", "")
    source = source.replace("import Quickshell.Io\n", "")
    var processStart = source.indexOf("\n  Process {") + 1
    var processEnd = source.indexOf("\n  Timer {", processStart) + 1
    testCase.verify(processStart > 0 && processEnd > processStart)
    testCase.verify(source.indexOf("\n  Process {", processEnd) < 0,
        "every Process block sits before the first Timer")
    var processMocks = [
      processMock("versionProbe", "versionOut", "versionErr"),
      processMock("statusProcess", "statusOut", "statusErr"),
      processMock("settingsReadProcess", "settingsReadOut", "settingsReadErr"),
      processMock("settingsBootstrapProcess", "settingsBootstrapOut", "settingsBootstrapErr"),
      processMock("settingsWriteProcess", "settingsWriteOut", "settingsWriteErr"),
      processMock("maintenanceCheckProcess", "maintenanceCheckOut", "maintenanceCheckErr"),
      processMock("maintenanceHandoffProcess", "maintenanceHandoffOut", "maintenanceHandoffErr"),
      processMock("resetProcess", "resetOut", "resetErr"),
      ""
    ].join("\n")
    source = source.slice(0, processStart) + processMocks + source.slice(processEnd)
    source = source.replace(/  IpcHandler \{[\s\S]*?\n  \}\n\n  onHelperPathChanged:/,
                            "  QtObject { }\n\n  onHelperPathChanged:")
    source = source.replace("property bool testMode: false", "property bool testMode: true")
    service = Qt.createQmlObject(source, parent, serviceUrl)
  }
  testCase.verify(service !== null, component.errorString())
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
