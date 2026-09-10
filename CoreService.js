.pragma library

var CLOSED_PROVIDERS = {
  "claude": true,
  "codex": true,
  "amp": true,
  "grok": true,
  "antigravity": true
}

var ACTION_KINDS = {
  "retry": true,
  "login": true,
  "view_installation": true
}

var PROVIDER_STATES = {
  "ready": true,
  "stale": true,
  "cli_missing": true,
  "unauthenticated": true,
  "rate_limited": true,
  "network_error": true,
  "provider_error": true
}

function pluginRootFromUrl(url) {
  var text = String(url || "")
  if (text.indexOf("file://") !== 0)
    return ""
  var path = decodeURIComponent(text.slice("file://".length))
  while (path.length > 1 && path.charAt(path.length - 1) === "/")
    path = path.slice(0, -1)
  return path
}

function health(versionReady, versionFailed, helperVersion, manifestVersion, expectedVersion, runtimeHealthValue) {
  if (runtimeHealthValue === "stalled")
    return "stalled"
  var expected = String(expectedVersion || "")
  if (!versionReady || versionFailed)
    return "unknown"
  if (String(helperVersion) === expected && String(manifestVersion) === expected)
    return "ok"
  return "unknown"
}

function runtimeHealth(timedOutLanes) {
  var count = 0
  for (var lane in (timedOutLanes || {})) {
    if (timedOutLanes[lane])
      count++
  }
  return count >= 2 ? "stalled" : "ok"
}

function recordLaneTimeout(timedOutLanes, lane) {
  var next = {}
  for (var key in (timedOutLanes || {}))
    next[key] = !!timedOutLanes[key]
  next[String(lane)] = true
  return next
}

function clearLaneTimeout(timedOutLanes, lane) {
  var next = {}
  for (var key in (timedOutLanes || {})) {
    if (key !== String(lane))
      next[key] = !!timedOutLanes[key]
  }
  return next
}

function settleLane(settledLanes, lane, generation) {
  var next = {}
  for (var key in (settledLanes || {}))
    next[key] = settledLanes[key]
  next[String(lane)] = Number(generation)
  return next
}

function isLaneSettled(settledLanes, lane, generation) {
  if (!settledLanes)
    return false
  var key = String(lane)
  return Object.prototype.hasOwnProperty.call(settledLanes, key)
      && Number(settledLanes[key]) === Number(generation)
}

function clearSettledLane(settledLanes, lane, generation) {
  if (generation !== undefined && !isLaneSettled(settledLanes, lane, generation))
    return settledLanes || {}
  var next = {}
  for (var key in settledLanes) {
    if (key !== String(lane))
      next[key] = settledLanes[key]
  }
  return next
}

function isClosedProvider(providerId) {
  return !!CLOSED_PROVIDERS[String(providerId || "")]
}

// QML property-var interop: nested arrays become array-like QVariantList where
// Array.isArray is false but .length and numeric keys still work.
function isArrayLike(value) {
  if (Array.isArray(value))
    return true
  return !!(value && typeof value === "object" && typeof value.length === "number")
}

function refreshResult(providerId) {
  if (!isClosedProvider(providerId))
    return "unknown"
  return "ok"
}

function parseVersionStdout(stdout, stderr, exitCode) {
  if (exitCode !== 0)
    return null
  if (stderr && String(stderr).length > 0)
    return null
  var m = String(stdout || "").match(/^(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)\n$/)
  return m ? m[1] : null
}

function emptyPending() {
  return { all: false, ids: {} }
}

function clonePending(pending) {
  var next = emptyPending()
  if (!pending)
    return next
  next.all = !!pending.all
  if (pending.ids) {
    for (var k in pending.ids)
      next.ids[k] = true
  }
  return next
}

function pendingIsEmpty(pending) {
  if (!pending)
    return true
  if (pending.all)
    return false
  for (var k in pending.ids)
    return false
  return true
}

function unionForced(pending, providerIdOrAll) {
  var next = clonePending(pending)
  if (providerIdOrAll === "all" || providerIdOrAll === true) {
    next.all = true
    next.ids = {}
    return next
  }
  if (next.all)
    return next
  var id = String(providerIdOrAll || "")
  if (!isClosedProvider(id))
    return next
  next.ids[id] = true
  return next
}

function takePending(pending) {
  return {
    captured: clonePending(pending),
    remaining: emptyPending()
  }
}

