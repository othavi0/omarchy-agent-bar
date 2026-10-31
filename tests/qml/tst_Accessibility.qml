import QtQuick
import QtTest
import "../../CoreView.js" as Core
import "TestPalette.js" as Palette

TestCase {
  id: testCase
  name: "AgentBarAccessibility"
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

  function read(rel) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "file://" + repoRoot + "/" + rel, false)
    xhr.send()
    return String(xhr.responseText || "")
  }

  function v10QmlFiles() {
    return [
      "BarWidget.qml",
      "Popup.qml",
      "SettingsView.qml",
      "MaintenanceView.qml",
      "Service.qml",
      "components/ProviderChip.qml",
      "components/StateMessage.qml",
      "components/SettingsProviderRow.qml",
      "components/SettingsFooter.qml",
      "components/SectionHeader.qml",
      "components/ConfirmDialog.qml",
      "components/FocusController.qml",
      "components/RestartBanner.qml",
      "components/OverviewList.qml",
      "components/ProviderRow.qml",
      "components/UsageMeter.qml",
      "components/ProviderIcon.qml",
      "components/PopupFooter.qml",
      "components/SettingsHeader.qml"
    ]
  }

  function test_no_plugin_authored_animations() {
    var files = v10QmlFiles()
    for (var i = 0; i < files.length; i++) {
      var src = read(files[i])
      verify(src.length > 0, files[i] + " exists")
      var code = src.replace(/\/\/[^\n]*/g, "")
      verify(!/\bBehavior\b/.test(code), files[i] + " has Behavior")
      verify(!/\bTransition\b/.test(code), files[i] + " has Transition")
      var stripped = code.replace(/Accessible\.[A-Za-z]+/g, "")
      verify(!/\b[A-Za-z]*Animation\b/.test(stripped), files[i] + " has Animation")
      verify(!/\b[A-Za-z]*Animator\b/.test(stripped), files[i] + " has Animator")
    }
  }

  function test_no_custom_icon_button_in_v10() {
    var files = v10QmlFiles()
    for (var i = 0; i < files.length; i++) {
      var src = read(files[i])
      verify(src.length > 0, files[i] + " exists")
      verify(src.indexOf("component IconButton") < 0, files[i])
      verify(src.indexOf("IconButton {") < 0, files[i])
    }
  }

  function test_interactive_controls_have_accessible_names() {
    var src = read("components/ProviderRow.qml")
    verify(src.indexOf("Accessible.name: root.row ? root.row.accessibleName") >= 0)
    verify(src.indexOf("Accessible.role: Accessible.Button") >= 0)
    verify(src.indexOf("Accessible.description: root.detail") >= 0)
    verify(src.indexOf("Accessible.expandable") < 0, "a group never folds, so it is not expandable")
    verify(src.indexOf("Accessible.name: text") >= 0, "every action button speaks its label")
    src = read("components/PopupFooter.qml")
    verify(src.indexOf('Accessible.name: "Settings"') >= 0)
    src = read("components/StateMessage.qml")
    verify(src.indexOf("Accessible.name") >= 0)
    src = read("SettingsView.qml")
    verify(src.indexOf("Accessible.name") >= 0)
    src = read("MaintenanceView.qml")
    verify(src.indexOf("Accessible.name") >= 0)
  }

  function test_state_cues_not_color_only() {
    verify(Core.chipStateCue({ state: "cli_missing" }).length > 0)
    verify(Core.chipStateCue({ state: "network_error" }).length > 0)
    compare(Core.stateQualifier("stale"), "stale")
    compare(Core.chipCueLabel({ state: "stale", windows: [] }), "")
  }

  function test_glyphs_and_text_labels() {
    var popupFooter = read("components/PopupFooter.qml")
    verify(popupFooter.indexOf("iconText: Tokens.GLYPH_SETTINGS") >= 0)
    verify(popupFooter.indexOf('text: "Settings"') >= 0)
    var footer = read("components/SettingsFooter.qml")
    verify(footer.indexOf("Save changes") >= 0)
    verify(footer.indexOf("Restore defaults") >= 0)
    var maint = read("MaintenanceView.qml")
    verify(maint.indexOf("Check for updates") >= 0)
    verify(maint.indexOf("Uninstall Agent Bar") >= 0)
  }

  function test_theme_palette_light_dark() {
    var light = Palette.themePalette("light")
    var dark = Palette.themePalette("dark")
    compare(light.mode, "light")
    compare(dark.mode, "dark")
    verify(light.background !== dark.background)
    verify(light.foreground !== dark.foreground)
  }

  function test_focus_controller_ordered_activation_api() {
    var src = read("components/FocusController.qml")
    verify(src.indexOf("function setTargets") >= 0)
    verify(src.indexOf("liveTargets") >= 0)
    verify(src.indexOf("focusActivate") >= 0)
  }

  function test_settings_editor_owns_focus_flag() {
    var src = read("SettingsView.qml")
    var prop = src.indexOf("property bool editorOwnsFocus")
    verify(prop >= 0)
    var propEnd = src.indexOf("readonly property var state", prop)
    verify(propEnd > prop)
    var body = src.substring(prop, propEnd)
    verify(body.indexOf("intervalField") >= 0)
    // The selectable update command line takes focus too (UX-042).
    verify(body.indexOf("maintenanceView.editorOwnsFocus") >= 0)
    var view = read("MaintenanceView.qml")
    verify(view.indexOf("readonly property bool editorOwnsFocus: commandField.activeFocus") >= 0)
  }
}
