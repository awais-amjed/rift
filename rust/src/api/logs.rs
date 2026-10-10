//! The app's log file: where it goes, and Dart's lines into it. The file
//! itself is `crate::logging`'s, which Rust's own `log::` lines reach first.

/// Starts writing this session's log in `dir`, with what was logged before,
/// and keeps only the newest few sessions there. Returns the file's path.
/// Calling it again returns the same path.
pub fn start_log_file(dir: String) -> Result<String, String> {
    crate::logging::start(std::path::Path::new(&dir)).map(|p| p.display().to_string())
}

/// Writes one of Dart's lines to the log, from `source` (`dart`, `flutter`).
#[flutter_rust_bridge::frb(sync)]
pub fn write_log_line(source: String, line: String) {
    let level = if source == "flutter" { "ERROR" } else { "INFO" };
    crate::logging::write_line(level, &source, &line);
}
