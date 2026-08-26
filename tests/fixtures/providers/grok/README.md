# Grok billing fixtures

Captured on 2026-08-26 from Grok CLI 1.0.5 against
`https://cli-chat-proxy.grok.com/v1/billing` with an X Premium account,
values sanitized; no credentials, identifiers, or account labels are kept.

| File | Endpoint | Provenance |
| --- | --- | --- |
| `billing-weekly.json`, `billing-weekly-wrapped.json` | `?format=credits` | SuperGrok account: `creditUsagePercent` and `subscriptionTiers` present. |
| `billing-credits-no-quota.json` | `?format=credits` | X Premium account, verbatim shape: no `creditUsagePercent`, no `subscriptionTiers`. |
| `billing-monthly-zero.json` | no `format` | X Premium account, verbatim shape: `monthlyLimit.val` and `used.val` are `0`. |
| `billing-monthly-limit.json` | no `format` | Same shape as above with `monthlyLimit`/`used` set to non-zero values to exercise the ratio; a live positive-limit capture is still wanted. |
| `signals-recent.json` | local `~/.grok` signals | Context tokens only. |
