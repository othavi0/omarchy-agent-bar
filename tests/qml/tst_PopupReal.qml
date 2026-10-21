import QtQuick
import QtTest
import "ServiceHarness.js" as ServiceHarness
import "ViewHarness.js" as ViewHarness

TestCase {
  id: testCase
  name: "AgentBarPopupReal"
  when: windowShown
  visible: true
  width: 600
  height: 700

  property string repoRoot: {
    var path = String(Qt.resolvedUrl(".")).replace("file://", "")
    if (path.endsWith("/"))
      path = path.slice(0, -1)
    var parts = path.split("/")
    parts.pop(); parts.pop()
    return parts.join("/")
  }
  property var service: null
  property var popup: null

  function snapshot() {
    return {
      schemaVersion: 2,
      helperVersion: "10.3.17",
      generatedAt: "2026-10-21T12:37:00Z",
      request: { provider: null, cache: "use" },
      providers: [{
        id: "claude",
        name: "Claude",
        state: "ready",
        source: "live",
        plan: null,
        windows: [
          { id: "session", label: "Session (5h)", usedPercent: 76, remainingPercent: 24,
            resetsAt: "2026-10-21T14:09:00Z" },
          { id: "weekly", label: "Weekly (7d)", usedPercent: 37, remainingPercent: 63,
            resetsAt: "2026-10-24T08:37:00Z" }
        ],
        resets: [],
        lastSuccessAt: "2026-10-21T12:37:00Z",
        error: null,
        action: null
      }]
    }
  }

  function openRealPopup() {
    service = ServiceHarness.createService("file://" + repoRoot + "/Service.qml", testCase, testCase)
    service.snapshot = snapshot()
    popup = ViewHarness.createReal(repoRoot, "Popup.qml", testCase, testCase,
                                   { agentService: service, owner: "mon-a" })
    service.requestPopup("mon-a", "claude", "usage")
    return popup
  }

  function cleanup() {
    if (popup) {
      popup.destroy()
      popup = null
    }
    if (service) {
      service.destroy()
      service = null
    }
  }

  function test_real_popup_loads_with_the_real_service() {
    var p = openRealPopup()
    compare(p.isOpen, true)
    compare(p.view, "usage")
    compare(p.selectedId, "claude")
    verify(p.width > 0 && p.height > 0, "the panel stub sizes the popup from its content")
    var texts = ViewHarness.findAll(p, function (item) {
      return item.textFormat !== undefined && String(item.text).indexOf("Session (5h)") >= 0
    })
    verify(texts.length > 0, "the real provider view renders the session window label")
  }

  function test_real_popup_grabs_to_an_image() {
    var p = openRealPopup()
    wait(50)
    var path = repoRoot + "/target/popup-real-smoke.png"
    var saved = null
    p.grabToImage(function (result) {
      saved = result.saveToFile(path)
    })
    tryVerify(function () { return saved !== null }, 2000, "grabToImage finished")
    verify(saved, "cannot write " + path + "; create target/ first")
  }
}
