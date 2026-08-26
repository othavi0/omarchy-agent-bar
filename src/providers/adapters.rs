//! Concrete [`ProviderAdapter`] implementations for the four locked providers.

use crate::cli::ProviderId;
use crate::status::schema::{Account, Plan, ProviderResult};
use crate::support::redact::strip_ansi_and_controls;

use super::adapter::{
    collection_exe, login_available, missing_collection, unauthenticated, BoxFuture,
    CollectionContext, ProviderAdapter,
};
use super::catalog::{AMP, ANTIGRAVITY, CLAUDE, CODEX, GROK};
use super::codex_app_server::{fetch_rate_limits_via_appserver, AppServerOutcome};
use super::codex_session_log::find_latest_rate_limits;
use super::process::{ProcessOutput, ProcessSpec};
use super::v2_map::{
    amp_from_usage_text, antigravity_from_usage_json, claude_from_usage_json,
    codex_from_rate_limits_json, grok_from_billing_json,
};
use super::{Discovery, ProviderDescriptor};

// ---------------------------------------------------------------------------
// Amp
// ---------------------------------------------------------------------------

pub struct AmpAdapter;

pub static AMP_ADAPTER: AmpAdapter = AmpAdapter;

impl ProviderAdapter for AmpAdapter {
    fn descriptor(&self) -> &'static ProviderDescriptor {
        &AMP
    }

    fn collect<'a>(
        &'a self,
        context: &'a CollectionContext<'a>,
        discovery: &'a Discovery,
    ) -> BoxFuture<'a, ProviderResult> {
        Box::pin(async move {
            let Some(exe) = collection_exe(discovery) else {
                return missing_collection(ProviderId::Amp, AMP.display_name, AMP.installation_url);
            };
            let spec = ProcessSpec::new(exe, ["usage"])
                .with_timeout(AMP.timeout)
                .with_max_output(AMP.max_output_bytes)
                .with_env("NO_COLOR", "1")
                .with_env("TERM", "dumb");
            match context.process.run(&spec).await {
                Ok(out) if out.timed_out => ProviderResult::NetworkError {
                    id: ProviderId::Amp,
                    name: AMP.display_name.to_owned(),
                    message: "Amp usage timed out.".into(),
                },
                Ok(out) if out.exit_code != Some(0) => {
                    classify_amp_failure(&out, login_available(discovery))
                }
                Ok(out) => amp_from_usage_text(&out.stdout, context.clock.now_utc()),
                Err(_) => ProviderResult::NetworkError {
                    id: ProviderId::Amp,
                    name: AMP.display_name.to_owned(),
                    message: "Failed to run Amp usage.".into(),
                },
            }
        })
    }
}

/// Classify a non-zero `amp usage` exit. Unauthenticated requires an explicit
/// marker; a bare "auth" substring (e.g. "authorization server unavailable")
/// is an operational failure, not a login problem.
fn classify_amp_failure(out: &ProcessOutput, login_available: bool) -> ProviderResult {
    let stdout = out.stdout.to_ascii_lowercase();
    let stderr = out.stderr.to_ascii_lowercase();
    let explicit = ["not signed", "sign in", "unauthorized", "please log in"];
    if explicit
        .iter()
        .any(|m| stdout.contains(m) || stderr.contains(m))
    {
        return unauthenticated(
            ProviderId::Amp,
            AMP.display_name,
            "Amp is not authenticated.",
            login_available,
            AMP.installation_url,
            false,
        );
    }
    ProviderResult::ProviderError {
        id: ProviderId::Amp,
        name: AMP.display_name.to_owned(),
        message: "Amp usage command failed.".into(),
        retryable: false,
    }
}

// ---------------------------------------------------------------------------
// Grok
// ---------------------------------------------------------------------------

/// Authenticated billing endpoint (literal; equality-tested).
pub const GROK_BILLING_URL: &str = "https://cli-chat-proxy.grok.com/v1/billing?format=credits";
/// Monthly-limit billing shape, consulted only when the credits shape carries
/// no percentage (literal; equality-tested).
pub const GROK_MONTHLY_BILLING_URL: &str = "https://cli-chat-proxy.grok.com/v1/billing";

pub struct GrokAdapter;

pub static GROK_ADAPTER: GrokAdapter = GrokAdapter;

impl ProviderAdapter for GrokAdapter {
    fn descriptor(&self) -> &'static ProviderDescriptor {
        &GROK
    }

    fn collect<'a>(
        &'a self,
        context: &'a CollectionContext<'a>,
        discovery: &'a Discovery,
    ) -> BoxFuture<'a, ProviderResult> {
        Box::pin(async move {
            let grok_home = match context.env.resolve_grok_home() {
                Ok(path) => path,
                Err(_) => {
                    return ProviderResult::ProviderError {
                        id: ProviderId::Grok,
                        name: GROK.display_name.to_owned(),
                        message: "GROK_HOME is invalid.".into(),
                        retryable: false,
                    };
                }
            };
            if !grok_home.is_absolute() {
                return ProviderResult::ProviderError {
                    id: ProviderId::Grok,
                    name: GROK.display_name.to_owned(),
                    message: "Grok home must be absolute.".into(),
                    retryable: false,
                };
            }

            let auth_path = grok_home.join("auth.json");
            let auth_bytes = match context.fs.read(&auth_path) {
                Ok(bytes) => bytes,
                Err(_) => {
                    return unauthenticated(
                        ProviderId::Grok,
                        GROK.display_name,
                        "Grok is not authenticated.",
                        login_available(discovery),
                        GROK.installation_url,
                        false,
                    );
                }
            };

            // Token is used only for the Authorization header — never stored in
            // ProviderResult, logs, or error messages.
            let (token, account) = match parse_grok_auth_token(&auth_bytes) {
                Some(v) => v,
                None => {
                    return unauthenticated(
                        ProviderId::Grok,
                        GROK.display_name,
                        "Grok is not authenticated.",
                        login_available(discovery),
                        GROK.installation_url,
                        false,
                    );
                }
            };

            let bearer = format!("Bearer {token}");
            let headers = [
                ("Authorization", bearer.as_str()),
                ("x-grok-client-mode", "cli"),
            ];
            let max_body = GROK.max_output_bytes;
            let login = login_available(discovery);
            let now = context.clock.now_utc();

            match super::retry::http_get_with_retry(
                context.http,
                &GROK,
                GROK_BILLING_URL,
                &headers,
                max_body,
            )
            .await
            {
                Ok(resp) if (200..300).contains(&resp.status) => {
                    let _ = resp.final_url;
                    let credits = grok_from_billing_json(&resp.body, account.clone(), now, login);
                    match &credits {
                        ProviderResult::Ready { windows, .. } if windows.is_empty() => {
                            grok_monthly_fallback(
                                context, &headers, max_body, account, now, login, credits,
                            )
                            .await
                        }
                        _ => credits,
                    }
                }
                other => grok_http_failure(other, login),
            }
        })
    }
}

/// Second billing shape for accounts whose credits payload publishes no
/// percentage (monthly-limit teams). Network errors and 5xx are the same
/// typed operational results as the primary request, so the coordinator's
/// stale retention keeps the last good reading instead of an empty `Ready`
/// overwriting it. A 4xx, or a 2xx body without a window, keeps the credits
/// reading, including its `plan`/`account`.
async fn grok_monthly_fallback(
    context: &CollectionContext<'_>,
    headers: &[(&str, &str)],
    max_body: usize,
    account: Option<String>,
    now: time::OffsetDateTime,
    login: bool,
    credits: ProviderResult,
) -> ProviderResult {
    let response = super::retry::http_get_with_retry(
        context.http,
        &GROK,
        GROK_MONTHLY_BILLING_URL,
        headers,
        max_body,
    )
    .await;
    // The credits request just proved the token, so a 4xx here (including
    // 401/403 or a missing route) is not a fault of this account: keep the
    // credits reading. Network errors and 5xx are typed failures so stale
    // retention can protect a cached monthly window.
    let resp = match response {
        Ok(resp) if (200..300).contains(&resp.status) => resp,
        Ok(resp) if resp.status < 500 => return credits,
        other => return grok_http_failure(other, login),
    };
    let monthly = grok_from_billing_json(&resp.body, account, now, login);
    match (monthly, credits) {
        (
            ProviderResult::Ready {
                windows,
                plan: monthly_plan,
                ..
            },
            ProviderResult::Ready {
                id,
                name,
                source,
                plan,
                account,
                last_success_at,
                rate_limit_resets_available,
                ..
            },
        ) => ProviderResult::Ready {
            id,
            name,
            source,
            plan: plan.or(monthly_plan),
            account,
            windows,
            last_success_at,
            rate_limit_resets_available,
        },
        (_, credits) => credits,
    }
}

