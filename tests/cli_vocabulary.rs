use std::fs;
use std::path::{Path, PathBuf};

fn is_token_boundary(line: &str, pos: usize) -> bool {
    pos == 0 || {
        let prev = line.as_bytes()[pos - 1];
        !(prev.is_ascii_alphanumeric() || prev == b'_')
    }
}

fn opens_raw_string(line: &str) -> bool {
    ["br#\"", "br\"", "r#\"", "r\""]
        .iter()
        .any(|prefix| matches!(line.find(prefix), Some(pos) if is_token_boundary(line, pos)))
}

fn string_literals(source: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut in_string = false;
    for line in source.lines() {
        if !in_string && line.trim_start().starts_with("//") {
            continue;
        }
        let quote_count = line.matches('"').count();
        if !in_string && opens_raw_string(line) && quote_count % 2 == 0 {
            continue;
        }
        for (idx, piece) in line.split('"').enumerate() {
            let is_inside = if in_string {
                idx % 2 == 0
            } else {
                idx % 2 == 1
            };
            if is_inside {
                out.push(piece.to_owned());
            }
        }
        if quote_count % 2 == 1 {
            in_string = !in_string;
        }
    }
    out
}

fn cli_files(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![root.join("src/cli")];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
                continue;
            }
            let is_source = path.extension().and_then(|e| e.to_str()) == Some("rs");
            if is_source {
                out.push(path);
            }
        }
    }
    out.sort();
    out
}

fn all_cli_source(root: &Path) -> String {
    let mut combined = String::new();
    for path in cli_files(root) {
        if let Ok(source) = fs::read_to_string(&path) {
            combined.push_str(&source);
            combined.push('\n');
        }
    }
    combined
}

#[test]
fn cli_messages_do_not_say_clause() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let mut violations = Vec::new();
    let files = cli_files(&root);
    assert!(
        files.len() >= 4,
        "expected the cli module tree, found {} files",
        files.len()
    );
    for path in files {
        let Ok(source) = fs::read_to_string(&path) else {
            continue;
        };
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("?")
            .to_owned();
        for literal in string_literals(&source) {
            if literal
                .to_lowercase()
                .split(|c: char| !c.is_ascii_alphabetic())
                .any(|token| token == "clause" || token == "clauses")
            {
                violations.push(format!("{name}: {literal:?}"));
            }
        }
    }
    assert!(
        violations.is_empty(),
        "CLI messages still say clause ({}):\n  - {}",
        violations.len(),
        violations.join("\n  - ")
    );
}

#[test]
fn cli_messages_are_defined_once() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let watched = ["config apply requires stdin, file <path>, or json <value>"];
    let mut violations = Vec::new();
    let files = cli_files(&root);
    let mut totals = vec![0usize; watched.len()];
    for path in &files {
        let Ok(source) = fs::read_to_string(path) else {
            continue;
        };
        for (idx, needle) in watched.iter().enumerate() {
            totals[idx] += source.matches(needle).count();
        }
    }
    for (idx, needle) in watched.iter().enumerate() {
        if totals[idx] > 1 {
            violations.push(format!("{needle:?} appears {} times", totals[idx]));
        }
    }
    assert!(
        violations.is_empty(),
        "CLI messages defined more than once ({}):\n  - {}",
        violations.len(),
        violations.join("\n  - ")
    );
}

#[test]
fn cli_messages_that_can_name_a_fix_do() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let source = all_cli_source(&root);
    let needle = "{} login executable was not found; install the provider CLI first";
    assert!(
        source.contains(needle),
        "missing fix-naming message: {needle}"
    );
}

#[test]
fn docs_commands_do_not_say_clause() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("docs/guide/commands.md");
    let source = fs::read_to_string(&path).expect("read docs/guide/commands.md");
    let lowered = source.to_lowercase();
    let violations: Vec<&str> = lowered
        .split(|c: char| !c.is_ascii_alphabetic())
        .filter(|token| *token == "clause" || *token == "clauses")
        .collect();
    assert!(
        violations.is_empty(),
        "docs/guide/commands.md still says clause ({} occurrences)",
        violations.len()
    );
}
