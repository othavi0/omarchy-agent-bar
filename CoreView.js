.pragma library
.import "CoreService.js" as Kernel
.import "components/Tokens.js" as Tokens

function displayMetric(settings) {
  if (settings && settings.display && settings.display.metric === "used")
    return "used"
  return "remaining"
}

function findCatalogProvider(id) {
  var key = String(id || "")
  for (var i = 0; i < Kernel.PROVIDERS.length; i++) {
    if (Kernel.PROVIDERS[i].id === key)
      return Kernel.PROVIDERS[i]
  }
  return null
}

function providerDisplayName(id) {
  var entry = findCatalogProvider(id)
  return entry ? entry.name : String(id || "")
}

function iconFileName(id) {
  var entry = findCatalogProvider(id)
  return entry ? entry.icon : ""
}

function iconUrl(id) {
  var name = iconFileName(id)
  if (!name.length)
    return ""
  return Qt.resolvedUrl("icons/" + name)
}

function placeholderProvider(id) {
  var key = String(id || "")
  return {
    id: key,
    name: providerDisplayName(key),
    state: "loading",
    source: null,
    plan: null,
    windows: [],
    resets: [],
    lastSuccessAt: null,
    error: null,
    action: null
  }
}

function visibleProviders(snapshot, settings) {
  var byId = {}
  if (snapshot && Array.isArray(snapshot.providers)) {
    for (var i = 0; i < snapshot.providers.length; i++) {
      var p = snapshot.providers[i]
      if (p && p.id)
        byId[String(p.id)] = p
    }
  }

  var cfg = settings && Array.isArray(settings.providers) ? settings.providers : null
  if (!cfg) {
    var fromSnap = []
    if (snapshot && Array.isArray(snapshot.providers)) {
      for (var s = 0; s < snapshot.providers.length; s++)
        fromSnap.push(snapshot.providers[s])
    }
    return fromSnap
  }

  var out = []
  for (var j = 0; j < cfg.length; j++) {
    var item = cfg[j]
    if (!item || !item.enabled)
      continue
    var id = String(item.id || "")
    if (!Kernel.CLOSED_PROVIDERS[id])
      continue
    if (byId[id])
      out.push(byId[id])
    else
      out.push(placeholderProvider(id))
  }
  return out
}

function chipPercentText(provider, metric, nowMs) {
  var lines = windowDisplayLines(provider, metric, nowMs)
  var lead = electLeadIndex(lines)
  if (lead < 0)
    return "\u2014"
  return lines[lead].percentText
}

var ERROR_STATES = {
  "cli_missing": true,
  "unauthenticated": true,
  "rate_limited": true,
  "network_error": true,
  "provider_error": true
}

var SEVERITY_CRITICAL_USED_PERCENT = 95
var SEVERITY_WARNING_USED_PERCENT = 90

function severityLevel(usedPercent) {
  var v = Number(usedPercent)
  if (!isFinite(v))
    return ""
  if (v >= SEVERITY_CRITICAL_USED_PERCENT)
    return "critical"
  if (v >= SEVERITY_WARNING_USED_PERCENT)
    return "warning"
  return ""
}

function severityTagText(level) {
  if (level === "critical")
    return "Critical"
  if (level === "warning")
    return "Low"
  return ""
}

function providerSeverity(provider) {
  if (!provider || !Kernel.isArrayLike(provider.windows))
    return ""
  var worst = ""
  for (var i = 0; i < provider.windows.length; i++) {
    var w = provider.windows[i]
    if (!w)
      continue
    var level = severityLevel(w.usedPercent)
    if (level === "critical")
      return "critical"
    if (level === "warning")
      worst = "warning"
  }
  return worst
}

function presentsReading(state) {
  var s = String(state || "")
  return s === "ready" || s === "stale"
}

function chipSeverityUrgent(provider) {
  if (!provider)
    return false
  return presentsReading(provider.state)
      && providerSeverity(provider) === "critical"
}

function chipStateCue(provider) {
  if (!provider)
    return ""
  var state = String(provider.state || "")
  if (ERROR_STATES[state] || chipSeverityUrgent(provider))
    return Tokens.GLYPH_ALERT
  return ""
}

function chipCueLabel(provider) {
  if (!provider)
    return ""
  if (chipSeverityUrgent(provider))
    return "critical"
  var state = String(provider.state || "")
  if (ERROR_STATES[state])
    return stateQualifier(state)
  return ""
}

var STATE_QUALIFIERS = {
  "stale": "stale",
  "loading": "loading",
  "cli_missing": "no CLI",
  "unauthenticated": "signed out",
  "rate_limited": "rate limited",
  "network_error": "offline",
  "provider_error": "failed"
}

