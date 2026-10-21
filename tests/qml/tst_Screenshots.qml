import QtQuick
import QtTest
import qs.Commons as Commons
import "TestPalette.js" as Palette
import "ServiceHarness.js" as ServiceHarness
import "ViewHarness.js" as ViewHarness
import "OverviewFixtures.js" as F

// TEST-043: the evidence is the real Popup.qml with the real Service, drawn
// against tests/qml/modules from deterministic fixtures. scripts/verify-v10-ui
// creates the output directory; without it every capture fails.
TestCase {
  id: testCase
  name: "AgentBarScreenshots"
  when: windowShown
  visible: true
  width: 900
  height: 1200

  property string repoRoot: {
    var path = String(Qt.resolvedUrl(".")).replace("file://", "")
    if (path.endsWith("/"))
      path = path.slice(0, -1)
    var parts = path.split("/")
    parts.pop(); parts.pop()
    return parts.join("/")
  }
  readonly property string evidenceDir: repoRoot + "/target/v10-ui-evidence"

  property var service: null
  property var popup: null
  property var defaultPalette: null

  function initTestCase() {
    defaultPalette = paletteOfStub()
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

  function cleanupTestCase() {
    applyPalette(defaultPalette)
  }

  function paletteOfStub() {
    var c = Commons.Color
    return {
      foreground: String(c.foreground),
      background: String(c.background),
      accent: String(c.accent),
      urgent: String(c.urgent),
      muted: String(c.muted),
      popups: { background: String(c.popups.background), border: String(c.popups.border) }
    }
  }

  function applyPalette(p) {
    var c = Commons.Color
    c.foreground = p.foreground
    c.background = p.background
    c.accent = p.accent
    c.urgent = p.urgent
    c.muted = p.muted
    c.popups.background = p.popups.background
    c.popups.border = p.popups.border
  }

  // Each name maps to the popup state the 07 inventory names. Error rows sit
  // open on the provider in that state.
  function scene(name) {
    var base = name.replace(/\.png$/, "")
    var mode = base.endsWith("-light") ? "light" : (base.endsWith("-white") ? "white" : "dark")
    var s = { mode: mode, env: F.normal(), providerId: "claude", settings: "", tab: "",
              refreshing: false, update: false, uninstall: false }
    switch (base.replace(/-(light|dark|white)$/, "")) {
    case "ready":
      break
    case "loading":
      s.env = null
      break
    case "refreshing-with-data":
      s.refreshing = true
      break
    case "stale":
      s.env = F.stale()
      s.providerId = "codex"
      break
    case "critical":
      s.env = F.critical()
      break
    case "cli-missing":
      s.env = F.problems()
      s.providerId = "codex"
      break
    case "unauthenticated":
      s.env = F.problems()
      break
    case "rate-limited":
      s.env = F.problems()
      s.providerId = "grok"
      break
    case "network-error":
      s.env = F.problems()
      s.providerId = "antigravity"
      break
    case "provider-error":
      s.env = F.providerError()
      break
    case "settings-clean":
      s.settings = "clean"
      s.tab = "providers"
      break
    case "settings-dirty":
      s.settings = "dirty"
      s.tab = "providers"
      break
    case "settings-invalid":
      s.settings = "invalid"
      s.tab = "general"
      break
    case "maintenance-update":
      s.settings = "clean"
      s.tab = "about"
      s.update = true
      break
    case "uninstall-confirmation":
      s.settings = "clean"
      s.tab = "about"
      s.uninstall = true
      break
    default:
      fail("no scene for " + name)
    }
    return s
  }

  function stage(s) {
    applyPalette(Palette.themePalette(s.mode))
    service = ServiceHarness.createService("file://" + repoRoot + "/Service.qml", testCase, testCase)
    service.appliedSettings = F.settings("used")
    service.snapshot = s.env
    popup = ViewHarness.createReal(repoRoot, "Popup.qml", testCase, testCase,
                                   { agentService: service, owner: "mon-a" })
    service.requestPopup("mon-a", s.providerId, "usage")
    popup.nowMs = F.FIXED_NOW
    if (s.refreshing) {
      compare(service.refresh(s.providerId), "ok")
      verify(service.refreshing, "the status lane is busy while the old rows stay")
    }
    if (s.settings) {
      popup.openSettings()
      wait(20)
      ServiceHarness.finishLane(service, "settingsRead", 0, JSON.stringify(F.settings("used")) + "\n")
      popup.settingsTab = s.tab
      if (s.settings === "dirty")
        service.setProviderEnabled("grok", false)
      if (s.settings === "invalid")
        service.setRefreshInterval(5)
      compare(popup.view, "settings")
    } else {
      compare(popup.view, "usage")
    }
    if (s.update) {
      service.checkForUpdates()
      ServiceHarness.finishLane(service, "maintenanceCheck", 0,
                                read("tests/fixtures/update-check/available.json"))
      compare(service.maintenanceUi.phase, "update_available")
    }
    if (s.uninstall) {
      service.openUninstallConfirm()
      verify(service.maintenanceUi.uninstallConfirmOpen, "the uninstall dialog is open")
      var dialogs = ViewHarness.findAll(popup, function (item) {
        return item.scrimColor !== undefined && item.opened === true
      })
      compare(dialogs.length, 1, "one open confirm dialog")
      verify(Qt.colorEqual(dialogs[0].scrimColor, Commons.Color.menu.scrim),
             "the dialog dims with the theme scrim, got " + dialogs[0].scrimColor)
    }
    compare(popup.isOpen, true)
    compare(String(Commons.Color.background), String(Qt.color(Palette.themePalette(s.mode).background)))
  }

  function read(relPath) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "file://" + repoRoot + "/" + relPath, false)
    xhr.send()
    return String(xhr.responseText)
  }

  function capture(name) {
    var path = evidenceDir + "/" + name
    var saved = null
    popup.grabToImage(function (result) {
      saved = result.saveToFile(path)
    })
    tryVerify(function () { return saved !== null }, 3000, "grabToImage finished for " + name)
    verify(saved, "cannot write " + path + "; create target/v10-ui-evidence (scripts/verify-v10-ui does)")
  }

  function test_capture_data() {
    return Palette.requiredScreenshotNames().map(function (name) {
      return { tag: name, name: name }
    })
  }

  function test_capture(data) {
    stage(scene(data.name))
    wait(150)
    capture(data.name)
  }

  function test_required_names_match_spec() {
    var names = Palette.requiredScreenshotNames()
    compare(names.length, 17)
    verify(names.indexOf("ready-light.png") >= 0)
    verify(names.indexOf("ready-white.png") >= 0)
    verify(names.indexOf("critical-dark.png") >= 0)
    verify(names.indexOf("uninstall-confirmation-dark.png") >= 0)
  }

  function test_palette_carries_every_role() {
    var modes = ["dark", "light", "white"]
    for (var i = 0; i < modes.length; i++) {
      var p = Palette.themePalette(modes[i])
      var roles = [p.foreground, p.background, p.accent, p.urgent, p.muted,
                   p.popups && p.popups.background, p.popups && p.popups.border]
      for (var r = 0; r < roles.length; r++)
        verify(typeof roles[r] === "string" && roles[r].charAt(0) === "#",
               modes[i] + " palette role " + r + " is a colour: " + roles[r])
    }
  }
}
