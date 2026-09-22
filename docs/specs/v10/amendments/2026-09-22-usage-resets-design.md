# Banked usage resets in the popup

Date: 2026-09-22
Status: approved

## Context

On 2026-09-22 Anthropic shipped Claude Opus 5.5 with "a banked reset" of
the usage limit. The OAuth usage endpoint reports it in two new blocks that
the helper does not read today:

- `cedar_ember`: a list of reset grants. Each grant carries a label, how
  many resets it still holds (`resets_left` of `resets_total`), which
  windows it clears (`five_hour`, `seven_day`), when it expires (`ends_at`),
  an optional `cooldown_until`, and `usable_now`. The block also carries
  `next_grant_id`, the grant the client should claim first.
- `juniper_tide`: one recurring reset per week (`resets_per_week`,
  `available`, `next_available_at`, `weekly_resets_at`).

Both blocks appear only on
`GET /api/oauth/usage?at_wall=1&skip_spend=1`, and only when the request
identifies a Claude Code client. Measured on 2026-09-22 against a Max
account: with the helper's current headers both blocks return
`eligible: false, ineligible_reason: "surface"`. With
`User-Agent: claude-cli/2.1.280 (external, cli)` and `x-app: cli` the
`cedar_ember` block returns the Opus 5.5 launch grant with one reset left.
Claude Code claims a reset with
`POST /api/organizations/<organization uuid>/reset_rate_limits` and a JSON
body of `program`, `grant_id`, and `request_id`. The response carries
`result` (`reset`, `already_used`, `not_limited`, `cooldown`,
`ineligible`, `unavailable`), `resets_left`, `cleared`, and
`cooldown_until`.

Codex already reports a reset count through `rateLimitResetCredits.
availableCount`, which the helper serializes as `rateLimitResetsAvailable`
(`JSON-022C`) and the popup renders as one caption line.

The owner reviewed four popup prototypes on 2026-09-22 and decided:

- The bar chip does not change. Nothing about resets appears in the bar.
- When a provider has no reset, the popup renders nothing about resets and
  keeps today's height.
- The popup gets a "Resets" section that lists one row per reset source
  and is ready for several sources at once.
- The section has a claim button. The click opens a confirmation, and the
  confirmed claim runs through the helper.
- The helper identifies as the installed Claude Code client on the usage
  request, with the version read from the installed binary, never a fixed
  string.

## Decision

### Domain type

`resets` replaces `rateLimitResetsAvailable`. It is a list of `UsageReset`
values on `ProviderResult::Ready` and on every `ProviderStatus` row:

```text
UsageReset
  id            "cedar-ember:<grant id>" | "juniper-tide" | "codex-credits"
  label         plain text, at most 64 characters, never empty
  available     non-negative integer
  total         non-negative integer or null
  clears        window ids from this provider's vocabulary; may be empty
  expiresAt     RFC 3339 UTC or null
  refillsAt     RFC 3339 UTC or null
  cooldownUntil RFC 3339 UTC or null
  claimable     boolean
```

- `JSON-022C` is withdrawn. `rateLimitResetsAvailable` leaves the schema,
  the Rust types, the QML, and the fixtures in the same change.
- `JSON-022D`: `resets` is a required array on every provider row. A row
  without resets carries `[]`. Each entry follows the `UsageReset` shape.
  `available` and `total` count resets, not money; `JSON-022B` still bans
  monetary fields.
- `JSON-022E`: `label` passes the same sanitization as a dynamic model
  label (plain text, control characters stripped, length capped). The
  grant id in `id` is lowercased and limited to `[a-z0-9-]`, at most 48
  characters.
- `JSON-022F`: `claimable` is true only when the helper can claim that
  reset through the `reset` command right now. Codex resets are never
  claimable here; Codex owns that action.

### Claude collection

- The usage URL becomes
  `https://api.anthropic.com/api/oauth/usage?at_wall=1&skip_spend=1`.
- Before the request, the adapter runs the discovered `claude` executable
  with `--version` through the process seam, with the provider timeout,
  and parses the leading `major.minor.patch`. With a version it adds
  `User-Agent: claude-cli/<version> (external, cli)` and `x-app: cli`.
  Without a discovered executable, a non-zero exit, or an unparsable
  version, the adapter sends the request without those two headers. The
  windows do not depend on them; only the reset blocks do.
- `cedar_ember` maps to one `UsageReset` per grant when `eligible` is true
  and the grant is not paused and has `resets_left > 0` or a
  `cooldown_until`. `id` is `cedar-ember:<grant id>`, `label` is the grant
  label, `available` is `resets_left`, `total` is `resets_total`, `clears`
  maps `five_hour` to `session` and `seven_day` to `weekly` and drops other
  keys, `expiresAt` is `ends_at`, `cooldownUntil` is `cooldown_until`, and
  `claimable` is `usable_now` with no cooldown. The grant named by
  `next_grant_id` comes first.
