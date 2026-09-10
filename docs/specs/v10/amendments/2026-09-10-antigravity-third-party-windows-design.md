# Antigravity reports its Claude/GPT quota

Date: 2026-09-10
Status: approved

## Context

`agy --print /usage --output-format json` reports two model families, each
on its own weekly and five-hour quota:

| Group | Bucket ids | Models (`agy` 1.2.0) |
|---|---|---|
| Gemini Models | `gemini-weekly`, `gemini-5h` | Gemini Flash, Gemini Pro |
| Claude and GPT models | `3p-weekly`, `3p-5h` | Claude Opus, Claude Sonnet, GPT-OSS |

The CLI describes them itself: "Within each group, models share a weekly
limit and a 5-hour limit. Quota is consumed proportionally to the cost of
the tokens." Agent Bar mapped only the Gemini pair, so an account working
through Claude or GPT in Antigravity saw nothing drain until the quota ran
out (issue #82).

A live probe on 2026-09-10 against `agy` 1.2.0 established how the buckets
behave:

- A bucket that no one has used reports `remaining_fraction` exactly `1`
  and `reset_time` equal to the request time plus the whole window. Two
  requests three seconds apart each got a reset about five hours (or
  seven days) after themselves, so the reset moves with the clock.
- The first prompt on a family starts both of its windows. From then on
  the reset is fixed at first use plus five hours (or seven days): a
  second Gemini prompt fifteen minutes later left it unchanged, and the
  Claude/GPT reset, read fifteen minutes apart, did not move either.
- A prompt debits both windows of its own family and nothing of the other.

## Decision

- The mapper reads all four bucket ids, in a fixed order: Gemini weekly,
  Gemini five-hour, Claude/GPT weekly, Claude/GPT five-hour. Any other id,
  including guessed aliases such as `claude-5h`, is ignored.
- Every Antigravity window names its family and duration: `Gemini · 7d`,
  `Gemini · 5h`, `Claude/GPT · 7d`, `Claude/GPT · 5h`. The longer
  `Claude/GPT · Session (5h)` measures 165 px in the 11 px popup font and
  the compact row gives its label about 118 px, so it would elide to
  `Claude/GPT · Ses…`; the short form is at most 99 px. Window ids do not
  change, so notification state keyed by window survives; notification
  titles gain the family.
- A bucket with a remaining fraction of `1` or more carries no reset. No
  window is running and the reset `agy` reports never arrives.
- `3p-5h` joins `SESSION_WINDOW_IDS`. When several session windows are
  delivered, the one with the lowest remaining percentage leads, and a tie
  keeps the delivered order. The rule is written for any provider; only
  Antigravity delivers more than one session id today, and the schema
  rejects duplicate window ids within a provider.

The lead is the tighter session, not a detected "current" family. With one
family in use, that is the family in use: an idle family sits at 100 % and
only wins a tie, where the chip number is identical anyway. With both in
use, the lower session leads even if the other family is the one being
used right now. On an account whose plan reports no five-hour buckets, a
full weekly bucket has no reset and does not compete in the nearest-reset
step; with both weeklies in use, the sooner reset leads.

Severity is unchanged (`UX-020C`): a critical window of either family still
tints the chip and shows `!`, even when the numeral belongs to the other
family's session.

## Contract changes

- `UX-020D`: session window ids are `session`, `gemini-5h`, and `3p-5h`;
  among several, the lowest remaining percentage leads, ties keep the
  delivered order. This supersedes "the first delivered one if several"
  from the 2026-09-04 amendment.
- `02-target-architecture.md`, locked collection policy: the Antigravity row
  lists all four bucket ids and the full-bucket reset rule, and the
  provider labels paragraph lists the four Antigravity labels.

## Tests

- `src/providers/v2_map.rs`: the fixture maps to four labelled windows;
  `claude-*` ids are ignored; a full bucket carries no reset while a used
  one keeps it; the order is fixed however the CLI orders groups.
- `tests/qml/tst_ProviderStates.qml`: the Claude/GPT session leads when it
  is lower, the Gemini session when it is lower, and a tie keeps Gemini.
