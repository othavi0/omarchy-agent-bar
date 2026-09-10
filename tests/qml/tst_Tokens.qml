import QtQuick
import QtTest

TestCase {
  id: testCase
  name: "AgentBarTokens"
  when: windowShown

  property string repoRoot: {
    var path = String(Qt.resolvedUrl(".")).replace("file://", "")
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

  function tokenScannedFiles() {
    return [
      "BarWidget.qml",
      "Popup.qml",
      "ProviderRail.qml",
      "ProviderView.qml",
      "SettingsView.qml",
      "MaintenanceView.qml",
      "components/ProviderChip.qml",
      "components/ProviderHeader.qml",
      "components/HeaderTag.qml",
      "components/UsageWindow.qml",
      "components/StateMessage.qml",
      "components/SettingsProviderRow.qml",
      "components/SettingsFooter.qml",
      "components/SectionHeader.qml",
      "components/ConfirmDialog.qml"
    ]
  }

  function test_no_qt_darker() {
    var files = tokenScannedFiles()
    for (var i = 0; i < files.length; i++) {
      var code = read(files[i]).replace(/\/\/[^\n]*/g, "")
      verify(code.indexOf("Qt.darker") < 0,
             files[i] + " still calls Qt.darker; use Util.alpha")
    }
  }

  function alphaArgValues(code) {
    var values = []
    var callRe = /Util\.alpha\(([^()]*)\)/g
    var m
    while ((m = callRe.exec(code)) !== null) {
      var args = m[1]
      var commaIdx = args.indexOf(",")
      if (commaIdx < 0)
        continue
      var opacityArg = args.slice(commaIdx + 1)
      var numRe = /\d+(?:\.\d+)?/g
      var nm
      while ((nm = numRe.exec(opacityArg)) !== null)
        values.push(nm[0])
    }
    return values
  }

  function convertedFiles() {
    return [
      "SettingsView.qml",
      "MaintenanceView.qml",
      "components/UsageWindow.qml",
      "components/StateMessage.qml",
      "components/ConfirmDialog.qml"
    ]
  }

  function textAlphaExceptions() {
    return {
      "components/UsageWindow.qml": ["0.12"]
    }
  }

  function test_no_third_alpha_value() {
    var files = tokenScannedFiles()
    var exceptions = textAlphaExceptions()
    var seen = {}
    for (var i = 0; i < files.length; i++) {
      var code = read(files[i]).replace(/\/\/[^\n]*/g, "")
      var values = alphaArgValues(code)
      var excepted = exceptions[files[i]] || []
      for (var j = 0; j < values.length; j++) {
        if (excepted.indexOf(values[j]) >= 0)
          continue
        seen[values[j]] = true
      }
    }
    var distinct = Object.keys(seen).sort()
    compare(distinct.join(","), "0.55,0.72",
            "Util.alpha opacity must be exactly 0.55 or 0.72, found: " + distinct.join(","))
  }

  function test_util_alpha_used_in_converted_files() {
    var files = convertedFiles()
    for (var i = 0; i < files.length; i++) {
      var code = read(files[i]).replace(/\/\/[^\n]*/g, "")
      verify(code.indexOf("Util.alpha(") >= 0,
             files[i] + " has no Util.alpha( call; conversion must use Util.alpha")
    }
  }

  // Composite a translucent foreground over a background, the way the
  // compositor does, then compare WCAG contrast.
  function composite(fg, bg, a) {
    return Qt.rgba(fg.r * a + bg.r * (1 - a),
                   fg.g * a + bg.g * (1 - a),
                   fg.b * a + bg.b * (1 - a), 1)
  }

  function luminance(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }

  function contrast(a, b) {
    var la = luminance(a), lb = luminance(b)
    var hi = Math.max(la, lb), lo = Math.min(la, lb)
    return (hi + 0.05) / (lo + 0.05)
  }

  function test_secondary_recedes_in_both_themes_data() {
    return [
      { tag: "dark",  fg: Qt.color("#fff6ff"), bg: Qt.color("#05080a") },
      { tag: "light", fg: Qt.color("#18181b"), bg: Qt.color("#f4f4f5") },
      { tag: "white", fg: Qt.color("#000000"), bg: Qt.color("#ffffff") }
    ]
  }

  function test_secondary_recedes_in_both_themes(data) {
    var primary = contrast(data.fg, data.bg)
    var supporting = contrast(composite(data.fg, data.bg, 0.72), data.bg)
    var meta = contrast(composite(data.fg, data.bg, 0.55), data.bg)
    verify(supporting < primary,
           data.tag + ": supporting " + supporting + " must be under primary " + primary)
    verify(meta < supporting,
           data.tag + ": meta " + meta + " must be under supporting " + supporting)
  }

  function allowedRawAlphaFiles() {
    return []
  }

  function test_usage_track_declared_once() {
    var code = read("components/UsageWindow.qml")
        .replace(/\/\/[^\n]*/g, "")
    var declarations = code.split("readonly property color trackColor").length - 1
    compare(declarations, 1, "trackColor must be declared exactly once")
    verify(code.indexOf("Qt.rgba(") < 0,
           "UsageWindow must reference trackColor, not a literal alpha")
  }

  function test_control_chrome_uses_style_tokens() {
    var files = tokenScannedFiles()
    var allowed = allowedRawAlphaFiles()
    for (var i = 0; i < files.length; i++) {
      if (allowed.indexOf(files[i]) >= 0)
        continue
      var code = read(files[i]).replace(/\/\/[^\n]*/g, "")
      verify(code.indexOf("Qt.rgba(") < 0,
             files[i] + " still hardcodes an alpha; use a Style state token")
    }
  }
}
