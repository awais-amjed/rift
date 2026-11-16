//! Linux: which streams are one application's.
//!
//! An application picked for a share is shown as one of its streams, but an
//! application plays in as many streams as it likes, one after another or at
//! once: a player that opens a stream per track, a browser per tab, a sound
//! effect per effect, and some from a new process each time. Following that
//! one stream went silent as soon as the application opened its next — seen
//! Nov 16 2026 with a sound looped by `paplay`, and the same would happen at a
//! player's second track. So the picked stream names the program, and every
//! stream it plays is followed (`linux_all`). A program can be picked while it
//! plays nothing ([`quiet`]): a paused player closes its stream, and the share
//! waits for its next.
use crate::api::screenshare::types::AudioSource;
use std::time::Duration;

/// The application a share follows.
#[derive(Clone, Debug)]
pub(super) struct App {
    /// The stream it was picked by, which is always its own; none when it
    /// was picked while playing nothing.
    index: Option<u32>,
    pid: Option<u32>,
    binary: String,
    name: String,
    /// Whether `pid` is the picked process as this machine sees it, so a
    /// share can tell an application that quit from one that is quiet.
    watched: bool,
    /// How long the application may play nothing, with no process running
    /// it, before the share ends. None for never.
    quiet_limit: Option<Duration>,
}

impl App {
    /// The application playing `picked`. `quiet_limit` is for a share that
    /// ends on its own (a sound share); a screen share passes none and keeps
    /// listening for as long as it lasts.
    pub(super) fn new(picked: &AudioSource, quiet_limit: Option<Duration>) -> Self {
        let binary = picked.binary.trim().to_string();
        let watched = picked.pid.is_some_and(|pid| runs(pid, &binary));
        Self {
            index: picked.playing.then_some(picked.index),
            pid: picked.pid,
            binary,
            name: picked.app_name.trim().to_string(),
            watched,
            quiet_limit,
        }
    }