function stateQualifier(state) {
  var s = String(state || "")
  if (s === "ready")
    return ""
  if (STATE_QUALIFIERS[s] !== undefined)
    return STATE_QUALIFIERS[s]
  return "unknown"
}

function chipNumeralText(provider, metric, nowMs) {
  if (provider && String(provider.state || "") === "loading")
    return "···"
  return chipPercentText(provider, metric, nowMs)
}

function chipDimmed(provider) {
  if (!provider)
    return true
  return !presentsReading(provider.state)
}

function chipAccessibleLabel(provider, metric, nowMs) {
  if (!provider)
    return ""
  var name = provider.name ? String(provider.name) : providerDisplayName(provider.id)
  var parts = [name]
  var state = provider.state ? String(provider.state) : "unknown"
  var pct = chipPercentText(provider, metric, nowMs)
  if (pct !== "—" || presentsReading(state))
    parts.push(pct)
  if (!presentsReading(state)) {
    var qualifier = stateQualifier(state)
    if (qualifier.length)
      parts.push(qualifier)
  }
  return parts.join(" · ")
}

var SETTINGS_PROVIDER_STATUS = {
  "cli_missing": "Not installed",
  "unauthenticated": "Signed out",
  "rate_limited": "Rate limited",
  "network_error": "Offline",
  "provider_error": "Failed"
}

function settingsProviderStatus(provider) {
  if (!provider)
    return ""
  var s = String(provider.state || "")
  if (SETTINGS_PROVIDER_STATUS[s] !== undefined)
    return SETTINGS_PROVIDER_STATUS[s]
  if (presentsReading(s) && (!provider.windows || provider.windows.length === 0))
    return "No percentage"
  return ""
}

function iconOpticalScale(id) {
  if (String(id || "") === "grok")
    return 0.875
  return 1.0
}

function iconTinted(id) {
  var key = String(id || "")
  return key === "codex" || key === "grok"
}

// button: Qt.LeftButton(1) | RightButton(2) | MiddleButton(4) or string.
function routeChipClick(button, owner, providerId, popupOwner) {
  var b = button
  var isLeft = b === 1 || b === "left" || b === "LeftButton"
  var isRight = b === 2 || b === "right" || b === "RightButton"
  var isMiddle = b === 4 || b === "middle" || b === "MiddleButton"

  if (isMiddle)
    return { action: "refreshAll", force: true }
  if (isRight)
    return { action: "openSettings", owner: owner }
  if (isLeft) {
    var pid = String(providerId || "")
    if (popupOwner
        && popupOwner.owner === owner
        && String(popupOwner.providerId || "") === pid
        && (!popupOwner.view || popupOwner.view === "usage")) {
      return { action: "closePopup", owner: owner }
    }
    return {
      action: "requestPopup",
      owner: owner,
      providerId: pid,
      view: "usage"
    }
  }
  return { action: "noop" }
}

var ACTION_INTENTS = {
  "retry": true,
  "login": true,
  "view_installation": true
}

var MONEY_COPY_RE = /(?:\bBRL\b|\$|USD|EUR|GBP|\bspend\b|\bbalance\b|\bcredits?\b|\bcost\b|\bprice\b|\bcurrency\b)/i

function findProvider(snapshot, providerId) {
  if (!snapshot || !Array.isArray(snapshot.providers))
    return null
  var want = String(providerId || "")
  for (var i = 0; i < snapshot.providers.length; i++) {
    var p = snapshot.providers[i]
    if (p && String(p.id) === want)
      return p
  }
  return null
}

function planBadge(provider) {
  if (!provider || !provider.plan)
    return ""
  if (provider.plan.label)
    return String(provider.plan.label)
  if (provider.plan.id)
    return String(provider.plan.id)
  return ""
}

function errorMessage(provider) {
  if (!provider || !provider.error)
    return ""
  var msg = provider.error.message
  if (msg === null || msg === undefined)
    return ""
  return plainText(String(msg))
}

