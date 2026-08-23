//! v10 provider adapter interface and collection context.

use std::future::Future;
use std::path::Path;
use std::pin::Pin;

use crate::cli::ProviderId;
use crate::status::schema::ProviderResult;
use crate::support::{Clock, FileSystem};

use super::catalog::{
    discover as catalog_discover, login_process_argv, CollectionAvailability, Discovery,
    ExecutionEnvironment, LoginAvailability, ProviderDescriptor,
};
use super::process::{ProcessRunner, ProcessSpec};

/// Boxed async collect future used by [`ProviderAdapter::collect`].
pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Narrow HTTP response for Claude (and future HTTP collectors).
#[derive(Debug, Clone)]
pub struct HttpResponse {
    pub status: u16,
    pub final_url: String,
    pub body: Vec<u8>,
}

/// Typed HTTP failure at the collection boundary.
#[derive(Debug)]
pub enum HttpError {
    Network(String),
    RedirectRefused(String),
    BodyTooLarge,
    InvalidResponse(String),
}

impl std::fmt::Display for HttpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Network(msg) => write!(f, "network error: {msg}"),
            Self::RedirectRefused(url) => write!(f, "redirect refused: {url}"),
            Self::BodyTooLarge => write!(f, "response body exceeded limit"),
            Self::InvalidResponse(msg) => write!(f, "invalid response: {msg}"),
        }
    }
}

impl std::error::Error for HttpError {}

/// Injectable HTTP client (no redirects; body capped before full buffer).
pub trait HttpClient: Send + Sync {
    fn get(
        &self,
        url: &str,
        headers: &[(&str, &str)],
        max_body_bytes: usize,
    ) -> BoxFuture<'_, Result<HttpResponse, HttpError>>;
}

/// Capabilities exposed to provider adapters during collection.
pub struct CollectionContext<'a> {
    pub env: &'a ExecutionEnvironment,
    pub clock: &'a dyn Clock,
    pub fs: &'a dyn FileSystem,
    pub process: &'a dyn ProcessRunner,
    pub http: &'a dyn HttpClient,
    /// Absolute plugin root for login IPC refresh (`…/othavi0.agent-bar`).
    pub plugin_root: Option<&'a Path>,
}

/// Closed adapter interface for every supported provider.
pub trait ProviderAdapter: Send + Sync {
    fn descriptor(&self) -> &'static ProviderDescriptor;

    fn discover(
        &self,
        env: &ExecutionEnvironment,
    ) -> Result<Discovery, super::catalog::CatalogError> {
        catalog_discover(self.descriptor(), env)
    }

    fn login_command(&self, discovery: &Discovery) -> Result<ProcessSpec, LoginError> {
        // Two different answers share one `None` from `login_process_argv`:
        // no executable to run, and a provider that publishes no login argv
        // at all. Installing a CLI fixes the first and can never fix the
        // second, so they must not report the same failure.
        if self.descriptor().login_argv.is_empty() {
            return Err(LoginError::UnsupportedProvider);
        }
        if discovery.login_executable().is_none() {
            return Err(LoginError::CliMissing);
        }
        let argv =
            login_process_argv(self.descriptor(), discovery).ok_or(LoginError::CliMissing)?;
        let mut iter = argv.into_iter();
        let program = iter.next().ok_or(LoginError::CliMissing)?;
        let args: Vec<String> = iter.collect();
        Ok(ProcessSpec::new(program, args)
            .with_timeout(self.descriptor().timeout)
            .with_max_output(self.descriptor().max_output_bytes))
    }

    fn collect<'a>(
        &'a self,
        context: &'a CollectionContext<'a>,
        discovery: &'a Discovery,
    ) -> BoxFuture<'a, ProviderResult>;
}

/// Login orchestration errors (helper-level, not provider domain).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LoginError {
    CliMissing,
    UnsupportedProvider,
}

impl std::fmt::Display for LoginError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::CliMissing => write!(f, "login executable not found"),
            Self::UnsupportedProvider => write!(f, "unsupported provider"),
        }
    }
}

impl std::error::Error for LoginError {}

/// Exit mapping for delegated login (CLI-017).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoginOutcome {
    /// Process exit code to return from `agent-bar login`.
    pub exit_code: i32,
    /// Whether best-effort refresh was attempted.
    pub refresh_attempted: bool,
    /// Exact refresh argv when attempted.
    pub refresh_argv: Option<Vec<String>>,
}

