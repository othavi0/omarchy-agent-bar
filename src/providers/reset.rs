//! Claims one banked Claude usage reset.
//!
//! See `docs/specs/v10/amendments/2026-09-22-usage-resets-design.md` (Reset
//! command). This is the helper's first authenticated write to a provider
//! API: one endpoint, one provider, run only after a fresh eligibility check.

use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Deserialize;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use super::adapter::{HttpClient, HttpError};
use super::adapters::{parse_claude_credentials, probe_claude_version, CLAUDE_USAGE_URL};
use super::catalog::{
    discover, CollectionAvailability, Discovery, ExecutionEnvironment, LoginAvailability, CLAUDE,
};
use super::process::ProcessRunner;
use super::v2_map::claude_from_usage_json;
use crate::status::schema::{ProviderResult, UsageReset};
use crate::support::{Clock, FileSystem};

const RESET_CLAIM_URL_PREFIX: &str = "https://api.anthropic.com/api/organizations/";
const RESET_CLAIM_URL_SUFFIX: &str = "/reset_rate_limits";

/// Typed `agent-bar reset claude <id>` outcome (CLI-034 vocabulary). Every
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

#[derive(Debug, Deserialize)]
struct ClaimResponse {
    result: String,
    #[serde(default)]
    resets_left: Option<u32>,
    #[serde(default)]
    cleared: Vec<String>,
    #[serde(default)]
    cooldown_until: Option<String>,
}

/// Maps a claim response's `cleared` window ids the same way collection maps
/// a grant's `clears`: `five_hour`/`seven_day` only, unknown keys dropped.
fn map_cleared(raw: &[String]) -> Vec<String> {
    raw.iter()
        .filter_map(|key| match key.as_str() {
            "five_hour" => Some("session".to_owned()),
            "seven_day" => Some("weekly".to_owned()),
            _ => None,
        })
        .collect()
}

/// `sha2` over wall-clock nanoseconds, pid, and the reset id: an
/// unpredictable-enough UUID-shaped request id without a new crate.
fn request_id_for(reset_id: &str, now_ns: i128, pid: u32) -> String {
    use sha2::{Digest, Sha256};
    let seed = format!("{now_ns}:{pid}:{reset_id}");
    let digest = Sha256::digest(seed.as_bytes());
    let hex: String = digest.iter().take(16).map(|b| format!("{b:02x}")).collect();
    format!(
        "{}-{}-{}-{}-{}",
        &hex[0..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..32]
    )
}

/// Reads `oauthAccount.organizationUuid` from `$HOME/.claude.json`. Never
/// logged, cached, or echoed back; used only to build the claim URL.
fn organization_uuid(fs: &dyn FileSystem, home: &Path) -> Option<String> {
    let bytes = fs.read(&home.join(".claude.json")).ok()?;
    let value: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    value
        .get("oauthAccount")?
        .get("organizationUuid")?
        .as_str()
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
}

/// `program`/`grant_id` for the POST body, derived from the validated id
/// shape (JSON-022E): `"cedar-ember:<grant id>"` or the literal
/// `"juniper-tide"`. Any other shape (e.g. `"codex-credits"`, which this
/// command never claims) has no program.
fn program_and_grant(reset_id: &str) -> Option<(&'static str, Option<String>)> {
    if reset_id == "juniper-tide" {
        return Some(("juniper_tide", None));
    }
    reset_id
        .strip_prefix("cedar-ember:")
        .map(|grant_id| ("cedar_ember", Some(grant_id.to_owned())))
}