function plainText(value) {
  var s = String(value === null || value === undefined ? "" : value)
  // Drop control chars / ANSI; never treat as HTML.
  s = s.replace(/\u001b\[[0-9;]*[A-Za-z]/g, "")
  s = s.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
  return s
}

function containsMoneyCopy(text) {
  return MONEY_COPY_RE.test(String(text || ""))
}

function emptyWindowsMessage() {
  return "This plan does not publish a usage percentage."
}

function stateTitle(provider) {
  if (!provider)
    return ""
  var name = plainText(provider.name || providerDisplayName(provider.id))
  var s = String(provider.state || "")
  if (s === "loading")
    return ""
  if (presentsReading(s) && (!provider.windows || provider.windows.length === 0))
    return name + " reports no quota"
  if (presentsReading(s))
    return ""
  if (s === "cli_missing")
    return name + " CLI is not installed"
  if (s === "unauthenticated")
    return "Not signed in to " + name
  if (s === "rate_limited")
    return name + " hit a rate limit"
  if (s === "network_error")
    return "Cannot reach " + name
  if (s === "provider_error")
    return name + " returned no limits"
  return name + " state is unknown"
}

function stateBody(provider) {
  if (!provider)
    return ""
  var name = plainText(provider.name || providerDisplayName(provider.id))
  var s = String(provider.state || "")
  if (s === "loading")
    return ""
  if (presentsReading(s) && (!provider.windows || provider.windows.length === 0))
    return emptyWindowsMessage()
  if (presentsReading(s))
    return ""
  var err = errorMessage(provider)
  if (err.length)
    return err
  if (s === "cli_missing")
    return "Agent Bar reads the quota through it."
  if (s === "unauthenticated")
    return "Signing in opens the official " + name + " CLI."
  if (s === "rate_limited")
    return "Try again in a few minutes."
  if (s === "network_error")
    return "Check your connection."
  return ""
}

function defaultActionLabel(kind) {
  if (kind === "retry")
    return "Retry"
  if (kind === "login")
    return "Sign in"
  if (kind === "view_installation")
    return "Install guide"
  return String(kind || "")
}

function stateActions(provider) {
  var out = []
  if (!provider)
    return out
  var state = String(provider.state || "")
  if (presentsReading(state))
    return out
  var seen = {}

  function pushAction(kind, label, target) {
    var k = String(kind || "")
    if (!ACTION_INTENTS[k] || seen[k])
      return
    seen[k] = true
    out.push({
      kind: k,
      label: plainText(label || defaultActionLabel(k)),
      target: target === undefined ? null : target
    })
  }

  if (provider.action && provider.action.kind)
    pushAction(provider.action.kind, provider.action.label, provider.action.target)

  if (state === "cli_missing")
    pushAction("retry", "Check again", null)
  if (state === "rate_limited" || state === "network_error" || state === "provider_error")
    pushAction("retry", "Retry", null)
  if (state === "unauthenticated" && !seen.login && !seen.view_installation)
    pushAction("login", "Sign in", null)

  var retryAllowed = !provider || !provider.error
      || provider.error.retryable === undefined
      || provider.error.retryable === true
  if (!retryAllowed)
    out = out.filter(function (a) { return a.kind !== "retry" })

  return out
}

function mapActionKind(kind) {
  var k = String(kind || "")
  if (!ACTION_INTENTS[k])
    return null
  return k
}

function parseIsoMs(iso) {
  if (iso === null || iso === undefined)
    return NaN
  var s = String(iso)
  if (!s.length)
    return NaN
  var ms = Date.parse(s)
  return isFinite(ms) ? ms : NaN
}

function countdownText(diffMs) {
  var totalMinutes = Math.floor(diffMs / 60000)
  var days = Math.floor(totalMinutes / 1440)
  var hours = Math.floor((totalMinutes % 1440) / 60)
  var minutes = totalMinutes % 60
  if (days > 0)
    return days + "d " + hours + "h"
  if (hours > 0)
    return hours + "h " + minutes + "m"
  return minutes + "m"
}

function resetCountdownText(iso, nowMs) {
  var ms = parseIsoMs(iso)
  if (!isFinite(ms))
    return ""
  var diff = ms - nowMs
  if (diff <= 0)
    return "now"
  return countdownText(diff)
}

function resetClockText(iso, localeTimeFormat) {
  var ms = parseIsoMs(iso)
  if (!isFinite(ms))
    return ""
  var fmt = String(localeTimeFormat || "")
  if (!fmt.length)
    return ""
  return "(" + Qt.formatTime(new Date(ms), fmt) + ")"
}

function resetPhrase(countdown) {
  var c = String(countdown || "")
  if (!c.length)
    return ""
  return c === "now" ? "resets" : "resets in"
}

function formatAgoText(iso, nowMs) {
  var ms = parseIsoMs(iso)
  if (!isFinite(ms))
    return ""
  var diff = Math.max(0, nowMs - ms)
  if (diff < 60000)
    return "just now"
  var minutes = Math.floor(diff / 60000)
  if (minutes < 60)
    return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24)
    return hours + "h ago"
  return Math.floor(hours / 24) + "d ago"
}