/// Map a non-2xx or failed billing request to its typed result. Shared by
/// the credits and monthly requests.
fn grok_http_failure(
    response: Result<super::adapter::HttpResponse, super::adapter::HttpError>,
    login: bool,
) -> ProviderResult {
    match response {
        Ok(resp) if resp.status == 401 || resp.status == 403 => unauthenticated(
            ProviderId::Grok,
            GROK.display_name,
            "Grok authentication was rejected.",
            login,
            GROK.installation_url,
            false,
        ),
        Ok(resp) => ProviderResult::ProviderError {
            id: ProviderId::Grok,
            name: GROK.display_name.to_owned(),
            message: "Grok billing request failed.".into(),
            retryable: resp.status >= 500,
        },
        Err(super::adapter::HttpError::Network(_)) => ProviderResult::NetworkError {
            id: ProviderId::Grok,
            name: GROK.display_name.to_owned(),
            message: "Network error while contacting Grok.".into(),
        },
        Err(super::adapter::HttpError::RedirectRefused(_)) => ProviderResult::ProviderError {
            id: ProviderId::Grok,
            name: GROK.display_name.to_owned(),
            message: "Grok billing redirect refused.".into(),
            retryable: false,
        },
        Err(super::adapter::HttpError::BodyTooLarge) => ProviderResult::ProviderError {
            id: ProviderId::Grok,
            name: GROK.display_name.to_owned(),
            message: "Grok billing response exceeded size limit.".into(),
            retryable: false,
        },
        Err(super::adapter::HttpError::InvalidResponse(_)) => ProviderResult::ProviderError {
            id: ProviderId::Grok,
            name: GROK.display_name.to_owned(),
            message: "Invalid Grok billing response.".into(),
            retryable: false,
        },
    }
}

/// Extract API key + optional first_name label from Grok `auth.json`.
///
/// Returns `None` when no non-empty `key` is present. The token must only be
/// used for the HTTP Authorization header and must never enter `ProviderResult`.
fn parse_grok_auth_token(bytes: &[u8]) -> Option<(String, Option<String>)> {
    let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let map = value.as_object()?;
    for (_k, entry) in map {
        let key = entry.get("key").and_then(|v| v.as_str()).unwrap_or("");
        if key.is_empty() {
            continue;
        }
        let name = entry
            .get("first_name")
            .and_then(|v| v.as_str())
            .map(str::to_owned);
        return Some((key.to_owned(), name));
    }
    None
}

// ---------------------------------------------------------------------------
// Codex
// ---------------------------------------------------------------------------

pub struct CodexAdapter;

pub static CODEX_ADAPTER: CodexAdapter = CodexAdapter;

impl ProviderAdapter for CodexAdapter {
    fn descriptor(&self) -> &'static ProviderDescriptor {
        &CODEX
    }

    fn collect<'a>(
        &'a self,
        context: &'a CollectionContext<'a>,
        discovery: &'a Discovery,
    ) -> BoxFuture<'a, ProviderResult> {
        Box::pin(async move {
            let home = &context.env.home;
            if !home.is_absolute() {
                return ProviderResult::ProviderError {
                    id: ProviderId::Codex,
                    name: CODEX.display_name.to_owned(),
                    message: "Codex home must be absolute.".into(),
                    retryable: false,
                };
            }

            // 1. App-server when collection exe is present (one timeout retry).
            if let Some(exe) = collection_exe(discovery) {
                let version = crate::app_identity::VERSION;
                let timeout = CODEX.timeout;
                let mut outcome = fetch_rate_limits_via_appserver(exe, version, timeout).await;
                if matches!(outcome, AppServerOutcome::TimedOut) {
                    tokio::time::sleep(std::time::Duration::from_millis(250)).await;
                    outcome = fetch_rate_limits_via_appserver(exe, version, timeout).await;
                }
                match outcome {
                    AppServerOutcome::Ok(bytes) => {
                        return codex_from_rate_limits_json(&bytes, context.clock.now_utc());
                    }
                    // JSON-004 / JSON-007: a signed-out account never falls
                    // through to obsolete session-log usage.
                    AppServerOutcome::Unauthenticated => {
                        return unauthenticated(
                            ProviderId::Codex,
                            CODEX.display_name,
                            "Codex is not authenticated.",
                            login_available(discovery),
                            CODEX.installation_url,
                            false,
                        );
                    }
                    AppServerOutcome::TimedOut | AppServerOutcome::Failed => {}
                }
            }

            // 2. Bounded session-log fallback (~/.codex/sessions/**/*.jsonl).
            // The log's own event timestamp — not collection time — becomes
            // last_success_at, since this data may be hours or days old.
            if let Some((bytes, log_timestamp)) =
                find_latest_rate_limits(&home.join(".codex/sessions"))
            {
                let now = log_timestamp.unwrap_or_else(|| context.clock.now_utc());
                return codex_from_rate_limits_json(&bytes, now);
            }

            // 3. Typed miss / cli_missing
            if collection_exe(discovery).is_none() {
                return missing_collection(
                    ProviderId::Codex,
                    CODEX.display_name,
                    CODEX.installation_url,
                );
            }
            ProviderResult::ProviderError {
                id: ProviderId::Codex,
                name: CODEX.display_name.to_owned(),
                message: "Codex rate limits were not available.".into(),
                retryable: true,
            }
        })
    }
}

// ---------------------------------------------------------------------------
// Claude
// ---------------------------------------------------------------------------

pub const CLAUDE_USAGE_URL: &str = "https://api.anthropic.com/api/oauth/usage";

pub struct ClaudeAdapter;

pub static CLAUDE_ADAPTER: ClaudeAdapter = ClaudeAdapter;

impl ProviderAdapter for ClaudeAdapter {
    fn descriptor(&self) -> &'static ProviderDescriptor {
        &CLAUDE
    }

    fn collect<'a>(
        &'a self,
        context: &'a CollectionContext<'a>,
        discovery: &'a Discovery,
    ) -> BoxFuture<'a, ProviderResult> {
        Box::pin(async move {
            let cred_path = context.env.home.join(".claude/.credentials.json");
            let cred_bytes = match context.fs.read(&cred_path) {
                Ok(b) => b,
                Err(_) => {
                    return unauthenticated(
                        ProviderId::Claude,
                        CLAUDE.display_name,
                        "Claude is not authenticated.",
                        login_available(discovery),
                        CLAUDE.installation_url,
                        false,
                    );
                }
            };
            let creds = match parse_claude_credentials(&cred_bytes) {
                Some(v) => v,
                None => {
                    return unauthenticated(
                        ProviderId::Claude,
                        CLAUDE.display_name,
                        "Claude is not authenticated.",
                        login_available(discovery),
                        CLAUDE.installation_url,
                        false,
                    );
                }
            };

            // An expired session self-heals when Claude Code refreshes the
            // token; report it as retryable so prior data is retained as stale.
            let now_ms = context
                .clock
                .now_utc()
                .unix_timestamp()
                .saturating_mul(1000);
            if creds.expires_at_ms.is_some_and(|exp| exp <= now_ms) {
                return unauthenticated(
                    ProviderId::Claude,
                    CLAUDE.display_name,
                    "Claude session expired. Open Claude Code to refresh it.",
                    login_available(discovery),
                    CLAUDE.installation_url,
                    true,
                );
            }

            // Never log the token. Pass only as Authorization header value.
            let bearer = format!("Bearer {}", creds.token);
            let headers = [
                ("Authorization", bearer.as_str()),
                ("anthropic-beta", "oauth-2025-04-20"),
            ];
            match super::retry::http_get_with_retry(
                context.http,
                &CLAUDE,
                CLAUDE_USAGE_URL,
                &headers,
                CLAUDE.max_output_bytes,
            )
            .await
            {
                Ok(resp) if resp.status == 401 || resp.status == 403 => unauthenticated(
                    ProviderId::Claude,
                    CLAUDE.display_name,
                    "Claude authentication was rejected.",
                    login_available(discovery),
                    CLAUDE.installation_url,
                    false,
                ),
                Ok(resp) if resp.status == 429 => ProviderResult::RateLimited {
                    id: ProviderId::Claude,
                    name: CLAUDE.display_name.to_owned(),
                    message: "Claude rate limited the request.".into(),
                },
                Ok(resp) if !(200..300).contains(&resp.status) => ProviderResult::ProviderError {
                    id: ProviderId::Claude,
                    name: CLAUDE.display_name.to_owned(),
                    message: "Claude usage request failed.".into(),
                    retryable: false,
                },
                Ok(resp) => {
                    // Redact: never store Authorization values in the domain result.
                    let _ = resp.final_url;
                    claude_from_usage_json(
                        &resp.body,
                        context.clock.now_utc(),
                        creds.plan,
                        creds.account,
                        login_available(discovery),
                    )
                }
                Err(super::adapter::HttpError::RedirectRefused(_)) => {
                    ProviderResult::ProviderError {
                        id: ProviderId::Claude,
                        name: CLAUDE.display_name.to_owned(),
                        message: "Claude usage redirect refused.".into(),
                        retryable: false,
                    }
                }
                Err(super::adapter::HttpError::BodyTooLarge) => ProviderResult::ProviderError {
                    id: ProviderId::Claude,
                    name: CLAUDE.display_name.to_owned(),
                    message: "Claude usage response exceeded size limit.".into(),
                    retryable: false,
                },
                Err(super::adapter::HttpError::Network(_)) => ProviderResult::NetworkError {
                    id: ProviderId::Claude,
                    name: CLAUDE.display_name.to_owned(),
                    message: "Network error while contacting Claude.".into(),
                },
                Err(super::adapter::HttpError::InvalidResponse(_)) => {
                    ProviderResult::ProviderError {
                        id: ProviderId::Claude,
                        name: CLAUDE.display_name.to_owned(),
                        message: "Invalid Claude usage response.".into(),
                        retryable: false,
                    }
                }
            }
        })
    }
}

