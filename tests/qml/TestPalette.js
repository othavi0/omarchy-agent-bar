.pragma library

function requiredScreenshotNames() {
  return [
    "ready-light.png",
    "ready-dark.png",
    "ready-white.png",
    "loading-dark.png",
    "refreshing-with-data-dark.png",
    "stale-dark.png",
    "critical-dark.png",
    "cli-missing-dark.png",
    "unauthenticated-dark.png",
    "rate-limited-dark.png",
    "network-error-dark.png",
    "provider-error-dark.png",
    "settings-clean-dark.png",
    "settings-dirty-dark.png",
    "settings-invalid-dark.png",
    "maintenance-update-dark.png",
    "uninstall-confirmation-dark.png"
  ]
}

// The values tst_Screenshots assigns to the stub qs.Commons Color.
function themePalette(mode) {
  if (mode === "white") {
    return {
      mode: "white",
      background: "#ffffff",
      foreground: "#000000",
      accent: "#0057d8",
      urgent: "#c31432",
      muted: "#8a8a8a",
      border: "#d4d4d8",
      popups: { background: "#ffffff", border: "#000000" }
    }
  }
  if (mode === "light") {
    return {
      mode: "light",
      background: "#f4f4f5",
      foreground: "#18181b",
      accent: "#2563eb",
      urgent: "#b91c1c",
      muted: "#a1a1aa",
      border: "#d4d4d8",
      popups: { background: "#f4f4f5", border: "#d4d4d8" }
    }
  }
  return {
    mode: "dark",
    background: "#18181b",
    foreground: "#e4e4e7",
    accent: "#60a5fa",
    urgent: "#f87171",
    muted: "#71717a",
    border: "#3f3f46",
    popups: { background: "#18181b", border: "#3f3f46" }
  }
}
