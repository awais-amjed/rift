//! Where `log::` output goes. Called once from the bridge's init hook.
//!
//! flutter_rust_bridge installs a logger for Android, iOS and macOS but has
//! none for Linux or Windows, where it would otherwise be silently dropped.
//!
//! Every line is also kept in a file, so that someone whose share stopped or
//! whose app closed can send what happened (`api::logs`). Rust owns the file
//! rather than Dart, and writes each line as it comes: a process that dies in
//! native code takes nothing it had buffered with it, and the last lines
//! before a crash are the ones worth having. Until Dart says where the file
//! goes, lines wait in memory.
use std::collections::VecDeque;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

/// Session files kept in the folder, this one included. A crash is reported
/// from the session after it, so the one before must survive the restart.
const KEPT_FILES: usize = 10;
/// A file this big is moved aside and a fresh one started, so a long session
/// keeps its last few megabytes rather than growing without end.
const ROTATE_BYTES: u64 = 8 * 1024 * 1024;
/// Lines held before the file is opened.
const EARLY_LINES: usize = 2000;

struct Sink {
    file: Option<File>,
    path: Option<PathBuf>,
    written: u64,
    early: VecDeque<String>,
}

static SINK: Mutex<Sink> = Mutex::new(Sink {
    file: None,
    path: None,
    written: 0,
    early: VecDeque::new(),
});

pub fn init() {
    flutter_rust_bridge::setup_default_user_utils();
    #[cfg(any(target_os = "linux", target_os = "windows"))]
    {
        let stderr =
            env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
                .build();
        let level = stderr.filter();
        if log::set_boxed_logger(Box::new(Tee { stderr })).is_ok() {
            log::set_max_level(level);
        }
    }
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        write_line("PANIC", "rust", &info.to_string());
        previous(info);
    }));
}

/// Sends each record to stderr as before, and the same records to the file.
#[cfg(any(target_os = "linux", target_os = "windows"))]
struct Tee {
    stderr: env_logger::Logger,
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
impl log::Log for Tee {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        log::Log::enabled(&self.stderr, metadata)
    }

    fn log(&self, record: &log::Record) {
        if !self.stderr.matches(record) {
            return;
        }
        log::Log::log(&self.stderr, record);
        write_line(
            record.level().as_str(),
            record.target(),
            &record.args().to_string(),
        );
    }

    fn flush(&self) {
        log::Log::flush(&self.stderr);
    }
}

/// Opens this session's file in `dir`, writes what was logged before it, and
/// deletes the oldest files past [KEPT_FILES]. Returns the file's path.
pub(crate) fn start(dir: &Path) -> Result<PathBuf, String> {
    fs::create_dir_all(dir).map_err(|e| format!("Could not make {}: {e}", dir.display()))?;
    let mut sink = SINK.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(path) = &sink.path {
        return Ok(path.clone());
    }
    let (secs, _) = now();
    let name = format!("rift-{}-{}.log", file_stamp(secs), std::process::id());
    let path = dir.join(name);
    let mut file = open(&path)?;
    let mut written = 0;
    for line in sink.early.drain(..) {
        written += line.len() as u64;
        let _ = file.write_all(line.as_bytes());
    }
    sink.file = Some(file);
    sink.path = Some(path.clone());
    sink.written = written;
    drop(sink);
    prune(dir);
    Ok(path)
}

/// Writes one line, timestamped and with anything secret taken out.
pub(crate) fn write_line(level: &str, target: &str, message: &str) {
    let (secs, millis) = now();
    let line = format!(
        "{}.{millis:03}Z {level:<5} {target}: {}\n",
        line_stamp(secs),
        redact(message)
    );
    let mut sink = SINK.lock().unwrap_or_else(|e| e.into_inner());
    if sink.file.is_none() {
        if sink.early.len() == EARLY_LINES {
            sink.early.pop_front();
        }
        sink.early.push_back(line);
        return;
    }
    if sink.written + line.len() as u64 > ROTATE_BYTES {
        rotate(&mut sink);
    }
    sink.written += line.len() as u64;
    if let Some(file) = sink.file.as_mut() {
        let _ = file.write_all(line.as_bytes());
    }
}

fn open(path: &Path) -> Result<File, String> {
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(|e| format!("Could not open {}: {e}", path.display()))
}