struct ClaudeCredentials {
    token: String,
    plan: Option<Plan>,
    account: Option<Account>,
    expires_at_ms: Option<i64>,
}

fn parse_claude_credentials(bytes: &[u8]) -> Option<ClaudeCredentials> {
    let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let oauth = value.get("claudeAiOauth")?;
    let token = oauth.get("accessToken")?.as_str()?.to_owned();
    if token.is_empty() {
        return None;
    }
    let plan = claude_plan(
        oauth.get("subscriptionType").and_then(|v| v.as_str()),
        oauth.get("rateLimitTier").and_then(|v| v.as_str()),
    );
    let expires_at_ms = oauth.get("expiresAt").and_then(|v| v.as_i64());
    Some(ClaudeCredentials {
        token,
        plan,
        account: None,
        expires_at_ms,
    })
}

/// Prefer the granular rate-limit tier ("max_20x" → "Max 20x"); fall back to
/// the capitalized subscription type. Mirrors the native widget's formatTier.
fn claude_plan(subscription_type: Option<&str>, rate_limit_tier: Option<&str>) -> Option<Plan> {
    if let Some(tier) = rate_limit_tier.filter(|t| !t.is_empty()) {
        if let Some(pos) = tier.find("max_") {
            let suffix = &tier[pos + 4..];
            let digits = suffix.strip_suffix('x').unwrap_or("");
            if !digits.is_empty() && digits.chars().all(|c| c.is_ascii_digit()) {
                return Some(Plan {
                    id: tier.to_owned(),
                    label: format!("Max {suffix}"),
                });
            }
        }
        return Some(Plan {
            id: tier.to_owned(),
            label: capitalize_ascii(tier),
        });
    }
    let sub = subscription_type.filter(|s| !s.is_empty())?;
    Some(Plan {
        id: sub.to_owned(),
        label: capitalize_ascii(sub),
    })
}

fn capitalize_ascii(raw: &str) -> String {
    let mut chars = raw.chars();
    match chars.next() {
        Some(first) => first.to_ascii_uppercase().to_string() + chars.as_str(),
        None => String::new(),
    }
}

/// Test-only fixed clock.
#[cfg(test)]
pub struct FixedClock(pub time::OffsetDateTime);

#[cfg(test)]
impl crate::support::Clock for FixedClock {
    fn now_utc(&self) -> time::OffsetDateTime {
        self.0
    }
}

// ---------------------------------------------------------------------------
// Antigravity
// ---------------------------------------------------------------------------

pub struct AntigravityAdapter;

pub static ANTIGRAVITY_ADAPTER: AntigravityAdapter = AntigravityAdapter;

impl ProviderAdapter for AntigravityAdapter {
    fn descriptor(&self) -> &'static ProviderDescriptor {
        &ANTIGRAVITY
    }

    fn collect<'a>(
        &'a self,
        context: &'a CollectionContext<'a>,
        discovery: &'a Discovery,
    ) -> BoxFuture<'a, ProviderResult> {
        Box::pin(async move {
            let Some(exe) = collection_exe(discovery) else {
                return missing_collection(
                    ProviderId::Antigravity,
                    ANTIGRAVITY.display_name,
                    ANTIGRAVITY.installation_url,
                );
            };

            // Version guard before the usage call: on releases older than
            // ANTIGRAVITY_MIN_VERSION the slash command is not intercepted and
            // "/usage" reaches the model as an ordinary prompt, spending the
            // very quota we are trying to report.
            match context
                .process
                .run(&antigravity_spec(exe, &["--version"]))
                .await
            {
                Ok(out) if out.timed_out => {
                    return ProviderResult::NetworkError {
                        id: ProviderId::Antigravity,
                        name: ANTIGRAVITY.display_name.to_owned(),
                        message: "Antigravity usage command timed out.".into(),
                    };
                }
                Err(_) => {
                    return ProviderResult::NetworkError {
                        id: ProviderId::Antigravity,
                        name: ANTIGRAVITY.display_name.to_owned(),
                        message: "Failed to run Antigravity usage.".into(),
                    };
                }
                Ok(out) => {
                    // A non-zero exit leaves us without a version, which is
                    // the same answer as an unparseable one: we may not run
                    // the usage command.
                    let supported = out.exit_code == Some(0)
                        && parse_version_prefix(&out.stdout)
                            .is_some_and(|found| found >= ANTIGRAVITY_MIN_VERSION);
                    if !supported {
                        return antigravity_unsupported_version();
                    }
                }
            }

            let spec = antigravity_spec(exe, ANTIGRAVITY_USAGE_ARGV);

            match context.process.run(&spec).await {
                Ok(out) if out.timed_out => ProviderResult::NetworkError {
                    id: ProviderId::Antigravity,
                    name: ANTIGRAVITY.display_name.to_owned(),
                    message: "Antigravity usage command timed out.".into(),
                },
                Ok(out) if out.exit_code != Some(0) => {
                    classify_antigravity_failure(&out, login_available(discovery))
                }
                // A logged-out `agy` prints its banner and still exits 0, so
                // the marker has to be checked before parsing; otherwise the
                // empty quota block would render as a connected provider.
                Ok(out) if antigravity_logged_out(&out) => unauthenticated(
                    ProviderId::Antigravity,
                    ANTIGRAVITY.display_name,
                    "Antigravity is not authenticated.",
                    login_available(discovery),
                    ANTIGRAVITY.installation_url,
                    false,
                ),
                Ok(out) => antigravity_from_usage_json(&out.stdout, context.clock.now_utc()),
                Err(_) => ProviderResult::NetworkError {
                    id: ProviderId::Antigravity,
                    name: ANTIGRAVITY.display_name.to_owned(),
                    message: "Failed to run Antigravity usage.".into(),
                },
            }
        })
    }
}

/// Oldest `agy` release Agent Bar is willing to query.
///
/// From 1.1.11 the CLI intercepts `-p "/usage"` and answers it from local
/// state without starting an agent turn; on earlier releases the same text is
/// forwarded to the model as an ordinary prompt, which spends the quota this
/// provider exists to report. Sourced from the changelog embedded in the
/// `agy` 1.1.18 binary.
const ANTIGRAVITY_MIN_VERSION: (u32, u32, u32) = (1, 1, 11);

/// Usage argv. `--output-format json` landed in the same 1.1.11 release the
/// version guard above requires, so the guard is what makes this argv safe to
/// send: an older CLI would neither intercept the slash command nor know the
/// flag.
const ANTIGRAVITY_USAGE_ARGV: &[&str] = &["--print", "/usage", "--output-format", "json"];

/// Build one `agy` invocation. Every call shares the catalog's timeout and
/// output cap, and both env vars: `agy` renders a coloured TUI when it
/// believes it has a terminal, and the escapes would reach the parser.
fn antigravity_spec(exe: &std::path::Path, args: &[&str]) -> ProcessSpec {
    ProcessSpec::new(exe, args.iter().copied())
        .with_timeout(ANTIGRAVITY.timeout)
        .with_max_output(ANTIGRAVITY.max_output_bytes)
        .with_env("NO_COLOR", "1")
        .with_env("TERM", "dumb")
}

/// Typed refusal for a CLI too old to answer `/usage` without spending quota.
/// Not retryable: only reinstalling the CLI can change the answer.
fn antigravity_unsupported_version() -> ProviderResult {
    let (major, minor, patch) = ANTIGRAVITY_MIN_VERSION;
    ProviderResult::ProviderError {
        id: ProviderId::Antigravity,
        name: ANTIGRAVITY.display_name.to_owned(),
        message: format!("Antigravity CLI {major}.{minor}.{patch} or newer is required."),
        retryable: false,
    }
}

