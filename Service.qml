import QtQuick
import Quickshell
import Quickshell.Io
import "CoreService.js" as Core
import "CoreSettings.js" as Settings
import "CoreMaintenance.js" as Maintenance
import "CoreView.js" as View
import "components"

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null

  // The plugin tree is this file's directory. The host's manifest copy carries
  // no source path for third-party plugins (Omarchy 4.0.3).
  readonly property string pluginRoot: Core.pluginRootFromUrl(Qt.resolvedUrl("."))

  property string helperPath: ""
  property bool testMode: false
  property int versionProbeTimeoutMs: 2000
  property int statusTimeoutMs: 60000
  property int settingsTimeoutMs: 15000
  property int maintenanceCheckTimeoutMs: 30000
  property int maintenanceHandoffTimeoutMs: 120000
  property int updateApplyTimeoutMs: 150000
  property int pollIntervalMs: Core.pollIntervalMs(appliedSettings)
  property int collectionDelayMs: 0

  property var snapshot: null
  readonly property bool refreshing: statusLane.busy
  property string selectedProviderId: ""
  property var popupOwner: null
  property var settingsState: Settings.settingsClosed()
  property var settingsDraft: null
  property var appliedSettings: null
  readonly property var resolvedSettings: appliedSettings ? appliedSettings : Core.defaultSettings()
  readonly property var visibleProviders: View.visibleProviders(snapshot, resolvedSettings)
  property var maintenanceState: Maintenance.maintenanceIdle()
  property var maintenanceUi: Maintenance.maintenanceUiIdle("")
  property var pendingForcedTargets: Core.emptyPending()
  property int loginRequestCount: 0
  property string lastLoginProviderId: ""
  property var lastLoginArgv: null
  property var lastRestartShellArgv: null
  property int restartShellRequestCount: 0
  property string lastViewInstallationUrl: ""
  property var pendingMaintenanceIntention: null
  property string pendingMaintenancePayload: ""
  property int resetTimeoutMs: 45000
  property var resetUi: Core.resetUiIdle()
  readonly property bool resetBusy: !resetLane.ready
  // UX-073: the refresh a settled claim fires must not erase that claim's
  // caption, so it is tracked from queueing to its status run's id.
  property bool resetRefreshQueued: false
  property int resetRefreshRunId: 0
  readonly property var lanes: ({
    versionProbe: versionProbeLane,
    status: statusLane,
    settingsRead: settingsReadLane,
    settingsBootstrap: settingsBootstrapLane,
    settingsWrite: settingsWriteLane,
    maintenanceCheck: maintenanceCheckLane,
    maintenanceHandoff: maintenanceHandoffLane,
    updateApply: updateApplyLane,
    reset: resetLane
  })
  readonly property int stalledLaneCount:
      (versionProbeLane.stalled ? 1 : 0)
      + (statusLane.stalled ? 1 : 0)
      + (settingsReadLane.stalled ? 1 : 0)
      + (settingsBootstrapLane.stalled ? 1 : 0)
      + (settingsWriteLane.stalled ? 1 : 0)
      + (maintenanceCheckLane.stalled ? 1 : 0)
      + (maintenanceHandoffLane.stalled ? 1 : 0)
      + (updateApplyLane.stalled ? 1 : 0)
      + (resetLane.stalled ? 1 : 0)
  readonly property string runtimeHealth: Core.runtimeHealth(stalledLaneCount)

  property string helperVersion: ""
  property bool versionReady: false
  property bool versionFailed: false
  property bool collectionStarted: false

  property int settingsGeneration: 0
  property string pendingSettingsPayload: ""

  property int refreshRequestCount: 0
  property string lastRefreshProviderId: ""
  property int settingsSaveCount: 0
  property bool pollEnabled: true
  property double nowMs: Date.now()

  readonly property string manifestVersion: manifest && manifest.version
      ? String(manifest.version)
      : ""

  function resolvedHelperPath() {
    if (helperPath && helperPath.length > 0)
      return helperPath
    if (pluginRoot.length > 0)
      return pluginRoot + "/bin/agent-bar"
    return ""
  }

  function health(expectedVersion) {
    return Core.health(
      versionReady,
      versionFailed,
      helperVersion,
      manifestVersion,
      expectedVersion,
      runtimeHealth
    )
  }

  // ARCH-021: any accepted callback clears every lane's stall mark.
  function noteLaneSettled(outcome) {
    if (outcome.timedOut)
      return
    for (var key in lanes)
      lanes[key].clearStall()
  }

  // IPC refresh(providerId) — queue one cache-bypass provider refresh.
  function refresh(providerId) {
    var result = Core.refreshResult(providerId)
    if (result !== "ok")
      return result
    lastRefreshProviderId = String(providerId)
    refreshRequestCount++
    refreshProvider(String(providerId), true)
    return "ok"
  }

  function refreshAll(force) {
    if (maintenanceState.blocked)
      return
    if (force)
      pendingForcedTargets = Core.unionForced(pendingForcedTargets, "all")
    kickStatus()
  }

  function refreshProvider(providerId, force) {
    if (maintenanceState.blocked)
      return
    if (!Core.isClosedProvider(providerId))
      return
    if (force)
      pendingForcedTargets = Core.unionForced(pendingForcedTargets, providerId)
    kickStatus()
  }

  function requestPopup(owner, providerId, view) {
    popupOwner = Core.requestPopup(popupOwner, owner, providerId, view)
    if (providerId)
      selectedProviderId = String(providerId)
  }

  function closePopup(owner) {
    popupOwner = Core.closePopup(popupOwner, owner)
    if (!popupOwner) {
      resetUi = Core.resetUiOnClose(resetUi, resetBusy)
      if (!Settings.settingsShouldRetainOnClose(settingsState)) {
        settingsState = Settings.settingsClosed()
        settingsDraft = null
      }
    }
  }

  function dismissPopup() {
    popupOwner = Core.dismissPopup(popupOwner)
    if (!popupOwner) {
      resetUi = Core.resetUiOnClose(resetUi, resetBusy)
      if (!Settings.settingsShouldRetainOnClose(settingsState)) {
        settingsState = Settings.settingsClosed()
        settingsDraft = null
      }
    }
  }

  function openSettings(owner) {
    // An update in flight or awaiting its restart keeps the About tab
    // reachable; the settings read stays off because the helper on disk may
    // already be the new version.
    if (maintenanceState.blocked) {
      if (Maintenance.maintenanceUiHoldsUpdate(maintenanceUi))
        requestPopup(owner, selectedProviderId || null, "settings")
      return
    }
    requestPopup(owner, selectedProviderId || null, "settings")
    if (!settingsState || settingsState.phase === "closed") {
      settingsGeneration++
      settingsState = Settings.settingsBeginLoad(settingsGeneration)
      settingsDraft = null
      kickSettingsRead()
    }
  }

  function settingsLocked() {
    return Settings.settingsControlsLocked(settingsState)
  }

  function mutateSettingsDraft(mutator) {
    if (settingsLocked())
      return
    if (!settingsDraft)
      return
    settingsDraft = mutator(settingsDraft)
    settingsState = Settings.settingsMarkDirty(settingsState)
    if (settingsState && settingsState.phase !== "closed") {
      var next = Settings.cloneState(settingsState)
      next.draft = settingsDraft
      settingsState = next
    }
  }

  function setProviderEnabled(providerId, enabled) {
    mutateSettingsDraft(function (d) {
      return Settings.setProviderEnabled(d, providerId, enabled)
    })
  }

  function moveProvider(providerId, delta) {
    mutateSettingsDraft(function (d) {
      return Settings.moveProvider(d, providerId, delta)
    })
  }

  function setDisplayMetric(metric) {
    mutateSettingsDraft(function (d) {
      return Settings.setDisplayMetric(d, metric)
    })
  }

  function setRefreshInterval(seconds) {
    mutateSettingsDraft(function (d) {
      return Settings.setRefreshInterval(d, seconds)
    })
  }

  function setNotificationsEnabled(enabled) {
    mutateSettingsDraft(function (d) {
      return Settings.setNotificationsEnabled(d, enabled)
    })
  }

  function setReminderMinutes(minutes) {
    mutateSettingsDraft(function (d) {
      return Settings.setReminderMinutes(d, minutes)
    })
  }

  function restoreSettingsDefaults() {
    if (settingsLocked())
      return
    settingsState = Settings.settingsRestoreDefaults(settingsState)
    settingsDraft = settingsState ? settingsState.draft : null
  }

  function cancelSettings() {
    if (settingsLocked() && settingsState && settingsState.phase === "saving")
      return
    settingsState = Settings.settingsCancel(settingsState)
    settingsDraft = settingsState ? settingsState.draft : null
  }

  function canSaveSettings() {
    return Settings.settingsCanSave(settingsState, settingsDraft)
  }

  function saveSettings() {
    if (maintenanceState.blocked)
      return false
    if (!canSaveSettings())
      return false
    if (!settingsWriteLane.ready)
      return false
    var payloadObj = JSON.parse(JSON.stringify(settingsDraft))
    var validation = Settings.validateSettingsDraft(payloadObj)
    if (!validation.ok)
      return false
    settingsGeneration++
    var gen = settingsGeneration
    pendingSettingsPayload = JSON.stringify(payloadObj)
    settingsState = Settings.settingsBeginSave(settingsState, gen, payloadObj)
    settingsDraft = settingsState.draft
    settingsSaveCount++
    kickSettingsWrite()
    return true
  }

  function retryProvider(providerId) {
    refreshProvider(providerId, true)
  }

  function loginProvider(providerId) {
    if (maintenanceState.blocked)
      return
    if (!Core.isClosedProvider(providerId))
      return
    var rootPath = pluginRoot
    if (!rootPath || !rootPath.length)
      return
    var argv = Maintenance.loginDetachedArgv(rootPath, providerId)
    if (!argv)
      return
    lastLoginProviderId = String(providerId)
    lastLoginArgv = argv.slice()
    loginRequestCount++
    if (testMode)
      return
    Quickshell.execDetached(argv)
  }

  function restartShell() {
    var argv = Maintenance.restartShellArgv()
    lastRestartShellArgv = argv.slice()
    restartShellRequestCount++
    if (testMode)
      return
    Quickshell.execDetached(argv)
  }

  function syncMaintenanceVersion() {
    var ver = helperVersion || manifestVersion || ""
    if (!maintenanceUi || !maintenanceUi.phase || maintenanceUi.phase === "idle") {
      maintenanceUi = Maintenance.maintenanceUiIdle(ver)
      return
    }
    if (ver && (!maintenanceUi.installedVersion || !String(maintenanceUi.installedVersion).length)) {
      var next = Maintenance.cloneMaintenanceUi(maintenanceUi)
      next.installedVersion = ver
      maintenanceUi = next
    }
  }

  function checkForUpdates() {
    startUpdateCheck()
  }

  function startUpdateCheck() {
    if (maintenanceState.blocked)
      return false
    if (!maintenanceCheckLane.ready)
      return false
    syncMaintenanceVersion()
    var helper = resolvedHelperPath()
    if (!helper.length) {
      maintenanceUi = Maintenance.maintenanceUiFromCheck(maintenanceUi, "", 1, helperVersion)
      return false
    }
    maintenanceUi = Maintenance.maintenanceUiChecking(maintenanceUi)
    return maintenanceCheckLane.start(Maintenance.updateCheckArgv(helper))
  }

  function applyUpdateCheckResult(outcome) {
    noteLaneSettled(outcome)
    tryMaintenanceDetach()
    maintenanceUi = Maintenance.maintenanceUiFromCheck(
      maintenanceUi,
      outcome.stdout,
      outcome.exitCode,
      helperVersion || manifestVersion
    )
  }

  function openUpdateConfirm() {
    if (maintenanceState.blocked)
      return
    maintenanceUi = Maintenance.maintenanceUiOpenUpdateConfirm(maintenanceUi)
  }

  function closeUpdateConfirm() {
    maintenanceUi = Maintenance.maintenanceUiCloseUpdateConfirm(maintenanceUi)
  }

  function confirmUpdate() {
    if (!maintenanceUi || !maintenanceUi.updateConfirmOpen || maintenanceState.blocked)
      return false
    var intention = Maintenance.maintenanceIntention("update", maintenanceUi)
    if (!intention || !resolvedHelperPath().length) {
      maintenanceUi = Maintenance.maintenanceUiFromUpdateApply(
        maintenanceUi, Maintenance.updateApplyOutcomeFromLane(null))
      return false
    }
    pendingMaintenanceIntention = intention
    pendingMaintenancePayload = JSON.stringify(intention.payload)
    maintenanceUi = Maintenance.maintenanceUiUpdating(maintenanceUi)
    beginMaintenanceHandoff()
    return true
  }

  function applyUpdateApplyDone(outcome) {
    noteLaneSettled(outcome)
    pendingMaintenanceIntention = null
    pendingMaintenancePayload = ""
    var result = Maintenance.updateApplyOutcomeFromLane(outcome)
    maintenanceUi = Maintenance.maintenanceUiFromUpdateApply(maintenanceUi, result)
    // The QML running now cannot read the new helper's envelopes, so nothing
    // polls again until restartShell() replaces both.
    if (result.result === "updated") {
      maintenanceState = Maintenance.maintenanceRestartPending()
      return
    }
    maintenanceState = Maintenance.maintenanceIdle()
    pollEnabled = true
    if (versionReady)
      pollTimer.restart()
  }

  function openUninstallConfirm() {
    maintenanceUi = Maintenance.maintenanceUiOpenUninstallConfirm(maintenanceUi)
  }

  function closeUninstallConfirm() {
    maintenanceUi = Maintenance.maintenanceUiCloseUninstallConfirm(maintenanceUi)
  }

  function setUninstallPurge(purge) {
    maintenanceUi = Maintenance.maintenanceUiSetPurge(maintenanceUi, purge)
  }

  function armOrConfirmUninstall() {
    var result = Maintenance.maintenanceUiArmOrConfirmUninstall(maintenanceUi)
    maintenanceUi = result.ui
    if (!result.confirmed)
      return false
    var intention = Maintenance.maintenanceIntention("uninstall", maintenanceUi)
    pendingMaintenanceIntention = intention
    pendingMaintenancePayload = JSON.stringify(intention.payload)
    maintenanceUi = Maintenance.maintenanceUiUninstalling(maintenanceUi)
    beginMaintenanceHandoff()
    return true
  }

  function openReleaseNotes() {
    var url = maintenanceUi && maintenanceUi.releaseNotesUrl
        ? String(maintenanceUi.releaseNotesUrl)
        : ""
    if (url.indexOf("https://") !== 0)
      return
    Qt.openUrlExternally(url)
  }

  function openMarketplacePage() {
    Qt.openUrlExternally(Maintenance.marketplaceUrl())
  }

  function viewInstallation(providerId, url) {
    if (!Core.isClosedProvider(providerId))
      return
    var target = String(url || "")
    if (target.indexOf("https://") !== 0)
      return
    lastViewInstallationUrl = target
    Qt.openUrlExternally(target)
  }

  function requestReset(providerId, resetId) {
    if (maintenanceState.blocked || resetBusy)
      return
    if (!Core.isClosedProvider(providerId))
      return
    resetUi = Core.resetUiOpenConfirm(providerId, resetId)
  }

  function closeResetConfirm() {
    resetUi = Core.resetUiOnClose(resetUi, resetBusy)
  }

  function confirmReset() {
    if (!resetUi || !resetUi.confirmOpen)
      return
    var helper = resolvedHelperPath()
    if (maintenanceState.blocked || !helper.length) {
      resetUi = Core.resetUiIdle()
      return
    }
    var target = { providerId: resetUi.providerId, resetId: resetUi.resetId }
    resetUi = Core.resetUiAwaiting(resetUi)
    resetLane.start(Core.resetArgv(helper, target.providerId, target.resetId), "", target)
  }

  function applyResetResult(outcome) {
    noteLaneSettled(outcome)
    tryMaintenanceDetach()
    var target = outcome.context
    resetUi = Core.resetUiSettled(target, Core.resetOutcomeFromLane(outcome))
    if (target && target.providerId && !maintenanceState.blocked) {
      resetRefreshQueued = true
      refreshProvider(target.providerId, true)
    }
  }

  function dispatchAction(providerId, action) {
    if (!action)
      return
    var kind = View.mapActionKind(action.kind)
    if (!kind)
      return
    if (kind === "retry") {
      retryProvider(providerId)
      return
    }
    if (kind === "login") {
      loginProvider(providerId)
      return
    }
    if (kind === "view_installation") {
      viewInstallation(providerId, action.target)
    }
  }

  function applyVersionProbeResult(outcome) {
    noteLaneSettled(outcome)
    var version = Core.parseVersionStdout(outcome.stdout, outcome.stderr, outcome.exitCode)
    if (version)
      finishVersionProbeSuccess(version)
    else
      finishVersionProbeFailure()
  }

  function tryStartProduction() {
    if (testMode)
      return
    if (versionReady || versionProbeLane.busy)
      return
    if (!resolvedHelperPath().length) {
      console.warn("Agent Bar: cannot resolve plugin root from " + Qt.resolvedUrl("."))
      return
    }
    startVersionProbe()
  }

  function startVersionProbe() {
    if (versionReady || !versionProbeLane.ready)
      return
    if (testMode)
      return
    var helper = resolvedHelperPath()
    if (!helper.length) {
      return
    }
    versionFailed = false
    versionProbeLane.start([helper, "version"])
  }

  function finishVersionProbeSuccess(versionText) {
    helperVersion = versionText
    versionReady = true
    versionFailed = false
    syncMaintenanceVersion()
    kickSettingsBootstrap()
    if (collectionDelayMs > 0) {
      collectionDelay.interval = collectionDelayMs
      collectionDelay.start()
    } else {
      beginCollection()
    }
  }

  function finishVersionProbeFailure() {
    versionReady = false
    versionFailed = true
    helperVersion = ""
  }

  function beginCollection() {
    collectionStarted = true
    pollTimer.restart()
    kickStatus()
  }

  function kickStatus() {
    if (!versionReady || versionFailed)
      return
    if (maintenanceState.blocked)
      return
    if (!statusLane.ready)
      return
    var helper = resolvedHelperPath()
    if (!helper.length)
      return
    var targets = Core.takePending(pendingForcedTargets)
    pendingForcedTargets = targets.remaining
    if (statusLane.start(Core.statusArgv(helper, targets.captured)) && resetRefreshQueued) {
      resetRefreshQueued = false
      resetRefreshRunId = statusLane.startedRunId
    }
  }

  function applyStatusResult(outcome) {
    noteLaneSettled(outcome)
    tryMaintenanceDetach()
    var keepsResetCaption = resetRefreshQueued || outcome.runId === resetRefreshRunId
    if (outcome.runId === resetRefreshRunId)
      resetRefreshRunId = 0

    if (outcome.exitCode !== 0) {
      maybeFollowUpStatus()
      return
    }
    var parsed = Core.parseStatusEnvelope(outcome.stdout, helperVersion)
    if (!parsed.ok) {
      maybeFollowUpStatus()
      return
    }
    snapshot = parsed.envelope
    resetUi = Core.resetUiAfterSnapshot(resetUi, snapshot)
    if (!keepsResetCaption)
      resetUi = Core.resetUiClearOutcome(resetUi)
    maybeFollowUpStatus()
  }

  function maybeFollowUpStatus() {
    if (!pendingIsEmptySafe())
      kickStatus()
  }

  function pendingIsEmptySafe() {
    return Core.pendingIsEmpty(pendingForcedTargets)
  }

  function kickSettingsBootstrap() {
    if (appliedSettings || maintenanceState.blocked)
      return
    if (!settingsBootstrapLane.ready)
      return
    var helper = resolvedHelperPath()
    if (!helper.length)
      return
    settingsBootstrapLane.start(Settings.settingsArgvShow(helper))
  }

  function applySettingsBootstrapResult(outcome) {
    noteLaneSettled(outcome)
    tryMaintenanceDetach()
    appliedSettings = Settings.settingsBootstrapResult(appliedSettings, outcome.stdout, outcome.exitCode)
  }

  function kickSettingsRead() {
    if (!settingsReadLane.ready)
      return
    var helper = resolvedHelperPath()
    if (!helper.length)
      return
    settingsReadLane.start(Settings.settingsArgvShow(helper), "", settingsState.generation)
  }

  function applySettingsReadResult(outcome) {
    noteLaneSettled(outcome)
    tryMaintenanceDetach()
    if (!settingsState || settingsState.phase === "closed")
      return
    var generation = outcome.context
    if (outcome.exitCode !== 0) {
      settingsState = Settings.settingsFailLoad(settingsState, generation)
      settingsDraft = null
      return
    }
    var doc = null
    try {
      doc = JSON.parse(String(outcome.stdout || "").trim())
    } catch (e) {
      doc = null
    }
    if (!doc || !Settings.validateSettingsDraft(doc).ok) {
      settingsState = Settings.settingsFailLoad(settingsState, generation)
      settingsDraft = null
      return
    }
    settingsState = Settings.settingsFinishLoad(settingsState, generation, doc)
    settingsDraft = settingsState.draft
    appliedSettings = doc
  }

  function kickSettingsWrite() {
    if (!settingsWriteLane.ready)
      return
    if (maintenanceState.blocked)
      return
    var helper = resolvedHelperPath()
    if (!helper.length)
      return
    settingsWriteLane.start(Settings.settingsArgvApplyStdin(helper),
                            pendingSettingsPayload,
                            settingsState.generation)
  }

  function applySettingsWriteResult(outcome) {
    noteLaneSettled(outcome)
    pendingSettingsPayload = ""
    var ok = outcome.exitCode === 0
    var canonical = null
    if (ok) {
      try {
        canonical = JSON.parse(String(outcome.stdout).trim())
        if (!Settings.validateSettingsDraft(canonical).ok)
          ok = false
      } catch (e) {
        ok = false
      }
    }
    settingsState = Settings.settingsFinishSave(settingsState, outcome.context, ok, canonical)
    settingsDraft = settingsState ? settingsState.draft : null
    if (ok && canonical)
      appliedSettings = canonical
    tryMaintenanceDetach()
  }

  function beginMaintenanceHandoff() {
    maintenanceState = Maintenance.maintenanceBeginHandoff(maintenanceState)
    pollEnabled = false
    pollTimer.stop()
    tryMaintenanceDetach()
  }

  function tryMaintenanceDetach() {
    var anyLaneBusy = statusLane.busy || settingsReadLane.busy
        || settingsBootstrapLane.busy || settingsWriteLane.busy
        || maintenanceCheckLane.busy || resetLane.busy
    if (!Maintenance.maintenanceCanDetach(maintenanceState, anyLaneBusy))
      return
    var intention = pendingMaintenanceIntention
    if (!intention)
      return
    var helper = resolvedHelperPath()
    var lane = intention.kind === "update" ? updateApplyLane : maintenanceHandoffLane
    if (!lane.ready)
      return
    var argv = intention.kind === "update"
        ? Maintenance.updateApplyArgv(helper)
        : Maintenance.uninstallArgv(helper, intention.purge)
    if (!argv)
      return
    lane.start(argv, pendingMaintenancePayload)
  }

  function applyMaintenanceHandoffDone(outcome) {
    noteLaneSettled(outcome)
    var intention = pendingMaintenanceIntention
    pendingMaintenanceIntention = null
    pendingMaintenancePayload = ""
    maintenanceState = Maintenance.maintenanceIdle()
    pollEnabled = true
    if (versionReady)
      pollTimer.restart()
    if (intention && intention.kind === "uninstall") {
      if (outcome.exitCode === 0) {
        maintenanceUi = Maintenance.maintenanceUiIdle(helperVersion)
        maintenanceUi.message = "Uninstall completed."
      } else {
        maintenanceUi = Maintenance.cloneMaintenanceUi(maintenanceUi)
        maintenanceUi.phase = "error"
        maintenanceUi.message = "Uninstall failed."
      }
    }
  }

  HelperLane {
    id: versionProbeLane
    process: versionProbe
    stdoutSource: versionOut
    stderrSource: versionErr
    timeoutMs: root.versionProbeTimeoutMs
    onSettled: function (outcome) { root.applyVersionProbeResult(outcome) }
  }

  HelperLane {
    id: statusLane
    process: statusProcess
    stdoutSource: statusOut
    stderrSource: statusErr
    timeoutMs: root.statusTimeoutMs
    onSettled: function (outcome) { root.applyStatusResult(outcome) }
    // A forced refresh queued while the killed run was still dying only gets
    // its kick once the lane reopens; callLater keeps that kick out of the
    // lane's own state transition.
    onReadyChanged: if (statusLane.ready) Qt.callLater(root.maybeFollowUpStatus)
  }

  HelperLane {
    id: settingsReadLane
    process: settingsReadProcess
    stdoutSource: settingsReadOut
    stderrSource: settingsReadErr
    timeoutMs: root.settingsTimeoutMs
    onSettled: function (outcome) { root.applySettingsReadResult(outcome) }
  }

  HelperLane {
    id: settingsBootstrapLane
    process: settingsBootstrapProcess
    stdoutSource: settingsBootstrapOut
    stderrSource: settingsBootstrapErr
    timeoutMs: root.settingsTimeoutMs
    onSettled: function (outcome) { root.applySettingsBootstrapResult(outcome) }
  }

  HelperLane {
    id: settingsWriteLane
    process: settingsWriteProcess
    stdoutSource: settingsWriteOut
    stderrSource: settingsWriteErr
    timeoutMs: root.settingsTimeoutMs
    onSettled: function (outcome) { root.applySettingsWriteResult(outcome) }
  }

  HelperLane {
    id: maintenanceCheckLane
    process: maintenanceCheckProcess
    stdoutSource: maintenanceCheckOut
    stderrSource: maintenanceCheckErr
    timeoutMs: root.maintenanceCheckTimeoutMs
    onSettled: function (outcome) { root.applyUpdateCheckResult(outcome) }
  }

  HelperLane {
    id: resetLane
    process: resetProcess
    stdoutSource: resetOut
    stderrSource: resetErr
    timeoutMs: root.resetTimeoutMs
    onSettled: function (outcome) { root.applyResetResult(outcome) }
  }

  HelperLane {
    id: maintenanceHandoffLane
    process: maintenanceHandoffProcess
    stdoutSource: maintenanceHandoffOut
    stderrSource: maintenanceHandoffErr
    timeoutMs: root.maintenanceHandoffTimeoutMs
    onSettled: function (outcome) { root.applyMaintenanceHandoffDone(outcome) }
  }

  HelperLane {
    id: updateApplyLane
    process: updateApplyProcess
    stdoutSource: updateApplyOut
    stderrSource: updateApplyErr
    timeoutMs: root.updateApplyTimeoutMs
    onSettled: function (outcome) { root.applyUpdateApplyDone(outcome) }
  }

  Process {
    id: versionProbe
    stdout: StdioCollector { id: versionOut; waitForEnd: true }
    stderr: StdioCollector { id: versionErr; waitForEnd: true }
  }

  Process {
    id: statusProcess
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
  }

  Process {
    id: settingsReadProcess
    stdout: StdioCollector { id: settingsReadOut; waitForEnd: true }
    stderr: StdioCollector { id: settingsReadErr; waitForEnd: true }
  }

  Process {
    id: settingsBootstrapProcess
    stdout: StdioCollector { id: settingsBootstrapOut; waitForEnd: true }
    stderr: StdioCollector { id: settingsBootstrapErr; waitForEnd: true }
  }

  Process {
    id: settingsWriteProcess
    stdout: StdioCollector { id: settingsWriteOut; waitForEnd: true }
    stderr: StdioCollector { id: settingsWriteErr; waitForEnd: true }
  }

  Process {
    id: maintenanceCheckProcess
    stdout: StdioCollector { id: maintenanceCheckOut; waitForEnd: true }
    stderr: StdioCollector { id: maintenanceCheckErr; waitForEnd: true }
  }

  Process {
    id: resetProcess
    stdout: StdioCollector { id: resetOut; waitForEnd: true }
    stderr: StdioCollector { id: resetErr; waitForEnd: true }
  }

  Process {
    id: maintenanceHandoffProcess
    stdout: StdioCollector { id: maintenanceHandoffOut; waitForEnd: true }
    stderr: StdioCollector { id: maintenanceHandoffErr; waitForEnd: true }
  }

  Process {
    id: updateApplyProcess
    stdout: StdioCollector { id: updateApplyOut; waitForEnd: true }
    stderr: StdioCollector { id: updateApplyErr; waitForEnd: true }
  }

  Timer {
    id: collectionDelay
    repeat: false
    onTriggered: root.beginCollection()
  }

  Timer {
    id: pollTimer
    interval: root.pollIntervalMs
    repeat: true
    running: false
    onTriggered: {
      if (!root.pollEnabled || root.maintenanceState.blocked)
        return
      root.kickStatus()
    }
  }

  Timer {
    id: nowTimer
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: "othavi0.agent-bar"
    function health(expectedVersion: string): string { return root.health(expectedVersion) }
    function refresh(providerId: string): string { return root.refresh(providerId) }
  }

  onHelperPathChanged: root.tryStartProduction()

  onManifestChanged: {
    root.syncMaintenanceVersion()
    root.tryStartProduction()
  }

  Component.onCompleted: {
    root.syncMaintenanceVersion()
    root.tryStartProduction()
  }

  Component.onDestruction: {
    collectionDelay.stop()
    pollTimer.stop()
    nowTimer.stop()
  }
}
