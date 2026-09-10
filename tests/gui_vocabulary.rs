use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

const BANNED: &[&str] = &[
    "adapter", "schema", "payload", "envelope", "bundle", "collect", "clause", "snapshot",
];

fn gui_files(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if dir == root && entry.file_name() != "components" {
                    continue;
                }
                stack.push(path);
                continue;
            }
            let is_source = path
                .extension()
                .and_then(|e| e.to_str())
                .is_some_and(|e| e == "qml" || e == "js");
            if is_source {
                out.push(path);
            }
        }
    }
    out.sort();
    out
}

fn user_facing_literals(source: &str) -> Vec<String> {
    let mut out = Vec::new();
    for line in source.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("//") {
            continue;
        }
        for piece in line.split('"').skip(1).step_by(2) {
            out.push(piece.to_owned());
        }
    }
    out
}

#[test]
fn gui_copy_has_no_internal_vocabulary() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let mut violations: BTreeSet<String> = BTreeSet::new();
    let files = gui_files(&root);
    assert!(
        files.len() >= 15,
        "expected the GUI source tree, found {} files",
        files.len()
    );
    for path in files {
        let Ok(source) = fs::read_to_string(&path) else {
            continue;
        };
        let rel = path
            .strip_prefix(&root)
            .unwrap_or(&path)
            .display()
            .to_string();
        for literal in user_facing_literals(&source) {
            let lowered = literal.to_lowercase();
            for word in BANNED {
                if lowered
                    .split(|c: char| !c.is_ascii_alphabetic())
                    .any(|t| t == *word)
                {
                    violations.insert(format!("{rel}: {word} in {literal:?}"));
                }
            }
        }
    }
    assert!(
        violations.is_empty(),
        "GUI copy leaks internal vocabulary ({}):\n  - {}",
        violations.len(),
        violations.into_iter().collect::<Vec<_>>().join("\n  - ")
    );
}