// The JSON contract allows a positive integer or null; anything else reads
// as "no known length", so pace never guesses a duration.
function windowMinutesOf(w) {
  if (!w || typeof w.windowMinutes !== "number" || !isFinite(w.windowMinutes))
    return null
  var n = Math.round(w.windowMinutes)
  return n >= 1 ? n : null
}

function windowDisplayLines(provider, metric, nowMs) {
  var lines = []
  if (!provider || !Kernel.isArrayLike(provider.windows))
    return lines
  var mode = metric === "used" ? "used" : "remaining"
  var effectiveNowMs = nowMs === undefined ? Date.now() : nowMs
  for (var i = 0; i < provider.windows.length; i++) {
    var w = provider.windows[i]
    if (!w)
      continue
    var used = Number(w.usedPercent)
    var remaining = Number(w.remainingPercent)
    var pct = mode === "used" ? used : remaining
    var finite = isFinite(pct)
    var rounded = finite ? Math.round(pct) : null
    var pctText = finite ? (rounded + "%") : "\u2014"
    var countdown = w.resetsAt
        ? resetCountdownText(String(w.resetsAt), effectiveNowMs)
        : ""
    lines.push({
      id: String(w.id || ("w" + i)),
      label: plainText(w.label || w.id || "Window"),
      percentText: pctText,
      percent: finite ? Math.max(0, Math.min(100, rounded)) : -1,
      usedPercent: isFinite(used) ? used : null,
      remainingPercent: isFinite(remaining) ? remaining : null,
      severity: severityLevel(used),
      resetsAt: w.resetsAt ? String(w.resetsAt) : null,
      resetCountdown: countdown,
      resetPhrase: resetPhrase(countdown),
      windowMinutes: windowMinutesOf(w)
    })
  }
  return lines
}

function remainingRank(line) {
  return line.remainingPercent === null ? Infinity : line.remainingPercent
}

var SESSION_WINDOW_IDS = ["session", "gemini-5h", "3p-5h"]

function isSessionWindowId(id) {
  return SESSION_WINDOW_IDS.indexOf(String(id)) >= 0
}

function electLeadIndex(lines) {
  if (!lines || !lines.length)
    return -1

  var i
  var best = -1

  for (i = 0; i < lines.length; i++) {
    if (!isSessionWindowId(lines[i].id))
      continue
    if (best < 0 || remainingRank(lines[i]) < remainingRank(lines[best]))
      best = i
  }
  if (best >= 0)
    return best

  for (i = 0; i < lines.length; i++) {
    if (lines[i].severity !== "critical")
      continue
    if (best < 0 || remainingRank(lines[i]) < remainingRank(lines[best]))
      best = i
  }
  if (best >= 0)
    return best

  for (i = 0; i < lines.length; i++) {
    if (lines[i].id.indexOf("plan-") !== 0)
      continue
    if (best < 0 || remainingRank(lines[i]) < remainingRank(lines[best]))
      best = i
  }
  if (best >= 0)
    return best

  var bestMs = NaN
  for (i = 0; i < lines.length; i++) {
    if (!lines[i].resetCountdown.length || lines[i].resetCountdown === "now")
      continue
    var ms = parseIsoMs(lines[i].resetsAt)
    if (!isFinite(ms))
      continue
    if (best < 0 || ms < bestMs) {
      best = i
      bestMs = ms
    }
  }
  if (best >= 0)
    return best

  return 0
}

function windowLayout(provider, metric, nowMs) {
  var lines = windowDisplayLines(provider, metric, nowMs)
  var leadIndex = electLeadIndex(lines)
  var layout = { lead: null, rest: [], lines: lines }
  for (var i = 0; i < lines.length; i++) {
    if (i === leadIndex)
      layout.lead = lines[i]
    else
      layout.rest.push(lines[i])
  }
  return layout
}

function resetsOf(provider) {
  if (!provider || !Kernel.isArrayLike(provider.resets))
    return []
  var out = []
  for (var i = 0; i < provider.resets.length; i++) {
    if (provider.resets[i])
      out.push(provider.resets[i])
  }
  return out
}

// "Session (5h)" -> "session"; falls back to a humanized window id when the
// provider carries no matching window (e.g. a stale clears list).
function clearWord(provider, windowId) {
  if (provider && Kernel.isArrayLike(provider.windows)) {
    for (var i = 0; i < provider.windows.length; i++) {
      var w = provider.windows[i]
      if (w && String(w.id) === String(windowId)) {
        var label = plainText(w.label || w.id)
        return label.replace(/\s*\([^)]*\)\s*$/, "").trim().toLowerCase()
      }
    }
  }
  return String(windowId || "").replace(/[-_:]+/g, " ").trim().toLowerCase()
}

