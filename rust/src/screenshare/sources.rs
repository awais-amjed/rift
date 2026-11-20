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

/// Whether a screen here is captured with Windows Graphics Capture: the rest are
/// duplicated with DXGI (see [`options`]), by Rift on the GPU where the share's
/// encoder takes textures, by libwebrtc otherwise.
#[cfg(target_os = "windows")]
pub(crate) fn screens_on_wgc() -> bool {
    capture_border_optional()
}

/// Whether Windows lets an app capture without the yellow border, asked of
/// the API itself rather than read from a build number.
///
/// `RIFT_SCREENS_ON_DXGI=1` answers no, so Windows 11 takes a screen the way
/// Windows 10 does: the DXGI duplication can then be tried on a computer that
/// is not on Windows 10 (`capture_wgc::dxgi`).
#[cfg(target_os = "windows")]
fn capture_border_optional() -> bool {
    use std::sync::OnceLock;
    use windows::core::h;
    use windows::Foundation::Metadata::ApiInformation;
    static OPTIONAL: OnceLock<bool> = OnceLock::new();
    *OPTIONAL.get_or_init(|| {
        let forced = std::env::var_os("RIFT_SCREENS_ON_DXGI").is_some_and(|v| v == "1");
        let optional = !forced
            && ApiInformation::IsPropertyPresent(
                h!("Windows.Graphics.Capture.GraphicsCaptureSession"),
                h!("IsBorderRequired"),
            )
            .unwrap_or(false);
        log::info!(
            "capture: screens with {}{}",
            if optional {
                "Windows Graphics Capture"
            } else {
                "DXGI, which draws no border"
            },
            if forced {
                " (RIFT_SCREENS_ON_DXGI)"
            } else {
                ""
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

/// The source a running share captures, as it was picked from a list Rift
/// showed. None while nothing is shared, or when the desktop's own picker
/// chose it (Wayland), when Rift cannot say which of its sources it is.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Sharing {
    pub kind: DesktopCaptureSourceType,
    pub id: u64,
}

static SHARING: Mutex<Option<Sharing>> = Mutex::new(None);

/// Noted by the share as it starts, switches and stops, for the picker to
/// mark the source being shared.
pub(crate) fn set_sharing(sharing: Option<Sharing>) {
    *SHARING.lock().unwrap() = sharing;
}

pub(crate) fn sharing() -> Option<Sharing> {
    *SHARING.lock().unwrap()
}

/// What a share of `index` in the last list of its kind would capture.
pub(crate) fn chosen(capture_full_screen: bool, index: Option<u32>) -> Option<Sharing> {
    let kind = source_type(capture_full_screen);
    let listed = listed(kind, index?)?;
    Some(Sharing {
        kind,
        id: listed.id,
    })
}

/// Whether a switch to `chosen` would change nothing. A source the desktop
/// picks is never known to be the same, so it is always switched to.
pub(crate) fn same_source(chosen: Option<Sharing>, sharing: Option<Sharing>) -> bool {
    chosen.is_some() && chosen == sharing
}

fn is_shared(sharing: Option<Sharing>, kind: DesktopCaptureSourceType, id: u64) -> bool {
    sharing == Some(Sharing { kind, id })
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
    let now = sharing();
    let listed = if capture_full_screen {
        let before: Vec<u64> = SCREENS.lock().unwrap().iter().map(|s| s.id).collect();
        with_minimised(with_shared_screen(found, now, &before), Vec::new())
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
                shared: is_shared(now, source_type, source.id),
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

/// The capturer's screens with the one being shared put back in its place.
///
/// On Windows 10 libwebrtc lists screens by duplicating each GPU's outputs,
/// and an output is duplicated once per process: while Rift's own duplication
/// holds the shared screen, that GPU's screens were left out, and with one
/// screen left the switch dialog took it as the only one and switched to it
/// (Nov 20 2026). A screen's id is its place among the display devices, so it
/// is the same in either list.
///
/// It goes back where `before`, the last list of screens shown, had it: the
/// capturer lists screens by GPU, not by id, and the dialog names a screen
/// and keeps its pick by place. Put back by id, the shared screen was
/// "Screen 1" when the share started and "Screen 2" in the switch, and the
/// pick landed on the other screen. Never shown, it goes in by id.
fn with_shared_screen(
    mut found: Vec<(u64, String)>,
    sharing: Option<Sharing>,
    before: &[u64],
) -> Vec<(u64, String)> {
    let Some(Sharing {
        kind: DesktopCaptureSourceType::Screen,
        id,
    }) = sharing
    else {
        return found;
    };
    if found.iter().all(|(listed, _)| *listed != id) {
        let at = match before.iter().position(|shown| *shown == id) {
            // Before the first screen that came after it last time.
            Some(place) => found
                .iter()
                .position(|(listed, _)| before[place + 1..].contains(listed))
                .unwrap_or(found.len()),
            None => found.partition_point(|(listed, _)| *listed < id),
        };
        found.insert(at, (id, String::new()));
    }
    found
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

    fn sharing(kind: DesktopCaptureSourceType, id: u64) -> Option<Sharing> {
        Some(Sharing { kind, id })
    }

    #[test]
    fn only_the_shared_source_of_its_kind_is_marked() {
        let now = sharing(DesktopCaptureSourceType::Window, 20);
        assert!(is_shared(now, DesktopCaptureSourceType::Window, 20));
        assert!(!is_shared(now, DesktopCaptureSourceType::Window, 10));
        assert!(!is_shared(now, DesktopCaptureSourceType::Screen, 20));
        assert!(!is_shared(None, DesktopCaptureSourceType::Window, 20));
    }

    #[test]
    fn the_source_already_shared_is_no_switch() {
        let screen = sharing(DesktopCaptureSourceType::Screen, 5);
        assert!(same_source(screen, screen));
        assert!(!same_source(
            sharing(DesktopCaptureSourceType::Window, 5),
            screen
        ));
        assert!(!same_source(sharing(DesktopCaptureSourceType::Screen, 6), screen));
    }

    #[test]
    fn a_source_the_desktop_picks_is_never_the_one_shared() {
        // Under Wayland nothing is chosen from Rift's list, on either side.
        assert!(!same_source(None, None));
        assert!(!same_source(None, sharing(DesktopCaptureSourceType::Screen, 5)));
    }

    #[test]
    fn a_shared_screen_the_capturer_left_out_is_listed_in_its_place() {
        // Windows 10, Nov 20 2026: Rift's own duplication held screen 0, and
        // libwebrtc's list had only screen 1.
        let now = sharing(DesktopCaptureSourceType::Screen, 0);
        assert_eq!(
            with_shared_screen(vec![window(1, "")], now, &[]),
            vec![window(0, ""), window(1, "")]
        );
        let now = sharing(DesktopCaptureSourceType::Screen, 2);
        assert_eq!(
            with_shared_screen(vec![window(0, ""), window(1, "")], now, &[]),
            vec![window(0, ""), window(1, ""), window(2, "")]
        );
    }

    #[test]
    fn a_listed_or_no_shared_screen_leaves_the_list_alone() {
        let found = vec![window(0, ""), window(1, "")];
        let screen = sharing(DesktopCaptureSourceType::Screen, 1);
        assert_eq!(with_shared_screen(found.clone(), screen, &[]), found);
        let window_shared = sharing(DesktopCaptureSourceType::Window, 7);
        assert_eq!(with_shared_screen(found.clone(), window_shared, &[]), found);
        assert_eq!(with_shared_screen(found.clone(), None, &[]), found);
    }

    #[test]
    fn a_shared_screen_goes_back_where_the_last_list_had_it() {
        // Windows 10, Nov 20 2026: libwebrtc lists screens by GPU, so the
        // Odyssey (display 1, on the NVIDIA card) came before the basic
        // screen (display 0). Put back by number it moved to second, and the
        // dialog's pick, kept by place, landed on the other screen.
        let now = sharing(DesktopCaptureSourceType::Screen, 1);
        assert_eq!(
            with_shared_screen(vec![window(0, "")], now, &[1, 0]),
            vec![window(1, ""), window(0, "")]
        );
        // A screen attached since keeps the capturer's place for it.
        assert_eq!(
            with_shared_screen(vec![window(0, ""), window(2, "")], now, &[1, 0]),
            vec![window(1, ""), window(0, ""), window(2, "")]
        );
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
