.pragma library
.import "CoreService.js" as Kernel

function maintenanceIdle() {
  return { phase: "idle", blocked: false }
}

function maintenanceBeginHandoff(state) {
  return { phase: "handoff", blocked: true }
}

function maintenanceCanDetach(maint, anyLaneBusy) {
  if (!maint || maint.phase !== "handoff")
    return false
  return !anyLaneBusy
}

function loginDetachedArgv(pluginRoot, providerId) {
  if (!pluginRoot || !String(pluginRoot).length)
    return null
  if (!Kernel.isClosedProvider(providerId))
    return null
  return [
    String(pluginRoot) + "/scripts/agent-bar-open-terminal",
    "login",
    String(providerId)
  ]
}

function restartShellArgv() {
  return ["omarchy-restart-shell"]
}

function updateCheckArgv(helperPath) {
  return [String(helperPath), "update", "check"]
}

function marketplaceUrl() {
  return "https://plugins.omarchy.org/plugin.html?id=othavi0.agent-bar"
}

function updateCommandText() {
  return "omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell"
}

function updateApplyArgv(helperPath) {
  if (!helperPath || !String(helperPath).length)
    return null
  return [String(helperPath), "update", "apply"]
}

function updateConfirmation(targetVersion) {
  return {
    schemaVersion: 1,
    operation: "update",
    confirmed: true,
    targetVersion: String(targetVersion)
  }
}

function updateConfirmModel(targetVersion) {
  return {
    title: "Update to " + targetVersion + "?",
    message: "Omarchy fetches the release, validates it, and installs it. "
        + "The bar keeps working until you restart the shell.",
    cancelText: "Cancel",
    confirmText: "Update"
  }
}

function updateStatusArgv(helperPath) {
  if (!helperPath || !String(helperPath).length)
    return null
  return [String(helperPath), "update", "status"]
}

function restartPendingMessage(version) {
  return String(version) + " installed. Restart the shell to load it."
}

var UPDATE_RESULT_MESSAGES = {
  updated: restartPendingMessage,
  up_to_date: function (v) { return "Agent Bar is up to date." },
  local_changes: function (v) {
    return "The plugin folder has local changes. "
        + "Run git status in ~/.config/omarchy/plugins/othavi0.agent-bar."
  },
  fetch_failed: function (v) { return "Could not reach GitHub. Try again." },
  validation_failed: function (v) {
    return "The update failed validation and was rolled back. You are still on " + v + "."
  },
  timed_out: function (v) { return "The update timed out. You are still on " + v + "." },
  locked: function (v) { return "Another maintenance task is running. Try again in a minute." },
  failed: function (v) { return "The update did not finish. You are still on " + v + "." }
}

var UPDATE_RETRYABLE_RESULTS = { fetch_failed: true, timed_out: true, locked: true, failed: true }

function failedUpdateOutcome() {
  return { result: "failed", installedVersion: "", restartRequired: false }
}

function updateDocFromLane(lane) {
  if (!lane || lane.timedOut || lane.exitCode !== 0)
    return null
  var doc = null
  try {
    doc = JSON.parse(String(lane.stdout || "").trim())
  } catch (e) {
    return null
  }
  if (!doc || typeof doc !== "object")
    return null
  if (doc.schemaVersion !== 1 || doc.operation !== "update")
    return null
  return doc
}

function updateStartFromLane(lane) {
  var doc = updateDocFromLane(lane)
  if (doc && (doc.result === "started" || doc.result === "already_running"))
    return doc.result
  return "failed"
}

function updateStatusFromLane(lane) {
  var doc = updateDocFromLane(lane)
  if (!doc)
    return { status: "unreadable" }
  if (doc.status === "none")
    return { status: "none" }
  if (doc.status === "running")
    return { status: "running", targetVersion: doc.targetVersion ? String(doc.targetVersion) : "" }
  if (doc.status !== "finished")
    return { status: "unreadable" }
  var result = String(doc.result || "")
  return {
    status: "finished",
    outcome: {
      result: UPDATE_RESULT_MESSAGES.hasOwnProperty(result) ? result : "failed",
      installedVersion: doc.installedVersion ? String(doc.installedVersion) : "",
      restartRequired: doc.restartRequired === true
    }
  }
}

function updateResultMessage(outcome, installedVersion) {
  var version = outcome.installedVersion && outcome.installedVersion.length
      ? outcome.installedVersion
      : String(installedVersion || "")
  var result = outcome.restartRequired ? "updated" : outcome.result
  return UPDATE_RESULT_MESSAGES[result](version)
}

function uninstallArgv(helperPath, purge) {
  if (purge)
    return [String(helperPath), "uninstall", "purge"]
  return [String(helperPath), "uninstall"]
}

function uninstallConfirmation(purge) {
  return {
    schemaVersion: 1,
    operation: "uninstall",
    confirmed: true,
    purgeSettingsAndBackups: !!purge
  }
}

function maintenanceUiIdle(installedVersion) {
  return {
    phase: "idle",
    installedVersion: installedVersion ? String(installedVersion) : "",
    targetVersion: "",
    releaseNotesUrl: "",
    updateCommand: "",
    purgeSettings: false,
    uninstallArmed: false,
    message: "",
    updateResult: "",
    uninstallConfirmOpen: false,
    updateConfirmOpen: false
  }
}

function maintenanceUiChecking(ui) {
  var next = cloneMaintenanceUi(ui)
  next.phase = "checking"
  next.message = "Checking for updates\u2026"
  return next
}