/// Fetches fresh usage, claims `reset_id` only when that fresh response lists
/// it as claimable, and reports one typed [`ResetResult`]. Never retries the
/// POST. Never panics: every failure is data, per CLI-034.
pub async fn claim_claude_reset(ctx: &ResetContext<'_>, reset_id: &str) -> ResetReport {
    let discovery = discover(&CLAUDE, ctx.env).unwrap_or(Discovery {
        collection: CollectionAvailability::Missing,
        login: LoginAvailability::Missing,
    });

    let cred_path = ctx.env.home.join(".claude/.credentials.json");
    let Ok(cred_bytes) = ctx.fs.read(&cred_path) else {
        return ResetReport::simple(ResetResult::Unauthenticated);
    };
    let Some(creds) = parse_claude_credentials(&cred_bytes) else {
        return ResetReport::simple(ResetResult::Unauthenticated);
    };
    let now_ms = ctx.clock.now_utc().unix_timestamp().saturating_mul(1000);
    if creds.expires_at_ms.is_some_and(|exp| exp <= now_ms) {
        return ResetReport::simple(ResetResult::Unauthenticated);
    }

    // Without the organization uuid the claim URL cannot be built at all;
    // that only happens for a Claude Code install this command cannot use.
    let Some(org_uuid) = organization_uuid(ctx.fs, &ctx.env.home) else {
        return ResetReport::simple(ResetResult::Unauthenticated);
    };

    let bearer = format!("Bearer {}", creds.token);
    let version = probe_claude_version(ctx.process, &discovery).await;
    let user_agent = version.map(|v| format!("claude-cli/{v} (external, cli)"));
    let mut headers = vec![
        ("Authorization", bearer.as_str()),
        ("anthropic-beta", "oauth-2025-04-20"),
    ];
    if let Some(ua) = user_agent.as_deref() {
        headers.push(("User-Agent", ua));
        headers.push(("x-app", "cli"));
    }

    let usage = match ctx
        .http
        .get(CLAUDE_USAGE_URL, &headers, CLAUDE.max_output_bytes)
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
    let Some((program, grant_id)) = program_and_grant(reset_id) else {
        return ResetReport::simple(ResetResult::Unavailable);
    };

    let now_ns: i128 = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as i128)
        .unwrap_or(0);
    let request_id = request_id_for(reset_id, now_ns, std::process::id());

    let mut body = serde_json::Map::new();
    body.insert(
        "program".to_owned(),
        serde_json::Value::String(program.to_owned()),
    );
    if let Some(grant_id) = grant_id {
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

    let Ok(claim) = serde_json::from_slice::<ClaimResponse>(&response.body) else {
        return ResetReport::simple(ResetResult::ProviderError);
    };
    let Some(result) = ResetResult::parse_claim_result(&claim.result) else {
        return ResetReport::simple(ResetResult::ProviderError);
    };

    ResetReport {
        result,
        resets_left: claim.resets_left,
        cooldown_until: claim
            .cooldown_until
            .as_deref()
            .and_then(|raw| OffsetDateTime::parse(raw, &Rfc3339).ok()),
        clears: map_cleared(&claim.cleared),
    }
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
            br#"{"oauthAccount":{"organizationUuid":"org-123"}}"#.to_vec(),
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
    async fn missing_organization_uuid_is_unauthenticated_without_http() {
        let mut fs = MapFileSystem::default();
        fs.files.insert(
            std::path::PathBuf::from("/home/u/.claude/.credentials.json"),
            br#"{"claudeAiOauth":{"accessToken":"tok"}}"#.to_vec(),
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
        let report = claim_claude_reset(&ctx, "juniper-tide").await;
        assert_eq!(report.result, ResetResult::Unauthenticated);
        assert!(http.last_url.lock().unwrap().is_none());
    }

    #[tokio::test]
    async fn usage_network_error_is_network_error() {
        let fs = creds_and_org_fs();
        let env = test_env();
        let clock = FixedClock(datetime!(2026-09-22 18:00:00 UTC));
        let process = version_process("2.1.280");
        let http = scripted_http(Err(HttpError::Network("blip".into())), ok(b"{}"));
        let ctx = ResetContext {
            env: &env,
            clock: &clock,
            fs: &fs,
            process: &process,
            http: &http,
        };
        let report = claim_claude_reset(&ctx, "juniper-tide").await;
        assert_eq!(report.result, ResetResult::NetworkError);
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
    fn program_and_grant_maps_known_shapes() {
        assert_eq!(
            program_and_grant("cedar-ember:g1"),
            Some(("cedar_ember", Some("g1".to_owned())))
        );
        assert_eq!(
            program_and_grant("juniper-tide"),
            Some(("juniper_tide", None))
        );
        assert_eq!(program_and_grant("codex-credits"), None);
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
    }
}
