use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use fs2::FileExt;
use time::OffsetDateTime;

use super::schema::{CacheDocument, CacheSchemaError, CachedProvider};
use crate::cli::ProviderId;
use crate::status::schema::ProviderStatus;
use crate::support::atomic_file::replace_atomically;
use crate::support::maintenance_gate::SharedMaintenanceGate;

/// Cache filesystem + lock paths.
#[derive(Debug, Clone)]
pub struct CachePaths {
    pub document: PathBuf,
    pub lock: PathBuf,
}

impl CachePaths {
    pub fn from_cache_home(cache_home: impl Into<PathBuf>) -> Self {
        let root = cache_home.into().join("agent-bar");
        Self {
            document: root.join("status-v2.json"),
            lock: root.join("status.lock"),
        }
    }

    pub fn default_xdg() -> Self {
        let base = std::env::var_os("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
            .unwrap_or_else(|| PathBuf::from(".cache"));
        Self::from_cache_home(base)
    }
}

#[derive(Debug)]
pub enum CacheStoreError {
    Schema(CacheSchemaError),
    Io(io::Error),
    MaintenanceBlocked,
}

impl std::fmt::Display for CacheStoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Schema(err) => write!(f, "{err}"),
            Self::Io(err) => write!(f, "{err}"),
            Self::MaintenanceBlocked => write!(f, "maintenance gate held exclusively"),
        }
    }
}

impl std::error::Error for CacheStoreError {}

impl From<io::Error> for CacheStoreError {
    fn from(value: io::Error) -> Self {
        Self::Io(value)
    }
}

impl From<CacheSchemaError> for CacheStoreError {
    fn from(value: CacheSchemaError) -> Self {
        Self::Schema(value)
    }
}

/// Persistent cache store with quarantine on corruption.
#[derive(Debug, Clone)]
pub struct CacheStore {
    paths: CachePaths,
    gate: SharedMaintenanceGate,
}

impl CacheStore {
    pub fn new(paths: CachePaths, gate: SharedMaintenanceGate) -> Self {
        Self { paths, gate }
    }

    pub fn paths(&self) -> &CachePaths {
        &self.paths
    }

    /// Load cache document. Missing file → empty. Corrupt → quarantine + empty.
    pub fn load(&self) -> Result<CacheDocument, CacheStoreError> {
        match fs::read(&self.paths.document) {
            Ok(bytes) => match parse_document(&bytes) {
                Ok(doc) => Ok(doc),
                Err(err) => {
                    self.quarantine(&bytes, &err.to_string())?;
                    Ok(CacheDocument::empty())
                }
            },
            Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(CacheDocument::empty()),
            Err(err) => Err(CacheStoreError::Io(err)),
        }
    }

    #[cfg(test)]
    pub fn merge_provider(
        &self,
        id: ProviderId,
        entry: CachedProvider,
        now: OffsetDateTime,
    ) -> Result<CacheDocument, CacheStoreError> {
        self.merge_providers(vec![(id, entry)], now)
    }

    /// Merge every entry from one poll in a single load-modify-write: one
    /// file lock, one `revision` bump, one atomic replace, however many
    /// providers were collected.
    pub fn merge_providers(
        &self,
        entries: Vec<(ProviderId, CachedProvider)>,
        _now: OffsetDateTime,
    ) -> Result<CacheDocument, CacheStoreError> {
        if entries.is_empty() {
            return self.load();
        }
        let _guard = self
            .gate
            .try_lock_shared()?
            .ok_or(CacheStoreError::MaintenanceBlocked)?;
        let file_lock = open_lock(&self.paths.lock)?;
        FileExt::lock_exclusive(&file_lock)?;
        let mut doc = self.load()?;
        for (id, entry) in entries {
            doc.providers.insert(id.as_str().to_owned(), entry);
        }
        doc.revision = doc.revision.saturating_add(1);
        doc.validate()?;
        let bytes = serde_json::to_vec_pretty(&doc).map_err(|err| {
            CacheStoreError::Schema(CacheSchemaError::InvalidJson(err.to_string()))
        })?;
        let mut with_nl = bytes;
        if !with_nl.ends_with(b"\n") {
            with_nl.push(b'\n');
        }
        replace_atomically(&self.paths.document, &with_nl, 0o600)?;
        FileExt::unlock(&file_lock)?;
        Ok(doc)
    }

    fn quarantine(&self, bytes: &[u8], reason: &str) -> Result<(), CacheStoreError> {
        if let Some(parent) = self.paths.document.parent() {
            fs::create_dir_all(parent)?;
        }
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let dest = self
            .paths
            .document
            .with_extension(format!("corrupt-{stamp}.json"));
        let _ = fs::write(&dest, bytes);
        let _ = fs::remove_file(&self.paths.document);
        log::warn!("quarantined corrupt cache ({}): {}", reason, dest.display());
        Ok(())
    }
}