function joinWords(words) {
  if (!words.length)
    return ""
  if (words.length === 1)
    return words[0]
  if (words.length === 2)
    return words[0] + " and " + words[1]
  return words.slice(0, -1).join(", ") + ", and " + words[words.length - 1]
}

function resetClearsText(provider, clears) {
  var list = Kernel.isArrayLike(clears) ? clears : []
  var words = []
  for (var i = 0; i < list.length; i++)
    words.push(clearWord(provider, list[i]))
  return joinWords(words)
}

function resetCountText(available, total) {
  var avail = Number(available)
  var a = isFinite(avail) ? Math.max(0, Math.floor(avail)) : 0
  if (total === null || total === undefined)
    return String(a)
  var t = Number(total)
  return a + "/" + (isFinite(t) ? Math.max(0, Math.floor(t)) : 0)
}

function resetDateText(reset, localeDateFormat, localeTimeFormat) {
  var dateFmt = String(localeDateFormat || "")
  var timeFmt = String(localeTimeFormat || "")
  if (reset.expiresAt) {
    var ms = parseIsoMs(reset.expiresAt)
    if (isFinite(ms) && dateFmt.length)
      return "until " + Qt.formatDate(new Date(ms), dateFmt)
  }
  if (reset.refillsAt) {
    var rms = parseIsoMs(reset.refillsAt)
    if (isFinite(rms) && dateFmt.length)
      return "next " + Qt.formatDate(new Date(rms), dateFmt)
  }
  if (reset.cooldownUntil) {
    var cms = parseIsoMs(reset.cooldownUntil)
    if (isFinite(cms) && timeFmt.length)
      return "cooldown " + Qt.formatTime(new Date(cms), timeFmt)
  }
  return ""
}

function resetCountAccessible(available, total) {
  var avail = Number(available)
  var a = isFinite(avail) ? Math.max(0, Math.floor(avail)) : 0
  if (total === null || total === undefined)
    return a + " available"
  var t = Number(total)
  return a + " of " + (isFinite(t) ? Math.max(0, Math.floor(t)) : 0)
}

function resetRows(provider, localeDateFormat, localeTimeFormat) {
  var resets = resetsOf(provider)
  var out = []
  for (var i = 0; i < resets.length; i++) {
    var r = resets[i]
    var label = plainText(r.label || "")
    var clearsText = resetClearsText(provider, r.clears)
    var countText = resetCountText(r.available, r.total)
    var dateText = resetDateText(r, localeDateFormat, localeTimeFormat)
    var accessibleParts = [label, resetCountAccessible(r.available, r.total)]
    if (dateText.length)
      accessibleParts.push(dateText)
    out.push({
      id: String(r.id || ""),
      label: label,
      clearsText: clearsText,
      countText: countText,
      dateText: dateText,
      claimable: !!r.claimable,
      accessibleName: accessibleParts.join(", ")
    })
  }
  return out
}

function resetsSummary(provider) {
  var resets = resetsOf(provider)
  var availableTotal = 0
  var claimableId = null
  for (var i = 0; i < resets.length; i++) {
    var r = resets[i]
    var n = Number(r.available)
    if (isFinite(n))
      availableTotal += Math.max(0, n)
    if (claimableId === null && r.claimable)
      claimableId = String(r.id || "")
  }
  return {
    visible: resets.length > 0,
    availableTotal: Math.floor(availableTotal),
    claimableId: claimableId
  }
}

var RESET_OUTCOME_TEXT = {
  "reset": "Reset applied.",
  "already_used": "This reset was already used.",
  "not_limited": "Not at the limit, nothing to reset.",
  "ineligible": "Reset not available right now.",
  "unavailable": "Reset not available right now.",
  "unauthenticated": "Sign in to Claude again.",
  "network_error": "Network error. Try again.",
  "provider_error": "Claude did not accept the reset.",
  "unconfirmed": "Could not confirm the reset. Refreshing."
}

function resetOutcomeText(outcome, localeShortFormat) {
  if (!outcome)
    return ""
  var result = String(outcome.result || "")
  if (result === "cooldown") {
    var fmt = String(localeShortFormat || "")
    var ms = parseIsoMs(outcome.cooldownUntil)
    if (isFinite(ms) && fmt.length)
      return "On cooldown until " + Qt.formatTime(new Date(ms), fmt) + "."
    return "Reset not available right now."
  }
  return RESET_OUTCOME_TEXT[result] || "Claude did not accept the reset."
}