/// Official login argv + best-effort IPC refresh after exit 0.
///
/// Refresh failure is ignored for exit status. Nonzero/signaled/invalid
/// provider status never requests refresh.
pub async fn run_login<R: ProcessRunner + ?Sized, I: ProcessRunner + ?Sized>(
    adapter: &dyn ProviderAdapter,
    discovery: &Discovery,
    provider_runner: &R,
    ipc_runner: &I,
) -> Result<LoginOutcome, LoginError> {
    let spec = adapter.login_command(discovery)?;
    let output = provider_runner
        .run(&spec)
        .await
        .map_err(|_| LoginError::CliMissing)?;

    if output.timed_out {
        return Ok(LoginOutcome {
            exit_code: 1,
            refresh_attempted: false,
            refresh_argv: None,
        });
    }

    let code = match output.exit_code {
        Some(0) => 0,
        Some(code) => code,
        None => 1, // signal / invalid platform status
    };

    if code != 0 {
        return Ok(LoginOutcome {
            exit_code: code,
            refresh_attempted: false,
            refresh_argv: None,
        });
    }

    let provider_id = adapter.descriptor().id.as_str();
    let refresh_argv = vec![
        "omarchy-shell".to_owned(),
        "-q".to_owned(),
        "othavi0.agent-bar".to_owned(),
        "refresh".to_owned(),
        provider_id.to_owned(),
    ];
    let refresh_spec = ProcessSpec::new(
        "omarchy-shell",
        ["-q", "othavi0.agent-bar", "refresh", provider_id],
    )
    .with_timeout(std::time::Duration::from_secs(5))
    .with_max_output(64 * 1024);
    // Best-effort: ignore errors and non-zero.
    let _ = ipc_runner.run(&refresh_spec).await;

    Ok(LoginOutcome {
        exit_code: 0,
        refresh_attempted: true,
        refresh_argv: Some(refresh_argv),
    })
}

/// Resolve the adapter for a closed provider id.
pub fn adapter_for(id: ProviderId) -> &'static dyn ProviderAdapter {
    match id {
        ProviderId::Amp => &super::adapters::AMP_ADAPTER,
        ProviderId::Grok => &super::adapters::GROK_ADAPTER,
        ProviderId::Codex => &super::adapters::CODEX_ADAPTER,
        ProviderId::Claude => &super::adapters::CLAUDE_ADAPTER,
        ProviderId::Antigravity => &super::adapters::ANTIGRAVITY_ADAPTER,
    }
}

/// Shared helpers for mapping discovery misses.
pub(crate) fn missing_collection(id: ProviderId, name: &str, url: &str) -> ProviderResult {
    ProviderResult::CliMissing {
        id,
        name: name.to_owned(),
        message: format!("{name} collection executable was not found."),
        installation_url: url.to_owned(),
    }
}

pub(crate) fn unauthenticated(
    id: ProviderId,
    name: &str,
    message: impl Into<String>,
    login_available: bool,
    url: &str,
    retryable: bool,
) -> ProviderResult {
    ProviderResult::Unauthenticated {
        id,
        name: name.to_owned(),
        message: message.into(),
        login_available,
        installation_url: url.to_owned(),
        retryable,
    }
}

pub(crate) fn login_available(discovery: &Discovery) -> bool {
    matches!(discovery.login, LoginAvailability::Available { .. })
}

pub(crate) fn collection_exe(discovery: &Discovery) -> Option<&Path> {
    match &discovery.collection {
        CollectionAvailability::Available { executable } => Some(executable.as_path()),
        CollectionAvailability::Missing => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::providers::adapters::{ANTIGRAVITY_ADAPTER, GROK_ADAPTER};
    use std::path::PathBuf;

    fn discovery_with_login(executable: Option<&str>) -> Discovery {
        Discovery {
            collection: CollectionAvailability::Missing,
            login: match executable {
                Some(path) => LoginAvailability::Available {
                    executable: PathBuf::from(path),
                },
                None => LoginAvailability::Missing,
            },
        }
    }

    #[test]
    fn unsupported_login_wins_over_missing_executable_from_real_discovery() {
        // `discover()` never reports login as available for an empty argv, so
        // the unsupported answer must come before the executable check or it
        // is unreachable in production.
        let env = ExecutionEnvironment {
            home: PathBuf::from("/nonexistent"),
            path_dirs: vec![],
            grok_home: None,
        };
        let discovery = ANTIGRAVITY_ADAPTER.discover(&env).unwrap();
        assert!(discovery.login_executable().is_none());
        let err = ANTIGRAVITY_ADAPTER.login_command(&discovery).unwrap_err();
        assert_eq!(err, LoginError::UnsupportedProvider);
    }

    #[test]
    fn present_cli_without_login_argv_is_unsupported_not_missing() {
        // Antigravity ships no official login command: `agy` is right there,
        // so "install the provider CLI first" would send the user nowhere.
        assert_eq!(
            ANTIGRAVITY_ADAPTER.descriptor().login_argv,
            &[] as &[&str],
            "test premise: this provider publishes no login argv"
        );
        let err = ANTIGRAVITY_ADAPTER
            .login_command(&discovery_with_login(Some("/usr/bin/agy")))
            .unwrap_err();
        assert_eq!(err, LoginError::UnsupportedProvider);
    }

    #[test]
    fn absent_login_executable_is_cli_missing() {
        // Grok publishes a login argv, so a missing executable is the only
        // reason login cannot run.
        assert_eq!(
            GROK_ADAPTER
                .login_command(&discovery_with_login(None))
                .unwrap_err(),
            LoginError::CliMissing
        );
        assert_eq!(
            GROK_ADAPTER
                .login_command(&discovery_with_login(None))
                .unwrap_err(),
            LoginError::CliMissing
        );
    }

    #[test]
    fn login_argv_keeps_the_discovered_executable_as_argv_zero() {
        let spec = GROK_ADAPTER
            .login_command(&discovery_with_login(Some("/opt/bin/grok")))
            .unwrap();
        assert_eq!(spec.program, PathBuf::from("/opt/bin/grok"));
        assert_eq!(spec.args, vec!["login".to_owned()]);
    }
}
