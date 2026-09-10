.pragma library
.import "CoreService.js" as Kernel

function displayMetric(settings) {
  if (settings && settings.display && settings.display.metric === "used")
    return "used"
  return "remaining"
}

function providerDisplayName(id) {
  var key = String(id || "")
  if (key === "claude")
    return "Claude"
  if (key === "codex")
    return "Codex"
  if (key === "amp")
    return "Amp"
  if (key === "grok")
    return "Grok"
  if (key === "antigravity")
    return "Antigravity"
  return key
}

function iconFileName(id) {
  var key = String(id || "")
  if (key === "claude")
    return "claude.png"
  if (key === "codex")
    return "codex.png"
  if (key === "amp")
    return "amp.svg"
  if (key === "grok")
    return "grok.svg"
  if (key === "antigravity")
    return "antigravity.png"
  return ""
}

function placeholderProvider(id) {
  var key = String(id || "")
  return {
    id: key,
    name: providerDisplayName(key),
    state: "loading",
    source: null,
    plan: null,
    account: null,
    windows: [],
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
  if (ERROR_STATES[state])
    return "!"
  if (chipSeverityUrgent(provider))
    return "!"
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

// The rail plate marks whoever owns the open content: the provider in the
// usage view, the Settings slot in the settings view.
function railProviderSelected(view, providerId, selectedId) {
  if (view === "settings")
    return false
  var id = String(providerId || "")
  return id.length > 0 && id === String(selectedId || "")
}

function railTooltipText(provider, metric, nowMs) {
  var label = chipAccessibleLabel(provider, metric, nowMs)
  if (chipSeverityUrgent(provider))
    label += " · critical"
  return label
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

function resolveSelectedProvider(snapshot, selectedProviderId, settings) {
  var chips = visibleProviders(snapshot, settings)
  if (!chips.length)
    return null
  var want = String(selectedProviderId || "")
  if (want) {
    for (var i = 0; i < chips.length; i++) {
      if (String(chips[i].id) === want)
        return chips[i]
    }
  }
  return chips[0]
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
      resetPhrase: resetPhrase(countdown)
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
  var layout = { lead: null, rest: [] }
  for (var i = 0; i < lines.length; i++) {
    if (i === leadIndex)
      layout.lead = lines[i]
    else
      layout.rest.push(lines[i])
  }
  return layout
}

function rateLimitResetsText(provider) {
  if (!provider)
    return ""
  var n = Number(provider.rateLimitResetsAvailable)
  if (!isFinite(n) || n <= 0)
    return ""
  n = Math.floor(n)
  return "↻ " + n + " rate-limit reset" + (n === 1 ? "" : "s") + " available"
}

function headerModel(provider, refreshing) {
  if (!provider) {
    return {
      name: "",
      plan: "",
      lastSuccessAt: null,
      refreshing: !!refreshing
    }
  }
  return {
    name: plainText(provider.name || providerDisplayName(provider.id)),
    plan: plainText(planBadge(provider)),
    lastSuccessAt: provider.lastSuccessAt ? String(provider.lastSuccessAt) : null,
    refreshing: !!refreshing
  }
}

function contentMode(provider) {
  if (!provider)
    return "skeleton"
  var s = String(provider.state || "")
  if (s === "loading")
    return "skeleton"
  if (presentsReading(s)) {
    if (!provider.windows || provider.windows.length === 0)
      return "empty_windows"
    return "windows"
  }
  return "state"
}
