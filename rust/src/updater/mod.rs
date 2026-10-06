//! Rift updating itself, through Velopack.
//!
//! A release is packed by `vpk` (`.github/workflows/release.yml`): on Windows
//! into an installer that puts Rift in the user's own folder, on Linux into an
//! AppImage. A copy installed either way finds newer releases, downloads one
//! in the background, and replaces itself when Rift quits for it. A copy that
//! was not installed by Velopack — a build run from its folder, the old
//! installer's, the `.tar.gz` — has nothing to replace and reports that.
//!
//! Windows' install, update and uninstall hooks run in the runner, before
//! Flutter starts (`windows/runner/velopack_hooks.cpp`): Velopack gives each
//! a few seconds, and a whole engine would spend them starting.

mod signature;
mod source;

use std::sync::{mpsc, Mutex};

use velopack::{UpdateCheck, UpdateInfo, UpdateManager, VelopackApp};

use crate::api::updater::AvailableUpdate;
use crate::frb_generated::StreamSink;
use source::SignedSource;

/// The manager of the last check, with what it found: a download continues
/// from the same source, which knows where each package of the feed it read
/// is.
struct Session {
    manager: UpdateManager,
    update: Option<UpdateInfo>,
}

static SESSION: Mutex<Option<Session>> = Mutex::new(None);

/// Velopack's start-up: applies an update downloaded in an earlier run that
/// was quit without restarting for it (the process is replaced, and this does
/// not return), and tidies older packages away. Returns the installed
/// version, or `None` when this copy was not installed by Velopack.
pub(crate) fn startup() -> Option<String> {
    let mut app = VelopackApp::build();
    #[cfg(target_os = "windows")]
    {
        // The id Rift's notifications are posted under (ToastIdentity), and
        // the one `vpk pack --aumid` gives the shortcuts.
        app = app.set_app_user_model_id("CodingFries.Rift");
    }
    app.run();
    installed_manager(false).ok().map(|m| m.get_current_version_as_string())
}

fn installed_manager(include_prereleases: bool) -> Result<UpdateManager, String> {
    let source = SignedSource::new(include_prereleases);
    UpdateManager::new(source, None, None).map_err(|e| e.to_string())
}

/// Asks for the newest release, among pre-releases too when
/// `include_prereleases`. `None` when there is nothing newer.
pub(crate) fn check(include_prereleases: bool) -> Result<Option<AvailableUpdate>, String> {
    let manager = installed_manager(include_prereleases)?;
    let found = match manager.check_for_updates().map_err(|e| e.to_string())? {
        UpdateCheck::UpdateAvailable(update) => Some(*update),
        UpdateCheck::NoUpdateAvailable | UpdateCheck::RemoteIsEmpty => None,
    };
    let available = found.as_ref().map(|update| {
        let target = &update.TargetFullRelease;
        AvailableUpdate {
            version: target.Version.clone(),
            notes_markdown: target.NotesMarkdown.clone(),
            download_bytes: u32::try_from(if update.DeltasToTarget.is_empty() {
                target.Size
            } else {
                update.DeltasToTarget.iter().map(|d| d.Size).sum()
            })
            .unwrap_or(u32::MAX),
        }
    });
    *SESSION.lock().unwrap() = Some(Session { manager, update: found });
    Ok(available)
}

/// Downloads what the last [check] found, sending its progress (0–100) to
/// `sink`; the stream ends when the update is ready, or with an error.
pub(crate) fn download(sink: StreamSink<i32>) {
    let Some((manager, update)) = SESSION
        .lock()
        .unwrap()
        .as_ref()
        .and_then(|s| s.update.clone().map(|u| (s.manager.clone(), u)))
    else {
        let _ = sink.add_error("There is no update to download".to_string());
        return;
    };
    std::thread::spawn(move || {
        let (progress_tx, progress_rx) = mpsc::channel::<i16>();
        let forward = {
            let sink = sink.clone();
            std::thread::spawn(move || {
                for p in progress_rx {
                    let _ = sink.add(p as i32);
                }
            })
        };
        let result = manager.download_updates(&update, Some(progress_tx));
        let _ = forward.join();
        match result {
            Ok(()) => {
                let _ = sink.add(100);
            }
            Err(e) => {
                let _ = sink.add_error(e.to_string());
            }
        }
    });
}

/// Hands a downloaded update to Velopack's updater, which waits for this
/// process to exit, puts the new version in place and starts it. The caller
/// quits Rift straight after; the updater gives up if that takes over a
/// minute.
pub(crate) fn apply_on_exit() -> Result<(), String> {
    let manager = installed_manager(false)?;
    let pending = manager.get_update_pending_restart().ok_or("No update has been downloaded")?;
    let restart_args: Vec<String> = Vec::new();
    manager
        .wait_exit_then_apply_updates(&pending, false, true, restart_args)
        .map_err(|e| e.to_string())
}

/// The version downloaded and waiting for a restart, if any.
pub(crate) fn pending_version() -> Option<String> {
    let manager = installed_manager(false).ok()?;
    manager.get_update_pending_restart().map(|asset| asset.Version)
}