- `juniper_tide` maps to one `UsageReset` when `eligible` is true and
  either `available` is true or `next_available_at` is set. `id` is
  `juniper-tide`, `label` is `Weekly reset`, `available` is 1 or 0, `total`
  is `resets_per_week`, `clears` is `["session"]`, `refillsAt` is
  `next_available_at` or else `weekly_resets_at`, and `claimable` equals
  `available`.
- An ineligible block, a missing block, or a malformed block yields no
  entries and does not fail the provider.
- Codex maps `rateLimitResetCredits.availableCount > 0` to one entry with
  `id` `codex-credits`, `label` `Rate-limit resets`, `available` equal to
  the count, `total` null, `clears` empty, and `claimable` false.

### Reset command

`agent-bar reset claude <reset-id>` claims one Claude reset.

- `CLI-030`: The grammar accepts only `reset claude <reset-id>`. Any other
  provider is a grammar error (`CLI-007`). A reset id that fails
  `JSON-022E` exits with `VALIDATION`.
- `CLI-031`: The command reads the same credentials file as collection and
  applies the same expiry precheck. It reads the organization uuid from
  `$HOME/.claude.json` at `oauthAccount.organizationUuid` and accepts only
  36 hex digits and hyphens. A missing file, a missing key, or any other
  value returns `unavailable` before any request, because signing in again
  does not create the key. The uuid, the token, and the request body never
  reach logs, cache, or stdout.
- `CLI-032`: The command fetches usage first, with the collection headers,
  and claims only a reset that the fresh response lists as `claimable`. An
  id that the fresh response does not list, or lists as not claimable,
  returns `unavailable` without a POST.
- `CLI-033`: The claim is one `POST` to
  `https://api.anthropic.com/api/organizations/<uuid>/reset_rate_limits`
  with `Content-Type: application/json`, the collection headers, and a body
  of `program` (`cedar_ember` or `juniper_tide`), `grant_id` for
  `cedar_ember`, and a fresh `request_id` in UUID form. The POST follows
  the GET discipline: HTTPS only, no redirects, body size cap, provider
  timeout. The POST is never retried.
- `CLI-034`: stdout is exactly one JSON object plus newline:

```json
{
  "schemaVersion": 1,
  "operation": "reset",
  "provider": "claude",
  "resetId": "cedar-ember:opus55-launch-promax-20260921",
  "result": "reset",
  "resetsLeft": 0,
  "cooldownUntil": null,
  "clears": ["session", "weekly"]
}
```

  `result` is one of `reset`, `already_used`, `not_limited`, `cooldown`,
  `ineligible`, `unavailable`, `unauthenticated`, `network_error`, or
  `provider_error`. Every one of them exits `0`; they are typed data.
  `resetsLeft` and `cooldownUntil` are null when the response does not
  carry them. `clears` lists the window ids the response reports as
  cleared, mapped as in collection.
- `CLI-035`: The command does not touch the cache. The popup forces a
  refresh of the provider after any result.

### Popup

- `UX-070`: `ProviderView` renders a "Resets" section after the usage
  windows only when `resets` is non-empty. The section header carries the
  title `Resets`, the sum of `available` across entries, and a `Use reset`
  button that is visible only when at least one entry is `claimable`.
- `UX-071`: Each row shows the label (elided), which windows it clears
  using the provider's window labels, the count (`available/total`, or
  `available` alone when `total` is null), and one date: `until <date>`
  from `expiresAt`, else `next <date>` from `refillsAt`, else
  `cooldown <time>` from `cooldownUntil`. Dates use the locale short
  format. Every row's accessible name spells out label, count, and date.
- `UX-072`: `Use reset` targets the first claimable entry. The click opens
  a `ConfirmDialog` whose message names the provider, the windows the reset
  clears, and the entry's label and count, with `Use reset` as the confirm
  text. Confirm runs `agent-bar reset claude <reset-id>` on its own helper
  lane. While the lane is busy the button is disabled.
- `UX-073`: The result renders as one plain-text caption under the section
  until the next successful refresh or until the popup closes: `Reset
  applied.`, `This reset was already used.`, `Not at the limit, nothing to
  reset.`, `On cooldown until <time>.`, `Reset not available right now.`
  (for `ineligible` and `unavailable`), `Sign in to Claude again.`,
  `Network error. Try again.`, and `Claude did not accept the reset.`
  After any result the service forces a refresh of the provider.
- `UX-074`: The bar chip, the rail, and the notifications do not change.

## Consequences

The `rateLimitResetsAvailable` count disappears from the schema, so a
consumer of the status JSON reads `resets` instead. The Claude usage
request now spawns `claude --version` once per collection, the same
pattern the Antigravity adapter uses for its version guard. The helper
sends its first authenticated write to a provider API, limited to one
endpoint, one provider, and one command that the popup runs only after a
confirmation. When Anthropic changes the eligibility rule, the section
disappears and the windows keep working.
