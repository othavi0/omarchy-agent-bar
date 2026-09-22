# Product

## Users

Omarchy Quattro users who work with Claude, Codex, Grok, or Antigravity and need a
reliable glanceable answer to:

- How much percentage quota remains?
- When does the relevant window reset?
- Is the provider connected and fresh?
- What action is required when data is unavailable?

## Product purpose

Agent Bar is a Quickshell plugin, not a general terminal application. The bar
provides the glanceable state. The consolidated popup provides quota details,
provider actions, Settings, an update check, and uninstall without requiring
the user to learn a CLI: Settings About checks for updates and, when one is
available, offers `Update to <version>`. After one confirmation the plugin
runs the Omarchy plugin manager and then offers `Restart shell`. The
terminal fallback
(`omarchy plugin update othavi0.agent-bar --yes && omarchy-restart-shell`)
stays visible. The uninstall
button delegates to the Omarchy plugin manager (`omarchy plugin remove`),
which owns the actual mutation.

Success means:

- every visible value comes from normalized provider data;
- all monitors share one state and polling source;
- stale and partial failures remain understandable;
- Settings changes are recoverable; update and uninstall are explicit,
  confirmed actions delegated to the Omarchy plugin manager, and the update
  runs in a transient user unit that reports through a state file;
- pointer, keyboard, focus, scrolling, themes, and absence of Agent
  Bar-authored motion work as native Quattro behavior;
- the plugin never leaks credentials or raw provider output.

## Product personality

Quiet, compact, and native to Omarchy. Provider identity comes from official
icons. Severity is visible but not theatrical. The UI prefers clear labels
over decorative or ambiguous controls.

## Design principles

1. **Real data or an explicit unavailable state.**
2. **One source of truth per concept.**
3. **Typed states instead of human-message parsing.**
4. **Last good data remains visible when it is honestly stale.**
5. **No color-only meaning.**
6. **No custom theme system over Quattro.**
7. **Destructive maintenance is explicit and recoverable.**
8. **No credentials, monetary data, or local history.**

## Scope

Included:

- Claude, Codex, Grok, and Antigravity.
- Provider percentage windows and reset times.
- Plan and connection state.
- Typed missing/auth/network/rate/provider states.
- Provider login delegation through the official CLI.
- Provider enablement/order, used/remaining, interval, and notifications.
- Plugin update check (install command shown for the user to run) and
  uninstall delegated to the Omarchy plugin manager.

Removed:

- TUI.
- Waybar.
- Session history.
- Charts.
- Local costs and BRL conversion.
- Provider spend, balance, and credits.
- Standalone/AUR/cargo-binstall distribution.
- Permanent daemon.

## Canonical specification

[docs/specs/v10/README.md](docs/specs/v10/README.md) contains the approved
requirements and their amendments.
