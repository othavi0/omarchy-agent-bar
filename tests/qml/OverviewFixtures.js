.pragma library

var FIXED_NOW = Date.parse("2026-10-21T12:37:00Z")

function at(minutesFromNow) {
  return new Date(FIXED_NOW + minutesFromNow * 60000).toISOString()
}

function win(id, label, used, minutes, resetInMinutes) {
  return {
    id: id,
    label: label,
    usedPercent: used,
    remainingPercent: 100 - used,
    resetsAt: resetInMinutes === null || resetInMinutes === undefined ? null : at(resetInMinutes),
    windowMinutes: minutes === undefined ? null : minutes
  }
}

function provider(id, name, state, windows, extra) {
  var p = {
    id: id,
    name: name,
    state: state,
    source: state === "ready" ? "live" : (state === "stale" ? "cache" : null),
    plan: null,
    windows: windows || [],
    resets: [],
    lastSuccessAt: state === "ready" || state === "stale" ? at(-1) : null,
    error: null,
    action: null
  }
  for (var k in (extra || {}))
    p[k] = extra[k]
  return p
}

function envelope(providers) {
  return {
    schemaVersion: 2,
    helperVersion: "10.6.3",
    generatedAt: at(0),
    request: { provider: null, cache: "use" },
    providers: providers
  }
}

function settings(metric) {
  return {
    schemaVersion: 1,
    providers: [
      { id: "claude", enabled: true },
      { id: "codex", enabled: true },
      { id: "grok", enabled: true },
      { id: "antigravity", enabled: true }
    ],
    display: { metric: metric === "used" ? "used" : "remaining" },
    refreshIntervalSeconds: 60,
    notifications: { enabled: true, reminderMinutes: 120 }
  }
}

function claudeReset(claimable) {
  return {
    id: "spring",
    label: "Usage reset",
    available: 1,
    total: 1,
    clears: ["session", "weekly"],
    expiresAt: at(2 * 1440),
    refillsAt: null,
    cooldownUntil: null,
    claimable: claimable
  }
}

function claudeReady(sessionUsed, sessionResetIn) {
  return provider("claude", "Claude", "ready", [
    win("session", "Session (5h)", sessionUsed, 300, sessionResetIn),
    win("weekly", "Weekly (7d)", 37, 10080, 4080),
    win("weekly-model:fable", "Fable", 45, 10080, 4080)
  ], { plan: { id: "max", label: "Max" }, resets: [claudeReset(true)] })
}

// Live shape since 2026-10-30: verified Ultra accounts have no 5-hour window.
function claudeUltraNoSession() {
  return provider("claude", "Claude", "ready", [
    win("weekly", "Weekly (7d)", 29, 10080, 8480),
    win("weekly-model:fable", "Fable", 0, 10080, 8480)
  ], { plan: { id: "default_claude_max_20x", label: "Ultra" } })
}

function codexReady() {
  return provider("codex", "Codex", "ready", [
    win("session", "Session (5h)", 2, 300, 250),
    win("weekly", "Weekly (7d)", 18, 10080, 7320)
  ], { plan: { id: "plus", label: "Plus" } })
}

function grokReady() {
  return provider("grok", "Grok", "ready", [
    win("monthly", "Monthly", 30, null, 20000)
  ])
}

function antigravityReady() {
  return provider("antigravity", "Antigravity", "ready", [
    win("gemini-5h", "Gemini · 5h", 0, 300, null),
    win("gemini-weekly", "Gemini · weekly", 0, 10080, null),
    win("3p-5h", "Claude and GPT · 5h", 0, 300, null),
    win("3p-weekly", "Claude and GPT · weekly", 0, 10080, null)
  ])
}

function normal() {
  return envelope([claudeReady(76, 92), codexReady(), grokReady(), antigravityReady()])
}

function critical() {
  return envelope([claudeReady(96, 38), codexReady(), grokReady(), antigravityReady()])
}

function stale() {
  var codex = provider("codex", "Codex", "stale", [
    win("session", "Session (5h)", 96, 300, 250),
    win("weekly", "Weekly (7d)", 18, 10080, 7320)
  ], { lastSuccessAt: at(-14) })
  return envelope([claudeReady(76, 92), codex, grokReady(), antigravityReady()])
}

function problemProvider(id, name, state) {
  if (state === "cli_missing") {
    return provider(id, name, state, [], {
      error: { message: name + " CLI was not found.", retryable: true },
      action: { kind: "view_installation", label: "Install guide", target: "https://example.com/install" }
    })
  }
  return provider(id, name, state, [])
}

function problems() {
  return envelope([
    problemProvider("claude", "Claude", "unauthenticated"),
    problemProvider("codex", "Codex", "cli_missing"),
    problemProvider("grok", "Grok", "rate_limited"),
    problemProvider("antigravity", "Antigravity", "network_error")
  ])
}

function providerError() {
  return envelope([problemProvider("claude", "Claude", "provider_error"), codexReady()])
}

function nopct() {
  return envelope([provider("claude", "Claude", "ready", []), codexReady()])
}

function early() {
  return envelope([
    provider("claude", "Claude", "ready", [win("session", "Session (5h)", 10, 300, 290)]),
    codexReady()
  ])
}

function full() {
  return envelope([
    provider("claude", "Claude", "ready", [
      win("session", "Session (5h)", 100, 300, 60),
      win("weekly", "Weekly (7d)", 37, 10080, 4080)
    ]),
    codexReady()
  ])
}