function cloneMaintenanceUi(ui) {
  return {
    phase: ui && ui.phase ? ui.phase : "idle",
    installedVersion: ui && ui.installedVersion ? String(ui.installedVersion) : "",
    targetVersion: ui && ui.targetVersion ? String(ui.targetVersion) : "",
    releaseNotesUrl: ui && ui.releaseNotesUrl ? String(ui.releaseNotesUrl) : "",
    updateCommand: ui && ui.updateCommand ? String(ui.updateCommand) : "",
    purgeSettings: !!(ui && ui.purgeSettings),
    uninstallArmed: !!(ui && ui.uninstallArmed),
    message: ui && ui.message ? String(ui.message) : "",
    updateResult: ui && ui.updateResult ? String(ui.updateResult) : "",
    uninstallConfirmOpen: !!(ui && ui.uninstallConfirmOpen),
    updateConfirmOpen: !!(ui && ui.updateConfirmOpen)
  }
}

function maintenanceUiFromCheck(ui, stdout, exitCode, fallbackVersion) {
  var next = cloneMaintenanceUi(ui)
  next.updateResult = ""
  if (exitCode === 0) {
    try {
      var doc = JSON.parse(String(stdout || ""))
      if (doc && doc.schemaVersion === 1) {
        var current = doc.current && doc.current.version ? String(doc.current.version) : ""
        next.installedVersion = current.length
            ? current
            : String(next.installedVersion || fallbackVersion || "")
        if (doc.reinstallRequired === true) {
          next.phase = "reinstall_required"
          next.targetVersion = ""
          next.releaseNotesUrl = ""
          next.updateCommand = ""
          next.message = "Installed without git. Run: omarchy plugin remove othavi0.agent-bar, "
              + "then omarchy plugin add https://github.com/othavi0/omarchy-agent-bar.git"
          return next
        }
        var latest = doc.latestCompatible
        if (doc.available === true && latest && latest.version) {
          next.phase = "update_available"
          next.targetVersion = String(latest.version)
          next.releaseNotesUrl = latest.releaseNotesUrl ? String(latest.releaseNotesUrl) : ""
          next.updateCommand = updateCommandText()
          next.message = next.targetVersion + " is available."
          return next
        }
        if (doc.available === false) {
          next.phase = "up_to_date"
          next.targetVersion = ""
          next.releaseNotesUrl = ""
          next.updateCommand = ""
          next.message = "Agent Bar is up to date."
          return next
        }
      }
    } catch (e) {
    }
  }
  next.phase = "error"
  next.updateCommand = ""
  next.message = "Update check failed."
  return next
}

function maintenanceUiCanUpdate(ui) {
  if (!ui || !ui.targetVersion || !String(ui.targetVersion).length)
    return false
  if (ui.phase === "update_available")
    return true
  return ui.phase === "update_failed" && UPDATE_RETRYABLE_RESULTS.hasOwnProperty(ui.updateResult)
}

function maintenanceUiOpenUpdateConfirm(ui) {
  var next = cloneMaintenanceUi(ui)
  next.updateConfirmOpen = maintenanceUiCanUpdate(next)
  return next
}

function maintenanceUiCloseUpdateConfirm(ui) {
  var next = cloneMaintenanceUi(ui)
  next.updateConfirmOpen = false
  return next
}

function maintenanceUiUpdating(ui, targetVersion) {
  var next = cloneMaintenanceUi(ui)
  if (targetVersion && String(targetVersion).length)
    next.targetVersion = String(targetVersion)
  next.phase = "updating"
  next.updateConfirmOpen = false
  next.message = "Updating\u2026 this takes a few seconds."
  return next
}

function maintenanceUiFromUpdateResult(ui, outcome) {
  var next = cloneMaintenanceUi(ui)
  next.updateConfirmOpen = false
  next.message = updateResultMessage(outcome, next.installedVersion)
  next.updateResult = outcome.result
  if (outcome.restartRequired) {
    next.phase = "restart_required"
    if (outcome.installedVersion.length)
      next.targetVersion = outcome.installedVersion
    next.updateCommand = ""
    return next
  }
  if (outcome.result === "up_to_date") {
    next.phase = "up_to_date"
    next.targetVersion = ""
    next.releaseNotesUrl = ""
    next.updateCommand = ""
    return next
  }
  next.phase = "update_failed"
  next.updateCommand = updateCommandText()
  return next
}

function maintenanceUiOpenUninstallConfirm(ui) {
  var next = cloneMaintenanceUi(ui)
  next.uninstallConfirmOpen = true
  next.uninstallArmed = false
  next.purgeSettings = false
  return next
}

function maintenanceUiCloseUninstallConfirm(ui) {
  var next = cloneMaintenanceUi(ui)
  next.uninstallConfirmOpen = false
  next.uninstallArmed = false
  return next
}

function maintenanceUiSetPurge(ui, purge) {
  var next = cloneMaintenanceUi(ui)
  next.purgeSettings = !!purge
  next.uninstallArmed = false
  return next
}

function maintenanceUiArmOrConfirmUninstall(ui) {
  var next = cloneMaintenanceUi(ui)
  if (!next.uninstallConfirmOpen)
    return { ui: next, confirmed: false }
  if (!next.uninstallArmed) {
    next.uninstallArmed = true
    return { ui: next, confirmed: false }
  }
  return { ui: next, confirmed: true }
}

function maintenanceUiUninstalling(ui) {
  var next = cloneMaintenanceUi(ui)
  next.phase = "uninstalling"
  next.uninstallConfirmOpen = false
  next.message = "Uninstalling\u2026"
  return next
}

function maintenanceIntention(kind, ui) {
  if (kind === "uninstall") {
    return {
      kind: "uninstall",
      purge: !!(ui && ui.purgeSettings),
      payload: uninstallConfirmation(!!(ui && ui.purgeSettings))
    }
  }
  return null
}
