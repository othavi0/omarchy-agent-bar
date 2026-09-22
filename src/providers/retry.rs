use super::adapter::{HttpClient, HttpError, HttpResponse};
use super::catalog::ProviderDescriptor;

/// Run `op` once; if the result is judged transient, wait the descriptor's
/// retry delay (when it has one) and run `op` a second and final time.
/// Shared by every adapter's single-retry policy, HTTP or subprocess alike.
pub(crate) async fn retry_once_if_transient<T, Fut>(
    descriptor: &ProviderDescriptor,
    is_transient: impl Fn(&T) -> bool,
    mut op: impl FnMut() -> Fut,
) -> T
where
    Fut: std::future::Future<Output = T>,
{
    let first = op().await;
    if !is_transient(&first) {
        return first;
    }
    let Some(delay) = descriptor.retry_delay() else {
        return first;
    };
    tokio::time::sleep(delay).await;
    op().await
}

/// GET with at most one extra attempt after a transient network error,
/// honoring the descriptor's retry policy and delay.
pub(crate) async fn http_get_with_retry(
    http: &dyn HttpClient,
    descriptor: &ProviderDescriptor,
    url: &str,
    headers: &[(&str, &str)],
    max_body_bytes: usize,
) -> Result<HttpResponse, HttpError> {
    retry_once_if_transient(
        descriptor,
        |result: &Result<HttpResponse, HttpError>| matches!(result, Err(HttpError::Network(_))),
        || http.get(url, headers, max_body_bytes),
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::providers::catalog::CLAUDE;
    use crate::providers::http::ScriptedHttpClient;

    fn ok_response() -> HttpResponse {
        HttpResponse {
            status: 200,
            final_url: "https://example.invalid/".into(),
            body: b"{}".to_vec(),
        }
    }

    #[tokio::test]
    async fn retries_once_after_network_error() {
        let http = ScriptedHttpClient {
            responses: std::sync::Mutex::new(vec![
                Ok(ok_response()),
                Err(HttpError::Network("transient".into())),
            ]),
            last_url: std::sync::Mutex::new(None),
            last_headers: std::sync::Mutex::new(Vec::new()),
            last_body: std::sync::Mutex::new(None),
        };
        let result = http_get_with_retry(&http, &CLAUDE, "https://x/", &[], 1024).await;
        assert!(result.is_ok(), "expected retry to succeed: {result:?}");
        assert!(
            http.responses.lock().unwrap().is_empty(),
            "both scripted responses must be consumed (two attempts)"
        );
    }

    #[tokio::test]
    async fn non_network_errors_do_not_retry() {
        let http = ScriptedHttpClient {
            responses: std::sync::Mutex::new(vec![
                Ok(ok_response()),
                Err(HttpError::RedirectRefused("https://evil/".into())),
            ]),
            last_url: std::sync::Mutex::new(None),
            last_headers: std::sync::Mutex::new(Vec::new()),
            last_body: std::sync::Mutex::new(None),
        };
        let result = http_get_with_retry(&http, &CLAUDE, "https://x/", &[], 1024).await;
        assert!(matches!(result, Err(HttpError::RedirectRefused(_))));
        assert_eq!(
            http.responses.lock().unwrap().len(),
            1,
            "second scripted response must remain unconsumed (single attempt)"
        );
    }

    #[tokio::test]
    async fn second_network_error_is_returned() {
        let http = ScriptedHttpClient {
            responses: std::sync::Mutex::new(vec![
                Err(HttpError::Network("second".into())),
                Err(HttpError::Network("first".into())),
            ]),
            last_url: std::sync::Mutex::new(None),
            last_headers: std::sync::Mutex::new(Vec::new()),
            last_body: std::sync::Mutex::new(None),
        };
        let result = http_get_with_retry(&http, &CLAUDE, "https://x/", &[], 1024).await;
        assert!(matches!(result, Err(HttpError::Network(_))));
    }
}