    /// Whether `input` is one of this application's streams.
    pub(super) fn plays(&self, input: &AudioSource) -> bool {
        if self.index == Some(input.index) {
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
    /// picked no longer running and no other running the program. A player
    /// paused for an hour is still there.
    pub(super) fn ended(&self, quiet_for: Duration) -> bool {
        self.quiet_limit.is_some_and(|limit| quiet_for >= limit) && !self.running()
    }

    fn running(&self) -> bool {
        let picked = self.watched
            && self
                .pid
                .is_some_and(|pid| std::path::Path::new(&format!("/proc/{pid}")).exists());
        picked || program_runs(&self.binary)
    }

    pub(super) fn describe(&self) -> String {
        let who = if self.name.is_empty() {
            &self.binary
        } else {
            &self.name
        };
        if self.index.is_none() {
            return format!("{who} (picked while playing nothing)");
        }
        match self.pid {
            Some(pid) if self.watched => format!("{who} (process {pid})"),
            Some(pid) => format!("{who} (process {pid}, not watched)"),
            None => format!("{who} (no process)"),
        }
    }
}

/// The programs in `known` that are running but not playing, to list after
/// what is playing: a paused player closes its stream, and a share of it
/// should not have to wait for it to play again. `runs` says whether a
/// program by that binary is running. Each is listed once, as not playing.
pub(super) fn quiet(
    playing: &[AudioSource],
    known: &[AudioSource],
    runs: impl Fn(&str) -> bool,
) -> Vec<AudioSource> {
    let same = |a: &AudioSource, b: &AudioSource| {
        a.binary.trim() == b.binary.trim() && a.app_name.trim() == b.app_name.trim()
    };
    let mut quiet: Vec<AudioSource> = Vec::new();
    for program in known {
        if program.binary.trim().is_empty()
            || playing.iter().any(|p| same(p, program))
            || quiet.iter().any(|q| same(q, program))
            || !runs(program.binary.trim())
        {
            continue;
        }
        quiet.push(AudioSource {
            index: 0,
            sink: 0,
            app_name: program.app_name.clone(),
            binary: program.binary.clone(),
            media_name: String::new(),
            app_id: program.app_id.clone(),
            pid: None,
            playing: false,
        });
    }
    quiet
}

/// Whether some process on this machine runs `binary`.
pub(super) fn program_runs(binary: &str) -> bool {
    if binary.trim().is_empty() {
        return false;
    }
    let Ok(entries) = std::fs::read_dir("/proc") else {
        return false;
    };
    entries
        .flatten()
        .filter_map(|entry| entry.file_name().to_str()?.parse::<u32>().ok())
        .any(|pid| runs(pid, binary))
}

/// Whether `pid` runs `binary` on this machine. A sandboxed application can
/// report its pid inside the sandbox, which here is some other process, or
/// none.
fn runs(pid: u32, binary: &str) -> bool {
    is_program(
        binary,
        process_name(pid).as_deref(),
        executable(pid).as_deref(),
    )
}

/// Whether a process the kernel calls `comm`, running the executable file
/// `exe`, is `binary` as PulseAudio names it: by the executable, which the
/// kernel's name need not be (`python3` runs `python3.14`). The executable
/// of another user's process cannot be read, and its name has to do.
fn is_program(binary: &str, comm: Option<&str>, exe: Option<&str>) -> bool {
    /// The most of its name the kernel keeps for a process.
    const KEPT: usize = 15;
    let binary = binary.trim().to_lowercase();
    if binary.is_empty() {
        return false;
    }
    if exe.is_some_and(|exe| exe.trim().to_lowercase() == binary) {
        return true;
    }
    let Some(name) = comm.map(|name| name.trim().to_lowercase()) else {
        return false;
    };
    !name.is_empty() && (name == binary || (name.len() == KEPT && binary.starts_with(&name)))
}

/// The file name of the executable process `pid` runs, if it can be read.
fn executable(pid: u32) -> Option<String> {
    let path = std::fs::read_link(format!("/proc/{pid}/exe")).ok()?;
    Some(path.file_name()?.to_string_lossy().into_owned())
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
            playing: true,
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
        let app = app(
            &source(40, Some(std::process::id()), "x", "x"),
            false,
            limit,
        );
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
        assert!(is_program("firefox", Some("firefox"), None));
        assert!(is_program("Firefox", Some("firefox"), None));
        assert!(!is_program("firefox", Some("kthreadd"), None));
        assert!(!is_program("firefox", None, None));
        // The kernel keeps 15 characters of a process's name.
        assert!(is_program(
            "chromium-browser",
            Some("chromium-browse"),
            None
        ));
        assert!(!is_program("", Some("firefox"), None));
    }

    #[test]
    fn a_program_picked_while_quiet_follows_any_stream_of_it() {
        let quiet = AudioSource {
            playing: false,
            ..source(0, None, "chrome", "Google Chrome")
        };
        let app = app(&quiet, false, None);
        assert!(app.plays(&source(57, Some(4000), "chrome", "Google Chrome")));
        // Its index is no stream's.
        assert!(!app.plays(&source(0, Some(1), "paplay", "paplay")));
    }

    #[test]
    fn a_quiet_share_stays_up_while_the_program_runs_in_another_process() {
        let limit = Some(Duration::from_secs(10));
        let own = process_name(std::process::id()).unwrap();
        let app = app(&source(40, Some(u32::MAX), own.trim(), "x"), true, limit);
        assert!(!app.ended(Duration::from_secs(3600)));
    }

    #[test]
    fn running_programs_known_but_not_playing_are_listed_once_as_quiet() {
        let playing = [source(41, Some(1), "paplay", "rift-talk")];
        let known = [
            source(3, Some(9), "chrome", "Google Chrome"),
            source(4, Some(8), "chrome", "Google Chrome"),
            source(5, Some(7), "paplay", "rift-talk"),
            source(6, Some(6), "mpv", "mpv"),
            source(7, Some(5), "", "Nameless"),
        ];
        let listed = quiet(&playing, &known, |binary| binary != "mpv");
        assert_eq!(listed.len(), 1);
        let chrome = &listed[0];
        assert_eq!(
            (chrome.binary.as_str(), chrome.app_name.as_str()),
            ("chrome", "Google Chrome")
        );
        assert!(!chrome.playing);
        assert_eq!(chrome.pid, None);
        assert!(chrome.media_name.is_empty());
    }

    #[test]
    fn a_process_runs_a_program_by_its_executable_when_its_name_differs() {
        // PulseAudio names the executable; the kernel, what it was run as.
        assert!(is_program(
            "python3.14",
            Some("python3"),
            Some("python3.14")
        ));
        assert!(is_program("chrome", Some("chrome"), None));
        assert!(!is_program("python3.14", Some("python3"), None));
        assert!(!is_program("mpv", Some("python3"), Some("python3.14")));
        assert!(!is_program("", Some(""), Some("")));
    }

    #[test]
    fn a_program_runs_when_any_process_has_its_name() {
        let own = process_name(std::process::id()).unwrap();
        assert!(program_runs(own.trim()));
        assert!(!program_runs("no-such-program-here"));
        assert!(!program_runs(""));
    }
}
