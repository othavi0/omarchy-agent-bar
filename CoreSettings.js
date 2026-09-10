.pragma library
.import "CoreService.js" as Kernel

function settingsClosed() {
  return {
    phase: "closed",
    generation: 0,
    snapshot: null,
    draft: null,
    busy: false,
    pendingPayload: null
  }
}

function settingsBeginLoad(generation) {
  return {
    phase: "loading",
    generation: generation,
    snapshot: null,
    draft: null,
    busy: true,
    pendingPayload: null
  }
}

function settingsFinishLoad(state, generation, doc) {
  if (!state || state.generation !== generation)
    return state
  if (state.phase === "closed")
    return state
  if (state.phase !== "loading" && state.phase !== "clean")
    return state
  var copy = JSON.parse(JSON.stringify(doc))
  return {
    phase: "clean",
    generation: generation,
    snapshot: copy,
    draft: JSON.parse(JSON.stringify(copy)),
    busy: false,
    pendingPayload: null
  }
}

function settingsFailLoad(state, generation) {
  if (!state || state.generation !== generation)
    return state
  if (state.phase !== "loading")
    return state
  return {
    phase: "load_failed",
    generation: generation,
    snapshot: null,
    draft: null,
    busy: false,
    pendingPayload: null
  }
}

function settingsOpen(state, snapshot, generation) {
  return {
    phase: "clean",
    generation: generation,
    snapshot: snapshot,
    draft: JSON.parse(JSON.stringify(snapshot)),
    busy: false,
    pendingPayload: null
  }
}

function cloneState(state) {
  return {
    phase: state.phase,
    generation: state.generation,
    snapshot: state.snapshot,
    draft: state.draft,
    busy: state.busy,
    pendingPayload: state.pendingPayload
  }
}

function settingsControlsLocked(state) {
  if (!state)
    return true
  return state.phase === "closed" || state.phase === "loading"
    || state.phase === "load_failed" || state.phase === "saving" || !!state.busy
}

function settingsMarkDirty(state) {
  if (!state || state.phase === "closed" || state.phase === "loading"
      || state.phase === "load_failed" || state.phase === "saving")
    return state
  var next = cloneState(state)
  next.phase = "dirty"
  next.draft = state.draft
  return next
}

function settingsBeginSave(state, generation, payload) {
  if (!state || state.phase === "closed" || state.phase === "loading" || state.phase === "load_failed")
    return state
  if (state.phase === "saving")
    return state
  var next = cloneState(state)
  next.generation = generation
  next.phase = "saving"
  next.busy = true
  next.pendingPayload = payload
  return next
}

function settingsFinishSave(state, generation, ok, canonical) {
  if (!state || state.generation !== generation)
    return state
  if (state.phase !== "saving")
    return state
  var next = cloneState(state)
  next.busy = false
  next.pendingPayload = null
  if (ok) {
    next.snapshot = canonical
    next.draft = JSON.parse(JSON.stringify(canonical))
    next.phase = "clean"
  } else {
    next.phase = "dirty"
  }
  return next
}

function settingsCancel(state) {
  if (!state || state.phase === "closed" || state.phase === "loading" || state.phase === "load_failed")
    return state
  if (state.phase === "saving")
    return state
  if (!state.snapshot)
    return state
  var next = cloneState(state)
  next.draft = JSON.parse(JSON.stringify(state.snapshot))
  next.phase = "clean"
  next.busy = false
  return next
}

function settingsRestoreDefaults(state) {
  if (!state || state.phase === "closed" || state.phase === "loading"
      || state.phase === "load_failed" || state.phase === "saving")
    return state
  var next = cloneState(state)
  next.draft = Kernel.defaultSettings()
  next.phase = "dirty"
  return next
}

function settingsShouldRetainOnClose(state) {
  if (!state)
    return false
  return state.phase === "loading" || state.phase === "saving" || !!state.busy
}

function cloneDraft(draft) {
  return JSON.parse(JSON.stringify(draft || Kernel.defaultSettings()))
}

function setProviderEnabled(draft, providerId, enabled) {
  var next = cloneDraft(draft)
  var id = String(providerId || "")
  if (!Array.isArray(next.providers))
    next.providers = Kernel.defaultSettings().providers
  for (var i = 0; i < next.providers.length; i++) {
    if (String(next.providers[i].id) === id) {
      next.providers[i].enabled = !!enabled
      break
    }
  }
  return next
}

