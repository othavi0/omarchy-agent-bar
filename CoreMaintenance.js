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

var UPDATE_APPLY_MESSAGES = {
  updated: function (v) { return v + " installed. Restart the shell to load it." },
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
  failed: function (v) { return "The update did not finish. You are still on " + v + "." }
}

function failedUpdateApplyOutcome() {
  return { result: "failed", installedVersion: "", restartRequired: false }
}

function parseUpdateApplyOutcome(stdout) {
  var doc = null
  try {
    doc = JSON.parse(String(stdout || "").trim())
  } catch (e) {
    return failedUpdateApplyOutcome()
  }
  if (!doc || doc.schemaVersion !== 1 || doc.operation !== "update")
    return failedUpdateApplyOutcome()
  var result = String(doc.result || "")
  if (!UPDATE_APPLY_MESSAGES.hasOwnProperty(result))
    return failedUpdateApplyOutcome()
  return {
    result: result,
    installedVersion: doc.installedVersion ? String(doc.installedVersion) : "",
    restartRequired: result === "updated"
  }
}

function updateApplyOutcomeFromLane(lane) {
  if (!lane || lane.timedOut || lane.exitCode !== 0)
    return failedUpdateApplyOutcome()
  return parseUpdateApplyOutcome(lane.stdout)
}

function updateApplyMessage(outcome, installedVersion) {
  var version = outcome.installedVersion && outcome.installedVersion.length
      ? outcome.installedVersion
      : String(installedVersion || "")
  return UPDATE_APPLY_MESSAGES[outcome.result](version)
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
    uninstallConfirmOpen: !!(ui && ui.uninstallConfirmOpen),
    updateConfirmOpen: !!(ui && ui.updateConfirmOpen)
  }
}

function maintenanceUiFromCheck(ui, stdout, exitCode, fallbackVersion) {
  var next = cloneMaintenanceUi(ui)
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
  return !!ui && (ui.phase === "update_available" || ui.phase === "update_failed")
      && !!ui.targetVersion && String(ui.targetVersion).length > 0
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

function maintenanceUiUpdating(ui) {
  var next = cloneMaintenanceUi(ui)
  next.phase = "updating"
  next.updateConfirmOpen = false
  next.message = "Updating\u2026 this takes a few seconds."
  return next
}

function maintenanceUiFromUpdateApply(ui, outcome) {
  var next = cloneMaintenanceUi(ui)
  next.updateConfirmOpen = false
  next.message = updateApplyMessage(outcome, next.installedVersion)
  if (outcome.result === "updated") {
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
