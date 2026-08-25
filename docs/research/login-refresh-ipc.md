# How a Bash script asks the Agent Bar service to refresh

Research for [issue #66](https://github.com/othavi0/omarchy-agent-bar/issues/66)
(child of #63).

## Question

> Which mechanism lets `scripts/agent-bar-open-terminal` (Bash, argv-safe, no
> `sh -c`) tell the shared `Service.qml` to refresh one provider with cache
> bypass after the login command exits? Candidates: Quickshell IPC (`qs ipc
> call` against `IpcHandler` — `Service.qml` already exposes
> `refresh(providerId)`), Omarchy shell IPC conventions in
> `/usr/share/omarchy/shell`, or a file/signal the service already watches.
> Output: what exists today, what each option needs, and constraints
> (multi-instance, sandbox, argv safety).

**Headline finding:** the mechanism already exists, is specified, is
implemented, is tested, and is live on this machine. The post-login refresh is
not `scripts/agent-bar-open-terminal`'s job — it can't be, because that script
`exec`s away before login even starts. The Rust login command does it. This
document records the existing contract and the options for any *other* Bash
script that wants to trigger the same refresh.

## What exists today

### Quickshell layer

`Service.qml:908-912` (repository root — the repository root *is* the plugin
tree, ADR 0006) declares the handler:

```qml
IpcHandler {
  target: "othavi0.agent-bar"
  function health(expectedVersion: string): string { return root.health(expectedVersion) }
  function refresh(providerId: string): string { return root.refresh(providerId) }
}
```

`root.refresh`, `Service.qml:113-122`:

```qml
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
```

`Core.refreshResult` rejects any ID outside the closed set
`claude, codex, amp, grok, antigravity` with `"unknown"`; a valid ID queues a
cache-bypass refresh (`force=true` → `cacheMode = "bypass"`) and returns
`"ok"`. Spec: `docs/specs/v10/02-target-architecture.md` `ARCH-020`/`ARCH-021`;
also documented at `docs/dev/omarchy-shell.md:78-82` ("`Service.qml` owns one
`IpcHandler` target `othavi0.agent-bar`. Its closed surface is
`health(expectedVersion)` for maintenance and `refresh(providerId)` for
successful interactive login.").

Per Quickshell's own docs
(`https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/IpcHandler/`),
`IpcHandler.target` must be unique, functions take up to 10 arguments, and
argument/return types must be explicit or the function is not registered.
External callers use `qs ipc call <target> <function> [args...]`; `qs ipc
show` lists registered targets read-only.

**Live verification on this machine** — `qs ipc -n -p /usr/share/omarchy/shell
show` lists `othavi0.agent-bar` among the shell's registered IPC targets,
exposing exactly:

```
target othavi0.agent-bar
  function refresh(providerId: string): string
  function health(expectedVersion: string): string
```

`qs list --all` shows exactly one running Quickshell instance for the session
(`config /usr/share/omarchy/shell/shell.qml`), confirming Omarchy runs one
shared shell process, not one per monitor.

### Omarchy layer: the `omarchy-shell` wrapper

Omarchy ships `/usr/share/omarchy/bin/omarchy-shell` (on `PATH` inside the
shell's own process environment) as the canonical way external scripts talk to
the running shell:

```bash
Usage: omarchy-shell [-q] <target> <method> [args...]
...
output=$(timeout --kill-after=1s "$ipc_timeout" qs ipc -n -p "$OMARCHY_PATH/shell" call -- "$@" 2>/dev/null)
```

Key behaviors, read from the script itself:

- `-q` (quiet/best-effort): suppresses output and returns success even when
  the shell, target, method, or arguments are unavailable.
- `-n -p "$OMARCHY_PATH/shell"` selects the shell's own config path as the
  instance, and recovers `WAYLAND_DISPLAY` from the compositor socket when the
  caller has none (e.g. an SSH session), because `qs` matches instances by
  display.
- `--` before the forwarded target/method/args keeps method names that shadow
  `qs` subcommands (like `show`) as positionals.
- Default timeout `2s` (`OMARCHY_SHELL_IPC_TIMEOUT` overrides it), via
  `timeout --kill-after=1s`.
- `qs` itself exits `0` even for IPC-level failures ("Target not found.",
  "Function not found.", bad-argument-count messages) — the wrapper
  string-matches these on stdout and converts them into a real failure/exit
  code, which a raw `qs ipc call` caller would have to reimplement itself.

Every existing Omarchy caller uses this wrapper, never raw `qs ipc call` —
e.g. media/notification keybindings and the power menu all shell out to
`omarchy-shell <target> <method> [...]`. The wrapper's own `--help` uses
`omarchy-shell -q omarchy.indicators refresh` as its example, structurally
identical to what Agent Bar needs.

### Already-shipping caller: the Rust login command

`src/providers/adapter.rs` (`run_login`) already performs exactly this call
after a successful provider login:

```rust
let refresh_spec = ProcessSpec::new(
    "omarchy-shell",
    ["-q", "othavi0.agent-bar", "refresh", provider_id],
)
.with_timeout(std::time::Duration::from_secs(5))
.with_max_output(64 * 1024);
// Best-effort: ignore errors and non-zero.
let _ = ipc_runner.run(&refresh_spec).await;
```

This only fires when the official provider CLI process exits `0`; a
nonzero/signaled/timed-out login never triggers a refresh, and a failed
refresh never changes the reported login exit status (`adapter.rs`, guarded by
exit-code checks before the refresh block). Spec:
`docs/specs/v10/02-target-architecture.md` — "After the official provider
process exits `0`, the Rust login command performs a best-effort argv call:
`omarchy-shell -q othavi0.agent-bar refresh <providerId>`. It then returns the
original provider exit status. ... Failure of the best-effort IPC never
changes the provider process result." Wired into production in
`src/cli/mod.rs` (`dispatch_login`) with the real process runner for both the
provider and IPC lanes.

**Why `scripts/agent-bar-open-terminal` itself can't do this:** it ends with
`exec xdg-terminal-exec ... "$helper" login "$provider"` — `exec` replaces the
script's own process image, so nothing runs after it. The refresh call had to
move into the Rust helper's `login` command, which runs *inside* the spawned
terminal and inherits `OMARCHY_PATH` and `/usr/share/omarchy/bin` on `PATH`
from the parent shell environment, so the bare `omarchy-shell` command
resolves without any extra setup.

## Options for a Bash script that needs to trigger a refresh

### Option A — `omarchy-shell` wrapper (recommended)

```bash
omarchy-shell -q othavi0.agent-bar refresh "$provider_id"
```

Or, to observe the result instead of firing best-effort:

```bash
result=$(omarchy-shell othavi0.agent-bar refresh "$provider_id") || exit 1
[[ $result == ok ]] || { echo "refresh rejected: $result" >&2; exit 1; }
```

This is the exact call the Rust helper already makes, and it matches every
other Omarchy IPC caller in this ecosystem. The wrapper absorbs instance
selection, `WAYLAND_DISPLAY` recovery, timeout, and the "`qs` exits 0 on IPC
error" trap.

### Option B — raw `qs ipc call`

```bash
qs ipc -n -p "$OMARCHY_PATH/shell" call -- othavi0.agent-bar refresh "$provider_id"
```

This is literally what the wrapper does internally. Only worth using directly
if a script needs different instance-selection flags (`--pid`, `-i`,
`--any-display`) or a different timeout than the wrapper offers — and doing so
means reimplementing the wrapper's stdout error-string mapping, since `qs`
reports IPC-level failures on stdout with exit `0`.

### Option C — `omarchy-shell shell call <plugin> <method> <arg>` — does not work

The shell's own generic `shell.call` dispatcher routes through a lookup in its
panel loaders, which only covers loaded panel plugins, not service plugins
like Agent Bar's `Service.qml`. Calling the generic dispatcher against
`othavi0.agent-bar` returns `"unknown"`. Direct-target IPC
(`othavi0.agent-bar refresh ...`) is the only route into a service plugin.

### Option D — a file or signal the service watches — does not exist

`Service.qml` declares no `FileView`, `Socket`, `SocketServer`, or
`watchChanges` construct. Adding one would introduce a second polling/watch
owner in a file whose contract (`CLAUDE.md`: "`Service.qml` is the sole
polling/process owner") already assigns that role exclusively to the poll
timer and IPC handler, plus a new path outside the documented XDG surface for
no benefit over IPC that already ships. Not recommended.

## Constraints

- **Argv safety.** The whole chain — `omarchy-shell` → `qs ipc … call --
  "$@"` → the Rust helper's `ProcessSpec` — passes the provider ID as a
  discrete argv element, never through a shell string; no `sh -c`, `eval`, or
  `cmd="$*"` appears anywhere in the path. A caller only has to quote its own
  expansion (`"$provider_id"`). Even so, `Core.refreshResult` rejects any ID
  outside the closed provider set with `"unknown"`, so a malformed or hostile
  argument cannot reach `refreshProvider`.
- **Instance selection / multi-instance.** Omarchy runs exactly one shared
  Quickshell process for the whole session (bar, popups, and all plugin
  services), confirmed live via `qs list --all` showing one instance. Agent
  Bar's service is likewise a single shared object, not one per monitor — the
  shell's plugin-sync logic creates at most one service instance per enabled
  plugin ID, so the `othavi0.agent-bar` `IpcHandler` target is registered
  exactly once regardless of how many monitor-local bar widgets exist. A
  second Wayland session would need the wrapper's `-n` plus display filtering
  to disambiguate; that is already built in.
- **Sandbox.** The IPC target is a per-user Quickshell IPC socket, visible to
  any process that can reach the session — it is not sandboxed per plugin.
  Disabling or removing the Agent Bar plugin destroys its service object and
  the target vanishes; `-q` mode swallows the resulting "Target not found."
  as a silent no-op, matching the best-effort contract.
- **Result visibility with `-q`.** `-q` suppresses stdout and forces exit `0`,
  so a caller using `-q` cannot distinguish "refreshed" from "target missing"
  from "invalid provider ID". That is the deliberate ARCH-021 contract for the
  login path (a refresh failure must never change the login command's own
  exit status). A script that needs to know the outcome should drop `-q` and
  compare stdout to the literal string `ok`.

## Testability

- **Rust side (already covered):** `tests/login.rs` injects a scripted process
  runner as the IPC lane and asserts the exact argv
  (`omarchy-shell -q othavi0.agent-bar refresh <id>`) byte-for-byte, plus the
  no-refresh-on-nonzero/timeout paths and the "refresh failure doesn't change
  login exit status" path. Any new Bash caller's argv should be pinned the
  same way, by literal-equality assertion, not a substring/regex match.
- **QML side (already covered):** `tests/qml/tst_Service.qml` drives
  `Core.*` functions directly (no live `Quickshell.Io` dependency in the
  test) and asserts `refresh("claude") == "ok"`, `refresh("nope") ==
  "unknown"`, `refreshRequestCount` increments, and the force/bypass argv is
  set correctly.
- **Bash side, for a new script:** ShellCheck (per this repo's contract),
  argv-only construction with no shell string, and validating the provider ID
  against the closed set before it ever reaches argv — the same pattern
  `scripts/agent-bar-open-terminal` already uses for its provider `case`
  guard. A fake `omarchy-shell` placed earlier on `PATH` that records `"$@"`
  gives an argv assertion with no live shell and no network involved.
- **Not testable in CI:** that a live shell actually re-polls after the IPC
  call — that is a live-QA concern, not a unit-test one, and belongs to the
  project's authorized QA gate rather than this research.

## Recommendation

Use `omarchy-shell -q othavi0.agent-bar refresh <providerId>` — it is already
the shipped, spec'd (`ARCH-020`/`ARCH-021`), tested, and live-verified path,
and it matches the convention every other Omarchy IPC caller in this
ecosystem already follows. For issue #66's literal subject (refreshing after
login), no code change is needed: `src/providers/adapter.rs`'s `run_login`
already fires this exact call after a zero-exit provider login, and
`scripts/agent-bar-open-terminal` cannot participate because it `exec`s away
before login even runs. The only gap is documentation: the wrapper invocation
is currently stated only in the v10 target-architecture spec and implied by
`docs/dev/omarchy-shell.md`; neither `docs/guide/commands.md` nor
`docs/dev/architecture.md` tells a script author how to call it directly.

## Sources

- `Service.qml` (repository root) — `IpcHandler` block and `refresh`/`health`
  functions.
- `scripts/agent-bar-open-terminal` — Bash launcher, `exec` hand-off.
- `src/providers/adapter.rs` — `run_login`, refresh argv construction.
- `tests/login.rs` — refresh-argv and failure-path assertions.
- `tests/qml/tst_Service.qml` — QML-side refresh assertions.
- `docs/specs/v10/02-target-architecture.md` — `ARCH-020`, `ARCH-021`, and the
  post-login refresh contract.
- `docs/dev/omarchy-shell.md` — Quattro plugin IPC surface.
- `/usr/share/omarchy/bin/omarchy-shell` (read-only, live system) — wrapper
  script and its documented usage/behavior.
- `/usr/share/omarchy/shell` (read-only, live system) — `IpcHandler` usage
  precedent across other Omarchy plugins.
- Live introspection on this machine: `qs --version`, `qs ipc --help`, `qs ipc
  call --help`, `qs ipc show --help`, `qs ipc -n -p /usr/share/omarchy/shell
  show` (read-only; no mutating IPC call was made).
- Quickshell official docs:
  `https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/IpcHandler/`.
