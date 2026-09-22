//! Claims one banked Claude usage reset.
//!
//! See `docs/specs/v10/amendments/2026-09-22-usage-resets-design.md` (Reset
//! command). This is the helper's first authenticated write to a provider
//! API: one endpoint, one provider, run only after a fresh eligibility check.

use std::path::Path;

use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use super::adapter::{HttpClient, HttpError};
use super::adapters::{
    probe_claude_version, read_claude_credentials, ClaudeRequestHeaders, CLAUDE_USAGE_URL,
};
use super::catalog::{
    discover, CollectionAvailability, Discovery, ExecutionEnvironment, LoginAvailability, CLAUDE,
};
use super::process::ProcessRunner;
use super::retry::http_get_with_retry;
use super::v2_map::{claude_cedar_ember_raw_grant_id, claude_from_usage_json, claude_reset_clears};
use crate::status::schema::{ProviderResult, UsageReset};
use crate::support::{Clock, FileSystem};

const RESET_CLAIM_URL_PREFIX: &str = "https://api.anthropic.com/api/organizations/";
const RESET_CLAIM_URL_SUFFIX: &str = "/reset_rate_limits";

/// Typed `agent-bar reset claude <id>` outcome (CLI-036 vocabulary). Every
/// value exits `0`; these are data, not process failures.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResetResult {
    Reset,
    AlreadyUsed,
    NotLimited,
    Cooldown,
    Ineligible,
    Unavailable,
    Unauthenticated,
    NetworkError,
    ProviderError,
}

