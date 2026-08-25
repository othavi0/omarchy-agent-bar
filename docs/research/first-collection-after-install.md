# Why Claude showed `—` with the error cue right after install

Research note for [issue #65](https://github.com/othavi0/omarchy-agent-bar/issues/65)
(child of #63). Read-only investigation: source, executable tests, the live
install, the live cache, and `journalctl --user` for 2026-08-25.

**Conclusion in one sentence.** The chip was not showing a stale or
mis-ordered value — the first collection ran live against an empty cache and
Claude genuinely returned a single-shot failure from its one HTTPS call, and
that failure row was then written to the cache with Claude's full 300-second
*success* TTL, so the correct-but-wrong-looking `—` + `!` was pinned for five
minutes across five polls; an always-bypass initial collection alone does not
fix this, because on a cold cache the initial collection is already live.

---

## 1. What the startup path actually does

`Service.qml` startup is: Quattro injects `manifest`, `tryStartProduction()`
starts the version probe, and on success `finishVersionProbeSuccess()` calls
`kickSettingsBootstrap()` and then `beginCollection()`
(`Service.qml:485-509`). `beginCollection()` restarts the poll timer and
calls `kickStatus()` (`Service.qml:505-509`).

`kickStatus()` takes whatever is in `pendingForcedTargets` and hands it to
`Core.statusArgv()` (`Service.qml:518-547`). At startup that queue is empty —
nothing calls `refresh()` or `refreshAll()` on the startup path — and
`CoreService.js:126-158` maps an empty target set to `cache use`:

```js
function statusArgv(helperPath, forceOrTargets) {
  var cacheMode = "use"
  if (forceOrTargets === true || forceOrTargets === "all") cacheMode = "bypass"
  ...
```

The repository already records this as the intended shape:
`tests/qml/tst_Service.qml:243` carries the comment
`// First kick uses empty pending → cache use`, and
`test_version_and_health` (`tests/qml/tst_Service.qml:220-226`) asserts that
`applyVersion()` alone sets `collectionStarted`.

Settings bootstrap is a *separate* helper process started in the same tick, so
the first `status` run can precede `appliedSettings`. That does not change the
provider set: the helper resolves its own settings
(`src/status/coordinator.rs:110-117`, `target_providers` at
`src/status/coordinator.rs:274-284`), and with no settings file on disk the
defaults enable all five providers — which is exactly what the live cache
shows for the first run (§3).

**`cache use` on a cold cache is indistinguishable from `cache bypass`.**
`src/status/coordinator.rs:127-141`: under `CacheMode::Use` a provider is
served from cache only when `cache_doc.is_fresh(id, requested_at)` and an
entry exists; otherwise it is pushed to `to_collect` and collected live. With
an empty document every provider is collected live.

## 2. What the Claude adapter can and cannot return

`ClaudeAdapter::collect` (`src/providers/adapters.rs:345-470`) does exactly
two things: read `$HOME/.claude/.credentials.json`, then issue one HTTPS GET
to `https://api.anthropic.com/api/oauth/usage`. It never executes a CLI. The
only use it makes of discovery is `login_available(discovery)`
(`src/providers/adapter.rs:240-242`), which reads `discovery.login` and feeds
the *action* on a failure row, never the state.

Reachable non-ready states for Claude:

| Trigger | Result state | `retryable` |
| --- | --- | --- |
| credentials file unreadable | `unauthenticated` | false |
| credentials unparsable / empty token | `unauthenticated` | false |
| `expiresAt <= now` | `unauthenticated` | true |
| HTTP 401 / 403 | `unauthenticated` | false |
| HTTP 429 | `rate_limited` | — |
| other non-2xx | `provider_error` | false |
| transport failure | `network_error` | — |
| redirect refused / body too large / bad JSON | `provider_error` | false |

Every one of those is in `ERROR_STATES` (`CoreView.js:109-115`), so every one
of them renders the same chip: the numeral box falls back to `—` and
`chipStateCue()` appends `!` (`CoreView.js:193-202`). The chip cannot
distinguish them, which is why the screenshot alone cannot name the cause.

## 3. Evidence from the live machine

Timeline, all local (`-0300`); UTC values are as stored in the cache.

| Time | Fact | Source |
| --- | --- | --- |
| 11:50:15.169 | plugin tree created | `birth` of `~/.config/omarchy/plugins/othavi0.agent-bar` |
| 11:50:26.127 | `bin/agent-bar` written | `birth` of `.../bin/agent-bar` |
| 11:50:26.271 | `DEBUG qml: Local plugin changed, reloading: othavi0.agent-bar` | `journalctl --user`, `omarchy-shell[1372]` |
| 11:50:26.40 / .79 / 11:50:31.22 / .26 | four shell-root instantiations (repeated `IpcHandler ... already registered` bursts) | same |
| 11:50:31.344 | `~/.local/state/agent-bar/maintenance.lock` created — helper's first exec | `birth` |
| 11:50:31.3997 | `~/.cache/agent-bar/` and `status.lock` created | `birth` |
| 11:50:31.663 | Amp collected (`startedAt 14:50:31.663234975Z`, `completedAt …663299176Z`) | live cache row |
| 11:50:31.666 | Grok collected (`startedAt 14:50:31.665962968Z`) | live cache row |
| 11:50:46 | screenshot: Claude, Codex, Amp, Grok all render `— !` | `~/Pictures/screenshot-2026-08-25_11-50-46.png` |
| 11:54:05.878 | `~/.config/agent-bar/settings.json` created, Amp and Grok disabled | `birth` + content |
| 12:07:12 | screenshot: Claude chip reads `18%` | `~/Pictures/screenshot-2026-08-25_12-07-12.png` |

Three of the four error chips in the 11:50:46 screenshot are correct and still
correct today: `amp` → `cli_not_found` (no `amp` on this machine), `grok` →
`unauthenticated`, `codex` → `provider_error`. Only Claude was wrong.

The Amp and Grok rows in the live cache are still the *original* rows from
11:50:31 — they were frozen when the user disabled both providers at 11:54,
because `target_providers` only collects enabled providers
(`src/status/coordinator.rs:274-284`) while `merge_provider` preserves
siblings (`src/cache/store.rs:104-118`). They are therefore a direct,
surviving sample of the first collection.

### Timing of the first Claude collection

The coordinator collects sequentially in settings order — Claude, Codex, Amp,
Grok, Antigravity (`src/status/coordinator.rs:167-180`). The cache lock is
created at 11:50:31.3997 as part of `cache_store.load()`, immediately before
the loop; Amp starts at 11:50:31.6632. So **Claude and Codex together
consumed at most ≈263 ms**.

For calibration, from later rows in the same live cache: a *successful* Claude
collection takes 379 ms (`15:53:31.291557Z` → `15:53:31.670602Z`), and a
failing Codex collection takes 92 ms (`15:57:31.292208Z` →
`15:57:31.384559Z`). That leaves Claude roughly 170 ms on the first run.

This matters because `RETRY_DELAY` is 250 ms (`src/providers/catalog.rs:16`)
and `http_get_with_retry` sleeps for it before the second attempt on a
transport error (`src/providers/retry.rs:18-27`). A retried `network_error`
could not have fitted in the observed window. A single completed HTTPS
response (401/403/429/non-2xx) or a purely local credential decision both fit.

## 4. Hypotheses

### H1 — Stale cache: **refuted**

`~/.cache/agent-bar/` and its lock were created at 11:50:31.3997, in the same
100 ms as the first collection, and `~/.local/state/agent-bar/` at
11:50:31.344. The plugin tree itself was created at 11:50:15. Nothing on this
machine predates the install, so no cache entry could have been served. Even
had one existed, `is_fresh` (`src/cache/schema.rs:68-70`) would have had to
find it unexpired, and a *stale* cache hit for Claude would have rendered the
previous good percentage, not `—`.

### H2 — First-poll timing / ordering: **refuted as the cause, confirmed as an aggravator**

Refuted as the cause: the initial `cache use` degenerates to a live collection
on a cold cache (§1), and the chip rendered a real typed result, not a
placeholder — `placeholderProvider()` produces `state: "loading"`, which
renders `···`, not `—` (`CoreView.js:41-55`, `CoreView.js:243-250`).

Confirmed as an aggravator, in two places:

1. `apply_stale_retention` (`src/status/coordinator.rs:242-265`) is the
   mechanism that hides transient failures — but it needs a prior `Ready` or
   `Stale` row. On the very first collection `prior` is `None`, so it returns
   the raw failure. The one code path designed to absorb exactly this event is
   structurally unavailable at install time.
2. `Service.qml` has no re-kick when a provider returns non-ready.
   `maybeFollowUpStatus()` (`Service.qml:577-580`) only fires when the forced
   queue is non-empty; a first collection that comes back all-error simply
   waits for the 60 s poll timer.

### H3 — Transient auth/HTTP failure on Claude's single request: **not refuted; the only surviving candidate**

By elimination of H1 and H4, and consistent with the timing in §3, the first
Claude collection returned one of the states in the §2 table from a single
non-retried attempt. It **cannot be narrowed to a specific error code from
surviving artifacts**:

- Quickshell reads the helper through `StdioCollector` and does not forward
  its stderr; `journalctl --user` for 11:45–12:10 contains no `agent-bar`
  records at all, only `omarchy-shell` QML output.
- The Claude cache row from 11:50:31 was overwritten by the next live Claude
  collection and is gone.
- Reading `~/.claude/.credentials.json` (to check whether `expiresAt` had
  already passed at 11:50:31, which is the `retryable: true` variant of
  `unauthenticated`) was refused by this session's tool policy, so that
  variant is neither confirmed nor excluded.

One additional condition is worth recording because it is specific to
"right after install": the shell instantiated four roots between 11:50:26.27
and 11:50:31.26 (§3). Each instantiation reruns the whole
probe → bootstrap → `beginCollection()` path, so two `agent-bar status`
processes can overlap. Nothing serializes them across processes — the
maintenance gate is taken *shared* (`src/status/coordinator.rs:118-121`) and
`CacheCoordinator` is in-process only (`src/cache/coordinator.rs`) — so two
near-simultaneous OAuth usage requests with the same bearer token are
possible. This is a plausible source of a one-shot rejection, but it is a
hypothesis, not an observation.

### H4 — CLI discovery race: **refuted**

Claude's collection never executes a CLI (§2), so no PATH or discovery timing
can produce a Claude error row; `cli_missing` is unreachable for Claude.
Independently, discovery would have succeeded anyway: `omarchy-shell` (pid
1372) has `/home/othavio/.local/share/mise/shims` on `PATH`, and both
`~/.local/bin/claude` (the descriptor's fallback,
`src/providers/catalog.rs:176-179`) and the shim resolve.

### H5 — Failure rows inherit the success TTL: **confirmed** (new)

This is the reason the wrong chip persisted rather than self-correcting on the
next poll.

`src/status/coordinator.rs:167-180` writes every collected row — ready or
failed — with `descriptor_ttl(id)`, and `entry_from_status`
(`src/cache/store.rs:193-203`) sets `expires_at = completed_at + ttl`.
`descriptor_ttl` has no state arm (`src/status/coordinator.rs:286-294`), and
`CacheDocument::is_fresh` only compares timestamps
(`src/cache/schema.rs:68-70`). Claude's TTL is 300 s
(`src/providers/catalog.rs:182`; asserted at `src/providers/catalog.rs:437`);
every other provider is 90 s.

The default poll interval is 60 s (`CoreService.js:299-316`) and every poll
after the first is also `cache use`. So the Claude error row written at
11:50:31 was served back unchanged — `for_cache_hit()` returns non-ready rows
verbatim (`src/status/schema.rs:419-441`) — at 11:51:31, 11:52:31, 11:53:31,
11:54:31 and 11:55:31 was the first poll able to re-collect. Applying settings
at 11:54:05 did not help: `applySettingsWriteResult`
(`Service.qml:671-681`) sets `appliedSettings` and does not enqueue a forced
refresh. The 12:07 screenshot shows Claude healthy again, consistent with
recovery on TTL expiry.

The same rule gives Codex, Amp, Grok and Antigravity a 90 s error pin.

## 5. Does an always-bypass initial collection alone fix it?

**No.**

1. It is a no-op for the reported scenario. On a fresh install the cache is
   empty, so the initial `cache use` already collects live (§1). Forcing
   `bypass` changes the argv and nothing else.
2. It does not touch the failure. The bad chip came from a live collection
   that failed; bypassing a cache that has no entry cannot make that
   collection succeed.
3. It does not shorten the consequence. The failure row is still cached for
   300 s (H5), so the chip is still pinned for five minutes.
4. Where it *would* change behaviour — service restart with a warm cache — it
   arguably makes things worse for this symptom, because a warm cache would
   have shown the previous good percentage instead of nothing.

The parent issue (#63) already lists "initial collection after service start
always bypasses cache" as a standing preference. It is defensible on freshness
grounds and should stay, but this note records that it is not a fix for #65
and should not be specified as one.

### What would fix it

In rough order of leverage, for the spec amendment to decide:

1. **Give failure rows their own short TTL** (e.g. 15–30 s), or do not cache
   non-ready rows at all. Single-line change in intent at
   `src/status/coordinator.rs:174`; it turns a five-minute wrong chip into one
   poll interval.
2. **Bounded re-kick on a cold non-ready result.** When a provider returns a
   retryable failure and has no prior `lastSuccessAt`, `Service.qml` should
   queue one forced (`bypass`) refresh for that provider instead of waiting
   out the poll timer. `pendingForcedTargets` and `maybeFollowUpStatus()`
   already carry the machinery (`Service.qml:113-144`, `574-577`).
3. **Do not paint an error cue before a provider has ever been reached.** A
   provider with no `lastSuccessAt` and a retryable error on the first
   collection is closer to `loading` than to a fault; #63 already wants the
   popup, not the chip, to carry login detail.
4. **Serialize collectors across processes.** The four-root reload burst (§3)
   can put two `agent-bar status` runs in flight at once. If the spec wants
   the initial collection to be authoritative, an exclusive collection lock
   (or a short in-cache in-flight marker) removes a whole class of
   first-boot-only transients.

## 6. Open questions for the spec

- Which Claude error code was it? Unrecoverable from this incident (§H3).
  Deciding it requires either helper stderr reaching journald, or a
  `lastError` breadcrumb kept in the cache row. Worth costing: today a
  first-boot failure leaves no forensic trace at all.
- Does the retryable `unauthenticated` ("session expired") case want the same
  treatment as #63's "never logged in" case? They render identically today,
  and only the retryable one self-heals.
- Should `apply_stale_retention` have a cold-start counterpart — e.g. a
  first-collection retry budget — rather than silently degrading to "show the
  raw error"?

## 7. Method and limits

- Sources read: `Service.qml`, `CoreService.js`, `CoreView.js`,
  `src/status/coordinator.rs`, `src/status/collect.rs`,
  `src/status/schema.rs`, `src/cache/{schema,store,coordinator}.rs`,
  `src/providers/{catalog,adapters,adapter,retry}.rs`,
  `tests/qml/tst_Service.qml`, `docs/guide/runtime.md`.
- Live inspection was read-only: `stat`/`ls` metadata, one redacted JSON dump
  of `~/.cache/agent-bar/status-v2.json` (state fields only), the two
  screenshots, and `journalctl --user`. No helper command was run, and no
  live config, cache or state file was modified.
- `~/.claude/.credentials.json` was not read; its `expiresAt` at 11:50:31 is
  therefore unknown.
- Sub-second attributions in §3 are derived from file birth times and cache
  timestamps, not from an instrumented run; the ≈170 ms figure for the first
  Claude collection carries the 92 ms Codex estimate borrowed from a later
  run.