/// Moves the full file to `<name>.old.log`, replacing an older one, and starts
/// the session's file again.
fn rotate(sink: &mut Sink) {
    let Some(path) = sink.path.clone() else {
        return;
    };
    sink.file = None;
    let _ = fs::rename(&path, path.with_extension("old.log"));
    sink.file = open(&path).ok();
    sink.written = 0;
}

/// Deletes all but the newest [KEPT_FILES] of Rift's logs in `dir`.
fn prune(dir: &Path) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut logs: Vec<(SystemTime, PathBuf)> = entries
        .flatten()
        .filter(|e| {
            let name = e.file_name();
            let name = name.to_string_lossy();
            name.starts_with("rift-") && name.ends_with(".log")
        })
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .collect();
    logs.sort_by(|a, b| b.0.cmp(&a.0));
    for (_, path) in logs.into_iter().skip(KEPT_FILES) {
        let _ = fs::remove_file(path);
    }
}

fn now() -> (u64, u32) {
    let since = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    (since.as_secs(), since.subsec_millis())
}

/// `2026-10-10 14:03:22`, UTC.
fn line_stamp(secs: u64) -> String {
    let (y, mo, d, h, mi, s) = civil(secs);
    format!("{y:04}-{mo:02}-{d:02} {h:02}:{mi:02}:{s:02}")
}

/// `20261010-140322`, UTC: sorts by time, and has no character a file name
/// cannot hold on Windows.
fn file_stamp(secs: u64) -> String {
    let (y, mo, d, h, mi, s) = civil(secs);
    format!("{y:04}{mo:02}{d:02}-{h:02}{mi:02}{s:02}")
}

/// Seconds since 1970 as a UTC date and time (Howard Hinnant's days-to-civil).
fn civil(secs: u64) -> (i64, u32, u32, u32, u32, u32) {
    let days = (secs / 86_400) as i64;
    let rest = secs % 86_400;
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let year = yoe + era * 400 + i64::from(month <= 2);
    (
        year,
        month,
        day,
        (rest / 3600) as u32,
        (rest % 3600 / 60) as u32,
        (rest % 60) as u32,
    )
}

/// Parameter names whose value is never written: a LiveKit URL carries its
/// access token, a Realtime URL its key, and an error can quote either.
const SECRET_NAMES: [&str; 8] = [
    "access_token",
    "refresh_token",
    "apikey",
    "api_key",
    "token",
    "password",
    "secret",
    "signature",
];

/// `message` with token-shaped values replaced by `[redacted]`: anything that
/// looks like a JWT, the word after `Bearer`, and the value of a parameter in
/// [SECRET_NAMES] (`name=value`, `name: value` or JSON's `"name":"value"`).
///
/// A safety net, not a licence: a log line should still never be written with
/// a secret in it. This catches the ones a library or an error message adds.
pub(crate) fn redact(message: &str) -> String {
    let bytes = message.as_bytes();
    let mut out = String::with_capacity(message.len());
    let mut i = 0;
    while i < bytes.len() {
        if let Some(end) = jwt_at(bytes, i) {
            out.push_str("[redacted]");
            i = end;
            continue;
        }
        if starts_word(bytes, i, b"bearer ") {
            out.push_str(&message[i..i + 7]);
            let end = value_end(bytes, i + 7);
            if end > i + 7 {
                out.push_str("[redacted]");
            }
            i = end;
            continue;
        }
        if let Some(value_start) = secret_name_at(bytes, i) {
            out.push_str(&message[i..value_start]);
            let end = value_end(bytes, value_start);
            if end > value_start {
                out.push_str("[redacted]");
            }
            i = end;
            continue;
        }
        let ch = message[i..].chars().next().unwrap_or('\u{fffd}');
        out.push(ch);
        i += ch.len_utf8().max(1);
    }
    out
}

