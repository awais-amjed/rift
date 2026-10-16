//! Rift updating itself, through Velopack.
//!
//! A release is packed by `vpk` (`.github/workflows/release.yml`): on Windows
//! into an installer that puts Rift in the user's own folder, on Linux into an
//! AppImage. A copy installed either way finds newer releases, downloads one
//! (a download the person can pause, resume and cancel), and replaces itself
//! when Rift quits for it. A copy that was not installed by Velopack — a build
//! run from its folder, the old installer's, the `.tar.gz` — has nothing to
//! replace and reports that.
//!
//! Windows' install, update and uninstall hooks run in the runner, before
//! Flutter starts (`windows/runner/velopack_hooks.cpp`): Velopack gives each
//! a few seconds, and a whole engine would spend them starting.

mod signature;
mod source;
mod transfer;

use std::sync::{mpsc, Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use velopack::{UpdateCheck, UpdateInfo, UpdateManager, VelopackApp};

use crate::api::updater::{AvailableUpdate, UpdateDownloadProgress};
use crate::frb_generated::StreamSink;
use source::SignedSource;
use transfer::{Rate, Transfer};

/// The manager of the last check, with what it found: a download continues
/// from the same source, which knows where each package of the feed it read
/// is, and is paused, resumed and cancelled through its transfer.
struct Session {
    manager: UpdateManager,
    update: Option<UpdateInfo>,
    transfer: Arc<Transfer>,
}

static SESSION: Mutex<Option<Session>> = Mutex::new(None);

/// The last download's thread. A cancelled one can still be in a read the
/// network is slow to answer, holding Velopack's lock on the packages folder,
/// so the next download waits for it to end before starting.
static LAST_DOWNLOAD: Mutex<Option<JoinHandle<()>>> = Mutex::new(None);

/// How often a download says how far it is.
const PROGRESS_EVERY: Duration = Duration::from_millis(250);

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
    installed_manager(false, Arc::new(Transfer::new())).ok().map(|m| m.get_current_version_as_string())
}

fn installed_manager(include_prereleases: bool, transfer: Arc<Transfer>) -> Result<UpdateManager, String> {
    let source = SignedSource::new(include_prereleases, transfer);
    UpdateManager::new(source, None, None).map_err(|e| e.to_string())
}

/// Asks for the newest release, among pre-releases too when
/// `include_prereleases`. `None` when there is nothing newer.
pub(crate) fn check(include_prereleases: bool) -> Result<Option<AvailableUpdate>, String> {
    let transfer = Arc::new(Transfer::new());
    let manager = installed_manager(include_prereleases, transfer.clone())?;
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
    *SESSION.lock().unwrap() = Some(Session { manager, update: found, transfer });
    Ok(available)
}

/// Downloads what the last [check] found, sending how far it is to `sink`
/// every [PROGRESS_EVERY]; the stream ends when the update is ready, or with
/// an error ([transfer::CANCELLED] once cancelled).
pub(crate) fn download(sink: StreamSink<UpdateDownloadProgress>) {
    let Some((manager, update, transfer)) = SESSION
        .lock()
        .unwrap()
        .as_ref()
        .and_then(|s| s.update.clone().map(|u| (s.manager.clone(), u, s.transfer.clone())))
    else {
        let _ = sink.add_error("There is no update to download".to_string());
        return;
    };
    let mut last = LAST_DOWNLOAD.lock().unwrap();
    let previous = last.take();
    *last = Some(std::thread::spawn(move || {
        if let Some(previous) = previous {
            let _ = previous.join();
        }
        let packages: Vec<_> = if update.DeltasToTarget.is_empty() {
            vec![&update.TargetFullRelease]
        } else {
            update.DeltasToTarget.iter().collect()
        };
        transfer.plan(&packages);
        let (done_tx, done_rx) = mpsc::channel();
        std::thread::spawn(move || {
            let _ = done_tx.send(manager.download_updates(&update, None));
        });
        let mut rate = Rate::default();
        let result = loop {
            let (done, total, paused) = transfer.progress();
            let _ = sink.add(UpdateDownloadProgress {
                downloaded_bytes: u32::try_from(done).unwrap_or(u32::MAX),
                total_bytes: u32::try_from(total).unwrap_or(u32::MAX),
                bytes_per_second: u32::try_from(rate.sample(Instant::now(), done, paused)).unwrap_or(u32::MAX),
            });
            match done_rx.recv_timeout(PROGRESS_EVERY) {
                Ok(result) => break result.map_err(|e| e.to_string()),
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => break Err("The download stopped".to_string()),
            }
        };
        if let Err(e) = result {
            log::warn!("updater: download – {e}");
            let _ = sink.add_error(e);
        }
    }));
}

/// Holds the download where it is; [resume] carries it on from there.
pub(crate) fn pause() {
    with_transfer(Transfer::pause);
}

pub(crate) fn resume() {
    with_transfer(Transfer::resume);
}

/// Ends the download, and throws away what it brought.
pub(crate) fn cancel() {
    with_transfer(Transfer::cancel);
}

fn with_transfer(act: impl FnOnce(&Transfer)) {
    if let Some(session) = SESSION.lock().unwrap().as_ref() {
        act(&session.transfer);
    }
}

/// Hands a downloaded update to Velopack's updater, which waits for this
/// process to exit, puts the new version in place and starts it. The caller
/// quits Rift straight after; the updater gives up if that takes over a
/// minute.
pub(crate) fn apply_on_exit() -> Result<(), String> {
    let manager = installed_manager(false, Arc::new(Transfer::new()))?;
    let pending = manager.get_update_pending_restart().ok_or("No update has been downloaded")?;
    let restart_args: Vec<String> = Vec::new();
    manager
        .wait_exit_then_apply_updates(&pending, false, true, restart_args)
        .map_err(|e| e.to_string())
}

/// The version downloaded and waiting for a restart, if any.
pub(crate) fn pending_version() -> Option<String> {
    let manager = installed_manager(false, Arc::new(Transfer::new())).ok()?;
    manager.get_update_pending_restart().map(|asset| asset.Version)
}