function moveProvider(draft, providerId, delta) {
  var next = cloneDraft(draft)
  var id = String(providerId || "")
  if (!Array.isArray(next.providers))
    return next
  var idx = -1
  for (var i = 0; i < next.providers.length; i++) {
    if (String(next.providers[i].id) === id) {
      idx = i
      break
    }
  }
  if (idx < 0)
    return next
  var target = idx + (delta > 0 ? 1 : -1)
  if (target < 0 || target >= next.providers.length)
    return next
  var tmp = next.providers[idx]
  next.providers[idx] = next.providers[target]
  next.providers[target] = tmp
  return next
}

function setDisplayMetric(draft, metric) {
  var next = cloneDraft(draft)
  if (!next.display)
    next.display = { metric: "remaining" }
  next.display.metric = metric === "used" ? "used" : "remaining"
  return next
}

function setRefreshInterval(draft, seconds) {
  var next = cloneDraft(draft)
  var n = Math.round(Number(seconds))
  if (!isFinite(n))
    n = 60
  next.refreshIntervalSeconds = n
  return next
}

function setNotificationsEnabled(draft, enabled) {
  var next = cloneDraft(draft)
  if (!next.notifications)
    next.notifications = { enabled: true }
  next.notifications.enabled = !!enabled
  return next
}

function setReminderMinutes(draft, minutes) {
  var next = cloneDraft(draft)
  if (!next.notifications)
    next.notifications = { enabled: true, reminderMinutes: 120 }
  var n = Math.round(Number(minutes))
  if (!isFinite(n))
    n = 120
  next.notifications.reminderMinutes = n
  return next
}

function setAutomaticUpdates(draft, enabled) {
  var next = cloneDraft(draft)
  next.updates = { automatic: !!enabled }
  return next
}

function validateSettingsDraft(draft) {
  if (!draft || typeof draft !== "object")
    return { ok: false, reason: "not an object" }
  if (draft.schemaVersion !== 1)
    return { ok: false, reason: "schemaVersion" }
  if (!draft.display || (draft.display.metric !== "used" && draft.display.metric !== "remaining"))
    return { ok: false, reason: "display.metric" }
  var interval = Number(draft.refreshIntervalSeconds)
  if (!isFinite(interval) || interval !== Math.floor(interval) || interval < 30 || interval > 3600)
    return { ok: false, reason: "refreshIntervalSeconds" }
  if (!draft.notifications || typeof draft.notifications.enabled !== "boolean")
    return { ok: false, reason: "notifications" }
  var reminder = Number(draft.notifications.reminderMinutes)
  if (!isFinite(reminder) || reminder !== Math.floor(reminder)
      || reminder < 15 || reminder > 1440)
    return { ok: false, reason: "notifications.reminderMinutes" }
  if (draft.updates !== undefined
      && (!draft.updates || typeof draft.updates.automatic !== "boolean"))
    return { ok: false, reason: "updates.automatic" }
  if (!Array.isArray(draft.providers))
    return { ok: false, reason: "providers length" }
  var seen = {}
  for (var i = 0; i < draft.providers.length; i++) {
    var p = draft.providers[i]
    if (!p || typeof p.id !== "string" || !p.id.length)
      return { ok: false, reason: "provider id" }
    if (seen[p.id])
      return { ok: false, reason: "duplicate provider" }
    seen[p.id] = true
    if (typeof p.enabled !== "boolean")
      return { ok: false, reason: "provider enabled" }
  }
  for (var id in Kernel.CLOSED_PROVIDERS) {
    if (!seen[id])
      return { ok: false, reason: "missing provider" }
  }
  return { ok: true, reason: null }
}

function settingsBootstrapResult(currentApplied, stdout, exitCode) {
  if (currentApplied)
    return currentApplied
  if (exitCode !== 0)
    return null
  try {
    var doc = JSON.parse(String(stdout || "").trim())
    if (!validateSettingsDraft(doc).ok)
      return null
    return doc
  } catch (e) {
    return null
  }
}

function settingsCanSave(state, draft) {
  if (!state)
    return false
  if (state.phase !== "dirty" && state.phase !== "clean")
    return false
  if (state.busy || state.phase === "saving" || state.phase === "loading")
    return false
  if (state.phase !== "dirty")
    return false
  return validateSettingsDraft(draft).ok
}

function settingsArgvShow(helperPath) {
  return [String(helperPath), "config", "show"]
}

function settingsArgvApplyStdin(helperPath) {
  return [String(helperPath), "config", "apply", "stdin"]
}
