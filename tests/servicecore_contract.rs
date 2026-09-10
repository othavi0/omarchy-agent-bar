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

    let providers = extract_keys(&js, "CLOSED_PROVIDERS");
    let expected_providers: BTreeSet<String> = ["claude", "codex", "amp", "grok", "antigravity"]
        .into_iter()
        .map(str::to_owned)
        .collect();
    assert_eq!(
        providers, expected_providers,
        "CLOSED_PROVIDERS drifted from ProviderId"
    );
}

fn default_settings_providers(js: &str) -> Vec<(String, bool)> {
    let start = js
        .find("function defaultSettings()")
        .expect("defaultSettings() not found in CoreService.js");
    let rest = &js[start..];
    let open = rest
        .find("providers: [")
        .expect("defaultSettings() has no providers array")
        + "providers: [".len();
    let close = open
        + rest[open..]
            .find(']')
            .expect("unterminated providers array");
    rest[open..close]
        .split('{')
        .skip(1)
        .map(|entry| {
            let id = entry
                .split('"')
                .nth(1)
                .unwrap_or_else(|| panic!("provider row without a quoted id: {entry}"));
            (id.to_owned(), entry.contains("enabled: true"))
        })
        .collect()
}

#[test]
fn servicecore_default_settings_match_rust_defaults() {
    let js = std::fs::read_to_string("CoreService.js").expect("read CoreService.js");
    let js_providers = default_settings_providers(&js);
    let rust_providers: Vec<(String, bool)> = agent_bar::settings::schema::Settings::defaults()
        .providers
        .into_iter()
        .map(|p| (p.id.0.as_str().to_owned(), p.enabled))
        .collect();
    assert_eq!(
        js_providers, rust_providers,
        "defaultSettings() providers drifted from Settings::defaults()"
    );
}
