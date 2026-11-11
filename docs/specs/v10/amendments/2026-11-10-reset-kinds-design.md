# Reset kinds

Date: 2026-11-10
Status: approved
Amends: the `UsageReset` shape, the `cedar_ember`, `juniper_tide`, and
Codex mappings, `CLI-036`, `UX-071`, and `UX-072` from
`2026-09-22-usage-resets-design.md`; `UX-088` and `UX-089` from
`2026-10-31-popup-grid-layout-design.md` as amended by
`2026-11-01-popup-compact-cleanup-design.md`; `JSON-022D` in
`03-cli-and-json-contract.md`. Adds `JSON-022G`.

## Context

- The Claude group note summed every reset into `2 resets left`, and
  `Use reset` always claimed the first claimable one. An account with a full
  reset and a Fable reset could not tell them apart or pick one.
- The helper dropped the fields that tell resets apart: a `cedar_ember`
  grant's `type` (`session`, `weekly`, `full`) and `gives_back_weekly`. A
  Fable reset came through with `clears: []`.
- A Fable reset returns what Fable used to the weekly limit. It does not
  bring the weekly window to zero, and the popup must not suggest it does.
- `juniper_tide` clears the 5-hour limit but carried the label
  `Weekly reset`.
- The owner picked the prototype variant with one `Use reset` button and a
  choice dialog. The group note counts each kind without a date; each
  reset's validity shows in the choice and in the confirmation.

## Decision

### Reset kind (JSON-022G)

- `UsageReset` gains `kind`, placed after `id`:

  ```text
  kind  "session" | "weekly" | "fable" | "full" | null
  ```

- `JSON-022G`: `kind` is a closed enum and always serialized. `null` means
  the provider does not say what the reset clears. A cache row written
  before the field existed loads with `kind` null and keeps its reset until
  the next collection. Any other value fails validation in the schema, in
  Rust deserialization, and in the QML envelope check.
- One Rust function derives a Claude grant's kind, following the official
  client:
  1. `gives_back_weekly` true gives `fable`;
  2. else a declared `type` of `session`, `weekly`, or `full` gives that
     kind; an unknown or non-string `type` counts as absent;
  3. else, from the raw `clears` keys: only `five_hour` gives `session`,
     only other keys gives `weekly`, both or none gives `full`.
- QML reads `kind` and never derives it from `label` or `clears`.

### Claude mapping

- `clears` maps the raw keys against the windows the same payload emits,
  deduplicated in order:
  - `five_hour` maps to `session` and `seven_day` to `weekly`;
  - `seven_day_overage_included` maps to the id of the single window
    emitted from a `weekly_scoped` `limits[]` entry (today
    `weekly-model:fable`) when the grant has `gives_back_weekly`, and is
    dropped when zero or several such windows exist; on any other grant it
    maps to `weekly`;
  - `seven_day_opus` and `seven_day_sonnet` map to `weekly-model:opus` and
    `weekly-model:sonnet` when that window was emitted, and are dropped
    otherwise;
  - every other key is dropped.
- For a Fable reset, `clears` names the window whose use goes back to the
  weekly limit. It does not claim that window resets to zero.
- `juniper_tide` has `kind` `session` and the label `5-hour reset`.
- Codex `codex-credits` has `kind` null: nothing in the payload says what
  the credit clears.
- Payload fields that stay out: `percent_used` (the windows carry the
  percentages), `blocking`, `unavailable_reason`, `use_requires_limit`,
  `at_limit`, and `exhausted` (`claimable` already decides the button and
  the claim returns typed results).

### Reset command (CLI-036)

- `CLI-036` (amended): the output keeps `schemaVersion` 1 and gains no
  field. `clears` maps the response's `cleared` keys with the collection
  rule, against the fresh usage response the claim was checked on and the
  claimed grant's `gives_back_weekly`.

### Popup (UX-071, UX-072, UX-088, UX-089)

- One table in `CoreView.js`, `RESET_KINDS`, holds each kind's noun, label,
  and effect text:

  | Kind | Label | Effect |
  | --- | --- | --- |
  | `session` | `5-hour reset` | `Clears your 5-hour limit.` |
  | `weekly` | `Weekly reset` | `Clears your weekly limits.` |
  | `fable` | `Fable reset` | `Returns what Fable used to your weekly limit. Weekly does not go to zero.` |
  | `full` | `Full reset` | `Clears your limits.` |

  The kind order is `session`, `weekly`, `fable`, `full`.
- `UX-088` (amended): when every reset of the provider has a kind, the note
  counts each kind in that order and shows no date: `1 Fable · 1 full`; with
  one kind, `1 Fable reset` or `2 Fable resets`. A provider with an untyped
  reset keeps `{n} reset(s) left` and the first reset's date.
- `UX-089` (amended): the group keeps one `Use reset` action, enabled when at
  least one reset is claimable and the reset lane is idle. Its `target` is
  null; the popup picks the reset on click.
- `UX-072` (amended): with one claimable reset, the click opens its
  confirmation. With several, it opens a choice dialog titled `Which reset
  do you want to use?`, with one option per claimable reset in kind order
  and a `Cancel` button. Each option reads `{kind label} · until {date}`
  over the kind's effect text. Choosing an option opens that reset's
  confirmation.
- `UX-071` (amended): the confirmation is built from the chosen reset id.
  Its title is `Use {kind noun} reset?` (`Use 5-hour reset?`, `Use weekly
  reset?`, `Use Fable reset?`, `Use full reset?`; `Use reset?` for an
  untyped reset), and its message is `{provider}: {label} ({count}).
  {effect} Valid until {date}.`; an untyped reset names what it clears,
  `Clears {windows}.`, in place of the effect. Confirming runs
  `agent-bar reset claude <reset-id>` with the chosen id.
- The bar chip does not change. No new key shortcut is added.

## Consequences

- A Fable reset shows as Fable everywhere the popup names it, and its
  effect text says the weekly window does not go to zero.
- The user picks which reset to spend, and sees its validity before
  confirming.
- A new kind from the provider is a schema change: Rust, the JSON Schema,
  `CoreService.js`, and `RESET_KINDS` change together.
- Open: the raw payload of a full grant without `type` has not been
  captured; by the rule above such a grant reads as `weekly` when it clears
  only weekly keys. Whether a Fable reset also zeroes the
  `weekly-model:fable` window has not been measured, and the effect text
  makes no claim about it.

## Contract changes

| ID | Before | After |
| --- | --- | --- |
| `UsageReset` | No kind. | `kind`: closed enum or null. |
| `JSON-022D` | Example without `kind`. | Example with `kind`. |
| `JSON-022G` | None. | `kind` is closed; a pre-kind cache row loads as null. |
| `cedar_ember` | `clears` keeps `five_hour` and `seven_day` only. | Kind rule; `clears` maps the Fable, Opus, and Sonnet keys to emitted windows. |
| `juniper_tide` | `Weekly reset`. | `5-hour reset`, `kind` `session`. |
| Codex | No kind. | `kind` null. |
| `CLI-036` | `cleared` mapped with the old rule. | Mapped with the collection rule and the claimed grant. |
| `UX-071` | Confirmation names the windows cleared. | Confirmation names the kind, its effect, and its validity. |
| `UX-072` | `Use reset` claims the first claimable entry. | One claimable: its confirmation. Several: a choice first. |
| `UX-088` | `{n} reset left` and its date. | Count per kind, no date. |
| `UX-089` | `use_reset` targets the first claimable id. | `use_reset` carries no target. |