fn is_word(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

fn is_b64url(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_' || b == b'-'
}

/// Whether `word` (lowercase) starts at `i`, ignoring case, with no word
/// character just before it.
fn starts_word(bytes: &[u8], i: usize, word: &[u8]) -> bool {
    (i == 0 || !is_word(bytes[i - 1]))
        && bytes.len() >= i + word.len()
        && bytes[i..i + word.len()].eq_ignore_ascii_case(word)
}

/// The end of a JWT starting at `i`: `eyJ`, then three base64url parts.
fn jwt_at(bytes: &[u8], i: usize) -> Option<usize> {
    if !bytes[i..].starts_with(b"eyJ") || (i > 0 && is_b64url(bytes[i - 1])) {
        return None;
    }
    let mut j = i;
    for part in 0..3 {
        let start = j;
        while j < bytes.len() && is_b64url(bytes[j]) {
            j += 1;
        }
        if j == start && part < 2 {
            return None;
        }
        if part < 2 {
            if j >= bytes.len() || bytes[j] != b'.' {
                return None;
            }
            j += 1;
        }
    }
    Some(j)
}

/// A name from [SECRET_NAMES] at `i`, followed by `=`, `:` or `":`, and the
/// spaces and quote after it. Returns where the value starts.
fn secret_name_at(bytes: &[u8], i: usize) -> Option<usize> {
    let name = SECRET_NAMES
        .iter()
        .find(|name| starts_word(bytes, i, name.as_bytes()))?;
    let mut j = i + name.len();
    if j < bytes.len() && bytes[j] == b'"' {
        j += 1;
    }
    if j >= bytes.len() || (bytes[j] != b'=' && bytes[j] != b':') {
        return None;
    }
    j += 1;
    while j < bytes.len() && bytes[j] == b' ' {
        j += 1;
    }
    if j < bytes.len() && (bytes[j] == b'"' || bytes[j] == b'\'') {
        j += 1;
    }
    Some(j)
}

/// Where a value starting at `i` ends: at a separator, a space or a quote.
fn value_end(bytes: &[u8], i: usize) -> usize {
    let mut j = i;
    while j < bytes.len()
        && !matches!(
            bytes[j],
            b'&' | b' ' | b'"' | b'\'' | b',' | b';' | b')' | b'}' | b'\n'
        )
    {
        j += 1;
    }
    j
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn civil_dates() {
        assert_eq!(civil(0), (1970, 1, 1, 0, 0, 0));
        // 2026-10-10 14:03:22 UTC.
        assert_eq!(civil(1_791_641_002), (2026, 10, 10, 14, 3, 22));
        // A leap day.
        assert_eq!(civil(1_709_164_800), (2024, 2, 29, 0, 0, 0));
        assert_eq!(file_stamp(1_791_641_002), "20261010-140322");
    }

    #[test]
    fn redacts_tokens() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl";
        assert_eq!(
            redact(&format!(
                "wss://lk.example/rtc?access_token={jwt}&auto_subscribe=1"
            )),
            "wss://lk.example/rtc?access_token=[redacted]&auto_subscribe=1"
        );
        assert_eq!(redact(&format!("got {jwt} back")), "got [redacted] back");
        assert_eq!(
            redact("Authorization: Bearer abc.def"),
            "Authorization: Bearer [redacted]"
        );
        assert_eq!(
            redact(r#"{"access_token":"abc","user":"x"}"#),
            r#"{"access_token":"[redacted]","user":"x"}"#
        );
        assert_eq!(
            redact("ws://h/realtime/v1/websocket?apikey=sb_publishable_x&vsn=1.0.0"),
            "ws://h/realtime/v1/websocket?apikey=[redacted]&vsn=1.0.0"
        );
        assert_eq!(redact("password: hunter2"), "password: [redacted]");
    }

    #[test]
    fn prune_keeps_the_newest_logs_and_nothing_else() {
        let dir = std::env::temp_dir().join(format!("rift-log-prune-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let start = SystemTime::now() - std::time::Duration::from_secs(3600);
        for n in 0..KEPT_FILES + 3 {
            let file = File::create(dir.join(format!("rift-{n:02}.log"))).unwrap();
            file.set_modified(start + std::time::Duration::from_secs(n as u64))
                .unwrap();
        }
        File::create(dir.join("notes.txt")).unwrap();
        prune(&dir);
        let mut left: Vec<String> = fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        left.sort();
        assert_eq!(left.len(), KEPT_FILES + 1);
        assert_eq!(left[0], "notes.txt");
        assert_eq!(left[1], "rift-03.log");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn leaves_ordinary_lines_alone() {
        for line in [
            "capture: source Counter-Strike 2",
            "[LiveKit] no channel key for 42 — refusing to join",
            "moved the call from key v3 to v4",
            "tokens: 3 left",
            "the token expired",
            "eyJ alone is not a token",
        ] {
            assert_eq!(redact(line), line);
        }
    }
}