function statusArgv(helperPath, forceOrTargets) {
  var cacheMode = "use"
  if (forceOrTargets === true || forceOrTargets === "all")
    cacheMode = "bypass"
  else if (forceOrTargets && forceOrTargets.all)
    cacheMode = "bypass"
  else if (forceOrTargets && forceOrTargets.ids) {
    for (var k in forceOrTargets.ids) {
      cacheMode = "bypass"
      break
    }
  }
  var argv = [
    helperPath,
    "status",
    "format", "json",
    "cache", cacheMode,
    "notifications", "evaluate"
  ]
  if (forceOrTargets && forceOrTargets.ids && !forceOrTargets.all) {
    var only = null
    var count = 0
    for (var id in forceOrTargets.ids) {
      only = id
      count++
    }
    if (count === 1) {
      argv.push("provider")
      argv.push(only)
    }
  }
  return argv
}

function isFinitePercent(n) {
  return typeof n === "number" && isFinite(n) && n >= 0 && n <= 100
}

function validateProvider(p) {
  if (!p || typeof p !== "object")
    return "provider not an object"
  if (!isClosedProvider(p.id))
    return "invalid provider id"
  if (!PROVIDER_STATES[p.state])
    return "invalid provider state"
  if (!Array.isArray(p.windows))
    return "windows not array"
  for (var i = 0; i < p.windows.length; i++) {
    var w = p.windows[i]
    if (!w || typeof w !== "object")
      return "window not object"
    if (!isFinitePercent(w.usedPercent) || !isFinitePercent(w.remainingPercent))
      return "invalid window percent"
    if (w.action && w.action.kind && !ACTION_KINDS[w.action.kind])
      return "invalid window action"
  }
  if (p.action && p.action.kind && !ACTION_KINDS[p.action.kind])
    return "invalid action kind"
  return null
}

function parseStatusEnvelope(stdout, expectedHelperVersion) {
  var text = String(stdout || "").trim()
  if (!text.length)
    return { ok: false, reason: "empty stdout" }
  var env
  try {
    env = JSON.parse(text)
  } catch (e) {
    return { ok: false, reason: "json parse failed" }
  }
  if (!env || typeof env !== "object")
    return { ok: false, reason: "not an object" }
  if (env.schemaVersion !== 2)
    return { ok: false, reason: "schemaVersion !== 2" }
  if (expectedHelperVersion && String(env.helperVersion) !== String(expectedHelperVersion))
    return { ok: false, reason: "helperVersion mismatch" }
  if (!Array.isArray(env.providers))
    return { ok: false, reason: "providers not array" }
  for (var i = 0; i < env.providers.length; i++) {
    var err = validateProvider(env.providers[i])
    if (err)
      return { ok: false, reason: err }
  }
  return { ok: true, envelope: env }
}

function shouldApplyGeneration(activeGeneration, callbackGeneration) {
  return activeGeneration === callbackGeneration
}

function requestPopup(current, owner, providerId, view) {
  var o = owner
  if (o === null || o === undefined)
    return current
  return {
    owner: o,
    providerId: providerId === null || providerId === undefined ? null : String(providerId),
    view: view ? String(view) : "usage"
  }
}

function closePopup(current, owner) {
  if (!current || current.owner === null || current.owner === undefined)
    return null
  if (current.owner !== owner)
    return current
  return null
}

function dismissPopup(_current) {
  return null
}

function foreignPopupOpen(popupOwner, selfOwner) {
  if (!popupOwner || popupOwner.owner === null || popupOwner.owner === undefined)
    return false
  if (selfOwner === null || selfOwner === undefined)
    return false
  return popupOwner.owner !== selfOwner
}

function popupOwnerId(popup) {
  return popup ? popup.owner : null
}

function popupOpenForOwner(popupOwner, owner) {
  if (!popupOwner || owner === null || owner === undefined)
    return false
  return popupOwner.owner === owner
}

function popupView(popupOwner) {
  if (!popupOwner || !popupOwner.view)
    return "usage"
  return String(popupOwner.view)
}

function canStartLane(laneBusy) {
  return !laneBusy
}

function pollIntervalMs(settings) {
  if (settings && settings.refreshIntervalSeconds)
    return Number(settings.refreshIntervalSeconds) * 1000
  return 60000
}

function defaultSettings() {
  return {
    schemaVersion: 1,
    providers: [
      { id: "claude", enabled: true },
      { id: "codex", enabled: true },
      { id: "amp", enabled: false },
      { id: "grok", enabled: false },
      { id: "antigravity", enabled: false }
    ],
    display: { metric: "remaining" },
    refreshIntervalSeconds: 60,
    notifications: { enabled: true, reminderMinutes: 120 },
    updates: { automatic: true }
  }
}

function automaticUpdatesEnabled(settings) {
  if (!settings || !settings.updates || typeof settings.updates.automatic !== "boolean")
    return true
  return settings.updates.automatic
}
