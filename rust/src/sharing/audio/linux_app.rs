//! Linux: which streams are one application's.
//!
//! An application picked for a share is shown as one of its streams, but an
//! application plays in as many streams as it likes, one after another or at
//! once: a player that opens a stream per track, a browser per tab, a sound
//! effect per effect, and some from a new process each time. Following that
//! one stream went silent as soon as the application opened its next — seen
//! Nov 16 2026 with a sound looped by `paplay`, and the same would happen at a
//! player's second track. So the picked stream names the program, and every
//! stream it plays is followed (`linux_all`).
use crate::api::screenshare::types::AudioSource;
use std::sync::Mutex;
use std::time::Duration;

/// The application a share follows.
#[derive(Clone, Debug)]
pub(super) struct App {
    /// The stream it was picked by, which is always its own.
    index: u32,
    pid: Option<u32>,
    binary: String,
    name: String,
    /// Whether `pid` is the picked process as this machine sees it, so a
    /// share can tell an application that quit from one that is quiet.
    watched: bool,
    /// How long the application may play nothing, its process gone or not
    /// watched, before the share ends. None for never.
    quiet_limit: Option<Duration>,
}

impl App {
    /// The application playing `picked`. `quiet_limit` is for a share that
    /// ends on its own (a sound share); a screen share passes none and keeps
    /// listening for as long as it lasts.
    pub(super) fn new(picked: &AudioSource, quiet_limit: Option<Duration>) -> Self {
        let binary = picked.binary.trim().to_string();
        let watched = picked
            .pid
            .is_some_and(|pid| runs(pid, &binary, process_name));
        Self {
            index: picked.index,
            pid: picked.pid,
            binary,
            name: picked.app_name.trim().to_string(),
            watched,
            quiet_limit,
        }
    }

    /// Whether `input` is one of this application's streams.
    pub(super) fn plays(&self, input: &AudioSource) -> bool {
        if input.index == self.index {
            return true;
        }
        // The program, not the process: a loop or a launcher plays each
        // sound from a process of its own. Two copies of one program both
        // playing are both heard.
        if !self.binary.is_empty() || !self.name.is_empty() {
            return input.binary.trim() == self.binary && input.app_name.trim() == self.name;
        }
        // Nothing to tell this program's streams from another's but where
        // they come from.
        self.pid.is_some() && input.pid == self.pid
    }

    /// Whether the application is gone, `quiet_for` after it last had a
    /// stream (zero while it has one): quiet for the limit, with the process
    /// picked no longer running. A player paused for an hour is still there.
    pub(super) fn ended(&self, quiet_for: Duration) -> bool {
        let running = self.watched
            && self
                .pid
                .is_some_and(|pid| std::path::Path::new(&format!("/proc/{pid}")).exists());
        !running && self.quiet_limit.is_some_and(|limit| quiet_for >= limit)
    }

    pub(super) fn describe(&self) -> String {
        let who = if self.name.is_empty() { &self.binary } else { &self.name };
        match self.pid {
            Some(pid) if self.watched => format!("{who} (process {pid})"),
            Some(pid) => format!("{who} (process {pid}, not watched)"),
            None => format!("{who} (no process)"),
        }
    }
}

/// The application `index` plays: from what is playing now, or else from what
/// the share dialog was shown. The stream picked there can end before the
/// share begins — the desktop's own picker alone takes longer than a short
/// sound — and its program is still the one wanted.
fn find(index: u32, playing: &[AudioSource], shown: &[AudioSource]) -> Option<AudioSource> {
    playing
        .iter()
        .chain(shown.iter().rev())
        .find(|input| input.index == index)
        .cloned()
}

/// Add `listed` to what was `shown`, newest kept, at most [`SHOWN_KEPT`].
fn merge(shown: &mut Vec<AudioSource>, listed: &[AudioSource]) {
    shown.retain(|old| !listed.iter().any(|new| new.index == old.index));
    shown.extend_from_slice(listed);
    let excess = shown.len().saturating_sub(SHOWN_KEPT);
    shown.drain(..excess);
}

/// What the share dialog has been shown, for [`picked`].
static SHOWN: Mutex<Vec<AudioSource>> = Mutex::new(Vec::new());

/// Note what the share dialog is being shown.
pub(super) fn remember(listed: &[AudioSource]) {
    merge(&mut SHOWN.lock().unwrap(), listed);
}

/// The stream `index` picked in the share dialog, playing or not.
pub(super) fn picked(index: u32) -> Option<AudioSource> {
    let playing = super::pulse::list_sink_inputs();
    find(index, &playing, &SHOWN.lock().unwrap())
}

/// How many streams the dialog was shown are remembered.
const SHOWN_KEPT: usize = 256;

/// Whether `pid` runs `binary` on this machine. A sandboxed application can
/// report its pid inside the sandbox, which here is some other process, or
/// none.
fn runs(pid: u32, binary: &str, comm: impl Fn(u32) -> Option<String>) -> bool {
    /// The most of its name the kernel keeps for a process.
    const KEPT: usize = 15;
    let Some(name) = comm(pid) else {
        return false;
    };
    let name = name.trim().to_lowercase();
    let binary = binary.to_lowercase();
    !name.is_empty() && (name == binary || (name.len() == KEPT && binary.starts_with(&name)))
}

