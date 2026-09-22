use std::time::Duration;

pub use super::adapter::HttpResponse;
use super::adapter::{BoxFuture, HttpClient, HttpError};

/// Production reqwest client: HTTPS only, no redirects, body size limit.
#[derive(Debug, Clone)]
pub struct ReqwestHttpClient {
    client: reqwest::Client,
}

impl ReqwestHttpClient {
    pub fn new(timeout: Duration) -> Result<Self, reqwest::Error> {
        let client = reqwest::Client::builder()
            .timeout(timeout)
            .redirect(reqwest::redirect::Policy::none())
            .build()?;
        Ok(Self { client })
    }
}

impl ReqwestHttpClient {
    fn send(
        &self,
        request: reqwest::RequestBuilder,
        url: String,
        headers: Vec<(String, String)>,
        max_body_bytes: usize,
    ) -> BoxFuture<'_, Result<HttpResponse, HttpError>> {
        Box::pin(async move {
            if !(url.starts_with("https://")) {
                return Err(HttpError::InvalidResponse(
                    "only https URLs are allowed".into(),
                ));
            }
            let mut req = request;
            for (k, v) in &headers {
                req = req.header(k.as_str(), v.as_str());
            }
            let response = req
                .send()
                .await
                .map_err(|err| HttpError::Network(err.without_url().to_string()))?;
            let status = response.status().as_u16();
            let final_url = response.url().to_string();
            if response.status().is_redirection() {
                return Err(HttpError::RedirectRefused(final_url));
            }
            let mut body = Vec::new();
            let mut stream = response.bytes_stream();
            use futures::StreamExt;
            while let Some(chunk) = stream.next().await {
                let chunk = chunk.map_err(|err| HttpError::Network(err.to_string()))?;
                if body.len().saturating_add(chunk.len()) > max_body_bytes {
                    return Err(HttpError::BodyTooLarge);
                }
                body.extend_from_slice(&chunk);
            }
            Ok(HttpResponse {
                status,
                final_url,
                body,
            })
        })
    }
}

impl HttpClient for ReqwestHttpClient {
    fn get(
        &self,
        url: &str,
        headers: &[(&str, &str)],
        max_body_bytes: usize,
    ) -> BoxFuture<'_, Result<HttpResponse, HttpError>> {
        let url = url.to_owned();
        let headers: Vec<(String, String)> = headers
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect();
        let request = self.client.get(&url);
        self.send(request, url, headers, max_body_bytes)
    }

    fn post(
        &self,
        url: &str,
        headers: &[(&str, &str)],
        body: Vec<u8>,
        max_body_bytes: usize,
    ) -> BoxFuture<'_, Result<HttpResponse, HttpError>> {
        let url = url.to_owned();
        let headers: Vec<(String, String)> = headers
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect();
        let request = self.client.post(&url).body(body);
        self.send(request, url, headers, max_body_bytes)
    }
}

/// Test double with scripted responses.
#[cfg(test)]
#[derive(Debug, Default)]
pub struct ScriptedHttpClient {
    pub responses: std::sync::Mutex<Vec<Result<HttpResponse, HttpError>>>,
    pub last_url: std::sync::Mutex<Option<String>>,
    pub last_headers: std::sync::Mutex<Vec<(String, String)>>,
    pub last_body: std::sync::Mutex<Option<Vec<u8>>>,
}

#[cfg(test)]
impl ScriptedHttpClient {
    pub fn single(response: Result<HttpResponse, HttpError>) -> Self {
        Self {
            responses: std::sync::Mutex::new(vec![response]),
            last_url: std::sync::Mutex::new(None),
            last_headers: std::sync::Mutex::new(Vec::new()),
            last_body: std::sync::Mutex::new(None),
        }
    }

    fn record(&self, url: &str, headers: &[(&str, &str)]) {
        *self.last_url.lock().unwrap_or_else(|e| e.into_inner()) = Some(url.to_owned());
        *self.last_headers.lock().unwrap_or_else(|e| e.into_inner()) = headers
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect();
    }

    fn next_response(&self) -> Result<HttpResponse, HttpError> {
        self.responses
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .pop()
            .unwrap_or_else(|| Err(HttpError::Network("scripted HTTP client exhausted".into())))
    }
}

#[cfg(test)]
impl HttpClient for ScriptedHttpClient {
    fn get(
        &self,
        url: &str,
        headers: &[(&str, &str)],
        _max_body_bytes: usize,
    ) -> BoxFuture<'_, Result<HttpResponse, HttpError>> {
        self.record(url, headers);
        *self.last_body.lock().unwrap_or_else(|e| e.into_inner()) = None;
        let next = self.next_response();
        Box::pin(async move { next })
    }

    fn post(
        &self,
        url: &str,
        headers: &[(&str, &str)],
        body: Vec<u8>,
        _max_body_bytes: usize,
    ) -> BoxFuture<'_, Result<HttpResponse, HttpError>> {
        self.record(url, headers);
        *self.last_body.lock().unwrap_or_else(|e| e.into_inner()) = Some(body);
        let next = self.next_response();
        Box::pin(async move { next })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn scripted_post_records_url_headers_and_body() {
        let http = ScriptedHttpClient::single(Ok(HttpResponse {
            status: 200,
            final_url: "https://api.anthropic.com/x".into(),
            body: b"{}".to_vec(),
        }));
        let result = http
            .post(
                "https://api.anthropic.com/x",
                &[("Content-Type", "application/json")],
                br#"{"a":1}"#.to_vec(),
                1024,
            )
            .await;
        assert!(result.is_ok());
        assert_eq!(
            http.last_url.lock().unwrap().as_deref(),
            Some("https://api.anthropic.com/x")
        );
        assert_eq!(
            http.last_headers.lock().unwrap().clone(),
            vec![("Content-Type".to_owned(), "application/json".to_owned())]
        );
        assert_eq!(
            http.last_body.lock().unwrap().clone(),
            Some(br#"{"a":1}"#.to_vec())
        );
    }

    #[tokio::test]
    async fn scripted_get_clears_last_body_from_a_prior_post() {
        let http = ScriptedHttpClient::single(Ok(HttpResponse {
            status: 200,
            final_url: "https://api.anthropic.com/x".into(),
            body: b"{}".to_vec(),
        }));
        http.responses.lock().unwrap().push(Ok(HttpResponse {
            status: 200,
            final_url: "https://api.anthropic.com/y".into(),
            body: b"{}".to_vec(),
        }));
        let _ = http.post("https://x/", &[], b"body".to_vec(), 1024).await;
        let _ = http.get("https://y/", &[], 1024).await;
        assert!(http.last_body.lock().unwrap().is_none());
    }
}
