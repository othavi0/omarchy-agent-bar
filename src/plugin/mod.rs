pub mod bundle;
pub mod maintenance;
pub mod omarchy;
pub mod paths;
pub mod update_apply;

pub use bundle::{
    BundleBuilder, BundleError, BundleFileEntry, BundleReceipt, BundleValidator,
    MINIMUM_QUICKSHELL_VERSION, OFFICIAL_TARGET, OMARCHY_CONTRACT,
};
pub use maintenance::{
    require_absolute_executable, resolve_absolute_executable, MaintenanceError, ReqwestReleaseHttp,
    UninstallConfirmation, UpdateCheck, UpdateCheckDocument, UpdateCheckProbe,
    UNINSTALL_TTY_PHRASE, UNINSTALL_TTY_PROMPT,
};
pub use omarchy::{CommandOutput, CommandRunner, OmarchyError, ProcessCommandRunner};
pub use paths::{txid_from_bytes, validate_archive_entry_path, PathError, PluginPaths, PLUGIN_ID};
pub use update_apply::{UpdateConfirmation, UPDATE_TTY_PHRASE, UPDATE_TTY_PROMPT};
