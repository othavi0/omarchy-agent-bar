use agent_bar::notifications::state::{
    NotificationLevel, CRITICAL_USED_PERCENT, WARNING_USED_PERCENT,
};

fn js_constant(source: &str, name: &str) -> f64 {
    let needle = format!("var {name} = ");
    let start = source
        .find(&needle)
        .unwrap_or_else(|| panic!("{name} not found in CoreView.js"));
    let rest = &source[start + needle.len()..];
    let end = rest
        .find(|c: char| !(c.is_ascii_digit() || c == '.'))
        .unwrap_or(rest.len());
    rest[..end]
        .parse()
        .unwrap_or_else(|_| panic!("{name} is not a number in CoreView.js"))
}

fn core_view() -> String {
    std::fs::read_to_string("CoreView.js").expect("read CoreView.js")
}

#[test]
fn severity_thresholds_match_core_view() {
    let js = core_view();
    assert_eq!(
        js_constant(&js, "SEVERITY_CRITICAL_USED_PERCENT"),
        CRITICAL_USED_PERCENT,
        "CoreView.js critical threshold drifted from NotificationLevel"
    );
    assert_eq!(
        js_constant(&js, "SEVERITY_WARNING_USED_PERCENT"),
        WARNING_USED_PERCENT,
        "CoreView.js warning threshold drifted from NotificationLevel"
    );
}

#[test]
fn severity_boundaries_agree_across_the_seam() {
    let js = core_view();
    let critical = js_constant(&js, "SEVERITY_CRITICAL_USED_PERCENT");
    let warning = js_constant(&js, "SEVERITY_WARNING_USED_PERCENT");

    let cases = [
        (warning - 0.1, None),
        (warning, Some(NotificationLevel::Warning)),
        (critical - 0.1, Some(NotificationLevel::Warning)),
        (critical, Some(NotificationLevel::Critical)),
        (100.0, Some(NotificationLevel::Critical)),
    ];
    for (used, expected) in cases {
        assert_eq!(
            NotificationLevel::from_used_percent(used),
            expected,
            "used = {used}"
        );
    }
}
