# An empty Grok reading does not erase a percentage

Date: 2026-09-21
Status: approved

## Context

A live Grok collect on 2026-09-21 stored `ready` with `windows: []`, no
error, and no action. The chip drew a dash. The popup said the plan does
not publish a usage percentage and offered no recovery action. Minutes
later the same credits endpoint returned `creditUsagePercent` and
`productUsage[].usagePercent` for GrokBuild. The credits parser read only
`creditUsagePercent` and `used / monthlyLimit`. `apply_stale_retention`
treated the empty ready row as the new truth, so it replaced the last
percentage.

`PROD-031` still describes a plan that has never published a quota, such
as the X Premium fixture. `PROD-025` already keeps a last good result,
including a zero-window result, across a temporary failure. It did not say
what an empty ready row does to a prior row that has windows.

## Decision

1. When `creditUsagePercent` is absent, the highest finite
   `productUsage[].usagePercent` becomes the same period window. Money
   fields stay discarded. A document with neither that percent, a credit
   percent, nor a positive monthly ratio stays `ready` with no windows.
2. `apply_stale_retention` keeps a prior ready or stale row that has
   windows when the new row is ready and has none. The kept row is
   `stale`, the prior percentage and `lastSuccessAt` stay, and the error
   is retryable. A prior row that already has no windows stays the new
   empty ready row, so `PROD-031` still holds for that plan.

## Consequences

The chip keeps the last percentage instead of switching to a dash that
claims the plan publishes nothing. The header refresh and the next poll
that carries a percent replace the stale row. A plan that never publishes
a percentage still shows the dash.
