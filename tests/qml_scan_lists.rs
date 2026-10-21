use std::collections::BTreeSet;
use std::path::Path;

fn listed_files(source: &str, function: &str) -> BTreeSet<String> {
    let header = format!("function {function}()");
    let start = source
        .find(&header)
        .unwrap_or_else(|| panic!("{function}() not found"));
    let body = &source[start..];
    let end = body
        .find("\n  }\n")
        .unwrap_or_else(|| panic!("{function}() has no closing brace"));
    body[..end]
        .split('"')
        .skip(1)
        .step_by(2)
        .filter(|s| s.ends_with(".qml"))
        .map(str::to_owned)
        .collect()
}

fn plugin_qml_files() -> BTreeSet<String> {
    let mut files = BTreeSet::new();
    for (dir, prefix) in [(".", ""), ("components", "components/")] {
        let entries = std::fs::read_dir(Path::new(dir)).expect("read plugin QML directory");
        for entry in entries {
            let name = entry.expect("read directory entry").file_name();
            let name = name.to_string_lossy();
            if name.ends_with(".qml") {
                files.insert(format!("{prefix}{name}"));
            }
        }
    }
    files
}

fn drift(test_file: &str, function: &str, exempt: &[&str]) -> Option<String> {
    let source = std::fs::read_to_string(test_file).expect("read QML test file");
    let listed = listed_files(&source, function);
    let expected: BTreeSet<String> = plugin_qml_files()
        .into_iter()
        .filter(|f| !exempt.contains(&f.as_str()))
        .collect();
    let unscanned: Vec<&String> = expected.difference(&listed).collect();
    let stale: Vec<&String> = listed.difference(&expected).collect();
    if unscanned.is_empty() && stale.is_empty() {
        return None;
    }
    Some(format!(
        "{test_file} {function}() drifted from the plugin QML files\n  \
         not scanned: {unscanned:?}\n  listed but absent or exempt: {stale:?}"
    ))
}

#[test]
fn scan_lists_cover_every_qml_file() {
    let failures: Vec<String> = [
        drift(
            "tests/qml/tst_Accessibility.qml",
            "v10QmlFiles",
            &["components/HelperLane.qml"],
        ),
        drift(
            "tests/qml/tst_Tokens.qml",
            "tokenScannedFiles",
            &[
                "Service.qml",
                "components/FocusController.qml",
                "components/HelperLane.qml",
            ],
        ),
    ]
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
