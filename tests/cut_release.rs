//! `scripts/agent-bar-cut-release` version contract (docs/dev/releasing.md,
//! "Manual boundary"): a version already carrying a tag bumps the patch; a
//! version set deliberately and not yet tagged is released as set.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn cut_release_script() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("scripts/agent-bar-cut-release")
}

fn git(repo: &Path, args: &[&str]) {
    let status = Command::new("git")
        .args([
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@t",
            "-c",
            "tag.gpgSign=false",
        ])
        .args([
            "-c",
            "commit.gpgSign=false",
            "-c",
            "core.hooksPath=/dev/null",
        ])
        .args(args)
        .current_dir(repo)
        .status()
        .expect("run git");
    assert!(status.success(), "git {args:?}");
}

fn write_cargo_version(repo: &Path, version: &str) {
    fs::write(
        repo.join("Cargo.toml"),
        format!("[package]\nname = \"fixture\"\nversion = \"{version}\"\nedition = \"2021\"\n"),
    )
    .unwrap();
}

fn write_version(repo: &Path, version: &str) {
    write_cargo_version(repo, version);
    fs::write(
        repo.join("manifest.json"),
        format!("{{\n  \"version\": \"{version}\"\n}}\n"),
    )
    .unwrap();
}

/// A repository whose last release is `v10.3.27`, then one feature commit.
fn released_repo(tmp: &Path) -> PathBuf {
    let repo = tmp.join("repo");
    fs::create_dir_all(repo.join("docs/releases")).unwrap();
    // A buildable crate so the real run's `cargo update --offline` works.
    fs::create_dir_all(repo.join("src")).unwrap();
    fs::write(repo.join("src/lib.rs"), "").unwrap();
    fs::write(
        repo.join("CHANGELOG.md"),
        "# Changelog\n\n## [Unreleased]\n",
    )
    .unwrap();
    write_version(&repo, "10.3.27");
    git(&repo, &["init", "-q"]);
    git(&repo, &["add", "-A"]);
    git(&repo, &["commit", "-q", "-m", "release: v10.3.27"]);
    git(&repo, &["tag", "v10.3.27"]);
    fs::write(repo.join("feature.txt"), "x\n").unwrap();
    git(&repo, &["add", "-A"]);
    git(&repo, &["commit", "-q", "-m", "feat: something new"]);
    repo
}

fn dry_run(repo: &Path) -> String {
    let out = Command::new("bash")
        .arg(cut_release_script())
        .arg("--dry-run")
        .current_dir(repo)
        .output()
        .expect("run cut-release");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap()
}

#[test]
fn tagged_version_bumps_the_patch() {
    let tmp = tempfile::tempdir().unwrap();
    let repo = released_repo(tmp.path());
    let out = dry_run(&repo);
    assert!(out.contains("next-version: 10.3.28\n"), "{out}");
    assert!(out.contains("Changes since 10.3.27:"), "{out}");
    assert!(out.contains("- feat: something new"), "{out}");
}

#[test]
fn untagged_version_is_released_as_set() {
    let tmp = tempfile::tempdir().unwrap();
    let repo = released_repo(tmp.path());
    write_version(&repo, "10.4.0");
    git(&repo, &["commit", "-q", "-am", "chore: set version 10.4.0"]);
    let out = dry_run(&repo);
    assert!(out.contains("next-version: 10.4.0\n"), "{out}");
    // Notes still cover everything since the last release tag.
    assert!(out.contains("Changes since 10.3.27:"), "{out}");
    assert!(out.contains("- feat: something new"), "{out}");
    assert!(out.contains("- chore: set version 10.4.0"), "{out}");
}

#[test]
fn untagged_version_below_the_last_release_is_refused() {
    let tmp = tempfile::tempdir().unwrap();
    let repo = released_repo(tmp.path());
    write_version(&repo, "10.3.9");
    git(&repo, &["commit", "-q", "-am", "chore: typo"]);
    let out = Command::new("bash")
        .arg(cut_release_script())
        .arg("--dry-run")
        .current_dir(&repo)
        .output()
        .expect("run cut-release");
    assert!(!out.status.success());
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("10.3.9 is not above the last release 10.3.27"),
        "{stderr}"
    );
}

fn cut(repo: &Path) -> std::process::Output {
    Command::new("bash")
        .arg(cut_release_script())
        .current_dir(repo)
        .output()
        .expect("run cut-release")
}

fn read(repo: &Path, rel: &str) -> String {
    fs::read_to_string(repo.join(rel)).unwrap()
}

#[test]
fn real_run_stamps_a_deliberate_version_as_set() {
    let tmp = tempfile::tempdir().unwrap();
    let repo = released_repo(tmp.path());
    write_version(&repo, "10.4.0");
    git(&repo, &["commit", "-q", "-am", "chore: set version 10.4.0"]);
    let out = cut(&repo);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(read(&repo, "Cargo.toml").contains("version = \"10.4.0\""));
    assert!(read(&repo, "manifest.json").contains("\"version\": \"10.4.0\""));
    assert!(read(&repo, "docs/releases/10.4.0.md").contains("Changes since 10.3.27:"));
    assert!(read(&repo, "CHANGELOG.md").contains("## [10.4.0] - "));
}

#[test]
fn real_run_bumps_a_tagged_version() {
    let tmp = tempfile::tempdir().unwrap();
    let repo = released_repo(tmp.path());
    let out = cut(&repo);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(read(&repo, "Cargo.toml").contains("version = \"10.3.28\""));
    assert!(read(&repo, "manifest.json").contains("\"version\": \"10.3.28\""));
    assert!(repo.join("docs/releases/10.3.28.md").is_file());
}

#[test]
fn deliberate_version_missing_from_the_manifest_is_refused() {
    let tmp = tempfile::tempdir().unwrap();
    let repo = released_repo(tmp.path());
    write_cargo_version(&repo, "10.4.0");
    git(
        &repo,
        &["commit", "-q", "-am", "chore: half a version bump"],
    );
    let out = cut(&repo);
    assert!(!out.status.success());
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("manifest.json version stamp failed"),
        "{stderr}"
    );
}
