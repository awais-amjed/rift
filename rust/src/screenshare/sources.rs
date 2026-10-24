//! What a share can capture, and which source each index in the list meant.
//!
//! Dart picks a source by its index in the list it was shown. The windows
//! behind that list move — one opens, one closes — so the index is read back
//! through the list as it was shown, to the source's own id, and never used
//! against a fresh list where it could land on somebody else's window.
use crate::api::screenshare::types::CaptureSource;
use livekit::webrtc::desktop_capturer::{
    DesktopCaptureSourceType, DesktopCapturer, DesktopCapturerOptions,
};
use std::sync::Mutex;

/// One entry of a list Dart was shown.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Listed {
    pub id: u64,
    pub title: String,
    /// Not in the capturer's list, because there is nothing on screen to
    /// capture until the user opens it again.
    pub minimised: bool,
}

// The last list shown of each kind, in index order.
static SCREENS: Mutex<Vec<Listed>> = Mutex::new(Vec::new());
static WINDOWS: Mutex<Vec<Listed>> = Mutex::new(Vec::new());

fn shown(source_type: DesktopCaptureSourceType) -> &'static Mutex<Vec<Listed>> {
    if source_type == DesktopCaptureSourceType::Screen {
        &SCREENS
    } else {
        &WINDOWS
    }
}

/// A capturer's options for `source_type`. Every capturer of a kind is made
/// here, since on Windows a screen's id depends on how it is captured, and a
/// list and its share must agree.
///
/// Windows Graphics Capture draws a yellow border round a captured screen,
/// which libwebrtc turns off where Windows allows it: from build 20348, in
/// practice Windows 11. On Windows 10 a screen is captured with DXGI desktop
/// duplication instead, which draws none (asked for Oct 24 2026). A window
/// keeps Windows Graphics Capture and its border there: the only borderless
/// way to capture one is GDI, which shows most games black.
pub(crate) fn options(source_type: DesktopCaptureSourceType) -> DesktopCapturerOptions {
    #[allow(unused_mut)]
    let mut options = DesktopCapturerOptions::new(source_type);
    #[cfg(target_os = "windows")]
    if source_type == DesktopCaptureSourceType::Screen {
        options.set_wgc_screen_capturer(capture_border_optional());
    }
    options
}

/// Whether Windows lets an app capture without the yellow border, asked of
/// the API itself rather than read from a build number.
#[cfg(target_os = "windows")]
fn capture_border_optional() -> bool {
    use std::sync::OnceLock;
    use windows::core::h;
    use windows::Foundation::Metadata::ApiInformation;
    static OPTIONAL: OnceLock<bool> = OnceLock::new();
    *OPTIONAL.get_or_init(|| {
        let optional = ApiInformation::IsPropertyPresent(
            h!("Windows.Graphics.Capture.GraphicsCaptureSession"),
            h!("IsBorderRequired"),
        )
        .unwrap_or(false);
        log::info!(
            "capture: screens with {}",
            if optional {
                "Windows Graphics Capture"
            } else {
                "DXGI, which draws no border"
            }
        );
        optional
    })
}

pub(crate) fn source_type(capture_full_screen: bool) -> DesktopCaptureSourceType {
    if capture_full_screen {
        DesktopCaptureSourceType::Screen
    } else {
        DesktopCaptureSourceType::Window
    }
}

/// The source at `index` in the last list shown, if there was one.
pub(crate) fn listed(source_type: DesktopCaptureSourceType, index: u32) -> Option<Listed> {
    shown(source_type)
        .lock()
        .unwrap()
        .get(index as usize)
        .cloned()
}

