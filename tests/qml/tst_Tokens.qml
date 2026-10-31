import QtQuick
import QtTest
import "../../components/Tokens.js" as Tokens

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
      "SettingsView.qml",
      "MaintenanceView.qml",
      "components/ProviderChip.qml",
      "components/StateMessage.qml",
      "components/SettingsProviderRow.qml",
      "components/SettingsFooter.qml",
      "components/SectionHeader.qml",
      "components/ConfirmDialog.qml",
      "components/RestartBanner.qml",
      "components/OverviewList.qml",
      "components/ProviderRow.qml",
      "components/UsageMeter.qml",
      "components/ProviderIcon.qml",
      "components/PopupFooter.qml",
      "components/SettingsHeader.qml"
    ]
  }

  function code(rel) {
    var src = read(rel)
    verify(src.length > 0, rel + " exists")
    return src.replace(/\/\/[^\n]*/g, "")
  }

  function test_tokens_values() {
    var alphas = {
      TEXT_SECONDARY: 0.72, TEXT_TERTIARY: 0.55, TRACK: 0.12, DIMMED: 0.45,
      LOCKED: 0.55, URGENT_RULE: 0.55, SIDE_COLUMN_PX: 118,
      PRIMARY_REST: 0.16, MIN_TEXT_CONTRAST: 4.5
    }
    for (var k in alphas)
      compare(Tokens[k], alphas[k], k)
    var gone = ["THIN_FILL", "TICK_MIN_ELAPSED", "ROW_ICON_SCALE", "NAME_COLUMN_EMS",
                "VALUE_COLUMN_EMS", "LABEL_COLUMN_MAX_SHARE", "CHEVRON_OPEN_DEGREES",
                "GLYPH_CHEVRON", "WELL_LIFT", "WELL_SINK", "DRAWER_RULE", "HEAD_OPEN"]
    for (var d = 0; d < gone.length; d++)
      compare(Tokens[gone[d]], undefined, gone[d] + " left with the accordion and the tick")
    var glyphs = {
      GLYPH_ALERT: 0xF0026, GLYPH_SETTINGS: 0xF0493, GLYPH_BACK: 0xF0141,
      GLYPH_UP: 0xF0143, GLYPH_DOWN: 0xF0140
    }
    for (var g in glyphs)
      compare(Tokens[g], String.fromCodePoint(glyphs[g]), g)
  }

  function test_tonal_label_reaches_readable_contrast_data() {
    return [
      { tag: "dark", accent: "#60a5fa", slab: "#222225", fg: "#e4e4e7" },
      { tag: "dark-dim-accent", accent: "#3b4261", slab: "#1f2335", fg: "#c0caf5" },
      { tag: "light", accent: "#2563eb", slab: "#f4f4f5", fg: "#18181b" },
      { tag: "light-pale-accent", accent: "#7dd3fc", slab: "#f4f4f5", fg: "#18181b" },
      { tag: "white", accent: "#0057d8", slab: "#ffffff", fg: "#000000" }
    ]
  }

  // The tonal button's label is the accent pulled toward the theme
  // foreground until it reads at 4.5:1 on the strongest fill it sits on.
  function test_tonal_label_reaches_readable_contrast(data) {
    var accent = Qt.color(data.accent)
    var fill = Tokens.mix(Qt.color(data.slab), accent, Tokens.PRIMARY_PRESS)
    var label = Tokens.readableAccent(accent, fill, Qt.color(data.fg))
    verify(contrast(label, fill) >= 4.5,
           data.tag + ": label " + label + " on " + fill + " reads at " + contrast(label, fill).toFixed(2))
  }

  function test_no_qt_darker() {
    var files = tokenScannedFiles()
    for (var i = 0; i < files.length; i++)
      verify(code(files[i]).indexOf("Qt.darker") < 0,
             files[i] + " still calls Qt.darker; use Util.alpha")
  }

  function test_alpha_arguments_are_tokens() {
    var files = tokenScannedFiles()
    for (var i = 0; i < files.length; i++) {
      var callRe = /Util\.alpha\(([^()]*)\)/g
      var src = code(files[i])
      var m
      while ((m = callRe.exec(src)) !== null) {
        var arg = m[1].slice(m[1].indexOf(",") + 1)
        verify(/^\s*Tokens\.[A-Z_]+\s*$/.test(arg),
               files[i] + ": Util.alpha(" + m[1] + ") must take a Tokens alpha")
      }
    }
  }

  function test_no_opacity_literal() {
    var files = tokenScannedFiles()
    var allowed = { "0": true, "1": true, "1.0": true }
    for (var i = 0; i < files.length; i++) {
      var lines = code(files[i]).split("\n")
      for (var j = 0; j < lines.length; j++) {
        if (!/[oO]pacity\s*:/.test(lines[j]))
          continue
        var nums = lines[j].replace(/Tokens\.[A-Z_]+/g, "").match(/\b\d+(?:\.\d+)?\b/g) || []
        for (var n = 0; n < nums.length; n++)
          verify(allowed[nums[n]] === true,
                 files[i] + ":" + (j + 1) + " opacity literal " + nums[n] + "; use Tokens")
      }
    }
  }

  function test_no_size_literal_above_one() {
    var files = tokenScannedFiles()
    var sizeRe = /(?:^|[\s.])(width|height|size|pixelSize|iconSize|preferredWidth|preferredHeight|sourceSize\.(?:width|height)):\s*(\d+(?:\.\d+)?)\s*$/
    for (var i = 0; i < files.length; i++) {
      var lines = code(files[i]).split("\n")
      for (var j = 0; j < lines.length; j++) {
        var m = sizeRe.exec(lines[j])
        if (m)
          verify(Number(m[2]) <= 1,
                 files[i] + ":" + (j + 1) + " size literal " + m[2] + "; use Style or a Tokens ratio")
      }
    }
  }

  function convertedFiles() {
    return [
      "SettingsView.qml",
      "MaintenanceView.qml",
      "components/UsageMeter.qml",
      "components/StateMessage.qml",
      "components/ConfirmDialog.qml"
    ]
  }

  function test_util_alpha_used_in_converted_files() {
    var files = convertedFiles()
    for (var i = 0; i < files.length; i++)
      verify(code(files[i]).indexOf("Util.alpha(") >= 0,
             files[i] + " has no Util.alpha( call; conversion must use Util.alpha")
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
    var supporting = contrast(composite(data.fg, data.bg, Tokens.TEXT_SECONDARY), data.bg)
    var meta = contrast(composite(data.fg, data.bg, Tokens.TEXT_TERTIARY), data.bg)
    verify(supporting < primary,
           data.tag + ": supporting " + supporting + " must be under primary " + primary)
    verify(meta < supporting,
           data.tag + ": meta " + meta + " must be under supporting " + supporting)
  }

  function allowedRawAlphaFiles() {
    return []
  }

  function test_usage_track_declared_once() {
    var src = code("components/UsageMeter.qml")
    var declarations = src.split("readonly property color trackColor").length - 1
    compare(declarations, 1, "trackColor must be declared exactly once")
    verify(src.indexOf("Qt.rgba(") < 0,
           "UsageMeter must reference trackColor, not a literal alpha")
    var files = tokenScannedFiles()
    for (var i = 0; i < files.length; i++) {
      if (files[i] === "components/UsageMeter.qml")
        continue
      verify(code(files[i]).indexOf("Tokens.TRACK") < 0,
             files[i] + " draws its own track; use UsageMeter")
    }
  }

  function test_control_chrome_uses_style_tokens() {
    var files = tokenScannedFiles()
    var allowed = allowedRawAlphaFiles()
    for (var i = 0; i < files.length; i++) {
      if (allowed.indexOf(files[i]) >= 0)
        continue
      verify(code(files[i]).indexOf("Qt.rgba(") < 0,
             files[i] + " still hardcodes an alpha; use a Style state token")
    }
  }
}
