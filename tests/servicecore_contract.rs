use std::collections::BTreeSet;

fn extract_keys(source: &str, var_name: &str) -> BTreeSet<String> {
    let start = source
        .find(&format!("var {var_name} = {{"))
        .unwrap_or_else(|| panic!("{var_name} not found in CoreService.js"));
    let rest = &source[start..];
    let end = rest.find('}').expect("unterminated const object");
    let body = &rest[..end];
    let mut keys = BTreeSet::new();
    for cap in body.split('"').skip(1).step_by(2) {
        if !cap.is_empty() && cap.chars().all(|c| c.is_ascii_lowercase() || c == '_') {
            keys.insert(cap.to_owned());
        }
    }
    keys
}

#[test]
fn servicecore_enums_match_schema() {
    let js = std::fs::read_to_string("CoreService.js").expect("read CoreService.js");

    let states = extract_keys(&js, "PROVIDER_STATES");
    let expected_states: BTreeSet<String> = [
        "ready",
        "stale",
        "cli_missing",
        "unauthenticated",
        "rate_limited",
        "network_error",
        "provider_error",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect();
    assert_eq!(
        states, expected_states,
        "PROVIDER_STATES drifted from ProviderState"
    );

    let kinds = extract_keys(&js, "ACTION_KINDS");
    let expected_kinds: BTreeSet<String> = ["retry", "login", "view_installation"]
        .into_iter()
        .map(str::to_owned)
        .collect();
    assert_eq!(
        kinds, expected_kinds,
        "ACTION_KINDS drifted from ActionKind"
    );

    let providers: BTreeSet<String> = extract_provider_table(&js)
        .into_iter()
        .filter(|p| p.closed)
        .map(|p| p.id)
        .collect();
    let expected_providers: BTreeSet<String> = ["claude", "codex", "amp", "grok", "antigravity"]
        .into_iter()
        .map(str::to_owned)
        .collect();
    assert_eq!(
        providers, expected_providers,
        "PROVIDERS drifted from ProviderId"
    );
}

struct ProviderRow {
    id: String,
    default_enabled: bool,
    closed: bool,
}

/// Parses `var PROVIDERS = [...]` in `CoreService.js`, the single JS-side
/// copy of the Rust `catalog::PROVIDERS` id/order/name/icon table.
fn extract_provider_table(js: &str) -> Vec<ProviderRow> {
    let start = js
        .find("var PROVIDERS = [")
        .expect("PROVIDERS not found in CoreService.js")
        + "var PROVIDERS = [".len();
    let rest = &js[start..];
    let end = rest.find(']').expect("unterminated PROVIDERS array");
    let body = &rest[..end];
    body.split('{')
        .skip(1)
        .map(|entry| {
            let close = entry.find('}').expect("unterminated provider row");
            let row = &entry[..close];
            let id = row
                .split('"')
                .nth(1)
                .unwrap_or_else(|| panic!("provider row without a quoted id: {row}"))
                .to_owned();
            ProviderRow {
                id,
                default_enabled: row.contains("defaultEnabled: true"),
                closed: row.contains("closed: true"),
            }
        })
        .collect()
}

#[test]
fn servicecore_default_settings_match_rust_defaults() {
    let js = std::fs::read_to_string("CoreService.js").expect("read CoreService.js");
    let js_providers: Vec<(String, bool)> = extract_provider_table(&js)
        .into_iter()
        .map(|p| (p.id, p.default_enabled))
        .collect();
    let rust_providers: Vec<(String, bool)> = agent_bar::settings::schema::Settings::defaults()
        .providers
        .into_iter()
        .map(|p| (p.id.0.as_str().to_owned(), p.enabled))
        .collect();
    assert_eq!(
        js_providers, rust_providers,
        "PROVIDERS defaultEnabled drifted from Settings::defaults()"
    );
}

#[test]
fn servicecore_provider_table_order_matches_catalog() {
    let js = std::fs::read_to_string("CoreService.js").expect("read CoreService.js");
    let js_ids: Vec<String> = extract_provider_table(&js)
        .into_iter()
        .map(|p| p.id)
        .collect();
    let rust_ids: Vec<String> = agent_bar::providers::catalog::PROVIDERS
        .iter()
        .map(|descriptor| descriptor.id.as_str().to_owned())
        .collect();
    assert_eq!(
        js_ids, rust_ids,
        "CoreService.js PROVIDERS order drifted from catalog::PROVIDERS"
    );
}