function resetConfirmModel(provider, row) {
  var name = plainText(provider ? (provider.name || providerDisplayName(provider.id)) : "")
  var label = row && row.label ? String(row.label) : ""
  var count = row && row.countText ? String(row.countText) : ""
  var clears = row && row.clearsText ? String(row.clearsText) : ""
  var message = name.length ? name + ": " : ""
  message += label
  if (count.length)
    message += " (" + count + ")"
  message += "."
  if (clears.length)
    message += " Clears " + clears + "."
  return {
    title: "Use reset?",
    message: message,
    confirmText: "Use reset"
  }
}

function unitWord(metric) {
  return metric === "used" ? "used" : "left"
}

// Highest usedPercent across providers that present a reading. Ties keep the
// first provider in display order, then the first window in delivered order.
// Unlike electLeadIndex, a session window gets no preference here.
function electTightest(providers, metric, nowMs) {
  var best = null
  var bestUsed = -Infinity
  var list = Kernel.isArrayLike(providers) ? providers : []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p || !presentsReading(p.state))
      continue
    var lines = windowDisplayLines(p, metric, nowMs)
    for (var j = 0; j < lines.length; j++) {
      if (lines[j].usedPercent === null || lines[j].usedPercent <= bestUsed)
        continue
      bestUsed = lines[j].usedPercent
      best = { providerId: String(p.id), windowId: lines[j].id }
    }
  }
  return best
}

function headlineModel(providers, tightest, metric, nowMs) {
  if (!tightest)
    return null
  var provider = null
  for (var i = 0; i < providers.length; i++) {
    if (providers[i] && String(providers[i].id) === tightest.providerId)
      provider = providers[i]
  }
  var lines = windowDisplayLines(provider, metric, nowMs)
  var line = null
  for (var j = 0; j < lines.length; j++) {
    if (lines[j].id === tightest.windowId)
      line = lines[j]
  }
  if (!provider || !line)
    return null
  var name = plainText(provider.name || providerDisplayName(provider.id))
  var word = line.id === "session" || line.id === "weekly" ? line.id : line.label
  var resetText = line.resetCountdown.length ? line.resetPhrase + " " + line.resetCountdown : ""
  var tagText = severityTagText(line.severity)
  var accessible = "Tightest: " + name + " " + word + " " + line.percentText + " " + unitWord(metric)
  if (tagText.length)
    accessible += ", " + tagText.toLowerCase()
  if (resetText.length)
    accessible += ", " + resetText
  return {
    providerId: tightest.providerId,
    providerName: name,
    windowWord: word,
    percentText: line.percentText,
    unitText: unitWord(metric),
    severity: line.severity,
    critical: line.severity === "critical",
    tagText: tagText,
    resetText: resetText,
    accessibleName: accessible
  }
}

var DAY_MS = 86400000

function overviewResetCellText(line, nowMs, timeFormat) {
  if (!line.resetCountdown.length)
    return ""
  var text = line.resetPhrase + " " + line.resetCountdown
  var diff = parseIsoMs(line.resetsAt) - nowMs
  if (diff > 0 && diff < DAY_MS) {
    var clock = resetClockText(line.resetsAt, timeFormat)
    if (clock.length)
      text += " " + clock
  }
  return text
}

function overviewWindow(line, provider, tightest, metric, nowMs, timeFormat) {
  var resetMs = parseIsoMs(line.resetsAt)
  var elapsed = null
  if (line.windowMinutes !== null && isFinite(resetMs))
    elapsed = Math.max(0, Math.min(1, 1 - (resetMs - nowMs) / (line.windowMinutes * 60000)))
  var tick = -1
  if (String(provider.state || "") === "ready" && elapsed !== null
      && elapsed >= Tokens.PACE_MIN_ELAPSED)
    tick = Math.round((metric === "used" ? elapsed : 1 - elapsed) * 100)
  var isTightest = !!tightest && tightest.providerId === String(provider.id)
      && tightest.windowId === line.id
  line.critical = line.severity === "critical"
  line.elapsed = elapsed
  line.tickPercent = tick
  line.isTightest = isTightest
  line.resetCellText = isTightest ? "" : overviewResetCellText(line, nowMs, timeFormat)
  return line
}

function paceDuration(minutes) {
  return countdownText(Math.max(60000, Math.round(minutes) * 60000))
}