/// Leading `major.minor.patch` of `agy --version` output ("1.1.18\n").
///
/// A `v` prefix and anything after the patch number are tolerated so a future
/// "v1.2.0-rc1" or "1.2.0 (build 4)" still reads as a version. The provider
/// output itself never reaches a message — only this triple is kept.
fn parse_version_prefix(text: &str) -> Option<(u32, u32, u32)> {
    let line = strip_ansi_and_controls(text);
    let token = line.trim().lines().next()?.trim();
    let token = token.strip_prefix(['v', 'V']).unwrap_or(token);
    let mut fields = token.splitn(3, '.');
    let major = fields.next()?.parse().ok()?;
    let minor = fields.next()?.parse().ok()?;
    let patch_field = fields.next()?;
    let digits: String = patch_field
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .collect();
    Some((major, minor, digits.parse().ok()?))
}

/// Explicit logged-out marker, matched on ANSI-stripped stdout and stderr —
/// same shape as [`classify_amp_failure`], deliberately narrow so an
/// unrelated "auth" mention never reads as a login problem.
///
/// The banner is the only logged-out signal: it is printed on an exit-0 run
/// (captured fixture), and the CLI documents no exit code to lean on.
fn antigravity_logged_out(out: &ProcessOutput) -> bool {
    const MARKER: &str = "not signed in";
    let stdout = strip_ansi_and_controls(&out.stdout).to_ascii_lowercase();
    let stderr = strip_ansi_and_controls(&out.stderr).to_ascii_lowercase();
    stdout.contains(MARKER) || stderr.contains(MARKER)
}

/// Classify a non-zero `agy` exit. The CLI documents no exit codes, so the
/// logged-out banner on stdout/stderr is the only signal trusted here;
/// anything else is a fixed provider error that echoes no provider output.
fn classify_antigravity_failure(out: &ProcessOutput, login_available: bool) -> ProviderResult {
    if antigravity_logged_out(out) {
        return unauthenticated(
            ProviderId::Antigravity,
            ANTIGRAVITY.display_name,
            "Antigravity is not authenticated.",
            login_available,
            ANTIGRAVITY.installation_url,
            false,
        );
    }
    ProviderResult::ProviderError {
        id: ProviderId::Antigravity,
        name: ANTIGRAVITY.display_name.to_owned(),
        message: "Antigravity usage command failed.".into(),
        retryable: false,
    }
}

/// In-memory filesystem for adapter tests.
#[cfg(test)]
#[derive(Default)]
pub struct MapFileSystem {
    pub files: std::collections::HashMap<std::path::PathBuf, Vec<u8>>,
}