/// What the kernel calls process `pid`, if there is one.
fn process_name(pid: u32) -> Option<String> {
    std::fs::read_to_string(format!("/proc/{pid}/comm")).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source(index: u32, pid: Option<u32>, binary: &str, name: &str) -> AudioSource {
        AudioSource {
            index,
            sink: 0,
            app_name: name.to_string(),
            binary: binary.to_string(),
            media_name: String::new(),
            app_id: String::new(),
            pid,
        }
    }

    fn app(picked: &AudioSource, watched: bool, quiet_limit: Option<Duration>) -> App {
        App {
            watched,
            ..App::new(picked, quiet_limit)
        }
    }

    #[test]
    fn a_new_stream_of_the_same_program_is_followed() {
        let app = app(&source(40, Some(900), "paplay", "paplay"), true, None);
        assert!(app.plays(&source(40, Some(900), "paplay", "paplay")));
        assert!(app.plays(&source(41, Some(900), "paplay", "paplay")));
        // The next sound of a loop is the next process.
        assert!(app.plays(&source(42, Some(901), "paplay", "paplay")));
    }

    #[test]
    fn another_program_is_not() {
        let app = app(&source(40, Some(900), "mpv", "mpv"), true, None);
        assert!(!app.plays(&source(41, Some(900), "mpv", "Other")));
        assert!(!app.plays(&source(42, Some(901), "vlc", "mpv")));
    }

    #[test]
    fn a_stream_naming_no_program_is_matched_by_its_process() {
        let app = app(&source(40, Some(900), "", ""), true, None);
        assert!(app.plays(&source(41, Some(900), "", "")));
        assert!(!app.plays(&source(42, Some(901), "", "")));
    }

    #[test]
    fn a_stream_naming_nothing_matches_only_itself() {
        let app = app(&source(40, None, "", ""), false, None);
        assert!(app.plays(&source(40, None, "", "")));
        assert!(!app.plays(&source(41, None, "", "")));
    }

    #[test]
    fn a_running_process_keeps_a_quiet_share_up() {
        let limit = Some(Duration::from_secs(10));
        let me = std::process::id();
        let app = app(&source(40, Some(me), "x", "x"), true, limit);
        assert!(!app.ended(Duration::from_secs(3600)));
    }

    #[test]
    fn once_its_process_is_gone_a_share_ends_after_the_quiet_limit() {
        let limit = Some(Duration::from_secs(10));
        // No process has that pid.
        let app = app(&source(40, Some(u32::MAX), "x", "x"), true, limit);
        assert!(!app.ended(Duration::from_secs(9)));
        assert!(app.ended(Duration::from_secs(10)));
    }

    #[test]
    fn an_unwatched_application_ends_after_the_quiet_limit_if_there_is_one() {
        let limit = Some(Duration::from_secs(10));
        let app = app(&source(40, Some(std::process::id()), "x", "x"), false, limit);
        assert!(!app.ended(Duration::from_secs(9)));
        assert!(app.ended(Duration::from_secs(10)));
        let forever = super::App {
            quiet_limit: None,
            ..app
        };
        assert!(!forever.ended(Duration::from_secs(3600)));
    }

    #[test]
    fn a_pid_is_watched_only_when_it_runs_the_program() {
        let comm = |pid: u32| match pid {
            7 => Some("firefox".to_string()),
            8 => Some("kthreadd".to_string()),
            9 => Some("chromium-browse".to_string()),
            _ => None,
        };
        assert!(runs(7, "firefox", comm));
        assert!(runs(7, "Firefox", comm));
        assert!(!runs(8, "firefox", comm));
        assert!(!runs(10, "firefox", comm));
        // The kernel keeps 15 characters of a process's name.
        assert!(runs(9, "chromium-browser", comm));
        assert!(!runs(7, "", comm));
    }

    #[test]
    fn a_picked_stream_is_found_playing_or_as_shown() {
        let now = [source(41, Some(1), "paplay", "rift-talk")];
        let shown = [
            source(40, Some(2), "paplay", "rift-talk"),
            source(41, Some(1), "old", "old"),
        ];
        assert_eq!(find(41, &now, &shown).unwrap().binary, "paplay");
        // Ended between the dialog and the share.
        assert_eq!(find(40, &now, &shown).unwrap().pid, Some(2));
        assert!(find(39, &now, &shown).is_none());
    }

    #[test]
    fn what_was_shown_keeps_the_newest_of_each_stream_and_no_more_than_its_limit() {
        let mut shown = vec![source(1, None, "a", "a"), source(2, None, "b", "b")];
        merge(&mut shown, &[source(2, None, "c", "c"), source(3, None, "d", "d")]);
        let names: Vec<_> = shown.iter().map(|s| (s.index, s.binary.as_str())).collect();
        assert_eq!(names, [(1, "a"), (2, "c"), (3, "d")]);
        let many: Vec<_> = (10..10 + SHOWN_KEPT as u32 + 5)
            .map(|i| source(i, None, "x", "x"))
            .collect();
        merge(&mut shown, &many);
        assert_eq!(shown.len(), SHOWN_KEPT);
        assert_eq!(shown.last().unwrap().index, 10 + SHOWN_KEPT as u32 + 4);
    }
}
