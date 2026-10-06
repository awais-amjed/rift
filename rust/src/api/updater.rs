//! Rift updating itself (see `crate::updater`). Windows and Linux only;
//! elsewhere every call reports that there is nothing to update.

use crate::frb_generated::StreamSink;

/// A release newer than the one installed.
pub struct AvailableUpdate {
    pub version: String,
    /// The release notes, as written in the tag's message.
    pub notes_markdown: String,
    /// What the download weighs: the changes since this version when the
    /// release carries them, otherwise the whole package.
    pub download_bytes: u32,
}

/// Run once at start, as early as possible. May apply an update downloaded
/// before and restart into it, in which case it does not return. Returns the
/// installed version, or `None` when this copy cannot update itself — it was
/// not installed by Rift's installer or AppImage.
pub fn updater_startup() -> Option<String> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        crate::updater::startup()
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        None
    }
}

/// Looks for a newer release; pre-releases count when `include_prereleases`.
pub fn updater_check(include_prereleases: bool) -> Result<Option<AvailableUpdate>, String> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        crate::updater::check(include_prereleases)
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        let _ = include_prereleases;
        Ok(None)
    }
}

/// Downloads what [updater_check] last found. The stream carries progress
/// from 0 to 100 and ends once the update is ready, or with an error.
pub fn updater_download(sink: StreamSink<i32>) {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        crate::updater::download(sink);
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        let _ = sink.add_error("Rift updates itself only on Windows and Linux".to_string());
    }
}

/// The version already downloaded and waiting for a restart, if any.
pub fn updater_pending_version() -> Option<String> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        crate::updater::pending_version()
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        None
    }
}

/// Sets the downloaded update to be put in place once this process exits;
/// Rift then starts again by itself. Quit straight after this succeeds.
pub fn updater_apply_on_exit() -> Result<(), String> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        crate::updater::apply_on_exit()
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        Err("Rift updates itself only on Windows and Linux".to_string())
    }
}
