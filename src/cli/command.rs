use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ProviderId {
    Claude,
    Codex,
    Amp,
    Grok,
    Antigravity,
}

impl ProviderId {
    pub const ALL: [ProviderId; 5] = [
        ProviderId::Claude,
        ProviderId::Codex,
        ProviderId::Amp,
        ProviderId::Grok,
        ProviderId::Antigravity,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            ProviderId::Claude => "claude",
            ProviderId::Codex => "codex",
            ProviderId::Amp => "amp",
            ProviderId::Grok => "grok",
            ProviderId::Antigravity => "antigravity",
        }
    }

    pub fn parse_word(word: &str) -> Option<Self> {
        match word {
            "claude" => Some(ProviderId::Claude),
            "codex" => Some(ProviderId::Codex),
            "amp" => Some(ProviderId::Amp),
            "grok" => Some(ProviderId::Grok),
            "antigravity" => Some(ProviderId::Antigravity),
            _ => None,
        }
    }
}

impl std::fmt::Display for ProviderId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatusFormat {
    Human,
    Json,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CacheMode {
    Use,
    Bypass,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotificationMode {
    Evaluate,
    Skip,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StatusOptions {
    pub format: StatusFormat,
    pub provider: Option<ProviderId>,
    pub cache: CacheMode,
    pub notifications: NotificationMode,
}

impl Default for StatusOptions {
    fn default() -> Self {
        Self {
            format: StatusFormat::Human,
            provider: None,
            cache: CacheMode::Use,
            notifications: NotificationMode::Skip,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConfigCommand {
    Show,
    Apply(ConfigInput),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConfigInput {
    Stdin,
    File(PathBuf),
    Json(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UpdateCommand {
    Interactive,
    Check,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HelpTopic {
    Status,
    Login,
    Config,
    Update,
    Uninstall,
    Help,
    Version,
}

impl HelpTopic {
    pub const ALL: [HelpTopic; 7] = [
        HelpTopic::Status,
        HelpTopic::Login,
        HelpTopic::Config,
        HelpTopic::Update,
        HelpTopic::Uninstall,
        HelpTopic::Help,
        HelpTopic::Version,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            HelpTopic::Status => "status",
            HelpTopic::Login => "login",
            HelpTopic::Config => "config",
            HelpTopic::Update => "update",
            HelpTopic::Uninstall => "uninstall",
            HelpTopic::Help => "help",
            HelpTopic::Version => "version",
        }
    }

    pub fn parse_word(word: &str) -> Option<Self> {
        match word {
            "status" => Some(HelpTopic::Status),
            "login" => Some(HelpTopic::Login),
            "config" => Some(HelpTopic::Config),
            "update" => Some(HelpTopic::Update),
            "uninstall" => Some(HelpTopic::Uninstall),
            "help" => Some(HelpTopic::Help),
            "version" => Some(HelpTopic::Version),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    Status(StatusOptions),
    Login(ProviderId),
    Config(ConfigCommand),
    Update(UpdateCommand),
    Uninstall { purge: bool },
    Help(Option<HelpTopic>),
    Version,
}