fn parse_document(bytes: &[u8]) -> Result<CacheDocument, CacheSchemaError> {
    let mut value: serde_json::Value = serde_json::from_slice(bytes)
        .map_err(|err| CacheSchemaError::InvalidJson(err.to_string()))?;
    strip_legacy_amp_cache_entry(&mut value);
    let doc: CacheDocument = serde_json::from_value(value)
        .map_err(|err| CacheSchemaError::InvalidJson(err.to_string()))?;
    doc.validate()?;
    Ok(doc)
}

/// Discard a legacy `"amp"` cache row (Amp was retired 2026-09-17) before the
/// document is deserialized, so an old cache file quarantines the whole
/// document only for a genuinely unknown key, not for this expected one.
fn strip_legacy_amp_cache_entry(value: &mut serde_json::Value) {
    if let Some(providers) = value
        .as_object_mut()
        .and_then(|obj| obj.get_mut("providers"))
        .and_then(serde_json::Value::as_object_mut)
    {
        providers.remove("amp");
    }
}

fn open_lock(path: &Path) -> io::Result<fs::File> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)
}

/// Build a cache entry from a live provider status and TTL.
pub fn entry_from_status(
    status: ProviderStatus,
    started_at: OffsetDateTime,
    completed_at: OffsetDateTime,
    ttl: std::time::Duration,
) -> CachedProvider {
    let expires_at = completed_at + ttl;
    CachedProvider {
        started_at,
        completed_at,
        expires_at,
        status,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::status::schema::{DataSource, ProviderStatus};
    use crate::support::maintenance_gate::MaintenanceGate;
    use std::sync::Arc;
    use time::macros::datetime;

    fn store_in(dir: &Path) -> CacheStore {
        CacheStore::new(
            CachePaths {
                document: dir.join("status-v2.json"),
                lock: dir.join("status.lock"),
            },
            Arc::new(MaintenanceGate::open(dir.join("maintenance.lock")).unwrap()),
        )
    }

    fn ready_status() -> ProviderStatus {
        ProviderStatus::ready(
            ProviderId::Claude,
            "Claude",
            DataSource::Live,
            None,
            vec![],
            datetime!(2026-07-26 18:42:00 UTC),
        )
        .unwrap()
    }

    #[test]
    fn missing_load_is_empty() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(dir.path());
        let doc = store.load().unwrap();
        assert_eq!(doc.revision, 0);
        assert!(doc.providers.is_empty());
    }

    #[test]
    fn expiry_at_or_after_expires_at() {
        let now = datetime!(2026-07-26 18:47:01 UTC);
        let mut doc = CacheDocument::empty();
        doc.providers.insert(
            "claude".into(),
            CachedProvider {
                started_at: datetime!(2026-07-26 18:42:00 UTC),
                completed_at: datetime!(2026-07-26 18:42:01 UTC),
                expires_at: datetime!(2026-07-26 18:47:01 UTC),
                status: ready_status(),
            },
        );
        assert!(!doc.is_fresh(ProviderId::Claude, now));
        assert!(doc.is_fresh(ProviderId::Claude, datetime!(2026-07-26 18:47:00 UTC)));
    }

    #[test]
    fn merge_preserves_siblings_and_increments_revision() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(dir.path());
        let now = datetime!(2026-07-26 18:42:00 UTC);
        let claude = entry_from_status(
            ready_status(),
            now,
            now,
            std::time::Duration::from_secs(300),
        );
        store
            .merge_provider(ProviderId::Claude, claude, now)
            .unwrap();
        let codex_status = ProviderStatus::ready(
            ProviderId::Codex,
            "Codex",
            DataSource::Live,
            None,
            vec![],
            now,
        )
        .unwrap();
        let codex = entry_from_status(codex_status, now, now, std::time::Duration::from_secs(90));
        let doc = store.merge_provider(ProviderId::Codex, codex, now).unwrap();
        assert_eq!(doc.revision, 2);
        assert!(doc.providers.contains_key("claude"));
        assert!(doc.providers.contains_key("codex"));
    }

    #[test]
    fn legacy_account_and_error_code_keys_are_tolerated() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(dir.path());
        fs::create_dir_all(store.paths.document.parent().unwrap()).unwrap();
        let legacy = br#"{
            "schemaVersion": 2,
            "revision": 1,
            "providers": {
                "claude": {
                    "startedAt": "2026-07-26T18:42:00Z",
                    "completedAt": "2026-07-26T18:42:01Z",
                    "expiresAt": "2026-07-26T18:47:01Z",
                    "status": {
                        "id": "claude",
                        "name": "Claude",
                        "state": "stale",
                        "source": "cache",
                        "plan": null,
                        "account": { "label": "Old Label" },
                        "windows": [],
                        "lastSuccessAt": "2026-07-26T18:40:00Z",
                        "error": {
                            "code": "network_error",
                            "message": "Temporary network failure.",
                            "retryable": true
                        },
                        "action": { "kind": "retry", "label": "Retry", "target": null }
                    }
                }
            }
        }"#;
        fs::write(&store.paths.document, legacy).unwrap();
        let doc = store.load().unwrap();
        assert_eq!(doc.revision, 1, "legacy document must not be quarantined");
        let entry = doc.get(ProviderId::Claude).expect("claude entry loads");
        assert_eq!(
            entry.status.error().map(|e| e.message.as_str()),
            Some("Temporary network failure.")
        );
        let corrupt_dir = fs::read_dir(store.paths.document.parent().unwrap()).unwrap();
        assert!(
            corrupt_dir
                .filter_map(|e| e.ok())
                .all(|e| !e.file_name().to_string_lossy().contains("corrupt")),
            "legacy keys must never quarantine the cache"
        );
    }

    #[test]
    fn legacy_amp_cache_row_is_discarded_not_quarantined() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(dir.path());
        fs::create_dir_all(store.paths.document.parent().unwrap()).unwrap();
        let legacy = br#"{
            "schemaVersion": 2,
            "revision": 3,
            "providers": {
                "claude": {
                    "startedAt": "2026-07-26T18:42:00Z",
                    "completedAt": "2026-07-26T18:42:01Z",
                    "expiresAt": "2026-07-26T18:47:01Z",
                    "status": {
                        "id": "claude",
                        "name": "Claude",
                        "state": "ready",
                        "source": "live",
                        "plan": null,
                        "windows": [],
                        "lastSuccessAt": "2026-07-26T18:40:00Z",
                        "error": null,
                        "action": null
                    }
                },
                "amp": {
                    "startedAt": "2026-07-26T18:42:00Z",
                    "completedAt": "2026-07-26T18:42:01Z",
                    "expiresAt": "2026-07-26T18:47:01Z",
                    "status": {
                        "id": "amp",
                        "name": "Amp",
                        "state": "ready",
                        "source": "live",
                        "plan": null,
                        "windows": [],
                        "lastSuccessAt": "2026-07-26T18:40:00Z",
                        "error": null,
                        "action": null
                    }
                }
            }
        }"#;
        fs::write(&store.paths.document, legacy).unwrap();
        let doc = store.load().unwrap();
        assert_eq!(doc.revision, 3, "legacy document must not be quarantined");
        assert!(doc.get(ProviderId::Claude).is_some(), "sibling survives");
        assert!(
            !doc.providers.contains_key("amp"),
            "retired amp row must be dropped"
        );
        let corrupt_dir = fs::read_dir(store.paths.document.parent().unwrap()).unwrap();
        assert!(
            corrupt_dir
                .filter_map(|e| e.ok())
                .all(|e| !e.file_name().to_string_lossy().contains("corrupt")),
            "a legacy amp row must never quarantine the cache"
        );
    }

    #[test]
    fn an_actually_unknown_cache_key_still_quarantines() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(dir.path());
        fs::create_dir_all(store.paths.document.parent().unwrap()).unwrap();
        let bogus = br#"{
            "schemaVersion": 2,
            "revision": 1,
            "providers": {
                "nope": {
                    "startedAt": "2026-07-26T18:42:00Z",
                    "completedAt": "2026-07-26T18:42:01Z",
                    "expiresAt": "2026-07-26T18:47:01Z",
                    "status": {
                        "id": "nope",
                        "name": "Nope",
                        "state": "ready",
                        "source": "live",
                        "plan": null,
                        "windows": [],
                        "lastSuccessAt": "2026-07-26T18:40:00Z",
                        "error": null,
                        "action": null
                    }
                }
            }
        }"#;
        fs::write(&store.paths.document, bogus).unwrap();
        let doc = store.load().unwrap();
        assert!(doc.providers.is_empty(), "quarantine resets to empty");
        let corrupt: Vec<_> = fs::read_dir(store.paths.document.parent().unwrap())
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().contains("corrupt-"))
            .collect();
        assert_eq!(
            corrupt.len(),
            1,
            "a genuinely unknown key still quarantines"
        );
    }

    #[test]
    fn corrupt_cache_is_quarantined() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(dir.path());
        fs::create_dir_all(store.paths.document.parent().unwrap()).unwrap();
        fs::write(&store.paths.document, b"{not-json").unwrap();
        let doc = store.load().unwrap();
        assert!(doc.providers.is_empty());
        let corrupt: Vec<_> = fs::read_dir(store.paths.document.parent().unwrap())
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().contains("corrupt-"))
            .collect();
        assert!(!corrupt.is_empty());
    }

    #[test]
    fn exclusive_maintenance_blocks_merge() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_in(dir.path());
        let exclusive = store.gate.lock_exclusive().unwrap();
        let now = datetime!(2026-07-26 18:42:00 UTC);
        let entry = entry_from_status(
            ready_status(),
            now,
            now,
            std::time::Duration::from_secs(300),
        );
        let err = store
            .merge_provider(ProviderId::Claude, entry, now)
            .unwrap_err();
        assert!(matches!(err, CacheStoreError::MaintenanceBlocked));
        drop(exclusive);
    }
}