#[cfg(test)]
impl crate::support::FileSystem for MapFileSystem {
    fn read(&self, path: &std::path::Path) -> std::io::Result<Vec<u8>> {
        self.files
            .get(path)
            .cloned()
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "missing"))
    }

    fn metadata(&self, path: &std::path::Path) -> std::io::Result<crate::support::FileMetadata> {
        let bytes = self.read(path)?;
        Ok(crate::support::FileMetadata {
            len: bytes.len() as u64,
            modified: None,
            is_dir: false,
            is_symlink: false,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::providers::adapter::{CollectionContext, HttpError, HttpResponse};
    use crate::providers::catalog::{
        CollectionAvailability, ExecutionEnvironment, LoginAvailability,
    };
    use crate::providers::http::ScriptedHttpClient;
    use crate::providers::process::{ProcessError, ProcessOutput, ProcessRunner, ProcessSpec};
    use crate::providers::v2_map::assert_no_money;
    use std::path::Path;
    use std::sync::Mutex;
    use time::macros::datetime;

    struct ScriptedProcess {
        /// Pending results in reverse order: `run` pops from the back.
        outputs: Mutex<Vec<Result<ProcessOutput, ProcessError>>>,
        pub last_spec: Mutex<Option<ProcessSpec>>,
        /// Every spec seen, in call order, so a multi-call adapter can be
        /// asserted invocation by invocation.
        pub specs: Mutex<Vec<ProcessSpec>>,
    }

    impl ScriptedProcess {
        fn one(out: ProcessOutput) -> Self {
            Self::sequence(vec![Ok(out)])
        }

        /// Script consecutive runs: `outputs[0]` answers the first call.
        fn sequence(outputs: Vec<Result<ProcessOutput, ProcessError>>) -> Self {
            let mut reversed = outputs;
            reversed.reverse();
            Self {
                outputs: Mutex::new(reversed),
                last_spec: Mutex::new(None),
                specs: Mutex::new(Vec::new()),
            }
        }

        fn calls(&self) -> Vec<ProcessSpec> {
            self.specs.lock().unwrap().clone()
        }
    }

    impl ProcessRunner for ScriptedProcess {
        fn run<'a>(
            &'a self,
            spec: &'a ProcessSpec,
        ) -> std::pin::Pin<
            Box<dyn std::future::Future<Output = Result<ProcessOutput, ProcessError>> + Send + 'a>,
        > {
            *self.last_spec.lock().unwrap() = Some(spec.clone());
            self.specs.lock().unwrap().push(spec.clone());
            let next = self
                .outputs
                .lock()
                .unwrap()
                .pop()
                .unwrap_or_else(|| Err(ProcessError::Spawn("empty".into())));
            Box::pin(async move { next })
        }
    }

    fn discovery_with_exe(path: &Path) -> Discovery {
        Discovery {
            collection: CollectionAvailability::Available {
                executable: path.to_path_buf(),
            },
            login: LoginAvailability::Available {
                executable: path.to_path_buf(),
            },
        }
    }

    #[tokio::test]
    async fn amp_collect_ready_from_fixture() {
        let fixture = include_str!("../../tests/fixtures/amp/usage-free-pct.txt");
        let process = ScriptedProcess::one(ProcessOutput {
            exit_code: Some(0),
            stdout: fixture.to_owned(),
            stderr: String::new(),
            timed_out: false,
            stdout_truncated: false,
            stderr_truncated: false,
        });
        let http = ScriptedHttpClient::default();
        let fs = MapFileSystem::default();
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/tmp/home"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(Path::new("/usr/bin/amp"));
        let result = AMP_ADAPTER.collect(&ctx, &discovery).await;
        assert_no_money(&result);
        assert!(matches!(result, ProviderResult::Ready { .. }));
        let spec = process.last_spec.lock().unwrap().clone().unwrap();
        assert_eq!(spec.args, vec!["usage".to_owned()]);
        assert!(spec.env.iter().any(|(k, v)| k == "NO_COLOR" && v == "1"));
    }

    fn fake_process_output(exit_code: i32, stdout: &str, stderr: &str) -> ProcessOutput {
        ProcessOutput {
            exit_code: Some(exit_code),
            stdout: stdout.to_owned(),
            stderr: stderr.to_owned(),
            timed_out: false,
            stdout_truncated: false,
            stderr_truncated: false,
        }
    }

    #[test]
    fn amp_network_flavored_auth_substring_is_not_unauthenticated() {
        // "authorization server unavailable" contains "auth" but is operational.
        let out = fake_process_output(1, "", "authorization server unavailable");
        let result = classify_amp_failure(&out, true);
        assert!(matches!(result, ProviderResult::ProviderError { .. }));
    }

    #[test]
    fn amp_not_signed_in_is_unauthenticated() {
        let out = fake_process_output(1, "You are not signed in. Run amp login.", "");
        let result = classify_amp_failure(&out, true);
        assert!(matches!(result, ProviderResult::Unauthenticated { .. }));
    }

    #[tokio::test]
    async fn claude_500_with_auth_wording_is_not_unauthenticated() {
        let http = ScriptedHttpClient::single(Ok(HttpResponse {
            status: 500,
            final_url: CLAUDE_USAGE_URL.into(),
            body: br#"{"error":"authorization server unavailable"}"#.to_vec(),
        }));
        let process = ScriptedProcess::one(fake_process_output(0, "", ""));
        let mut fs = MapFileSystem::default();
        fs.files.insert(
            std::path::PathBuf::from("/home/u/.claude/.credentials.json"),
            br#"{"claudeAiOauth":{"accessToken":"SECRET_TOKEN_VALUE","subscriptionType":"pro"}}"#
                .to_vec(),
        );
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/home/u"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(Path::new("/usr/bin/claude"));
        let result = CLAUDE_ADAPTER.collect(&ctx, &discovery).await;
        assert!(!format!("{result:?}").contains("SECRET_TOKEN_VALUE"));
        assert!(
            !matches!(result, ProviderResult::Unauthenticated { .. }),
            "status 500 is operational, got {result:?}"
        );
    }

    async fn grok_ctx_collect(http: &ScriptedHttpClient) -> ProviderResult {
        let process = empty_process();
        let mut fs = MapFileSystem::default();
        let env = grok_test_env_and_auth(&mut fs);
        let clock = FixedClock(datetime!(2026-08-26 12:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http,
            plugin_root: None,
        };
        let discovery = Discovery {
            collection: CollectionAvailability::Missing,
            login: LoginAvailability::Available {
                executable: std::path::PathBuf::from("/usr/bin/grok"),
            },
        };
        GROK_ADAPTER.collect(&ctx, &discovery).await
    }

    fn scripted_pair(
        first: HttpResponse,
        second: Result<HttpResponse, HttpError>,
    ) -> ScriptedHttpClient {
        // Responses pop from the end: push the second call first.
        let client = ScriptedHttpClient::single(second);
        client
            .responses
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(Ok(first));
        client
    }

    #[tokio::test]
    async fn grok_credits_without_quota_falls_back_to_monthly_limit() {
        let credits =
            include_bytes!("../../tests/fixtures/providers/grok/billing-credits-no-quota.json");
        let monthly =
            include_bytes!("../../tests/fixtures/providers/grok/billing-monthly-limit.json");
        let http = scripted_pair(
            HttpResponse {
                status: 200,
                final_url: GROK_BILLING_URL.into(),
                body: credits.to_vec(),
            },
            Ok(HttpResponse {
                status: 200,
                final_url: GROK_MONTHLY_BILLING_URL.into(),
                body: monthly.to_vec(),
            }),
        );
        let result = grok_ctx_collect(&http).await;
        assert_no_money(&result);
        assert_eq!(
            http.last_url.lock().unwrap().as_deref(),
            Some(GROK_MONTHLY_BILLING_URL)
        );
        match result {
            ProviderResult::Ready { windows, .. } => {
                assert_eq!(windows.len(), 1, "got {windows:?}");
                assert_eq!(windows[0].id(), "monthly");
                assert!((windows[0].used_percent() - 25.0).abs() < 0.01);
            }
            other => panic!("expected ready, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn grok_monthly_fallback_network_failure_is_typed() {
        // A failed second request must not become an empty `Ready` that
        // evicts a cached monthly window; it is a retryable operational result.
        let credits =
            include_bytes!("../../tests/fixtures/providers/grok/billing-credits-no-quota.json");
        let http = scripted_pair(
            HttpResponse {
                status: 200,
                final_url: GROK_BILLING_URL.into(),
                body: credits.to_vec(),
            },
            Err(HttpError::Network("offline".into())),
        );
        let result = grok_ctx_collect(&http).await;
        assert!(
            matches!(result, ProviderResult::NetworkError { .. }),
            "{result:?}"
        );
    }

    #[tokio::test]
    async fn grok_monthly_fallback_5xx_is_retryable_provider_error() {
        let credits =
            include_bytes!("../../tests/fixtures/providers/grok/billing-credits-no-quota.json");
        let http = scripted_pair(
            HttpResponse {
                status: 200,
                final_url: GROK_BILLING_URL.into(),
                body: credits.to_vec(),
            },
            Ok(HttpResponse {
                status: 503,
                final_url: GROK_MONTHLY_BILLING_URL.into(),
                body: b"{}".to_vec(),
            }),
        );
        let result = grok_ctx_collect(&http).await;
        assert!(
            matches!(
                result,
                ProviderResult::ProviderError {
                    retryable: true,
                    ..
                }
            ),
            "{result:?}"
        );
    }

    #[tokio::test]
    async fn grok_monthly_fallback_4xx_keeps_credits_reading() {
        let credits =
            include_bytes!("../../tests/fixtures/providers/grok/billing-credits-no-quota.json");
        for status in [401u16, 403, 404, 429] {
            let http = scripted_pair(
                HttpResponse {
                    status: 200,
                    final_url: GROK_BILLING_URL.into(),
                    body: credits.to_vec(),
                },
                Ok(HttpResponse {
                    status,
                    final_url: GROK_MONTHLY_BILLING_URL.into(),
                    body: b"{}".to_vec(),
                }),
            );
            let result = grok_ctx_collect(&http).await;
            match result {
                ProviderResult::Ready {
                    windows, account, ..
                } => {
                    assert!(windows.is_empty(), "status {status}: {windows:?}");
                    assert!(account.is_some(), "status {status}");
                }
                other => panic!("status {status}: expected ready, got {other:?}"),
            }
        }
    }

    #[tokio::test]
    async fn grok_monthly_fallback_keeps_plan_and_account_from_credits() {
        let credits = br#"{"config": {"subscriptionTiers": "SuperGrok",
            "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY"}}}"#;
        let monthly =
            include_bytes!("../../tests/fixtures/providers/grok/billing-monthly-limit.json");
        let http = scripted_pair(
            HttpResponse {
                status: 200,
                final_url: GROK_BILLING_URL.into(),
                body: credits.to_vec(),
            },
            Ok(HttpResponse {
                status: 200,
                final_url: GROK_MONTHLY_BILLING_URL.into(),
                body: monthly.to_vec(),
            }),
        );
        let result = grok_ctx_collect(&http).await;
        match result {
            ProviderResult::Ready {
                windows,
                plan,
                account,
                ..
            } => {
                assert_eq!(windows.len(), 1);
                assert_eq!(windows[0].id(), "monthly");
                assert_eq!(plan.as_ref().map(|p| p.label.as_str()), Some("SuperGrok"));
                assert!(
                    account.is_some(),
                    "account label from auth.json must survive"
                );
            }
            other => panic!("expected ready, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn grok_no_quota_on_either_shape_keeps_credits_account() {
        let credits =
            include_bytes!("../../tests/fixtures/providers/grok/billing-credits-no-quota.json");
        let monthly =
            include_bytes!("../../tests/fixtures/providers/grok/billing-monthly-zero.json");
        let http = scripted_pair(
            HttpResponse {
                status: 200,
                final_url: GROK_BILLING_URL.into(),
                body: credits.to_vec(),
            },
            Ok(HttpResponse {
                status: 200,
                final_url: GROK_MONTHLY_BILLING_URL.into(),
                body: monthly.to_vec(),
            }),
        );
        let result = grok_ctx_collect(&http).await;
        match result {
            ProviderResult::Ready {
                windows,
                account,
                source,
                ..
            } => {
                assert!(windows.is_empty());
                assert!(account.is_some());
                assert_eq!(source, crate::status::schema::DataSource::Live);
            }
            other => panic!("expected ready, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn grok_credits_with_quota_makes_a_single_request() {
        let body = include_bytes!("../../tests/fixtures/providers/grok/billing-weekly.json");
        let http = ScriptedHttpClient::single(Ok(HttpResponse {
            status: 200,
            final_url: GROK_BILLING_URL.into(),
            body: body.to_vec(),
        }));
        let result = grok_ctx_collect(&http).await;
        assert!(matches!(result, ProviderResult::Ready { .. }), "{result:?}");
        assert_eq!(
            http.last_url.lock().unwrap().as_deref(),
            Some(GROK_BILLING_URL)
        );
    }

    #[tokio::test]
    async fn grok_500_with_auth_wording_is_not_unauthenticated() {
        let http = ScriptedHttpClient::single(Ok(HttpResponse {
            status: 500,
            final_url: GROK_BILLING_URL.into(),
            body: br#"{"error":"authorization server unavailable"}"#.to_vec(),
        }));
        let process = empty_process();
        let mut fs = MapFileSystem::default();
        let env = grok_test_env_and_auth(&mut fs);
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = Discovery {
            collection: CollectionAvailability::Missing,
            login: LoginAvailability::Available {
                executable: std::path::PathBuf::from("/usr/bin/grok"),
            },
        };
        let result = GROK_ADAPTER.collect(&ctx, &discovery).await;
        assert!(
            !matches!(result, ProviderResult::Unauthenticated { .. }),
            "status 500 is operational, got {result:?}"
        );
    }

    #[test]
    fn antigravity_auth_wording_without_marker_is_not_unauthenticated() {
        let out = fake_process_output(1, "", "authorization server unavailable");
        let result = classify_antigravity_failure(&out, true);
        assert!(
            matches!(result, ProviderResult::ProviderError { .. }),
            "got {result:?}"
        );
    }

    #[tokio::test]
    async fn amp_missing_collection_source() {
        let process = ScriptedProcess::one(ProcessOutput {
            exit_code: Some(0),
            stdout: String::new(),
            stderr: String::new(),
            timed_out: false,
            stdout_truncated: false,
            stderr_truncated: false,
        });
        let http = ScriptedHttpClient::default();
        let fs = MapFileSystem::default();
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/tmp/home"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = Discovery {
            collection: CollectionAvailability::Missing,
            login: LoginAvailability::Missing,
        };
        let result = AMP_ADAPTER.collect(&ctx, &discovery).await;
        assert!(matches!(result, ProviderResult::CliMissing { .. }));
    }

    #[tokio::test]
    async fn claude_http_exact_url_and_redacts_auth_from_domain() {
        let body = br#"{"five_hour":{"utilization":10.0,"resets_at":"2026-07-26T22:00:00Z"}}"#;
        let http = ScriptedHttpClient::single(Ok(HttpResponse {
            status: 200,
            final_url: CLAUDE_USAGE_URL.into(),
            body: body.to_vec(),
        }));
        let process = ScriptedProcess::one(ProcessOutput {
            exit_code: Some(0),
            stdout: String::new(),
            stderr: String::new(),
            timed_out: false,
            stdout_truncated: false,
            stderr_truncated: false,
        });
        let mut fs = MapFileSystem::default();
        let cred_path = std::path::PathBuf::from("/home/u/.claude/.credentials.json");
        fs.files.insert(
            cred_path.clone(),
            br#"{"claudeAiOauth":{"accessToken":"SECRET_TOKEN_VALUE","subscriptionType":"pro"}}"#
                .to_vec(),
        );
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/home/u"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(Path::new("/usr/bin/claude"));
        let result = CLAUDE_ADAPTER.collect(&ctx, &discovery).await;
        let dbg = format!("{result:?}");
        assert!(!dbg.contains("SECRET_TOKEN_VALUE"));
        assert_eq!(
            http.last_url.lock().unwrap().as_deref(),
            Some(CLAUDE_USAGE_URL)
        );
        let headers = http.last_headers.lock().unwrap().clone();
        assert!(
            headers.iter().any(|(k, v)| {
                k == "Authorization" && v.starts_with("Bearer ") && v.contains("SECRET_TOKEN_VALUE")
            }),
            "Authorization Bearer header missing: got keys {:?}",
            headers.iter().map(|(k, _)| k.as_str()).collect::<Vec<_>>()
        );
        assert!(
            headers
                .iter()
                .any(|(k, v)| k == "anthropic-beta" && v == "oauth-2025-04-20"),
            "anthropic-beta header missing"
        );
        assert!(matches!(result, ProviderResult::Ready { .. }));
        assert_no_money(&result);
    }

    #[tokio::test]
    async fn claude_redirect_refused() {
        let http = ScriptedHttpClient::single(Err(
            crate::providers::adapter::HttpError::RedirectRefused("https://evil.example/".into()),
        ));
        let process = ScriptedProcess::one(ProcessOutput {
            exit_code: Some(0),
            stdout: String::new(),
            stderr: String::new(),
            timed_out: false,
            stdout_truncated: false,
            stderr_truncated: false,
        });
        let mut fs = MapFileSystem::default();
        fs.files.insert(
            std::path::PathBuf::from("/home/u/.claude/.credentials.json"),
            br#"{"claudeAiOauth":{"accessToken":"tok"}}"#.to_vec(),
        );
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/home/u"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(Path::new("/usr/bin/claude"));
        let result = CLAUDE_ADAPTER.collect(&ctx, &discovery).await;
        assert!(matches!(result, ProviderResult::ProviderError { .. }));
    }

    #[tokio::test]
    async fn claude_retries_once_on_network_error() {
        let body = br#"{"five_hour":{"utilization":10.0,"resets_at":"2026-07-28T22:00:00Z"}}"#;
        let http = ScriptedHttpClient {
            responses: Mutex::new(vec![
                Ok(HttpResponse {
                    status: 200,
                    final_url: CLAUDE_USAGE_URL.into(),
                    body: body.to_vec(),
                }),
                Err(crate::providers::adapter::HttpError::Network("blip".into())),
            ]),
            last_url: Mutex::new(None),
            last_headers: Mutex::new(Vec::new()),
        };
        let process = empty_process();
        let mut fs = MapFileSystem::default();
        fs.files.insert(
            std::path::PathBuf::from("/home/u/.claude/.credentials.json"),
            br#"{"claudeAiOauth":{"accessToken":"tok"}}"#.to_vec(),
        );
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/home/u"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-07-28 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(Path::new("/usr/bin/claude"));
        let result = CLAUDE_ADAPTER.collect(&ctx, &discovery).await;
        assert!(
            matches!(result, ProviderResult::Ready { .. }),
            "one transient network error must be retried: {result:?}"
        );
    }

    #[tokio::test]
    async fn claude_expired_token_skips_http_and_is_retryable() {
        let http = ScriptedHttpClient::default(); // any HTTP call would error
        let process = empty_process();
        let mut fs = MapFileSystem::default();
        fs.files.insert(
            std::path::PathBuf::from("/home/u/.claude/.credentials.json"),
            // expiresAt in the past relative to the fixed clock below.
            br#"{"claudeAiOauth":{"accessToken":"tok","expiresAt":1690000000000}}"#.to_vec(),
        );
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/home/u"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-07-28 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(Path::new("/usr/bin/claude"));
        let result = CLAUDE_ADAPTER.collect(&ctx, &discovery).await;
        assert!(
            http.last_url.lock().unwrap().is_none(),
            "expired token must not trigger an HTTP request"
        );
        match result {
            ProviderResult::Unauthenticated {
                message, retryable, ..
            } => {
                assert!(message.contains("expired"), "message: {message}");
                assert!(retryable, "expired session must be retryable");
            }
            other => panic!("expected unauthenticated, got {other:?}"),
        }
    }

    #[test]
    fn claude_plan_formats_rate_limit_tier() {
        let plan = claude_plan(Some("max"), Some("max_20x"));
        assert_eq!(plan.as_ref().map(|p| p.label.as_str()), Some("Max 20x"));
        assert_eq!(plan.as_ref().map(|p| p.id.as_str()), Some("max_20x"));

        // Real-world tier shape observed live: prefix before max_.
        let real = claude_plan(Some("max"), Some("default_claude_max_20x"));
        assert_eq!(real.as_ref().map(|p| p.label.as_str()), Some("Max 20x"));
        assert_eq!(
            real.as_ref().map(|p| p.id.as_str()),
            Some("default_claude_max_20x")
        );

        let fallback = claude_plan(Some("pro"), None);
        assert_eq!(fallback.as_ref().map(|p| p.label.as_str()), Some("Pro"));
        assert_eq!(fallback.as_ref().map(|p| p.id.as_str()), Some("pro"));

        assert!(claude_plan(None, None).is_none());
    }

    fn grok_test_env_and_auth(fs: &mut MapFileSystem) -> ExecutionEnvironment {
        let home = std::path::PathBuf::from("/home/u");
        let grok_home = home.join(".grok");
        fs.files.insert(
            grok_home.join("auth.json"),
            // Synthetic key — not a real JWT or credential.
            br#"{"acct":{"key":"SYNTH_GROK_KEY_NOT_REAL","first_name":"Ada"}}"#.to_vec(),
        );
        ExecutionEnvironment {
            home,
            path_dirs: vec![],
            grok_home: None,
        }
    }

    fn empty_process() -> ScriptedProcess {
        ScriptedProcess::one(ProcessOutput {
            exit_code: Some(0),
            stdout: String::new(),
            stderr: String::new(),
            timed_out: false,
            stdout_truncated: false,
            stderr_truncated: false,
        })
    }

    #[tokio::test]
    async fn grok_ready_from_billing_http() {
        let body = include_bytes!("../../tests/fixtures/providers/grok/billing-weekly.json");
        let http = ScriptedHttpClient::single(Ok(HttpResponse {
            status: 200,
            final_url: GROK_BILLING_URL.into(),
            body: body.to_vec(),
        }));
        let process = empty_process();
        let mut fs = MapFileSystem::default();
        let env = grok_test_env_and_auth(&mut fs);
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = Discovery {
            collection: CollectionAvailability::Missing,
            login: LoginAvailability::Available {
                executable: std::path::PathBuf::from("/usr/bin/grok"),
            },
        };
        let result = GROK_ADAPTER.collect(&ctx, &discovery).await;
        assert_no_money(&result);
        let dbg = format!("{result:?}");
        assert!(
            !dbg.contains("SYNTH_GROK_KEY_NOT_REAL"),
            "token must not appear in domain result"
        );
        assert_eq!(
            http.last_url.lock().unwrap().as_deref(),
            Some(GROK_BILLING_URL)
        );
        let headers = http.last_headers.lock().unwrap().clone();
        assert!(
            headers.iter().any(|(k, v)| {
                k == "Authorization" && v.starts_with("Bearer ") && v.contains("SYNTH_GROK_KEY")
            }),
            "Authorization Bearer header missing: {headers:?}"
        );
        assert!(
            headers
                .iter()
                .any(|(k, v)| k == "x-grok-client-mode" && v == "cli"),
            "x-grok-client-mode header missing: {headers:?}"
        );
        match result {
            ProviderResult::Ready {
                windows, account, ..
            } => {
                assert_eq!(windows.len(), 1);
                assert_eq!(windows[0].id(), "weekly");
                assert_eq!(windows[0].label(), "Weekly (7d)");
                assert!(windows.iter().all(|w| w.id() != "context"));
                assert_eq!(account.as_ref().map(|a| a.label.as_str()), Some("Ada"));
            }
            other => panic!("{other:?}"),
        }
    }

    #[tokio::test]
    async fn grok_billing_401_unauthenticated() {
        let http = ScriptedHttpClient::single(Ok(HttpResponse {
            status: 401,
            final_url: GROK_BILLING_URL.into(),
            body: br#"{"error":"unauthorized"}"#.to_vec(),
        }));
        let process = empty_process();
        let mut fs = MapFileSystem::default();
        let env = grok_test_env_and_auth(&mut fs);
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = Discovery {
            collection: CollectionAvailability::Missing,
            login: LoginAvailability::Available {
                executable: std::path::PathBuf::from("/usr/bin/grok"),
            },
        };
        let result = GROK_ADAPTER.collect(&ctx, &discovery).await;
        let dbg = format!("{result:?}");
        assert!(!dbg.contains("SYNTH_GROK_KEY_NOT_REAL"));
        assert!(matches!(result, ProviderResult::Unauthenticated { .. }));
    }

    #[tokio::test]
    async fn grok_billing_timeout_network_error() {
        let http = ScriptedHttpClient::single(Err(crate::providers::adapter::HttpError::Network(
            "timeout".into(),
        )));
        let process = empty_process();
        let mut fs = MapFileSystem::default();
        let env = grok_test_env_and_auth(&mut fs);
        let clock = FixedClock(datetime!(2026-07-26 18:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(Path::new("/usr/bin/grok"));
        let result = GROK_ADAPTER.collect(&ctx, &discovery).await;
        let dbg = format!("{result:?}");
        assert!(!dbg.contains("SYNTH_GROK_KEY_NOT_REAL"));
        assert!(matches!(result, ProviderResult::NetworkError { .. }));
    }

    #[tokio::test]
    async fn codex_session_log_last_success_at_uses_log_timestamp_not_clock() {
        let process = empty_process();
        let http = ScriptedHttpClient::default();
        let fs = MapFileSystem::default();

        // Real tempdir: find_latest_rate_limits walks std::fs directly, not
        // the injected fs seam.
        let home_dir = tempfile::tempdir().expect("tempdir");
        let home = home_dir.path().to_path_buf();
        let sessions = home.join(".codex/sessions/2026/07/28");
        std::fs::create_dir_all(&sessions).expect("mkdir sessions");
        let jsonl = concat!(
            r#"{"timestamp":"2026-07-28T10:00:00Z","type":"event","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.5,"window_minutes":10080}}}}"#,
            "\n",
        );
        std::fs::write(sessions.join("rollout.jsonl"), jsonl).expect("write jsonl");

        let env = ExecutionEnvironment {
            home,
            path_dirs: vec![],
            grok_home: None,
        };
        // Fake clock's "now" is far after the log's own timestamp — asserts
        // last_success_at reflects data generation, not collection time.
        let clock = FixedClock(datetime!(2026-08-06 12:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        // Non-existent exe so app-server spawn fails immediately and
        // collection falls through to the session-log fallback (no live
        // Codex dependency, no rate-limits.json — that stage is gone).
        let discovery = discovery_with_exe(Path::new("/nonexistent/codex"));
        let result = CODEX_ADAPTER.collect(&ctx, &discovery).await;
        assert_no_money(&result);
        match result {
            ProviderResult::Ready {
                windows,
                last_success_at,
                ..
            } => {
                assert_eq!(windows[0].id(), "weekly");
                assert_eq!(last_success_at, datetime!(2026-07-28 10:00:00 UTC));
            }
            other => panic!("{other:?}"),
        }
    }

    /// Writes an executable fake `codex` that speaks just enough app-server
    /// protocol to answer initialize, account/read, and refuse rateLimits.
    fn write_fake_codex_unauthenticated(dir: &Path) -> std::path::PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let exe = dir.join("codex");
        let script = r#"#!/usr/bin/env bash
# Fake Codex app-server: signed-out account.
[[ "$1" == "app-server" ]] || exit 2
while IFS= read -r line; do
  case "$line" in
    *'"initialize"'*) printf '%s\n' '{"id":0,"result":{}}' ;;
    *'account/rateLimits/read'*) printf '%s\n' '{"id":2,"error":{"code":-32600,"message":"codex account authentication required to read rate limits"}}' ;;
    *'account/read'*) printf '%s\n' '{"id":1,"result":{"account":{}}}' ;;
  esac
done
"#;
        std::fs::write(&exe, script).expect("write fake codex");
        std::fs::set_permissions(&exe, std::fs::Permissions::from_mode(0o755)).expect("chmod");
        exe
    }

    #[tokio::test]
    async fn codex_unauthenticated_appserver_ignores_session_log() {
        let dir = tempfile::tempdir().expect("tempdir");
        let home = dir.path().join("home");
        let sessions = home.join(".codex/sessions/2026/07/28");
        std::fs::create_dir_all(&sessions).expect("mkdir");
        // Old usage on disk must NOT be presented for a signed-out account (JSON-007).
        std::fs::write(
            sessions.join("rollout.jsonl"),
            concat!(
                r#"{"timestamp":"2026-07-28T10:00:00Z","type":"event","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.5,"window_minutes":10080}}}}"#,
                "\n"
            ),
        )
        .expect("write jsonl");
        let exe = write_fake_codex_unauthenticated(dir.path());

        let env = ExecutionEnvironment {
            home,
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-08-25 12:00:00 UTC));
        let fs = MapFileSystem::default();
        let process = empty_process();
        let http = ScriptedHttpClient::single(Err(crate::providers::adapter::HttpError::Network(
            "unused".into(),
        )));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(&exe);
        let result = CODEX_ADAPTER.collect(&ctx, &discovery).await;
        match result {
            ProviderResult::Unauthenticated {
                id,
                message,
                login_available,
                retryable,
                ..
            } => {
                assert_eq!(id, ProviderId::Codex);
                assert_eq!(message, "Codex is not authenticated.");
                assert!(login_available, "discovery_with_exe resolves the login exe");
                assert!(!retryable);
            }
            other => panic!("expected Unauthenticated, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn antigravity_collect_ready_from_fixture() {
        let fixture = include_str!("../../tests/fixtures/antigravity/usage.json");
        let process = ScriptedProcess::sequence(vec![
            Ok(antigravity_output(0, "1.1.18\n")),
            Ok(antigravity_output(0, fixture)),
        ]);
        let http = ScriptedHttpClient::default();
        let fs = MapFileSystem::default();
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/tmp/home"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-08-21 12:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(Path::new("/usr/bin/agy"));
        let result = ANTIGRAVITY_ADAPTER.collect(&ctx, &discovery).await;
        assert_no_money(&result);
        match result {
            ProviderResult::Ready { windows, .. } => {
                assert_eq!(windows.len(), 2);
                assert_eq!(windows[0].id(), "gemini-weekly");
                assert_eq!(windows[1].id(), "gemini-5h");
            }
            other => panic!("expected ready, got {other:?}"),
        }

        // The version guard runs first, then the usage call; both must carry
        // the catalog timeout/cap and the two env vars that keep `agy` from
        // drawing a TUI.
        let calls = process.calls();
        assert_eq!(calls.len(), 2, "{calls:?}");
        assert_eq!(calls[0].args, vec!["--version".to_owned()]);
        assert_eq!(
            calls[1].args,
            vec![
                "--print".to_owned(),
                "/usage".to_owned(),
                "--output-format".to_owned(),
                "json".to_owned()
            ]
        );
        for spec in &calls {
            assert_eq!(spec.timeout, ANTIGRAVITY.timeout);
            assert_eq!(spec.max_stdout_bytes, ANTIGRAVITY.max_output_bytes);
            assert_eq!(spec.max_stderr_bytes, ANTIGRAVITY.max_output_bytes);
            assert!(
                spec.env.contains(&("NO_COLOR".to_owned(), "1".to_owned())),
                "{:?}",
                spec.env
            );
            assert!(
                spec.env.contains(&("TERM".to_owned(), "dumb".to_owned())),
                "{:?}",
                spec.env
            );
        }
    }

    /// Run the Antigravity adapter against a scripted `--version` result
    /// followed by a scripted usage result.
    async fn antigravity_collect_scripted(process: ScriptedProcess) -> (ProviderResult, usize) {
        let http = ScriptedHttpClient::default();
        let fs = MapFileSystem::default();
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/tmp/home"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-08-21 12:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = discovery_with_exe(Path::new("/usr/bin/agy"));
        let result = ANTIGRAVITY_ADAPTER.collect(&ctx, &discovery).await;
        let calls = process.calls().len();
        (result, calls)
    }

    /// Collect with a supported CLI version, scripting only the usage result.
    async fn antigravity_collect(usage: ProcessOutput) -> ProviderResult {
        let (result, _) = antigravity_collect_scripted(ScriptedProcess::sequence(vec![
            Ok(antigravity_output(0, "1.1.18\n")),
            Ok(usage),
        ]))
        .await;
        result
    }

    /// Collect with `--version` answering `version`, and a usage call that
    /// would succeed — so a refusal proves the guard, not the usage path.
    async fn antigravity_collect_at_version(version: ProcessOutput) -> (ProviderResult, usize) {
        let fixture = include_str!("../../tests/fixtures/antigravity/usage.json");
        antigravity_collect_scripted(ScriptedProcess::sequence(vec![
            Ok(version),
            Ok(antigravity_output(0, fixture)),
        ]))
        .await
    }

    fn antigravity_output(exit_code: i32, stdout: &str) -> ProcessOutput {
        ProcessOutput {
            exit_code: Some(exit_code),
            stdout: stdout.to_owned(),
            stderr: String::new(),
            timed_out: false,
            stdout_truncated: false,
            stderr_truncated: false,
        }
    }

    #[tokio::test]
    async fn antigravity_collect_unauthenticated() {
        // A non-zero exit is only a login problem when the banner says so.
        let fixture = include_str!("../../tests/fixtures/antigravity/unauthorized.json");
        let result = antigravity_collect(antigravity_output(1, fixture)).await;
        assert_no_money(&result);
        match result {
            ProviderResult::Unauthenticated { id, .. } => {
                assert_eq!(id, ProviderId::Antigravity);
            }
            other => panic!("expected Unauthenticated, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn antigravity_logged_out_banner_on_exit_zero_is_unauthenticated() {
        // `agy` prints the logged-out banner and still exits 0, so the exit
        // code alone would let an empty Ready through.
        let fixture = include_str!("../../tests/fixtures/antigravity/unauthorized.json");
        let result = antigravity_collect(antigravity_output(0, fixture)).await;
        match result {
            ProviderResult::Unauthenticated { id, .. } => {
                assert_eq!(id, ProviderId::Antigravity);
            }
            other => panic!("expected Unauthenticated, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn antigravity_timeout_is_network_error() {
        let result = antigravity_collect(ProcessOutput {
            exit_code: None,
            stdout: String::new(),
            stderr: String::new(),
            timed_out: true,
            stdout_truncated: false,
            stderr_truncated: false,
        })
        .await;
        match result {
            ProviderResult::NetworkError { id, message, .. } => {
                assert_eq!(id, ProviderId::Antigravity);
                assert!(message.contains("timed out"), "{message}");
            }
            other => panic!("expected NetworkError, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn antigravity_too_old_a_cli_is_refused_before_the_usage_call() {
        // The whole point of the guard: on 1.1.10 the "/usage" text reaches
        // the model as a prompt and spends quota, so the usage call must never
        // be made.
        let (result, calls) =
            antigravity_collect_at_version(antigravity_output(0, "1.1.10\n")).await;
        assert_eq!(calls, 1, "the usage command must not run");
        match result {
            ProviderResult::ProviderError {
                id,
                message,
                retryable,
                ..
            } => {
                assert_eq!(id, ProviderId::Antigravity);
                assert_eq!(message, "Antigravity CLI 1.1.11 or newer is required.");
                assert!(!retryable, "reinstalling is the only fix");
            }
            other => panic!("expected ProviderError, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn antigravity_accepts_a_newer_version_with_a_v_prefix() {
        let (result, calls) =
            antigravity_collect_at_version(antigravity_output(0, "v1.2.0\n")).await;
        assert_eq!(calls, 2, "a supported version proceeds to the usage call");
        match result {
            ProviderResult::Ready { windows, .. } => assert_eq!(windows.len(), 2),
            other => panic!("expected ready, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn antigravity_unparseable_version_is_refused_not_assumed_new() {
        // Failing open would spend quota on an unknown build; the guard treats
        // "no version" exactly like "too old".
        for stdout in ["not a version\n", "", "1.1\n", "abc.def.ghi\n"] {
            let (result, calls) =
                antigravity_collect_at_version(antigravity_output(0, stdout)).await;
            assert_eq!(calls, 1, "{stdout:?} must not reach the usage call");
            match result {
                ProviderResult::ProviderError { message, .. } => {
                    assert_eq!(message, "Antigravity CLI 1.1.11 or newer is required.");
                }
                other => panic!("expected ProviderError for {stdout:?}, got {other:?}"),
            }
        }
    }

    #[tokio::test]
    async fn antigravity_failing_version_command_is_refused() {
        // A non-zero `--version` leaves us without a version, which is the
        // same answer as an unparseable one.
        let (result, calls) =
            antigravity_collect_at_version(antigravity_output(1, "1.1.18\n")).await;
        assert_eq!(calls, 1);
        assert!(matches!(result, ProviderResult::ProviderError { .. }));
    }

    #[tokio::test]
    async fn antigravity_version_timeout_is_network_error() {
        let (result, calls) = antigravity_collect_at_version(ProcessOutput {
            exit_code: None,
            stdout: String::new(),
            stderr: String::new(),
            timed_out: true,
            stdout_truncated: false,
            stderr_truncated: false,
        })
        .await;
        assert_eq!(calls, 1);
        match result {
            ProviderResult::NetworkError { id, message, .. } => {
                assert_eq!(id, ProviderId::Antigravity);
                assert!(message.contains("timed out"), "{message}");
            }
            other => panic!("expected NetworkError, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn antigravity_version_spawn_failure_is_network_error() {
        let (result, _) = antigravity_collect_scripted(ScriptedProcess::sequence(vec![Err(
            ProcessError::Spawn("boom".into()),
        )]))
        .await;
        match result {
            ProviderResult::NetworkError { id, message, .. } => {
                assert_eq!(id, ProviderId::Antigravity);
                assert_eq!(message, "Failed to run Antigravity usage.");
            }
            other => panic!("expected NetworkError, got {other:?}"),
        }
    }

    #[test]
    fn antigravity_version_parse_tolerates_prefix_and_trailing_junk() {
        assert_eq!(parse_version_prefix("1.1.18\n"), Some((1, 1, 18)));
        assert_eq!(parse_version_prefix("v1.2.0"), Some((1, 2, 0)));
        assert_eq!(parse_version_prefix("1.1.18-rc1"), Some((1, 1, 18)));
        assert_eq!(parse_version_prefix("1.1.18 (build 4)"), Some((1, 1, 18)));
        assert_eq!(parse_version_prefix("1.1"), None);
        assert_eq!(parse_version_prefix("nope"), None);
        assert_eq!(parse_version_prefix(""), None);
        // The boundary the constant encodes.
        assert!(parse_version_prefix("1.1.11").unwrap() >= ANTIGRAVITY_MIN_VERSION);
        assert!(parse_version_prefix("1.1.10").unwrap() < ANTIGRAVITY_MIN_VERSION);
        assert!(parse_version_prefix("1.0.99").unwrap() < ANTIGRAVITY_MIN_VERSION);
        assert!(parse_version_prefix("2.0.0").unwrap() >= ANTIGRAVITY_MIN_VERSION);
    }

    #[tokio::test]
    async fn antigravity_other_failure_message_has_no_debug_residue() {
        let result = antigravity_collect(antigravity_output(2, "boom")).await;
        match result {
            ProviderResult::ProviderError { id, message, .. } => {
                assert_eq!(id, ProviderId::Antigravity);
                assert_eq!(message, "Antigravity usage command failed.");
            }
            other => panic!("expected ProviderError, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn antigravity_missing_collection_source() {
        let process = ScriptedProcess::one(ProcessOutput {
            exit_code: Some(0),
            stdout: String::new(),
            stderr: String::new(),
            timed_out: false,
            stdout_truncated: false,
            stderr_truncated: false,
        });
        let http = ScriptedHttpClient::default();
        let fs = MapFileSystem::default();
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/tmp/home"),
            path_dirs: vec![],
            grok_home: None,
        };
        let clock = FixedClock(datetime!(2026-08-21 12:00:00 UTC));
        let ctx = CollectionContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
            plugin_root: None,
        };
        let discovery = Discovery {
            collection: CollectionAvailability::Missing,
            login: LoginAvailability::Missing,
        };
        let result = ANTIGRAVITY_ADAPTER.collect(&ctx, &discovery).await;
        assert!(matches!(result, ProviderResult::CliMissing { .. }));
        // Neither the version guard nor the usage call may run without an
        // executable to run them with.
        assert_eq!(process.calls().len(), 0, "{:?}", process.calls());
    }

    #[tokio::test]
    async fn antigravity_failed_exit_without_the_banner_is_a_provider_error() {
        let result = antigravity_collect(antigravity_output(41, "{\"status\":\"ERROR\"}")).await;
        match result {
            ProviderResult::ProviderError { id, message, .. } => {
                assert_eq!(id, ProviderId::Antigravity);
                assert_eq!(message, "Antigravity usage command failed.");
            }
            other => panic!("expected ProviderError, got {other:?}"),
        }
    }

    #[test]
    fn discover_delegates_to_catalog() {
        let env = ExecutionEnvironment {
            home: std::path::PathBuf::from("/tmp"),
            path_dirs: vec![],
            grok_home: None,
        };
        let d = AMP_ADAPTER.discover(&env).unwrap();
        assert!(matches!(d.collection, CollectionAvailability::Missing));
    }
}
