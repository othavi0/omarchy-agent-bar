# Plugin root comes from Service.qml's own URL

Date: 2026-09-10
Status: approved

## Context

Omarchy 4.0.3 ships basecamp/omarchy#9618, merged 2026-09-07, which narrows
what third-party plugins receive from the shell. Service instances now get
`shell.publicPluginManifest(manifest)`, a JSON copy without the host-only
fields `__sourceDir`, `__isFirstParty`, and `__hostCapabilities`.

`Service.qml` built `pluginRoot`, and from it the helper path and the login
launcher path, out of `manifest.__sourceDir`. On 4.0.3 that field is gone, so
the helper path was empty, no process lane ever started, and the bar stayed on
its loading state on every updated machine.

## Decision

`pluginRoot` is the directory of `Service.qml` itself:
`Core.pluginRootFromUrl(Qt.resolvedUrl("."))`. The host loads `Service.qml`
from `__sourceDir + "/Service.qml"`, so this value equals the old one by
construction, and it exists at object construction instead of after manifest
injection.

The plugin reads no host-only manifest field. `manifest` stays injected and
is used only for public fields such as `version`.

## Contract changes

- `02-target-architecture.md`, "Target QML boundaries": the injection snippet
  derives `pluginRoot` from the service URL.
- `08-plugin-bundle-and-release.md`, "Update check": Omarchy contract `1`
  requires service injection of a public `manifest` copy instead of
  `manifest.__sourceDir` service injection.
- `Service.qml` must stay at the plugin root, which the manifest entry point
  already requires.