/// Screens or windows, in the order their indexes refer to. On Windows and
/// X11 each window carries its process so audio can follow the picked window
/// (X11 its app too), and on Windows minimised windows are listed as well.
pub(crate) fn list(capture_full_screen: bool) -> Vec<CaptureSource> {
    let source_type = source_type(capture_full_screen);
    let found = match DesktopCapturer::new(options(source_type)) {
        Some(capturer) => capturer
            .get_source_list()
            .iter()
            .map(|source| (source.id(), source.title()))
            .collect(),
        None => {
            log::warn!("capture: could not create a desktop capturer to list sources");
            Vec::new()
        }
    };
    let listed = if capture_full_screen {
        with_minimised(found, Vec::new())
    } else {
        with_minimised(found, minimised_windows())
    };
    log::info!("capture: {} sources", listed.len());

    let owners = (!capture_full_screen).then(Owners::open).flatten();
    let sources = listed
        .iter()
        .enumerate()
        .map(|(index, source)| {
            let (pid, app_id) = owners
                .as_ref()
                .map(|owners| owners.of(source.id))
                .unwrap_or_default();
            CaptureSource {
                index: index as u32,
                title: source.title.clone(),
                audio_source_pid: pid,
                app_id,
                minimised: source.minimised,
            }
        })
        .collect();
    *shown(source_type).lock().unwrap() = listed;
    sources
}

#[cfg(target_os = "windows")]
use super::window_win::list_minimised as minimised_windows;

/// Elsewhere a minimised window is the desktop's to offer (the Wayland
/// portal), or not offered at all (X11).
#[cfg(not(target_os = "windows"))]
fn minimised_windows() -> Vec<(u64, String)> {
    Vec::new()
}

/// Who each window belongs to: its process, and on X11 its app.
struct Owners {
    #[cfg(target_os = "linux")]
    x11: super::window_x11::Windows,
}

impl Owners {
    #[cfg(target_os = "windows")]
    fn open() -> Option<Self> {
        Some(Self {})
    }

    #[cfg(target_os = "linux")]
    fn open() -> Option<Self> {
        super::window_x11::Windows::open().map(|x11| Self { x11 })
    }

    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    fn open() -> Option<Self> {
        None
    }

    #[cfg(target_os = "windows")]
    fn of(&self, window: u64) -> (Option<u32>, String) {
        (super::window_win::pid(window), String::new())
    }

    #[cfg(target_os = "linux")]
    fn of(&self, window: u64) -> (Option<u32>, String) {
        (self.x11.pid(window), self.x11.app_id(window))
    }

    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    fn of(&self, _window: u64) -> (Option<u32>, String) {
        (None, String::new())
    }
}

/// The capturer's list followed by the minimised windows it left out. A
/// window that turns up in both — minimised or restored between the two
/// looks — is listed once, where the capturer put it.
fn with_minimised(capturable: Vec<(u64, String)>, minimised: Vec<(u64, String)>) -> Vec<Listed> {
    let mut listed: Vec<Listed> = capturable
        .into_iter()
        .map(|(id, title)| Listed {
            id,
            title,
            minimised: false,
        })
        .collect();
    for (id, title) in minimised {
        if listed.iter().all(|source| source.id != id) {
            listed.push(Listed {
                id,
                title,
                minimised: true,
            });
        }
    }
    listed
}

#[cfg(test)]
mod tests {
    use super::*;

    fn window(id: u64, title: &str) -> (u64, String) {
        (id, title.to_string())
    }

    #[test]
    fn minimised_windows_come_after_the_capturable_ones() {
        let listed = with_minimised(
            vec![window(1, "Browser"), window(2, "Editor")],
            vec![window(3, "Game")],
        );
        let shape: Vec<(u64, bool)> = listed.iter().map(|s| (s.id, s.minimised)).collect();
        assert_eq!(shape, vec![(1, false), (2, false), (3, true)]);
    }

    #[test]
    fn a_window_in_both_lists_is_listed_once_as_capturable() {
        let listed = with_minimised(vec![window(1, "Game")], vec![window(1, "Game")]);
        assert_eq!(
            listed,
            vec![Listed {
                id: 1,
                title: "Game".to_string(),
                minimised: false,
            }]
        );
    }
}
