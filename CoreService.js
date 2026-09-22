.pragma library

// Order must match Rust's catalog::PROVIDERS (src/providers/catalog.rs).
var PROVIDERS = [
  { id: "claude", name: "Claude", icon: "claude.png", closed: true, defaultEnabled: true },
  { id: "codex", name: "Codex", icon: "codex.png", closed: true, defaultEnabled: true },
  { id: "grok", name: "Grok", icon: "grok.svg", closed: true, defaultEnabled: false },
  { id: "antigravity", name: "Antigravity", icon: "antigravity.png", closed: true, defaultEnabled: false }
]

var CLOSED_PROVIDERS = (function () {
  var out = {}
  for (var i = 0; i < PROVIDERS.length; i++) {
    if (PROVIDERS[i].closed)
      out[PROVIDERS[i].id] = true
  }
  return out
})()

var ACTION_KINDS = {
  "retry": true,
  "login": true,
  "view_installation": true
}

var RESET_RESULTS = {
  "reset": true,
  "already_used": true,
  "not_limited": true,
  "cooldown": true,
  "ineligible": true,
  "unavailable": true,
  "unauthenticated": true,
  "network_error": true,
  "provider_error": true
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

function runtimeHealth(stalledCount) {
  return stalledCount >= 2 ? "stalled" : "ok"
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

function isNonNegNumber(n) {
  return typeof n === "number" && isFinite(n) && n >= 0
}

function isNonNegIntOrNull(v) {
  if (v === null)
    return true
  return typeof v === "number" && isFinite(v) && v >= 0 && Math.floor(v) === v
}

function isIsoOrNull(v) {
  return v === null || typeof v === "string"
}

function validateReset(r) {
  if (!r || typeof r !== "object")
    return "reset not object"
  if (typeof r.id !== "string" || !r.id.length)
    return "invalid reset id"
  if (typeof r.label !== "string" || !r.label.length)
    return "invalid reset label"
  if (!isNonNegNumber(r.available))
    return "invalid reset available"
  if (!isNonNegIntOrNull(r.total))
    return "invalid reset total"
  if (!Array.isArray(r.clears))
    return "reset clears not array"
  for (var i = 0; i < r.clears.length; i++) {
    if (typeof r.clears[i] !== "string")
      return "invalid reset clears entry"
  }
  if (!isIsoOrNull(r.expiresAt))
    return "invalid reset expiresAt"
  if (!isIsoOrNull(r.refillsAt))
    return "invalid reset refillsAt"
  if (!isIsoOrNull(r.cooldownUntil))
    return "invalid reset cooldownUntil"
  if (typeof r.claimable !== "boolean")
    return "invalid reset claimable"
  return null
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
  if (!Array.isArray(p.resets))
    return "resets not array"
  for (var j = 0; j < p.resets.length; j++) {
    var resetErr = validateReset(p.resets[j])
    if (resetErr)
      return resetErr
  }
  if (p.action && p.action.kind && !ACTION_KINDS[p.action.kind])
    return "invalid action kind"
  return null
}

function resetArgv(helperPath, providerId, resetId) {
  return [String(helperPath), "reset", String(providerId), String(resetId)]
}

function parseResetOutcome(stdout) {
  var text = String(stdout || "").trim()
  if (!text.length)
    return { ok: false, reason: "empty stdout" }
  var doc
  try {
    doc = JSON.parse(text)
  } catch (e) {
    return { ok: false, reason: "json parse failed" }
  }
  if (!doc || typeof doc !== "object")
    return { ok: false, reason: "not an object" }
  if (doc.schemaVersion !== 1)
    return { ok: false, reason: "schemaVersion !== 1" }
  if (doc.operation !== "reset")
    return { ok: false, reason: "operation !== reset" }
  if (!RESET_RESULTS[doc.result])
    return { ok: false, reason: "invalid result" }
  if (doc.resetsLeft !== null && !isNonNegIntOrNull(doc.resetsLeft))
    return { ok: false, reason: "invalid resetsLeft" }
  if (!isIsoOrNull(doc.cooldownUntil))
    return { ok: false, reason: "invalid cooldownUntil" }
  if (!Array.isArray(doc.clears))
    return { ok: false, reason: "clears not array" }
  for (var i = 0; i < doc.clears.length; i++) {
    if (typeof doc.clears[i] !== "string")
      return { ok: false, reason: "invalid clears entry" }
  }
  return {
    ok: true,
    outcome: {
      provider: String(doc.provider || ""),
      resetId: String(doc.resetId || ""),
      result: String(doc.result),
      resetsLeft: doc.resetsLeft === null ? null : Number(doc.resetsLeft),
      cooldownUntil: doc.cooldownUntil === null ? null : String(doc.cooldownUntil),
      clears: doc.clears.map(function (c) { return String(c) })
    }
  }
}

function resetUiIdle() {
  return { confirmOpen: false, providerId: "", resetId: "", busy: false, outcome: null }
}

function resetUiOpenConfirm(providerId, resetId) {
  return {
    confirmOpen: true,
    providerId: String(providerId || ""),
    resetId: String(resetId || ""),
    busy: false,
    outcome: null
  }
}

function resetUiBusy(ui) {
  return {
    confirmOpen: false,
    providerId: ui ? String(ui.providerId || "") : "",
    resetId: ui ? String(ui.resetId || "") : "",
    busy: true,
    outcome: null
  }
}

function resetUiSettled(ui, outcome) {
  return {
    confirmOpen: false,
    providerId: ui ? String(ui.providerId || "") : "",
    resetId: ui ? String(ui.resetId || "") : "",
    busy: false,
    outcome: outcome || null
  }
}

function resetUiClearOutcome(ui) {
  if (!ui || !ui.outcome)
    return ui || resetUiIdle()
  return resetUiIdle()
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

function pollIntervalMs(settings) {
  if (settings && settings.refreshIntervalSeconds)
    return Number(settings.refreshIntervalSeconds) * 1000
  return 60000
}

function defaultSettings() {
  return {
    schemaVersion: 1,
    providers: PROVIDERS.map(function (p) {
      return { id: p.id, enabled: p.defaultEnabled }
    }),
    display: { metric: "remaining" },
    refreshIntervalSeconds: 60,
    notifications: { enabled: true, reminderMinutes: 120 }
  }
}
