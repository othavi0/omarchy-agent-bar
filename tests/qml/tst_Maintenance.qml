import QtQuick
import QtTest
import "../../CoreMaintenance.js" as Core

TestCase {
  id: testCase
  name: "AgentBarMaintenance"
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

  function test_login_detached_argv() {
    var argv = Core.loginDetachedArgv("/home/u/.config/omarchy/plugins/othavi0.agent-bar", "claude")
    compare(argv.length, 3)
    compare(argv[0], "/home/u/.config/omarchy/plugins/othavi0.agent-bar/scripts/agent-bar-open-terminal")
    compare(argv[1], "login")
    compare(argv[2], "claude")
    compare(Core.loginDetachedArgv("/x", "nope"), null)
    compare(Core.loginDetachedArgv("", "claude"), null)
  }

  function test_restart_shell_argv_exact() {
    var argv = Core.restartShellArgv()
    compare(argv.length, 1)
    compare(argv[0], "omarchy-restart-shell")
  }

  function test_update_and_uninstall_argv() {
    var check = Core.updateCheckArgv("/bin/agent-bar")
    compare(check.join(" "), "/bin/agent-bar update check")
    compare(Core.uninstallArgv("/bin/agent-bar", false).join(" "), "/bin/agent-bar uninstall")
    compare(Core.uninstallArgv("/bin/agent-bar", true).join(" "), "/bin/agent-bar uninstall purge")
  }

  function test_marketplace_url_and_update_command_text_exact() {
    compare(Core.marketplaceUrl(), "https://plugins.omarchy.org/plugin.html?id=othavi0.agent-bar")
    compare(Core.updateCommandText(),
            "omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell")
  }

  function test_update_apply_and_status_argv_and_confirmation() {
    compare(Core.updateApplyArgv("/p/bin/agent-bar").join(" "), "/p/bin/agent-bar update apply")
    compare(Core.updateApplyArgv(""), null)
    compare(Core.updateStatusArgv("/p/bin/agent-bar").join(" "), "/p/bin/agent-bar update status")
    compare(Core.updateStatusArgv(""), null)
    compare(JSON.stringify(Core.updateConfirmation("10.6.2")),
            '{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":"10.6.2"}')
  }

  function lane(stdout, exitCode, timedOut) {
    return { stdout: stdout, exitCode: exitCode === undefined ? 0 : exitCode, timedOut: !!timedOut }
  }

  function finishedDoc(result, installed, restartRequired) {
    return JSON.stringify({
      schemaVersion: 1,
      operation: "update",
      status: "finished",
      result: result,
      fromVersion: "10.6.1",
      installedVersion: installed,
      restartRequired: restartRequired === undefined ? result === "updated" : restartRequired,
      finishedAt: "2026-09-22T12:00:00Z"
    }) + "\n"
  }

  function test_update_start_reads_started_and_already_running() {
    compare(Core.updateStartFromLane(lane('{"schemaVersion":1,"operation":"update","result":"started","unit":"agent-bar-update-1.service"}\n')), "started")
    compare(Core.updateStartFromLane(lane('{"result":"already_running"}\n')), "already_running")
    compare(Core.updateStartFromLane(lane('{"result":"started"}', 4)), "failed")
    compare(Core.updateStartFromLane(lane("", 1, true)), "failed")
    compare(Core.updateStartFromLane(lane("Starting unit\n")), "failed")
    compare(Core.updateStartFromLane(lane('{"schemaVersion":2,"operation":"update","result":"started"}')), "failed")
    compare(Core.updateStartFromLane(lane('{"schemaVersion":1,"operation":"uninstall","result":"started"}')), "failed")
    compare(Core.updateStartFromLane(lane('{"result":"updated"}')), "failed")
    compare(Core.updateStartFromLane(null), "failed")
  }

  function test_update_status_reads_each_status() {
    compare(Core.updateStatusFromLane(lane('{"schemaVersion":1,"operation":"update","status":"none"}\n')).status, "none")
    var running = Core.updateStatusFromLane(lane('{"schemaVersion":1,"operation":"update","status":"running","startedAt":"2026-09-22T12:00:00Z","targetVersion":"10.6.2"}'))
    compare(running.status, "running")
    compare(running.targetVersion, "10.6.2")
    var done = Core.updateStatusFromLane(lane(finishedDoc("updated", "10.6.2")))
    compare(done.status, "finished")
    compare(JSON.stringify(done.outcome), '{"result":"updated","installedVersion":"10.6.2","restartRequired":true}')
    var kinds = ["up_to_date", "local_changes", "fetch_failed", "validation_failed", "timed_out", "locked", "failed"]
    for (var i = 0; i < kinds.length; i++) {
      var o = Core.updateStatusFromLane(lane(finishedDoc(kinds[i], "10.6.1"))).outcome
      compare(o.result, kinds[i])
      compare(o.restartRequired, false)
    }
    compare(Core.updateStatusFromLane(lane(finishedDoc("exploded", "10.6.1"))).outcome.result, "failed")
    compare(Core.updateStatusFromLane(lane(finishedDoc("failed", "10.6.2", true))).outcome.restartRequired, true)
    compare(Core.updateStatusFromLane(lane("")).status, "unreadable")
    compare(Core.updateStatusFromLane(lane("not json")).status, "unreadable")
    compare(Core.updateStatusFromLane(lane('{"status":"none"}', 3)).status, "unreadable")
    compare(Core.updateStatusFromLane(lane("", 1, true)).status, "unreadable")
    compare(Core.updateStatusFromLane(lane('{"schemaVersion":1,"operation":"update","status":"paused"}')).status, "unreadable")
    compare(Core.updateStatusFromLane(lane('{"schemaVersion":2,"operation":"update","status":"none"}')).status, "unreadable")
  }

  function test_update_result_message_table() {
    function msg(result, installed) {
      return Core.updateResultMessage({ result: result, installedVersion: installed || "", restartRequired: result === "updated" }, "10.6.1")
    }
    compare(msg("updated", "10.6.2"), "10.6.2 installed. Restart the shell to load it.")
    compare(msg("up_to_date"), "Agent Bar is up to date.")
    compare(msg("local_changes"),
            "The plugin folder has local changes. Run git status in ~/.config/omarchy/plugins/othavi0.agent-bar.")
    compare(msg("fetch_failed"), "Could not reach GitHub. Try again.")
    compare(msg("validation_failed"), "The update failed validation and was rolled back. You are still on 10.6.1.")
    compare(msg("timed_out"), "The update timed out. You are still on 10.6.1.")
    compare(msg("locked"), "Another maintenance task is running. Try again in a minute.")
    compare(msg("failed"), "The update did not finish. You are still on 10.6.1.")
    compare(msg("validation_failed", "10.6.0"), "The update failed validation and was rolled back. You are still on 10.6.0.")
  }

  function test_update_confirm_model() {
    var m = Core.updateConfirmModel("10.6.2")
    compare(m.title, "Update to 10.6.2?")
    compare(m.message, "Omarchy fetches the release, validates it, and installs it. The bar keeps working until you restart the shell.")
    compare(m.confirmText, "Update")
    compare(m.cancelText, "Cancel")
  }

  function availableUi() {
    return Core.maintenanceUiFromCheck(Core.maintenanceUiIdle("10.3.1"), checkFixture("available.json"), 0, "10.3.1")
  }

  function test_update_confirm_opens_only_with_a_target() {
    compare(Core.maintenanceUiOpenUpdateConfirm(Core.maintenanceUiIdle("10.3.1")).updateConfirmOpen, false)
    var open = Core.maintenanceUiOpenUpdateConfirm(availableUi())
    compare(open.updateConfirmOpen, true)
    compare(open.phase, "update_available")
    var closed = Core.maintenanceUiCloseUpdateConfirm(open)
    compare(closed.updateConfirmOpen, false)
    compare(closed.phase, "update_available")
  }

  function outcome(result, installed) {
    return Core.updateStatusFromLane(lane(finishedDoc(result, installed))).outcome
  }

  function test_update_transitions_to_restart_required() {
    var ui = Core.maintenanceUiUpdating(Core.maintenanceUiOpenUpdateConfirm(availableUi()))
    compare(ui.phase, "updating")
    compare(ui.updateConfirmOpen, false)
    compare(ui.message, "Updating\u2026 this takes a few seconds.")
    compare(ui.updateCommand, "omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell")
    var done = Core.maintenanceUiFromUpdateResult(ui, outcome("updated", "10.4.0"))
    compare(done.phase, "restart_required")
    compare(done.installedVersion, "10.3.1")
    compare(done.targetVersion, "10.4.0")
    compare(done.message, "10.4.0 installed. Restart the shell to load it.")
    compare(done.updateCommand, "")
  }

  function test_update_transitions_to_up_to_date() {
    var ui = Core.maintenanceUiUpdating(availableUi())
    var done = Core.maintenanceUiFromUpdateResult(ui, outcome("up_to_date", "10.3.1"))
    compare(done.phase, "up_to_date")
    compare(done.message, "Agent Bar is up to date.")
    compare(done.targetVersion, "")
    compare(done.releaseNotesUrl, "")
    compare(done.updateCommand, "")
  }

  function test_update_failure_keeps_target_and_fallback() {
    var ui = Core.maintenanceUiUpdating(availableUi())
    var done = Core.maintenanceUiFromUpdateResult(ui, outcome("fetch_failed", "10.3.1"))
    compare(done.phase, "update_failed")
    compare(done.message, "Could not reach GitHub. Try again.")
    compare(done.targetVersion, "10.4.0")
    compare(done.releaseNotesUrl, "https://github.com/othavi0/omarchy-agent-bar/releases/tag/v10.4.0")
    compare(done.updateCommand, "omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell")
    compare(Core.maintenanceUiOpenUpdateConfirm(done).updateConfirmOpen, true)
    var failed = Core.maintenanceUiFromUpdateResult(ui, Core.failedUpdateOutcome())
    compare(failed.message, "The update did not finish. You are still on 10.3.1.")
  }

  function test_a_failure_offers_the_update_again_only_when_retrying_can_help() {
    var retry = ["fetch_failed", "timed_out", "locked", "failed"]
    for (var i = 0; i < retry.length; i++) {
      var ui = Core.maintenanceUiFromUpdateResult(Core.maintenanceUiUpdating(availableUi()), outcome(retry[i], "10.3.1"))
      compare(ui.phase, "update_failed", retry[i])
      compare(Core.maintenanceUiCanUpdate(ui), true, retry[i])
    }
    var stuck = ["local_changes", "validation_failed"]
    for (var j = 0; j < stuck.length; j++) {
      var held = Core.maintenanceUiFromUpdateResult(Core.maintenanceUiUpdating(availableUi()), outcome(stuck[j], "10.3.1"))
      compare(held.phase, "update_failed", stuck[j])
      compare(Core.maintenanceUiCanUpdate(held), false, stuck[j])
      compare(Core.maintenanceUiOpenUpdateConfirm(held).updateConfirmOpen, false, stuck[j])
      var rechecked = Core.maintenanceUiFromCheck(held, checkFixture("available.json"), 0, "10.3.1")
      compare(Core.maintenanceUiCanUpdate(rechecked), true, "the next check offers it again")
    }
  }

  function test_a_run_seen_at_startup_enters_updating_with_its_target() {
    var ui = Core.maintenanceUiUpdating(Core.maintenanceUiIdle("10.3.1"), "10.4.0")
    compare(ui.phase, "updating")
    compare(ui.targetVersion, "10.4.0")
    compare(ui.message, "Updating\u2026 this takes a few seconds.")
    compare(Core.maintenanceUiUpdating(availableUi(), "").targetVersion, "10.4.0")
  }

  function test_uninstall_confirmation_json() {
    var keep = Core.uninstallConfirmation(false)
    compare(keep.schemaVersion, 1)
    compare(keep.operation, "uninstall")
    compare(keep.confirmed, true)
    compare(keep.purgeSettingsAndBackups, false)
    var purge = Core.uninstallConfirmation(true)
    compare(purge.purgeSettingsAndBackups, true)
  }

  function checkFixture(name) {
    return read("tests/fixtures/update-check/" + name)
  }

  function test_update_check_parse_available() {
    var ui = Core.maintenanceUiIdle("10.3.1")
    ui = Core.maintenanceUiFromCheck(ui, checkFixture("available.json"), 0, "10.3.1")
    compare(ui.phase, "update_available")
    compare(ui.installedVersion, "10.3.1")
    compare(ui.targetVersion, "10.4.0")
    compare(ui.releaseNotesUrl, "https://github.com/othavi0/omarchy-agent-bar/releases/tag/v10.4.0")
    compare(ui.message, "10.4.0 is available.")
    compare(ui.updateCommand, "omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell")
    compare(ui.updateConfirmOpen, false)
  }

  function test_update_check_up_to_date() {
    var ui = Core.maintenanceUiIdle("")
    ui.targetVersion = "10.4.0"
    ui.releaseNotesUrl = "https://github.com/othavi0/omarchy-agent-bar/releases/tag/v10.4.0"
    ui = Core.maintenanceUiFromCheck(ui, checkFixture("up-to-date.json"), 0, "")
    compare(ui.phase, "up_to_date")
    compare(ui.installedVersion, "10.4.0")
    compare(ui.targetVersion, "")
    compare(ui.releaseNotesUrl, "")
    compare(ui.updateCommand, "")
    var none = Core.maintenanceUiFromCheck(Core.maintenanceUiIdle("10.3.1"), checkFixture("no-compatible.json"), 0, "10.3.1")
    compare(none.phase, "up_to_date")
  }

  function test_update_check_reinstall_required() {
    var ui = Core.maintenanceUiIdle("10.3.1")
    ui.targetVersion = "10.4.0"
    ui.releaseNotesUrl = "https://github.com/othavi0/omarchy-agent-bar/releases/tag/v10.4.0"
    ui = Core.maintenanceUiFromCheck(ui, checkFixture("reinstall-required.json"), 0, "10.3.1")
    compare(ui.phase, "reinstall_required")
    compare(ui.targetVersion, "")
    compare(ui.releaseNotesUrl, "")
    compare(ui.updateCommand, "")
    verify(ui.message.indexOf("omarchy plugin remove othavi0.agent-bar") >= 0)
    verify(ui.message.indexOf("omarchy plugin add https://github.com/othavi0/omarchy-agent-bar.git") >= 0)
  }

  function test_update_check_rejects_unusable_stdout() {
    compare(Core.maintenanceUiFromCheck(Core.maintenanceUiIdle("1.0.0"), "", 1, "1.0.0").phase, "error")
    compare(Core.maintenanceUiFromCheck(Core.maintenanceUiIdle("1.0.0"), "", 0, "1.0.0").phase, "error")
    compare(Core.maintenanceUiFromCheck(Core.maintenanceUiIdle("1.0.0"), "Agent Bar is up to date.\n", 0, "1.0.0").phase, "error")
    var wrongSchema = JSON.stringify({ schemaVersion: 2, available: true })
    var rejected = Core.maintenanceUiFromCheck(Core.maintenanceUiIdle("1.0.0"), wrongSchema, 0, "1.0.0")
    compare(rejected.phase, "error")
    compare(rejected.updateCommand, "")
  }

  function test_update_check_failure_has_one_string() {
    var src = read("CoreMaintenance.js")
    verify(src.indexOf("Update check returned an unusable response.") < 0)
    var first = src.indexOf("Update check failed.")
    verify(first >= 0)
    verify(src.indexOf("Update check failed.", first + 1) < 0,
           "every failure path must share the single string")
  }

  function test_uninstall_double_confirm() {
    var ui = Core.maintenanceUiOpenUninstallConfirm(Core.maintenanceUiIdle("10.0.0"))
    compare(ui.uninstallConfirmOpen, true)
    compare(ui.purgeSettings, false)
    compare(ui.uninstallArmed, false)
    var r1 = Core.maintenanceUiArmOrConfirmUninstall(ui)
    compare(r1.confirmed, false)
    compare(r1.ui.uninstallArmed, true)
    var r2 = Core.maintenanceUiArmOrConfirmUninstall(r1.ui)
    compare(r2.confirmed, true)
  }

  function test_purge_toggle_resets_arm() {
    var ui = Core.maintenanceUiOpenUninstallConfirm(Core.maintenanceUiIdle("10.0.0"))
    ui = Core.maintenanceUiArmOrConfirmUninstall(ui).ui
    compare(ui.uninstallArmed, true)
    ui = Core.maintenanceUiSetPurge(ui, true)
    compare(ui.purgeSettings, true)
    compare(ui.uninstallArmed, false)
  }

  function test_arming_sets_no_unseen_message() {
    var src = read("CoreMaintenance.js")
    verify(src.indexOf("Click Uninstall again") < 0)
    var view = read("MaintenanceView.qml")
    verify(view.indexOf('"Uninstall now"') >= 0)
  }

  function test_maintenance_intention_shapes() {
    var ui = Core.maintenanceUiIdle("10.0.0")
    ui.targetVersion = "10.1.0"
    ui.purgeSettings = true
    var un = Core.maintenanceIntention("uninstall", ui)
    compare(un.kind, "uninstall")
    compare(un.purge, true)
    compare(un.payload.purgeSettingsAndBackups, true)
  }

  function test_uninstall_is_the_only_maintenance_intention() {
    var ui = Core.maintenanceUiIdle("10.0.0")
    ui.targetVersion = "10.1.0"
    compare(Core.maintenanceIntention("update", ui), null)
    compare(Core.maintenanceIntention("reinstall", ui), null)
    compare(Core.maintenanceIntention("", ui), null)
    compare(Core.maintenanceIntention("uninstall", ui).kind, "uninstall")
  }

  function test_service_login_uses_exec_detached() {
    var src = read("Service.qml")
    verify(src.indexOf("Quickshell.execDetached") >= 0)
    verify(src.indexOf("loginDetachedArgv") >= 0)
    verify(src.indexOf("bash -lc") < 0)
    verify(src.indexOf("sh -c") < 0)
  }

  function test_service_restart_shell_uses_exec_detached() {
    var src = read("Service.qml")
    var start = src.indexOf("function restartShell()")
    verify(start >= 0)
    var end = src.indexOf("function ", start + 10)
    verify(end > start)
    var body = src.substring(start, end)
    verify(body.indexOf("Maintenance.restartShellArgv()") >= 0)
    verify(body.indexOf("lastRestartShellArgv = argv.slice()") >= 0)
    verify(body.indexOf("restartShellRequestCount++") >= 0)
    verify(body.indexOf("if (testMode)") >= 0)
    verify(body.indexOf("Quickshell.execDetached(argv)") >= 0)
    verify(body.indexOf("sh -c") < 0)
  }

  function test_maintenance_view_ux_copy() {
    var src = read("MaintenanceView.qml")
    verify(src.indexOf("Check for updates") >= 0)
    verify(src.indexOf("Marketplace page") >= 0)
    verify(src.indexOf("Uninstall Agent Bar") >= 0)
    verify(src.indexOf("Also delete saved settings and backups") >= 0)
    verify(src.indexOf("ConfirmDialog") >= 0)
    verify(src.indexOf("Release notes") >= 0)
    verify(src.indexOf("Text.RichText") < 0)
    verify(src.indexOf("Uninstall agent-bar") < 0)
    verify(src.indexOf("Installation type") < 0)
    verify(src.indexOf("Plugin bundle") < 0)
    verify(src.indexOf("Final confirmation") < 0)
    verify(src.indexOf("Deletes Agent Bar, your settings and every backup.") >= 0)
    verify(src.indexOf("Deletes Agent Bar. Your settings stay.") >= 0)
    verify(src.indexOf("Removes Agent Bar. Your settings stay.") >= 0)
  }

  // The maintainer-blocked update path (marketplace maintainer issue #4979):
  // the plugin only points the user at the marketplace page and the manual
  // command now, mirroring how the release-notes and restart-shell buttons
  // wire their source contract to a plain, testable Service call.
  function test_maintenance_view_marketplace_button_source_contract() {
    var src = read("MaintenanceView.qml")
    var start = src.indexOf("id: marketplaceButton")
    verify(start >= 0)
    var onClicked = src.indexOf("onClicked:", start)
    verify(onClicked >= 0)
    var closeAt = src.indexOf("}", onClicked)
    verify(closeAt > onClicked)
    var body = src.substring(onClicked, closeAt)
    verify(body.indexOf("root.agentService.openMarketplacePage()") >= 0)
  }

  function clickBody(src, id) {
    var start = src.indexOf("id: " + id)
    verify(start >= 0, id)
    var onClicked = src.indexOf("onClicked:", start)
    verify(onClicked >= 0, id + " onClicked")
    var closeAt = src.indexOf("}", onClicked)
    return src.substring(onClicked, closeAt)
  }

  function blockOf(src, id) {
    var start = src.indexOf("id: " + id)
    verify(start >= 0, id)
    var next = src.indexOf("id: ", start + 4)
    return src.substring(start, next < 0 ? src.length : next)
  }

  function test_maintenance_view_update_buttons_source_contract() {
    var src = read("MaintenanceView.qml")
    verify(clickBody(src, "updateButton").indexOf("root.agentService.openUpdateConfirm()") >= 0)
    verify(clickBody(src, "restartButton").indexOf("root.agentService.restartShell()") >= 0)
    verify(clickBody(src, "laterButton").indexOf("root.agentService.dismissPopup()") >= 0)
    var update = blockOf(src, "updateButton")
    verify(update.indexOf('"Update to " + ui.targetVersion') >= 0)
    verify(update.indexOf("selected: true") >= 0)
    verify(update.indexOf("Accessible.name:") >= 0)
    verify(update.indexOf("enabled: root.canUpdate && !root.blocked") >= 0)
    var restart = blockOf(src, "restartButton")
    verify(restart.indexOf('text: "Restart shell"') >= 0)
    verify(restart.indexOf("selected: true") >= 0)
    verify(restart.indexOf('Accessible.name: "Restart shell"') >= 0)
    var later = blockOf(src, "laterButton")
    verify(later.indexOf('text: "Later"') >= 0)
    verify(later.indexOf('Accessible.name: "Later"') >= 0)
  }

  function test_maintenance_view_update_phases_source_contract() {
    var src = read("MaintenanceView.qml")
    verify(src.indexOf("readonly property bool canUpdate: Core.maintenanceUiCanUpdate(ui)") >= 0)
    verify(src.indexOf('readonly property bool updating: ui.phase === "updating"') >= 0)
    verify(src.indexOf('readonly property bool restartRequired: ui.phase === "restart_required"') >= 0)
    verify(src.indexOf('readonly property bool maintenanceBusy: ui.phase === "uninstalling" || root.updating') >= 0)
    verify(src.indexOf('ui.phase === "error" || ui.phase === "update_failed"') >= 0)
    var banner = blockOf(src, "restartBanner")
    verify(banner.indexOf("visible: root.restartRequired") >= 0)
    verify(banner.indexOf("Style.selectedFillFor(") >= 0)
    verify(src.indexOf('"Or run this in a terminal:"') >= 0)
    verify(src.indexOf("id: commandField") > src.indexOf("id: marketplaceButton"),
           "the fallback command sits under the buttons")
  }

  function test_maintenance_view_update_dialog_source_contract() {
    var src = read("MaintenanceView.qml")
    var dialog = blockOf(src, "updateConfirmDialog")
    verify(dialog.indexOf("opened: !!ui.updateConfirmOpen") >= 0)
    verify(dialog.indexOf("title: root.updateConfirm.title") >= 0)
    verify(dialog.indexOf("message: root.updateConfirm.message") >= 0)
    verify(dialog.indexOf("confirmText: root.updateConfirm.confirmText") >= 0)
    verify(dialog.indexOf("destructive: false") >= 0)
    verify(dialog.indexOf("root.agentService.confirmUpdate()") >= 0)
    verify(dialog.indexOf("root.agentService.closeUpdateConfirm()") >= 0)
    verify(dialog.indexOf("Toggle") < 0, "one confirmation, no arming")
    verify(src.indexOf("readonly property var updateConfirm: Core.updateConfirmModel(ui.targetVersion)") >= 0)
  }

  function test_maintenance_view_text_is_plain_and_buttons_are_named() {
    var src = read("MaintenanceView.qml")
    var texts = src.match(/\bText \{/g).length
    var plain = src.match(/textFormat: Text\.PlainText/g).length
    compare(plain, texts, "every Text renders plain")
    var buttons = src.match(/\bButton \{/g).length
    var named = src.match(/Accessible\.name:/g).length
    verify(named >= buttons, "every button carries an accessible name")
  }

  function test_popup_reads_update_state_from_the_service() {
    var src = read("Popup.qml")
    verify(src.indexOf("CoreMaintenance.js") < 0, "the popup never reads the maintenance view model")
    verify(src.indexOf("agentService.updateRunning || agentService.restartPending") >= 0)
    verify(src.indexOf('? "about" : "providers"') >= 0)
  }

  function test_service_open_marketplace_page_source_contract() {
    var src = read("Service.qml")
    var start = src.indexOf("function openMarketplacePage()")
    verify(start >= 0)
    var end = src.indexOf("function ", start + 10)
    verify(end > start)
    var body = src.substring(start, end)
    verify(body.indexOf("Qt.openUrlExternally(Maintenance.marketplaceUrl())") >= 0)
  }

  function test_install_type_is_gone_from_the_model() {
    var src = read("CoreMaintenance.js")
    verify(src.indexOf("installType") < 0)
  }

  function test_settings_hosts_maintenance_view() {
    var src = read("SettingsView.qml")
    verify(src.indexOf("MaintenanceView") >= 0)
    verify(src.indexOf("land in the next task") < 0)
  }

  function test_helper_script_source_contract() {
    var src = read("scripts/agent-bar-open-terminal")
    verify(src.indexOf("xdg-terminal-exec") >= 0)
    verify(src.indexOf("--app-id=org.omarchy.terminal") >= 0)
    verify(src.indexOf("Agent Bar Login") >= 0)
    verify(src.indexOf("BASH_SOURCE") >= 0)
    verify(src.indexOf("cmd=\"$*\"") < 0)
    verify(src.indexOf("bash -lc") < 0)
    verify(src.indexOf("alacritty") < 0)
  }
}
