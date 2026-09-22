use serde::Deserialize;

use crate::plugin::maintenance::MaintenanceError;

/// Exact TTY phrase required for interactive `update apply` (CLI-029).
pub const UPDATE_TTY_PHRASE: &str = "update agent-bar";

/// TTY prompt text written to stderr.
pub const UPDATE_TTY_PROMPT: &str = "Type update agent-bar to continue:";

/// Non-TTY structured `update apply` confirmation (CLI-029).
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateConfirmation {
    pub schema_version: u32,
    pub operation: String,
    pub confirmed: bool,
    pub target_version: String,
}

impl UpdateConfirmation {
    /// Parse exactly one JSON object with optional surrounding whitespace.
    pub fn parse_strict(bytes: &[u8]) -> Result<Self, MaintenanceError> {
        let text = std::str::from_utf8(bytes)
            .map_err(|_| MaintenanceError::msg("update confirmation is not valid UTF-8"))?;
        let doc: Self = serde_json::from_str(text)
            .map_err(|e| MaintenanceError::msg(format!("malformed update confirmation: {e}")))?;
        doc.validate()?;
        Ok(doc)
    }

    fn validate(&self) -> Result<(), MaintenanceError> {
        if self.schema_version != 1 {
            return Err(MaintenanceError::msg(
                "update confirmation schemaVersion must be 1",
            ));
        }
        if self.operation != "update" {
            return Err(MaintenanceError::msg(
                "update confirmation operation must be \"update\"",
            ));
        }
        if !self.confirmed {
            return Err(MaintenanceError::msg(
                "update confirmation requires confirmed: true",
            ));
        }
        if !is_release_version(&self.target_version) {
            return Err(MaintenanceError::msg(
                "update confirmation targetVersion must be major.minor.patch",
            ));
        }
        Ok(())
    }
}

fn is_release_version(version: &str) -> bool {
    let parts: Vec<&str> = version.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|part| !part.is_empty() && part.bytes().all(|b| b.is_ascii_digit()))
}

#[cfg(test)]
mod tests {
    use super::*;

    const GOOD: &str =
        r#"{"schemaVersion":1,"operation":"update","confirmed":true,"targetVersion":"10.7.0"}"#;

    #[test]
    fn accepts_one_document_with_surrounding_whitespace() {
        let doc = UpdateConfirmation::parse_strict(format!("\n  {GOOD}\n\n").as_bytes()).unwrap();
        assert_eq!(doc.target_version, "10.7.0");
    }

    #[test]
    fn rejects_every_other_shape() {
        for bad in [
            String::new(),
            "null".to_owned(),
            "[]".to_owned(),
            format!("{GOOD}{GOOD}"),
            format!("{GOOD} x"),
            GOOD.replace("\"confirmed\":true", "\"confirmed\":false"),
            GOOD.replace("\"schemaVersion\":1", "\"schemaVersion\":2"),
            GOOD.replace("\"update\"", "\"uninstall\""),
            GOOD.replace("10.7.0", ""),
            GOOD.replace("10.7.0", "10.7"),
            GOOD.replace("10.7.0", "10.7.0.1"),
            GOOD.replace("10.7.0", "v10.7.0"),
            GOOD.replace("10.7.0", "10..0"),
            GOOD.replace("10.7.0", "10.7.0-rc1"),
            GOOD.replace("\"10.7.0\"", "10"),
            GOOD.replace("}", ",\"purgeSettingsAndBackups\":false}"),
            r#"{"schemaVersion":1,"operation":"update","confirmed":true}"#.to_owned(),
        ] {
            assert!(
                UpdateConfirmation::parse_strict(bad.as_bytes()).is_err(),
                "{bad:?}"
            );
        }
        assert!(UpdateConfirmation::parse_strict(&[0xff, 0xfe]).is_err());
    }
}
