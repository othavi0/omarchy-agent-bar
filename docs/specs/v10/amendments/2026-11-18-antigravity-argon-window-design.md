# Antigravity reports its Gemini 4 Argon quota

Date: 2026-11-18
Status: approved

## Context

On paid Pro plans, `agy --print /usage --output-format json` reports a third
model group next to the two that the 2026-09-10 amendment maps:

| Group | Bucket ids | Models |
|---|---|---|
| Gemini Models | `gemini-weekly`, `gemini-5h` | Gemini Flash, Gemini Pro |
| Claude and GPT models | `3p-weekly`, `3p-5h` | Claude Opus, Claude Sonnet, GPT-OSS |
| Gemini 4 Argon | `gemini-argon-wtu-weekly` | Gemini 4 Argon |

The CLI describes the Argon group itself: "For paid Pro plans, Argon quota
is separate. Higher Argon quota (included as part of the larger Gemini quota
bucket) is available on Ultra plans." The captured output in
`tests/fixtures/antigravity/usage-with-argon.json` holds one Argon bucket,
`gemini-argon-wtu-weekly`, with `window` `weekly`, a remaining fraction of
`0`, and a reset on 2026-11-10T14:55:43Z. Agent Bar ignored that id, so a Pro
account saw no Argon window, even with its Argon week spent.

## Decision

- The mapper reads `gemini-argon-wtu-weekly` as a fifth window, after the
  Gemini and Claude/GPT windows, labelled `Argon · 7d` with a window of
  10,080 minutes. The full-bucket rule applies unchanged: a remaining
  fraction of `1` or more carries no reset.
- No Argon five-hour bucket has been observed, so none is mapped. Guessed
  ids such as `gemini-argon-weekly`, `gemini-argon-wtu-5h`, and
  `gemini-argon-5h` stay ignored, as the 2026-09-10 amendment decides for
  any id without captured evidence. A five-hour Argon bucket seen in real
  output is a new amendment with its fixture.
- The Argon window is weekly, not a session window, so `UX-020D` and
  `SESSION_WINDOW_IDS` do not change. The lower of the Gemini and
  Claude/GPT sessions still leads the chip.
- Severity is unchanged (`UX-020C`): an exhausted Argon week is a critical
  window, so it tints the chip and shows `!` even while the numeral belongs
  to a session window of another family.
- The CLI description places Ultra Argon use inside the Gemini buckets, so
  an Ultra account is expected to report no Argon bucket and keep its four
  windows. No Ultra output has been captured.
- The mapper keeps its windows in one ordered table of id, label, and
  window minutes. The table order is the delivered order, and adding a
  family is one row.

## Contract changes

- `02-target-architecture.md`, locked collection policy: the Antigravity row
  lists `gemini-argon-wtu-weekly` after the four existing ids, and the
  provider labels paragraph adds `Argon · 7d`.
- `docs/guide/runtime.md`: the Antigravity paragraph names three families
  and says Argon has only a weekly window.

## Tests

- `src/providers/v2_map.rs`: the Argon fixture maps to five windows, the
  last one `gemini-argon-wtu-weekly` labelled `Argon · 7d` with 0 %
  remaining, a reset on 2026-11-10T14:55:43Z, and 10,080 minutes; the
  guessed Argon ids are ignored; the order stays fixed however the CLI
  orders groups, with the Argon window last.