// Linear projection over the windows whose tick shows. lines are WindowModels
// in delivered order.
function paceModel(provider, lines, primaryId, metric, nowMs) {
  if (!provider || String(provider.state || "") !== "ready" || !lines.length)
    return null
  var full = metric === "used" ? "full" : "empty"
  var key = metric === "used" ? "= time passed" : "= time left"
  var candidates = []
  var timed = false
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].elapsed !== null)
      timed = true
    if (lines[i].tickPercent >= 0 && lines[i].usedPercent !== null)
      candidates.push(lines[i])
  }
  if (!candidates.length) {
    if (!timed)
      return null
    return {
      kind: "tooEarly",
      glyph: Tokens.GLYPH_CLOCK,
      critical: false,
      text: "Too early to project, under " + Math.round(Tokens.PACE_MIN_ELAPSED * 100)
          + "% of the window has passed.",
      strong: "",
      rest: "",
      key: ""
    }
  }

  function prefixOf(w) {
    return w.id === primaryId || w.isTightest ? "" : w.label + " is "
  }

  for (var f = 0; f < candidates.length; f++) {
    if (candidates[f].usedPercent < 100)
      continue
    var fullPrefix = prefixOf(candidates[f])
    return {
      kind: "fullNow",
      glyph: Tokens.GLYPH_ALERT,
      critical: true,
      text: fullPrefix,
      strong: fullPrefix.length ? full + " now" : full.charAt(0).toUpperCase() + full.slice(1) + " now",
      rest: "",
      key: key
    }
  }

  var soonest = null
  var soonestMin = Infinity
  var widest = null
  var widestProjected = -Infinity
  for (var c = 0; c < candidates.length; c++) {
    var w = candidates[c]
    var projected = w.usedPercent / w.elapsed
    if (projected >= 100) {
      var toFull = (100 - w.usedPercent) / (w.usedPercent / (w.elapsed * w.windowMinutes))
      if (toFull < soonestMin) {
        soonest = w
        soonestMin = toFull
      }
    } else if (projected > widestProjected) {
      widest = w
      widestProjected = projected
    }
  }

  if (soonest) {
    var resetMin = (parseIsoMs(soonest.resetsAt) - nowMs) / 60000
    return {
      kind: "runsOut",
      glyph: Tokens.GLYPH_ALERT,
      critical: soonest.critical,
      text: "At this pace " + prefixOf(soonest),
      strong: full + " in ~" + paceDuration(soonestMin),
      rest: ", " + paceDuration(Math.max(0, resetMin - soonestMin)) + " before reset",
      key: key
    }
  }

  var n = Math.min(99, Math.round(widestProjected))
  return {
    kind: "lasts",
    glyph: Tokens.GLYPH_CHECK,
    critical: false,
    text: "",
    strong: "Lasts to reset",
    rest: ", " + widest.label + " ends near " + (metric === "used" ? n + "% used" : (100 - n) + "% left"),
    key: key
  }
}

function statusGlyph(state) {
  switch (String(state || "")) {
  case "cli_missing": return Tokens.GLYPH_PLUG
  case "unauthenticated": return Tokens.GLYPH_USER
  case "rate_limited": return Tokens.GLYPH_CLOCK
  case "network_error": return Tokens.GLYPH_WIFI_OFF
  case "provider_error": return Tokens.GLYPH_ALERT
  default: return ""
  }
}

function overviewRowKind(provider) {
  var state = String(provider.state || "")
  if (state === "loading")
    return "loading"
  if (presentsReading(state) && Kernel.isArrayLike(provider.windows) && provider.windows.length > 0)
    return "reading"
  return "status"
}

function overviewResetLines(provider, dateFormat, timeFormat) {
  var raw = resetsOf(provider)
  var rows = resetRows(provider, dateFormat, timeFormat)
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var hasTotal = raw[i].total !== null && raw[i].total !== undefined
    var facts = [
      resetCountAccessible(raw[i].available, raw[i].total) + (hasTotal ? " available" : ""),
      rows[i].clearsText.length ? "clears " + rows[i].clearsText : "",
      rows[i].dateText
    ]
    out.push({
      label: rows[i].label,
      facts: facts.filter(function (fact) { return fact.length > 0 })
    })
  }
  return out
}