impl ResetResult {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Reset => "reset",
            Self::AlreadyUsed => "already_used",
            Self::NotLimited => "not_limited",
            Self::Cooldown => "cooldown",
            Self::Ineligible => "ineligible",
            Self::Unavailable => "unavailable",
            Self::Unauthenticated => "unauthenticated",
            Self::NetworkError => "network_error",
            Self::ProviderError => "provider_error",
        }
    }

    fn parse_claim_result(raw: &str) -> Option<Self> {
        match raw {
            "reset" => Some(Self::Reset),
            "already_used" => Some(Self::AlreadyUsed),
            "not_limited" => Some(Self::NotLimited),
            "cooldown" => Some(Self::Cooldown),
            "ineligible" => Some(Self::Ineligible),
            "unavailable" => Some(Self::Unavailable),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResetReport {
    pub result: ResetResult,
    pub resets_left: Option<u32>,
    pub cooldown_until: Option<OffsetDateTime>,
    pub clears: Vec<String>,
}

impl ResetReport {
    fn simple(result: ResetResult) -> Self {
        Self {
            result,
            resets_left: None,
            cooldown_until: None,
            clears: Vec::new(),
        }
    }
}

/// Narrow seams a claim needs. Deliberately not
/// [`super::adapter::CollectionContext`]: a claim has no plugin-root IPC
/// refresh to make.
pub struct ResetContext<'a> {
    pub env: &'a ExecutionEnvironment,
    pub clock: &'a dyn Clock,
    pub fs: &'a dyn FileSystem,
    pub process: &'a dyn ProcessRunner,
    pub http: &'a dyn HttpClient,
}

/// Reads a 2xx claim response. The POST already had its side effect, so only
/// `result` is required; every other field is read leniently and a
/// malformed one is simply absent from the report.
fn report_from_claim_body(body: &[u8]) -> ResetReport {
    let Ok(value) = serde_json::from_slice::<serde_json::Value>(body) else {
        return ResetReport::simple(ResetResult::ProviderError);
    };
    let Some(result) = value
        .get("result")
        .and_then(serde_json::Value::as_str)
        .and_then(ResetResult::parse_claim_result)
    else {
        return ResetReport::simple(ResetResult::ProviderError);
    };
    let cleared: Vec<String> = value
        .get("cleared")
        .and_then(serde_json::Value::as_array)
        .map(|keys| {
            keys.iter()
                .filter_map(serde_json::Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default();
    let timestamp = |key: &str| {
        value
            .get(key)
            .and_then(serde_json::Value::as_str)
            .and_then(|raw| OffsetDateTime::parse(raw, &Rfc3339).ok())
            .map(|ts| ts.to_offset(time::UtcOffset::UTC))
    };
    ResetReport {
        result,
        resets_left: value
            .get("resets_left")
            .and_then(serde_json::Value::as_u64)
            .and_then(|n| u32::try_from(n).ok()),
        cooldown_until: timestamp("cooldown_until").or_else(|| timestamp("next_available_at")),
        clears: claude_reset_clears(&cleared),
    }
}

/// `sha2` over clock nanoseconds, pid, and the reset id, stamped with the
/// RFC 9562 version-4 and variant bits: a UUID v4 without a new crate.
fn request_id_for(reset_id: &str, now_ns: i128, pid: u32) -> String {
    use sha2::{Digest, Sha256};
    let seed = format!("{now_ns}:{pid}:{reset_id}");
    let digest = Sha256::digest(seed.as_bytes());
    let mut bytes = [0u8; 16];
    bytes.copy_from_slice(&digest[..16]);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!(
        "{}-{}-{}-{}-{}",
        &hex[0..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..32]
    )
}

/// Reads `oauthAccount.organizationUuid` from `$HOME/.claude.json`, accepting
/// only 36 hex-or-hyphen characters since the value becomes a URL path
/// segment. Never logged, cached, or echoed back.
fn organization_uuid(fs: &dyn FileSystem, home: &Path) -> Option<String> {
    let bytes = fs.read(&home.join(".claude.json")).ok()?;
    let value: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    value
        .get("oauthAccount")?
        .get("organizationUuid")?
        .as_str()
        .filter(|s| s.len() == 36 && s.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-'))
        .map(str::to_owned)
}

/// The claim program a validated reset id (JSON-022E) names:
/// `"cedar-ember:<grant id>"` or the literal `"juniper-tide"`. Any other id
/// (e.g. `"codex-credits"`) has no claim program.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClaimTarget<'a> {
    CedarEmber { sanitized_id: &'a str },
    JuniperTide,
}

impl<'a> ClaimTarget<'a> {
    pub fn parse(reset_id: &'a str) -> Option<Self> {
        if reset_id == "juniper-tide" {
            return Some(Self::JuniperTide);
        }
        reset_id
            .strip_prefix("cedar-ember:")
            .map(|sanitized_id| Self::CedarEmber { sanitized_id })
    }

    fn program(self) -> &'static str {
        match self {
            Self::CedarEmber { .. } => "cedar_ember",
            Self::JuniperTide => "juniper_tide",
        }
    }
}

/// Fetches fresh usage, claims `reset_id` only when that fresh response lists
/// it as claimable, and reports one typed [`ResetResult`]. Never retries the
/// POST. Never panics: every failure is data, per CLI-036.
pub async fn claim_claude_reset(ctx: &ResetContext<'_>, reset_id: &str) -> ResetReport {
    let Some(target) = ClaimTarget::parse(reset_id) else {
        return ResetReport::simple(ResetResult::Unavailable);
    };

    let discovery = discover(&CLAUDE, ctx.env).unwrap_or(Discovery {
        collection: CollectionAvailability::Missing,
        login: LoginAvailability::Missing,
    });

    let Ok(creds) = read_claude_credentials(ctx.fs, &ctx.env.home, ctx.clock.now_utc()) else {
        return ResetReport::simple(ResetResult::Unauthenticated);
    };

    // Signing in again does not create the organization uuid, so its absence
    // is `unavailable`, not `unauthenticated`.
    let Some(org_uuid) = organization_uuid(ctx.fs, &ctx.env.home) else {
        return ResetReport::simple(ResetResult::Unavailable);
    };

    let version = probe_claude_version(ctx.process, &discovery).await;
    let request = ClaudeRequestHeaders::new(&creds, version.as_deref());
    let headers = request.pairs();

    let usage = match http_get_with_retry(
        ctx.http,
        &CLAUDE,
        CLAUDE_USAGE_URL,
        &headers,
        CLAUDE.max_output_bytes,
    )
    .await
    {
        Ok(resp) if (200..300).contains(&resp.status) => resp,
        Ok(resp) if resp.status == 401 || resp.status == 403 => {
            return ResetReport::simple(ResetResult::Unauthenticated);
        }
        Ok(_) => return ResetReport::simple(ResetResult::ProviderError),
        Err(HttpError::Network(_)) => return ResetReport::simple(ResetResult::NetworkError),
        Err(_) => return ResetReport::simple(ResetResult::ProviderError),
    };

    let resets = match claude_from_usage_json(&usage.body, ctx.clock.now_utc(), None, false) {
        ProviderResult::Ready { resets, .. } => resets,
        ProviderResult::Unauthenticated { .. } => {
            return ResetReport::simple(ResetResult::Unauthenticated);
        }
        _ => return ResetReport::simple(ResetResult::ProviderError),
    };

    let target_claimable = resets
        .iter()
        .find(|r: &&UsageReset| r.id() == reset_id)
        .is_some_and(|r| r.claimable());
    if !target_claimable {
        return ResetReport::simple(ResetResult::Unavailable);
    }
    let raw_grant_id = match target {
        ClaimTarget::CedarEmber { sanitized_id } => {
            match claude_cedar_ember_raw_grant_id(&usage.body, sanitized_id) {
                Some(raw) => Some(raw),
                None => return ResetReport::simple(ResetResult::Unavailable),
            }
        }
        ClaimTarget::JuniperTide => None,
    };

    let request_id = request_id_for(
        reset_id,
        ctx.clock.now_utc().unix_timestamp_nanos(),
        std::process::id(),
    );

    let mut body = serde_json::Map::new();
    body.insert(
        "program".to_owned(),
        serde_json::Value::String(target.program().to_owned()),
    );
    if let Some(grant_id) = raw_grant_id {
        body.insert("grant_id".to_owned(), serde_json::Value::String(grant_id));
    }
    body.insert(
        "request_id".to_owned(),
        serde_json::Value::String(request_id),
    );
    let Ok(body_bytes) = serde_json::to_vec(&serde_json::Value::Object(body)) else {
        return ResetReport::simple(ResetResult::ProviderError);
    };

    let claim_url = format!("{RESET_CLAIM_URL_PREFIX}{org_uuid}{RESET_CLAIM_URL_SUFFIX}");
    let mut post_headers = headers.clone();
    post_headers.push(("Content-Type", "application/json"));

    let response = match ctx
        .http
        .post(
            &claim_url,
            &post_headers,
            body_bytes,
            CLAUDE.max_output_bytes,
        )
        .await
    {
        Ok(resp) if (200..300).contains(&resp.status) => resp,
        Ok(resp) if resp.status == 401 || resp.status == 403 => {
            return ResetReport::simple(ResetResult::Unauthenticated);
        }
        Ok(_) => return ResetReport::simple(ResetResult::ProviderError),
        Err(HttpError::Network(_)) => return ResetReport::simple(ResetResult::NetworkError),
        Err(_) => return ResetReport::simple(ResetResult::ProviderError),
    };

    report_from_claim_body(&response.body)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::providers::adapter::HttpResponse;
    use crate::providers::adapters::{FixedClock, MapFileSystem};
    use crate::providers::http::ScriptedHttpClient;
    use crate::providers::process::{ProcessError, ProcessOutput, ProcessSpec};
    use std::sync::Mutex;
    use time::macros::datetime;

    /// One canned `--version` reply for every process call.
    struct FixedVersionProcess(ProcessOutput);

    impl ProcessRunner for FixedVersionProcess {
        fn run<'a>(
            &'a self,
            _spec: &'a ProcessSpec,
        ) -> std::pin::Pin<
            Box<dyn std::future::Future<Output = Result<ProcessOutput, ProcessError>> + Send + 'a>,
        > {
            let out = self.0.clone();
            Box::pin(async move { Ok(out) })
        }
    }

    fn version_process(stdout: &str) -> FixedVersionProcess {
        FixedVersionProcess(ProcessOutput {
            exit_code: Some(0),
            stdout: stdout.to_owned(),
            stderr: String::new(),
            timed_out: false,
            stdout_truncated: false,
            stderr_truncated: false,
        })
    }

    fn creds_and_org_fs() -> MapFileSystem {
        let mut fs = MapFileSystem::default();
        fs.files.insert(
            std::path::PathBuf::from("/home/u/.claude/.credentials.json"),
            br#"{"claudeAiOauth":{"accessToken":"tok","subscriptionType":"pro"}}"#.to_vec(),
        );
        fs.files.insert(
            std::path::PathBuf::from("/home/u/.claude.json"),
            br#"{"oauthAccount":{"organizationUuid":"0f8e6a52-3c1d-4b7a-9e2f-5d4c3b2a1908"}}"#
                .to_vec(),
        );
        fs
    }

    fn test_env() -> ExecutionEnvironment {
        ExecutionEnvironment {
            home: std::path::PathBuf::from("/home/u"),
            path_dirs: vec![],
            grok_home: None,
        }
    }

    /// Two scripted responses consumed in call order: GET usage, then POST
    /// claim (the double pops from the end, so the vec is built reversed).
    fn scripted_http(
        usage: Result<HttpResponse, HttpError>,
        claim: Result<HttpResponse, HttpError>,
    ) -> ScriptedHttpClient {
        ScriptedHttpClient {
            responses: Mutex::new(vec![claim, usage]),
            last_url: Mutex::new(None),
            last_headers: Mutex::new(Vec::new()),
            last_body: Mutex::new(None),
        }
    }

    fn ok(body: &[u8]) -> Result<HttpResponse, HttpError> {
        Ok(HttpResponse {
            status: 200,
            final_url: "https://api.anthropic.com/x".into(),
            body: body.to_vec(),
        })
    }

    const CLAIMABLE_USAGE_BODY: &[u8] = br#"{"cedar_ember":{"eligible":true,
        "grants":[{"id":"g1","label":"Grant","resets_left":1,"paused":false,"usable_now":true}]}}"#;

    const NOT_CLAIMABLE_USAGE_BODY: &[u8] = br#"{"cedar_ember":{"eligible":true,
        "grants":[{"id":"g1","label":"Grant","resets_left":1,"paused":false,"usable_now":false}]}}"#;

    #[tokio::test]
    async fn expired_token_is_unauthenticated_without_any_http_call() {
        let mut fs = creds_and_org_fs();
        fs.files.insert(
            std::path::PathBuf::from("/home/u/.claude/.credentials.json"),
            br#"{"claudeAiOauth":{"accessToken":"tok","expiresAt":1}}"#.to_vec(),
        );
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(ok(b"{}"), ok(b"{}"));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
        assert_eq!(report.result, ResetResult::Unauthenticated);
        assert!(http.last_url.lock().unwrap().is_none());
    }

    #[tokio::test]
    async fn missing_credentials_is_unauthenticated() {
        let fs = MapFileSystem::default();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(ok(b"{}"), ok(b"{}"));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "juniper-tide").await;
        assert_eq!(report.result, ResetResult::Unauthenticated);
    }

    #[tokio::test]
    async fn missing_or_malformed_organization_uuid_is_unavailable_without_http() {
        for claude_json in [
            None,
            Some(&br#"{}"#[..]),
            Some(br#"{"oauthAccount":{}}"#),
            Some(br#"{"oauthAccount":{"organizationUuid":"org-123"}}"#),
            Some(
                br#"{"oauthAccount":{"organizationUuid":"../../../../../../../../../../../../x"}}"#,
            ),
            Some(
                br#"{"oauthAccount":{"organizationUuid":"0f8e6a52-3c1d-4b7a-9e2f-5d4c3b2a19080"}}"#,
            ),
            Some(br#"{"oauthAccount":{"organizationUuid":42}}"#),
            Some(b"not json"),
        ] {
            let mut fs = MapFileSystem::default();
            fs.files.insert(
                std::path::PathBuf::from("/home/u/.claude/.credentials.json"),
                br#"{"claudeAiOauth":{"accessToken":"tok"}}"#.to_vec(),
            );
            if let Some(bytes) = claude_json {
                fs.files.insert(
                    std::path::PathBuf::from("/home/u/.claude.json"),
                    bytes.to_vec(),
                );
            }
            let env = test_env();
            let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
            let process = version_process("2.1.280");
            let http = scripted_http(ok(CLAIMABLE_USAGE_BODY), ok(br#"{"result":"reset"}"#));
            let ctx = ResetContext {
                env: &env,
                clock: &clock,
                fs: &fs,
                process: &process,
                http: &http,
            };
            let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
            let label = claude_json.map(String::from_utf8_lossy);
            assert_eq!(report.result, ResetResult::Unavailable, "{label:?}");
            assert!(http.last_url.lock().unwrap().is_none(), "{label:?}");
        }
    }

    #[tokio::test]
    async fn claim_url_carries_the_organization_uuid() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(ok(CLAIMABLE_USAGE_BODY), ok(br#"{"result":"reset"}"#));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        claim_claude_reset(&ctx, "cedar-ember:g1").await;
        assert_eq!(
            http.last_url.lock().unwrap().as_deref(),
            Some("https://api.anthropic.com/api/organizations/0f8e6a52-3c1d-4b7a-9e2f-5d4c3b2a1908/reset_rate_limits")
        );
    }

    #[tokio::test]
    async fn id_without_a_claim_program_is_unavailable_without_http() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(ok(CLAIMABLE_USAGE_BODY), ok(br#"{"result":"reset"}"#));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "codex-credits").await;
        assert_eq!(report.result, ResetResult::Unavailable);
        assert!(http.last_url.lock().unwrap().is_none());
    }

    #[tokio::test]
    async fn usage_network_error_is_network_error() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(
            Err(HttpError::Network("blip".into())),
            Err(HttpError::Network("blip again".into())),
        );
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "juniper-tide").await;
        assert_eq!(report.result, ResetResult::NetworkError);
        assert!(http.last_body.lock().unwrap().is_none());
    }

    #[tokio::test]
    async fn usage_get_retries_one_network_error_and_post_runs_once() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let unused = ok(br#"{"result":"reset"}"#);
        let http = ScriptedHttpClient {
            responses: Mutex::new(vec![
                unused,
                Err(HttpError::Network("post blip".into())),
                ok(CLAIMABLE_USAGE_BODY),
                Err(HttpError::Network("get blip".into())),
            ]),
            last_url: Mutex::new(None),
            last_headers: Mutex::new(Vec::new()),
            last_body: Mutex::new(None),
        };
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
        assert_eq!(report.result, ResetResult::NetworkError);
        assert!(http.last_body.lock().unwrap().is_some(), "the POST ran");
        assert_eq!(
            http.responses.lock().unwrap().len(),
            1,
            "GET retried once, POST attempted once"
        );
    }

    #[tokio::test]
    async fn usage_non_2xx_is_provider_error() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(
            Ok(HttpResponse {
                status: 500,
                final_url: "https://api.anthropic.com/x".into(),
                body: b"{}".to_vec(),
            }),
            ok(b"{}"),
        );
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "juniper-tide").await;
        assert_eq!(report.result, ResetResult::ProviderError);
    }

    #[tokio::test]
    async fn unlisted_reset_id_is_unavailable_without_post() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(ok(b"{}"), ok(b"{}"));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:no-such-grant").await;
        assert_eq!(report.result, ResetResult::Unavailable);
        // Only the usage GET happened; the claim POST never ran.
        assert!(http.last_body.lock().unwrap().is_none());
    }

    #[tokio::test]
    async fn listed_but_not_claimable_is_unavailable_without_post() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(ok(NOT_CLAIMABLE_USAGE_BODY), ok(b"{}"));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
        assert_eq!(report.result, ResetResult::Unavailable);
        assert!(http.last_body.lock().unwrap().is_none());
    }

    #[tokio::test]
    async fn claimable_reset_posts_and_maps_a_successful_claim() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let claim_body =
            br#"{"result":"reset","resets_left":0,"cleared":["five_hour","seven_day"],"cooldown_until":null}"#;
        let http = scripted_http(ok(CLAIMABLE_USAGE_BODY), ok(claim_body));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
        assert_eq!(report.result, ResetResult::Reset);
        assert_eq!(report.resets_left, Some(0));
        assert_eq!(
            report.clears,
            vec!["session".to_owned(), "weekly".to_owned()]
        );
        let body = http.last_body.lock().unwrap().clone().unwrap();
        let value: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(value["program"], "cedar_ember");
        assert_eq!(value["grant_id"], "g1");
        assert!(value["request_id"].is_string());
        let headers = http.last_headers.lock().unwrap().clone();
        assert!(headers
            .iter()
            .any(|(k, v)| k == "Content-Type" && v == "application/json"));
    }

    #[tokio::test]
    async fn claim_posts_the_raw_grant_id_behind_the_sanitized_reset_id() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let usage = br#"{"cedar_ember":{"eligible":true,"grants":[
            {"id":"Opus55_Launch.PROMAX","label":"Grant","resets_left":1,"paused":false,"usable_now":true}
        ]}}"#;
        let http = scripted_http(ok(usage), ok(br#"{"result":"reset"}"#));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:opus55launchpromax").await;
        assert_eq!(report.result, ResetResult::Reset);
        let body = http.last_body.lock().unwrap().clone().unwrap();
        let value: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(value["grant_id"], "Opus55_Launch.PROMAX");
    }

    #[tokio::test]
    async fn colliding_sanitized_grant_ids_are_unavailable_without_post() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let usage = br#"{"cedar_ember":{"eligible":true,"grants":[
            {"id":"Opus55_Launch","label":"A","resets_left":1,"paused":false,"usable_now":true},
            {"id":"opus55launch","label":"B","resets_left":1,"paused":false,"usable_now":true}
        ]}}"#;
        let http = scripted_http(ok(usage), ok(br#"{"result":"reset"}"#));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:opus55launch").await;
        assert_eq!(report.result, ResetResult::Unavailable);
        assert!(http.last_body.lock().unwrap().is_none());
    }

    #[tokio::test]
    async fn already_used_result_round_trips() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let claim_body = br#"{"result":"already_used"}"#;
        let http = scripted_http(ok(CLAIMABLE_USAGE_BODY), ok(claim_body));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
        assert_eq!(report.result, ResetResult::AlreadyUsed);
    }

    #[tokio::test]
    async fn cooldown_result_parses_cooldown_until() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let claim_body = br#"{"result":"cooldown","cooldown_until":"2026-09-22T20:00:00Z"}"#;
        let http = scripted_http(ok(CLAIMABLE_USAGE_BODY), ok(claim_body));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
        assert_eq!(report.result, ResetResult::Cooldown);
        assert_eq!(
            report.cooldown_until,
            Some(datetime!(2026-09-22 20:00:00 UTC))
        );
    }

    #[tokio::test]
    async fn claim_response_optional_fields_are_read_leniently() {
        let cases: [(&[u8], ResetReport); 3] = [
            (
                br#"{"result":"reset","resets_left":1.5,"cleared":null,"cooldown_until":7}"#,
                ResetReport::simple(ResetResult::Reset),
            ),
            (
                br#"{"result":"already_used","resets_left":-1,"cleared":["five_hour",3,"seven_day"]}"#,
                ResetReport {
                    result: ResetResult::AlreadyUsed,
                    resets_left: None,
                    cooldown_until: None,
                    clears: vec!["session".to_owned(), "weekly".to_owned()],
                },
            ),
            (
                br#"{"result":"cooldown","resets_left":2,"cleared":"five_hour","next_available_at":"2026-09-22T20:00:00Z"}"#,
                ResetReport {
                    result: ResetResult::Cooldown,
                    resets_left: Some(2),
                    cooldown_until: Some(datetime!(2026-09-22 20:00:00 UTC)),
                    clears: Vec::new(),
                },
            ),
        ];
        for (claim_body, expected) in cases {
            let fs = creds_and_org_fs();
            let env = test_env();
            let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
            let process = version_process("2.1.280");
            let http = scripted_http(ok(CLAIMABLE_USAGE_BODY), ok(claim_body));
            let ctx = ResetContext {
                env: &env,
                clock: &clock,
                fs: &fs,
                process: &process,
                http: &http,
            };
            let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
            assert_eq!(report, expected, "{}", String::from_utf8_lossy(claim_body));
        }
    }

    #[tokio::test]
    async fn claim_response_without_a_string_result_is_provider_error() {
        for claim_body in [
            &br#"{"resets_left":0}"#[..],
            br#"{"result":null}"#,
            br#"{"result":"exploded"}"#,
        ] {
            let fs = creds_and_org_fs();
            let env = test_env();
            let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
            let process = version_process("2.1.280");
            let http = scripted_http(ok(CLAIMABLE_USAGE_BODY), ok(claim_body));
            let ctx = ResetContext {
                env: &env,
                clock: &clock,
                fs: &fs,
                process: &process,
                http: &http,
            };
            let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
            assert_eq!(report.result, ResetResult::ProviderError);
        }
    }

    #[tokio::test]
    async fn claim_post_401_is_unauthenticated() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(
            ok(CLAIMABLE_USAGE_BODY),
            Ok(HttpResponse {
                status: 401,
                final_url: "https://api.anthropic.com/x".into(),
                body: b"{}".to_vec(),
            }),
        );
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
        assert_eq!(report.result, ResetResult::Unauthenticated);
    }

    #[tokio::test]
    async fn claim_post_network_error_is_network_error() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(
            ok(CLAIMABLE_USAGE_BODY),
            Err(HttpError::Network("blip".into())),
        );
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
        assert_eq!(report.result, ResetResult::NetworkError);
    }

    #[tokio::test]
    async fn claim_post_malformed_body_is_provider_error() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(ok(CLAIMABLE_USAGE_BODY), ok(b"not json"));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "cedar-ember:g1").await;
        assert_eq!(report.result, ResetResult::ProviderError);
    }

    #[test]
    fn claim_target_maps_known_shapes() {
        assert_eq!(
            ClaimTarget::parse("cedar-ember:g1"),
            Some(ClaimTarget::CedarEmber { sanitized_id: "g1" })
        );
        assert_eq!(
            ClaimTarget::parse("juniper-tide"),
            Some(ClaimTarget::JuniperTide)
        );
        assert_eq!(ClaimTarget::parse("codex-credits"), None);
    }

    #[test]
    fn request_id_is_uuid_shaped_and_varies_with_its_seed() {
        let a = request_id_for("cedar-ember:g1", 1, 100);
        let b = request_id_for("cedar-ember:g1", 2, 100);
        assert_ne!(a, b);
        let groups: Vec<&str> = a.split('-').collect();
        assert_eq!(
            groups.iter().map(|g| g.len()).collect::<Vec<_>>(),
            vec![8, 4, 4, 4, 12]
        );
        for seed in 0..64 {
            let id = request_id_for("juniper-tide", seed, 7);
            let hex: Vec<char> = id.chars().filter(|c| *c != '-').collect();
            assert_eq!(hex[12], '4', "version nibble: {id}");
            assert!(
                matches!(hex[16], '8' | '9' | 'a' | 'b'),
                "variant nibble: {id}"
            );
        }
    }
}
