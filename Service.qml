import QtQuick
import Quickshell
import Quickshell.Io
import "CoreService.js" as Core
import "CoreSettings.js" as Settings
import "CoreMaintenance.js" as Maintenance
import "CoreView.js" as View

// Shared Agent Bar service — one instance per shell (ARCH-023 / ARCH-024).
Item {
  id: root

  // --- Quattro injection ---
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null

  readonly property string pluginRoot: manifest && manifest.__sourceDir
      ? String(manifest.__sourceDir)
      : ""

  // Test harness: absolute helper path. Production uses pluginRoot/bin/agent-bar.
  property string helperPath: ""
  // Skip auto Process start; tests drive apply* methods.
  property bool testMode: false
  property int versionProbeTimeoutMs: 2000
  property int statusTimeoutMs: 60000
  property int settingsTimeoutMs: 15000
  property int maintenanceCheckTimeoutMs: 30000
  property int maintenanceHandoffTimeoutMs: 120000
  property int pollIntervalMs: Core.pollIntervalMs(appliedSettings)
  property int collectionDelayMs: 0

  // --- Public service surface (Task 9 / Task 10) ---
  property var snapshot: null
  property bool refreshing: false
  property string selectedProviderId: ""
  property var popupOwner: null // { owner, providerId, view } or null
  property var settingsState: Settings.settingsClosed()
  property var settingsDraft: null
  // Applied product settings for bar chips (order / metric). Null → defaults.
  property var appliedSettings: null
  property var maintenanceState: Maintenance.maintenanceIdle()
  property var maintenanceUi: Maintenance.maintenanceUiIdle("")
  property var pendingForcedTargets: Core.emptyPending()
  // Login bookkeeping + last detached argv (testable without exec).
  property int loginRequestCount: 0
  property string lastLoginProviderId: ""
  property var lastLoginArgv: null
  property string lastViewInstallationUrl: ""
  // Pending maintenance intention after confirm (update apply / uninstall).
  property var pendingMaintenanceIntention: null
  property string pendingMaintenancePayload: ""
  property var timedOutLanes: ({})
  property var settledLanes: ({})
  property int completedCallbackCount: 0
  readonly property string runtimeHealth: Core.runtimeHealth(timedOutLanes)

  // Version probe
  property string helperVersion: ""
  property bool versionReady: false
  property bool versionFailed: false
  property bool versionProbeRunning: false
  property bool collectionStarted: false

  // Lane busy flags (one Process per lane; never re-exec while running)
  property bool statusBusy: false
  property bool settingsReadBusy: false
  property bool settingsBootstrapBusy: false
  property bool settingsWriteBusy: false
  property bool maintenanceCheckBusy: false
  property bool maintenanceHandoffBusy: false

  // Generation counters for stale-callback rejection
  property int statusGeneration: 0
  property int settingsGeneration: 0
  property int versionProbeGeneration: 0
  property int settingsBootstrapGeneration: 0
  property int maintenanceCheckGeneration: 0
  property int maintenanceHandoffGeneration: 0
  property int activeVersionProbeGeneration: 0
  property int activeStatusGeneration: 0
  property int activeSettingsReadGeneration: 0
  property int activeSettingsBootstrapGeneration: 0
  property int activeSettingsWriteGeneration: 0
  property int activeMaintenanceCheckGeneration: 0
  property int activeMaintenanceHandoffGeneration: 0
  property int versionProbeStartedGeneration: 0
  property int statusStartedGeneration: 0
  property int settingsReadStartedGeneration: 0
  property int settingsBootstrapStartedGeneration: 0
  property int settingsWriteStartedGeneration: 0
  property int maintenanceCheckStartedGeneration: 0
  property int maintenanceHandoffStartedGeneration: 0
  // Immutable captured JSON for the in-flight config apply (SET-018).
  property string pendingSettingsPayload: ""
  property int pendingSettingsPayloadGeneration: 0

  // Bookkeeping
  property int refreshRequestCount: 0
  property string lastRefreshProviderId: ""
  property int statusStartCount: 0
  property int settingsSaveCount: 0
  property bool pollEnabled: true

  readonly property string manifestVersion: manifest && manifest.version
      ? String(manifest.version)
      : ""

  // -------------------------------------------------------------------------
  // Paths / IPC
  // -------------------------------------------------------------------------

  function resolvedHelperPath() {
    if (helperPath && helperPath.length > 0)
      return helperPath
    // Prefer live manifest.__sourceDir over pluginRoot: Quattro sets `manifest`
    // after createObject, and onManifestChanged can run before the pluginRoot
    // binding re-evaluates (nested JS field access is not a QML property).
    var root = ""
    if (manifest && manifest.__sourceDir)
      root = String(manifest.__sourceDir)
    else if (pluginRoot && pluginRoot.length > 0)
      root = pluginRoot
    if (root && root.length > 0)
      return root + "/bin/agent-bar"
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

  function recordLaneTimeout(lane, generation) {
    timedOutLanes = Core.recordLaneTimeout(timedOutLanes, lane)
    if (generation !== undefined)
      settledLanes = Core.settleLane(settledLanes, lane, generation)
  }

  function recordCompletedCallback(fromTimeout, lane) {
    if (fromTimeout)
      return
    settledLanes = Core.clearSettledLane(settledLanes, lane)
    completedCallbackCount++
    timedOutLanes = ({})
  }

  function shouldApplyProcessExit(lane, generation, activeGeneration) {
    if (Core.isLaneSettled(settledLanes, lane, generation)) {
      settledLanes = Core.clearSettledLane(settledLanes, lane, generation)
      timedOutLanes = Core.clearLaneTimeout(timedOutLanes, lane)
      return false
    }
    return Core.shouldApplyGeneration(activeGeneration, generation)
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

  // -------------------------------------------------------------------------
  // Public methods
  // -------------------------------------------------------------------------

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
    // SET-019: closing never fabricates load/save completion.
    if (!popupOwner && !Settings.settingsShouldRetainOnClose(settingsState)) {
      settingsState = Settings.settingsClosed()
      settingsDraft = null
    }
  }

  // Outside-click on any monitor (including foreign-monitor dismiss layer).
  function dismissPopup() {
    popupOwner = Core.dismissPopup(popupOwner)
    if (!popupOwner && !Settings.settingsShouldRetainOnClose(settingsState)) {
      settingsState = Settings.settingsClosed()
      settingsDraft = null
    }
  }

  function openSettings(owner) {
    if (maintenanceState.blocked)
      return
    requestPopup(owner, selectedProviderId || null, "settings")
    // SET-014/020: only start a new load when closed; reopen during save keeps busy.
    if (!settingsState || settingsState.phase === "closed") {
      settingsGeneration++
      activeSettingsReadGeneration = settingsGeneration
      settingsState = Settings.settingsBeginLoad(settingsGeneration)
      settingsDraft = null
      kickSettingsRead()
    }
  }

  // ---- Draft mutations (dirty only when unlocked) ----

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
    // Keep draft pointer on state for consumers that read settingsState.draft.
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
    if (!Core.canStartLane(settingsWriteBusy))
      return false
    // SET-018: capture immutable payload before process start.
    var payloadObj = JSON.parse(JSON.stringify(settingsDraft))
    var validation = Settings.validateSettingsDraft(payloadObj)
    if (!validation.ok)
      return false
    // SET-016: every save gets a new generation id.
    settingsGeneration++
    var gen = settingsGeneration
    pendingSettingsPayload = JSON.stringify(payloadObj)
    pendingSettingsPayloadGeneration = gen
    settingsState = Settings.settingsBeginSave(settingsState, gen, payloadObj)
    settingsDraft = settingsState.draft
    activeSettingsWriteGeneration = gen
    settingsSaveCount++
    kickSettingsWrite()
    return true
  }

  // JSON-025: map closed action kinds to typed service methods.
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
    // Exact argv array — never shell-string construction (UX-048).
    Quickshell.execDetached(argv)
  }

  // ---- Maintenance UI (update / uninstall) ----

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
    if (maintenanceState.blocked)
      return
    if (!Core.canStartLane(maintenanceCheckBusy))
      return
    syncMaintenanceVersion()
    maintenanceCheckGeneration++
    activeMaintenanceCheckGeneration = maintenanceCheckGeneration
    maintenanceUi = Maintenance.maintenanceUiChecking(maintenanceUi)
    maintenanceCheckBusy = true
    maintenanceCheckTimeout.restart()
    var helper = resolvedHelperPath()
    if (!helper.length) {
      maintenanceCheckBusy = false
      maintenanceUi = Maintenance.maintenanceUiFromCheck(maintenanceUi, "", 1, helperVersion)
      return
    }
    maintenanceCheckProcess.command = Maintenance.updateCheckArgv(helper)
    maintenanceCheckStartedGeneration = activeMaintenanceCheckGeneration
    if (testMode) {
      return
    }
    maintenanceCheckProcess.running = true
  }

  function applyUpdateCheckResult(generation, stdout, exitCode, fromTimeout) {
    if (!Core.shouldApplyGeneration(activeMaintenanceCheckGeneration, generation))
      return
    maintenanceCheckTimeout.stop()
    maintenanceCheckBusy = false
    recordCompletedCallback(!!fromTimeout, "maintenanceCheck")
    maintenanceUi = Maintenance.maintenanceUiFromCheck(
      maintenanceUi,
      stdout,
      exitCode,
      helperVersion || manifestVersion
    )
  }

  function openUpdateConfirm() {
    maintenanceUi = Maintenance.maintenanceUiOpenUpdateConfirm(maintenanceUi)
  }

  function closeUpdateConfirm() {
    maintenanceUi = Maintenance.maintenanceUiCloseUpdateConfirm(maintenanceUi)
  }

  function confirmUpdateApply() {
    if (!maintenanceUi || !maintenanceUi.targetVersion)
      return false
    var intention = Maintenance.maintenanceIntention("update_apply", maintenanceUi)
    if (!intention || !intention.version.length)
      return false
    pendingMaintenanceIntention = intention
    pendingMaintenancePayload = ""
    maintenanceUi = Maintenance.maintenanceUiApplying(maintenanceUi)
    beginMaintenanceHandoff()
    return true
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

  // UX-047: first click arms, second confirms.
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

  function viewInstallation(providerId, url) {
    if (!Core.isClosedProvider(providerId))
      return
    var target = String(url || "")
    if (target.indexOf("https://") !== 0)
      return
    lastViewInstallationUrl = target
    Qt.openUrlExternally(target)
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

  // -------------------------------------------------------------------------
  // Version probe lane
  // -------------------------------------------------------------------------

  function applyVersionProbeResult(generation, stdout, stderr, exitCode, fromTimeout) {
    if (!Core.shouldApplyGeneration(activeVersionProbeGeneration, generation))
      return
    recordCompletedCallback(!!fromTimeout, "versionProbe")
    var version = Core.parseVersionStdout(stdout, stderr, exitCode)
    if (version)
      finishVersionProbeSuccess(version)
    else
      finishVersionProbeFailure()
  }

  // Quattro injects `manifest` (and thus pluginRoot) after createObject returns.
  // The completed handler therefore often runs with an empty helper path; do not
  // treat that as a permanent probe failure — retry when the path appears.
  function tryStartProduction() {
    if (testMode)
      return
    if (versionReady || versionProbeRunning)
      return
    if (!resolvedHelperPath().length)
      return
    startVersionProbe()
  }

  function startVersionProbe() {
    if (versionProbeRunning || versionReady)
      return
    if (testMode)
      return
    if (!Core.canStartLane(versionProbeRunning))
      return
    var helper = resolvedHelperPath()
    if (!helper.length) {
      // Empty path is expected before Quattro property injection; wait for
      // onManifestChanged / onHelperPathChanged rather than locking out.
      return
    }
    versionProbeRunning = true
    versionFailed = false
    versionProbeGeneration++
    activeVersionProbeGeneration = versionProbeGeneration
    // StdioCollector.text is read-only; waitForEnd replaces content per run.
    versionProbe.command = [helper, "version"]
    versionProbeStartedGeneration = activeVersionProbeGeneration
    versionProbe.running = true
    versionTimeout.restart()
  }

  function finishVersionProbeSuccess(versionText) {
    versionTimeout.stop()
    versionProbeRunning = false
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
    versionTimeout.stop()
    versionProbeRunning = false
    versionReady = false
    versionFailed = true
    helperVersion = ""
  }

  function beginCollection() {
    collectionStarted = true
    pollTimer.restart()
    kickStatus()
  }

  // -------------------------------------------------------------------------
  // Status lane
  // -------------------------------------------------------------------------

  function kickStatus() {
    if (!versionReady || versionFailed)
      return
    if (maintenanceState.blocked)
      return
    if (!Core.canStartLane(statusBusy))
      return
    var helper = resolvedHelperPath()
    if (!helper.length)
      return

    statusGeneration++
    var gen = statusGeneration
    activeStatusGeneration = gen
    var targets = Core.takePending(pendingForcedTargets)
    pendingForcedTargets = targets.remaining
    var argv = Core.statusArgv(helper, targets.captured)
    var request = {
      generation: gen,
      argv: argv.slice(),
      forced: targets.captured
    }

    statusBusy = true
    refreshing = true
    statusStartCount++
    statusTimeout.restart()
    // StdioCollector.text is read-only; waitForEnd replaces content per run.
    statusProcess.command = argv
    statusStartedGeneration = gen
    if (testMode) {
      // Tests call applyStatusResult(gen, stdout, stderr, code)
      return
    }
    statusProcess.running = true
  }

  function applyStatusResult(generation, stdout, stderr, exitCode, fromTimeout) {
    if (!Core.shouldApplyGeneration(activeStatusGeneration, generation))
      return
    statusTimeout.stop()
    statusBusy = false
    refreshing = false
    recordCompletedCallback(!!fromTimeout, "status")

    if (exitCode !== 0) {
      // Keep last snapshot (CACHE-021 / malformed retention).
      maybeFollowUpStatus()
      return
    }
    var parsed = Core.parseStatusEnvelope(stdout, helperVersion)
    if (!parsed.ok) {
      // Malformed envelope: retain previous snapshot.
      maybeFollowUpStatus()
      return
    }
    // Immutable replacement.
    snapshot = parsed.envelope
    maybeFollowUpStatus()
  }

  function maybeFollowUpStatus() {
    if (!pendingIsEmptySafe())
      kickStatus()
  }

  function pendingIsEmptySafe() {
    return Core.pendingIsEmpty(pendingForcedTargets)
  }

  // -------------------------------------------------------------------------
  // Settings lanes (read / write)
  // -------------------------------------------------------------------------

  // SET-023: adopt persisted settings at service start. Reads only — the
  // dialog state machine (SET-014..022) keeps its own snapshot untouched.
  function kickSettingsBootstrap() {
    if (appliedSettings || settingsBootstrapBusy || maintenanceState.blocked)
      return
    var helper = resolvedHelperPath()
    if (!helper.length)
      return
    settingsBootstrapGeneration++
    activeSettingsBootstrapGeneration = settingsBootstrapGeneration
    settingsBootstrapBusy = true
    settingsBootstrapTimeout.restart()
    settingsBootstrapProcess.command = Settings.settingsArgvShow(helper)
    settingsBootstrapStartedGeneration = activeSettingsBootstrapGeneration
    if (testMode) {
      return
    }
    settingsBootstrapProcess.running = true
  }

  function applySettingsBootstrapResult(generation, stdout, exitCode, fromTimeout) {
    if (!Core.shouldApplyGeneration(activeSettingsBootstrapGeneration, generation))
      return
    settingsBootstrapTimeout.stop()
    settingsBootstrapBusy = false
    recordCompletedCallback(!!fromTimeout, "settingsBootstrap")
    appliedSettings = Settings.settingsBootstrapResult(appliedSettings, stdout, exitCode)
  }

  function kickSettingsRead() {
    // ARCH-024: maintenance rejects new writes/polling; reads may still start.
    if (!Core.canStartLane(settingsReadBusy))
      return
    var helper = resolvedHelperPath()
    if (!helper.length)
      return
    settingsReadBusy = true
    settingsReadTimeout.restart()
    settingsReadProcess.command = Settings.settingsArgvShow(helper)
    settingsReadStartedGeneration = activeSettingsReadGeneration
    if (testMode) {
      return
    }
    settingsReadProcess.running = true
  }

  function applySettingsReadResult(generation, stdout, exitCode, fromTimeout) {
    if (!Core.shouldApplyGeneration(activeSettingsReadGeneration, generation))
      return
    settingsReadTimeout.stop()
    settingsReadBusy = false
    recordCompletedCallback(!!fromTimeout, "settingsRead")
    if (!settingsState || settingsState.phase === "closed")
      return
    // SET-026: any failure is a visible terminal state, never an endless
    // locked "Loading". The helper's message is not shown (plain-text rule);
    // the dialog renders its own fixed copy.
    if (exitCode !== 0) {
      settingsState = Settings.settingsFailLoad(settingsState, generation)
      settingsDraft = null
      return
    }
    var doc = null
    try {
      doc = JSON.parse(String(stdout || "").trim())
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
    if (!Core.canStartLane(settingsWriteBusy))
      return
    if (maintenanceState.blocked)
      return
    var helper = resolvedHelperPath()
    if (!helper.length)
      return
    settingsWriteBusy = true
    settingsWriteTimeout.restart()
    // Re-arm stdin: each save closes it after writing (EOF delivery below).
    settingsWriteProcess.stdinEnabled = true
    settingsWriteProcess.command = Settings.settingsArgvApplyStdin(helper)
    settingsWriteStartedGeneration = activeSettingsWriteGeneration
    if (testMode) {
      return
    }
    settingsWriteProcess.running = true
  }

  function applySettingsWriteResult(generation, ok, canonical, fromTimeout) {
    if (!Core.shouldApplyGeneration(activeSettingsWriteGeneration, generation))
      return
    settingsWriteTimeout.stop()
    settingsWriteBusy = false
    recordCompletedCallback(!!fromTimeout, "settingsWrite")
    if (pendingSettingsPayloadGeneration === generation) {
      pendingSettingsPayload = ""
      pendingSettingsPayloadGeneration = 0
    }
    settingsState = Settings.settingsFinishSave(settingsState, generation, ok, canonical)
    settingsDraft = settingsState ? settingsState.draft : null
    if (ok && canonical)
      appliedSettings = canonical
    tryMaintenanceDetach()
  }

  // -------------------------------------------------------------------------
  // Maintenance handoff
  // -------------------------------------------------------------------------

  function beginMaintenanceHandoff() {
    maintenanceState = Maintenance.maintenanceBeginHandoff(maintenanceState)
    pollEnabled = false
    pollTimer.stop()
    tryMaintenanceDetach()
  }

  function tryMaintenanceDetach() {
    if (!Maintenance.maintenanceCanDetach(maintenanceState, statusBusy, settingsWriteBusy))
      return
    if (!Core.canStartLane(maintenanceHandoffBusy))
      return
    maintenanceHandoffGeneration++
    activeMaintenanceHandoffGeneration = maintenanceHandoffGeneration
    maintenanceHandoffBusy = true
    maintenanceHandoffTimeout.restart()
    var helper = resolvedHelperPath()
    var intention = pendingMaintenanceIntention
    var argv = null
    if (intention && intention.kind === "update_apply")
      argv = Maintenance.updateApplyArgv(helper)
    else if (intention && intention.kind === "uninstall")
      argv = Maintenance.uninstallArgv(helper, intention.purge)
    else
      argv = helper && helper.length ? [helper, "doctor", "scan"] : null

    if (!argv) {
      maintenanceHandoffBusy = false
      return
    }
    // Uninstall confirmation document is written on stdin (BUNDLE-036).
    if (intention && intention.kind === "uninstall" && pendingMaintenancePayload.length) {
      maintenanceHandoffProcess.stdinEnabled = true
    } else {
      maintenanceHandoffProcess.stdinEnabled = false
    }
    maintenanceHandoffProcess.command = argv
    maintenanceHandoffStartedGeneration = activeMaintenanceHandoffGeneration
    if (testMode) {
      return
    }
    maintenanceHandoffProcess.running = true
  }

  function applyMaintenanceHandoffDone(generation, exitCode, fromTimeout) {
    if (!Core.shouldApplyGeneration(activeMaintenanceHandoffGeneration, generation))
      return
    maintenanceHandoffTimeout.stop()
    maintenanceHandoffBusy = false
    recordCompletedCallback(!!fromTimeout, "maintenanceHandoff")
    var intention = pendingMaintenanceIntention
    pendingMaintenanceIntention = null
    pendingMaintenancePayload = ""
    maintenanceState = Maintenance.maintenanceIdle()
    pollEnabled = true
    if (versionReady)
      pollTimer.restart()
    if (intention && intention.kind === "update_apply") {
      if (exitCode === 0) {
        maintenanceUi = Maintenance.maintenanceUiIdle(helperVersion || intention.version)
        maintenanceUi.message = "Update applied."
      } else {
        maintenanceUi = Maintenance.cloneMaintenanceUi(maintenanceUi)
        maintenanceUi.phase = "error"
        maintenanceUi.message = "Update failed."
      }
    } else if (intention && intention.kind === "uninstall") {
      if (exitCode === 0) {
        maintenanceUi = Maintenance.maintenanceUiIdle(helperVersion)
        maintenanceUi.message = "Uninstall completed."
      } else {
        maintenanceUi = Maintenance.cloneMaintenanceUi(maintenanceUi)
        maintenanceUi.phase = "error"
        maintenanceUi.message = "Uninstall failed."
      }
    }
  }

  function versionProbeExited(exitCode, generation, stdout, stderr) {
    var gen = generation === undefined ? versionProbeStartedGeneration : generation
    if (!shouldApplyProcessExit("versionProbe", gen, activeVersionProbeGeneration))
      return
    applyVersionProbeResult(gen,
                            stdout === undefined ? versionOut.text || "" : stdout,
                            stderr === undefined ? versionErr.text || "" : stderr,
                            exitCode)
  }

  function statusExited(exitCode, generation, stdout, stderr) {
    var gen = generation === undefined ? statusStartedGeneration : generation
    if (!shouldApplyProcessExit("status", gen, activeStatusGeneration))
      return
    applyStatusResult(gen,
                      stdout === undefined ? statusOut.text || "" : stdout,
                      stderr === undefined ? statusErr.text || "" : stderr,
                      exitCode)
  }

  function settingsReadExited(exitCode, generation, stdout) {
    var gen = generation === undefined ? settingsReadStartedGeneration : generation
    if (!shouldApplyProcessExit("settingsRead", gen, activeSettingsReadGeneration))
      return
    applySettingsReadResult(gen,
                            stdout === undefined ? settingsReadOut.text || "" : stdout,
                            exitCode)
  }

  function settingsBootstrapExited(exitCode, generation, stdout) {
    var gen = generation === undefined ? settingsBootstrapStartedGeneration : generation
    if (!shouldApplyProcessExit("settingsBootstrap", gen, activeSettingsBootstrapGeneration))
      return
    applySettingsBootstrapResult(
      gen,
      stdout === undefined ? settingsBootstrapOut.text || "" : stdout,
      exitCode
    )
  }

  function settingsWriteExited(exitCode, generation, stdout) {
    var gen = generation === undefined ? settingsWriteStartedGeneration : generation
    if (!shouldApplyProcessExit("settingsWrite", gen, activeSettingsWriteGeneration))
      return
    var ok = exitCode === 0
    var canonical = null
    if (ok) {
      try {
        var output = stdout === undefined ? settingsWriteOut.text || "" : stdout
        canonical = JSON.parse(String(output).trim())
        if (!Settings.validateSettingsDraft(canonical).ok)
          ok = false
      } catch (e) {
        ok = false
      }
    }
    applySettingsWriteResult(gen, ok, canonical)
  }

  function maintenanceCheckExited(exitCode, generation, stdout) {
    var gen = generation === undefined ? maintenanceCheckStartedGeneration : generation
    if (!shouldApplyProcessExit("maintenanceCheck", gen, activeMaintenanceCheckGeneration))
      return
    applyUpdateCheckResult(
      gen,
      stdout === undefined ? maintenanceCheckOut.text || "" : stdout,
      exitCode
    )
  }

  function maintenanceHandoffExited(exitCode, generation) {
    var gen = generation === undefined ? maintenanceHandoffStartedGeneration : generation
    if (!shouldApplyProcessExit("maintenanceHandoff", gen, activeMaintenanceHandoffGeneration))
      return
    applyMaintenanceHandoffDone(gen, exitCode)
  }

  // -------------------------------------------------------------------------
  // Processes (isolated lanes)
  // -------------------------------------------------------------------------

  Process {
    id: versionProbe
    stdout: StdioCollector { id: versionOut; waitForEnd: true }
    stderr: StdioCollector { id: versionErr; waitForEnd: true }
    onExited: function (exitCode) { root.versionProbeExited(exitCode) }
  }

  Process {
    id: statusProcess
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function (exitCode) { root.statusExited(exitCode) }
  }

  Process {
    id: settingsReadProcess
    stdout: StdioCollector { id: settingsReadOut; waitForEnd: true }
    stderr: StdioCollector { id: settingsReadErr; waitForEnd: true }
    onExited: function (exitCode) { root.settingsReadExited(exitCode) }
  }

  Process {
    id: settingsBootstrapProcess
    stdout: StdioCollector { id: settingsBootstrapOut; waitForEnd: true }
    stderr: StdioCollector { id: settingsBootstrapErr; waitForEnd: true }
    onExited: function (exitCode) { root.settingsBootstrapExited(exitCode) }
  }

  Process {
    id: settingsWriteProcess
    stdinEnabled: true
    stdout: StdioCollector { id: settingsWriteOut; waitForEnd: true }
    stderr: StdioCollector { id: settingsWriteErr; waitForEnd: true }
    onStarted: {
      // Write the immutable captured payload; never re-read live draft (SET-018).
      // config apply stdin reads until EOF — write() alone does not deliver it;
      // stdinEnabled=false closes the write channel (same as maintenance handoff).
      if (root.pendingSettingsPayloadGeneration === root.settingsWriteStartedGeneration
          && root.pendingSettingsPayload && root.pendingSettingsPayload.length) {
        write(root.pendingSettingsPayload + "\n")
        settingsWriteProcess.stdinEnabled = false
      }
    }
    onExited: function (exitCode) { root.settingsWriteExited(exitCode) }
  }

  Process {
    id: maintenanceCheckProcess
    stdout: StdioCollector { id: maintenanceCheckOut; waitForEnd: true }
    stderr: StdioCollector { id: maintenanceCheckErr; waitForEnd: true }
    onExited: function (exitCode) { root.maintenanceCheckExited(exitCode) }
  }

  Process {
    id: maintenanceHandoffProcess
    stdinEnabled: false
    stdout: StdioCollector { id: maintenanceHandoffOut; waitForEnd: true }
    stderr: StdioCollector { id: maintenanceHandoffErr; waitForEnd: true }
    onStarted: {
      // BUNDLE-036 / UX-048: non-TTY uninstall confirmation uses read_to_end.
      // write() alone does not deliver EOF; stdinEnabled=false closes the write channel.
      if (root.pendingMaintenancePayload && root.pendingMaintenancePayload.length
          && maintenanceHandoffProcess.stdinEnabled) {
        write(root.pendingMaintenancePayload + "\n")
        maintenanceHandoffProcess.stdinEnabled = false
      }
    }
    onExited: function (exitCode) { root.maintenanceHandoffExited(exitCode) }
  }

  // Single completed handler — QML rejects duplicate assignments of this
  // handler (live Quattro: "Property value set multiple times" at service load).

  Timer {
    id: versionTimeout
    interval: root.versionProbeTimeoutMs
    repeat: false
    onTriggered: {
      if (!root.versionProbeRunning)
        return
      if (versionProbe.running)
        versionProbe.running = false
      root.recordLaneTimeout("versionProbe", root.activeVersionProbeGeneration)
      root.applyVersionProbeResult(root.activeVersionProbeGeneration, "", "timeout", 1, true)
    }
  }

  Timer {
    id: statusTimeout
    interval: root.statusTimeoutMs
    repeat: false
    onTriggered: {
      if (!root.statusBusy)
        return
      if (statusProcess.running)
        statusProcess.running = false
      root.recordLaneTimeout("status", root.activeStatusGeneration)
      root.applyStatusResult(root.activeStatusGeneration, "", "timeout", 1, true)
    }
  }

  Timer {
    id: settingsReadTimeout
    interval: root.settingsTimeoutMs
    repeat: false
    onTriggered: {
      if (!root.settingsReadBusy)
        return
      if (settingsReadProcess.running)
        settingsReadProcess.running = false
      root.recordLaneTimeout("settingsRead", root.activeSettingsReadGeneration)
      root.applySettingsReadResult(root.activeSettingsReadGeneration, "", 1, true)
    }
  }

  Timer {
    id: settingsBootstrapTimeout
    interval: root.settingsTimeoutMs
    repeat: false
    onTriggered: {
      if (!root.settingsBootstrapBusy)
        return
      if (settingsBootstrapProcess.running)
        settingsBootstrapProcess.running = false
      root.recordLaneTimeout("settingsBootstrap", root.activeSettingsBootstrapGeneration)
      root.applySettingsBootstrapResult(root.activeSettingsBootstrapGeneration, "", 1, true)
    }
  }

  Timer {
    id: settingsWriteTimeout
    interval: root.settingsTimeoutMs
    repeat: false
    onTriggered: {
      if (!root.settingsWriteBusy)
        return
      if (settingsWriteProcess.running)
        settingsWriteProcess.running = false
      root.recordLaneTimeout("settingsWrite", root.activeSettingsWriteGeneration)
      root.applySettingsWriteResult(root.activeSettingsWriteGeneration, false, null, true)
    }
  }

  Timer {
    id: maintenanceCheckTimeout
    interval: root.maintenanceCheckTimeoutMs
    repeat: false
    onTriggered: {
      if (!root.maintenanceCheckBusy)
        return
      if (maintenanceCheckProcess.running)
        maintenanceCheckProcess.running = false
      root.recordLaneTimeout("maintenanceCheck", root.activeMaintenanceCheckGeneration)
      root.applyUpdateCheckResult(root.activeMaintenanceCheckGeneration, "", 1, true)
    }
  }

  Timer {
    id: maintenanceHandoffTimeout
    interval: root.maintenanceHandoffTimeoutMs
    repeat: false
    onTriggered: {
      if (!root.maintenanceHandoffBusy)
        return
      if (maintenanceHandoffProcess.running)
        maintenanceHandoffProcess.running = false
      root.recordLaneTimeout("maintenanceHandoff", root.activeMaintenanceHandoffGeneration)
      root.applyMaintenanceHandoffDone(root.activeMaintenanceHandoffGeneration, 1, true)
    }
  }

  Timer {
    id: collectionDelay
    repeat: false
    onTriggered: root.beginCollection()
  }

  // One automatic poll timer (CACHE-005).
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
    versionTimeout.stop()
    statusTimeout.stop()
    settingsReadTimeout.stop()
    settingsBootstrapTimeout.stop()
    settingsWriteTimeout.stop()
    maintenanceCheckTimeout.stop()
    maintenanceHandoffTimeout.stop()
    collectionDelay.stop()
    pollTimer.stop()
    if (versionProbe.running)
      versionProbe.running = false
    if (statusProcess.running)
      statusProcess.running = false
    if (settingsReadProcess.running)
      settingsReadProcess.running = false
    if (settingsBootstrapProcess.running)
      settingsBootstrapProcess.running = false
    if (settingsWriteProcess.running)
      settingsWriteProcess.running = false
    if (maintenanceCheckProcess.running)
      maintenanceCheckProcess.running = false
    if (maintenanceHandoffProcess.running)
      maintenanceHandoffProcess.running = false
  }
}