function overviewRow(provider, metric, nowMs, tightest, ui) {
  var id = String(provider.id || "")
  var state = String(provider.state || "")
  var name = plainText(provider.name || providerDisplayName(id))
  var kind = overviewRowKind(provider)
  var timeFormat = ui.timeFormat
  var layout = windowLayout(provider, metric, nowMs)
  for (var i = 0; i < layout.lines.length; i++)
    overviewWindow(layout.lines[i], provider, tightest, metric, nowMs, timeFormat)
  var primary = layout.lead
  var reading = kind === "reading"

  var ago = formatAgoText(provider.lastSuccessAt, nowMs)
  var updatedText = ago.length ? "Updated " + ago : ""

  var subText = ""
  var subTag = ""
  if (reading) {
    subText = primary.label
    if (state === "stale") {
      if (updatedText.length)
        subText += " · " + updatedText
    } else if (primary.isTightest) {
      subTag = "Tightest"
    } else if (primary.resetCountdown.length) {
      subText += " · " + primary.resetPhrase + " " + primary.resetCountdown
    }
  }

  var actions = stateActions(provider)
  var action = null
  var refreshLabel = "Refresh"
  for (var a = 0; a < actions.length; a++) {
    if (actions[a].kind === "retry")
      refreshLabel = actions[a].label
    else if (action === null)
      action = actions[a]
  }

  var severity = reading ? providerSeverity(provider) : ""
  var severityWord = severity === "critical" ? "critical" : (severity === "warning" ? "low" : "")
  var valueText = reading ? primary.percentText
      : (kind === "loading" ? chipNumeralText(provider, metric, nowMs) : "—")
  var unitText = reading ? unitWord(metric) : ""
  var statusWord = settingsProviderStatus(provider)

  var accessibleName
  if (reading) {
    accessibleName = name + ", " + valueText + " " + unitText
    if (severityWord.length)
      accessibleName += ", " + severityWord
    accessibleName += ", " + subText
    if (subTag.length)
      accessibleName += ", tightest"
  } else if (kind === "loading") {
    accessibleName = name + ", loading"
  } else {
    accessibleName = statusWord.length ? name + ", " + statusWord : name
  }

  var summary = resetsSummary(provider)
  var resetUi = ui.resetUi
  return {
    id: id,
    name: name,
    kind: kind,
    state: state,
    plan: plainText(planBadge(provider)),
    openable: kind !== "loading",
    selected: false,
    open: false,
    dimIcon: kind === "status" && !!ERROR_STATES[state],
    primary: primary,
    windows: layout.rest,
    valueText: valueText,
    unitText: unitText,
    critical: reading && primary.critical,
    alert: severityWord === "critical",
    severityWord: severityWord,
    subText: subText,
    subTag: subTag,
    statusWord: statusWord,
    statusGlyph: statusGlyph(state),
    statusBody: stateBody(provider),
    action: action,
    refreshLabel: refreshLabel,
    updatedText: updatedText,
    pace: reading ? paceModel(provider, layout.lines, primary.id, metric, nowMs) : null,
    tickDescription: primary && primary.tickPercent >= 0
        ? Math.round(primary.elapsed * 100) + "% of the window has passed."
        : "",
    resets: overviewResetLines(provider, ui.dateFormat, timeFormat),
    useReset: {
      visible: summary.visible,
      enabled: summary.claimableId !== null && !ui.resetBusy,
      resetId: summary.claimableId,
      text: ui.resetBusy ? "Using reset…" : "Use reset"
    },
    outcomeText: resetUi && String(resetUi.providerId || "") === id
        ? resetOutcomeText(resetUi.outcome, timeFormat)
        : "",
    refreshing: !!ui.refreshing,
    accessibleName: accessibleName
  }
}

// selection = { id, collapsed } from the service popup owner.
// ui = { refreshing, resetUi, resetBusy, dateFormat, timeFormat }.
function overviewModel(snapshot, settings, nowMs, selection, ui) {
  var metric = displayMetric(settings)
  var opts = ui || {}
  var providers = visibleProviders(snapshot, settings)
  var tightest = electTightest(providers, metric, nowMs)
  var rows = []
  for (var i = 0; i < providers.length; i++)
    rows.push(overviewRow(providers[i], metric, nowMs, tightest, opts))

  var want = selection && selection.id ? String(selection.id) : ""
  var selectedId = rows.length ? rows[0].id : ""
  for (var s = 0; s < rows.length; s++) {
    if (rows[s].id === want)
      selectedId = want
  }
  var collapsed = !!(selection && selection.collapsed)
  var openId = ""
  for (var r = 0; r < rows.length; r++) {
    rows[r].selected = rows[r].id === selectedId
    if (rows[r].selected && rows[r].openable && !collapsed)
      openId = rows[r].id
  }
  for (var o = 0; o < rows.length; o++)
    rows[o].open = rows[o].id === openId

  return {
    metric: metric,
    unitText: unitWord(metric),
    rows: rows,
    selectedId: selectedId,
    openId: openId,
    tightest: tightest,
    headline: headlineModel(providers, tightest, metric, nowMs)
  }
}
