//! What a bug report needs that nothing else in the app logs: the GPUs and
//! their drivers, and how a session that crashed in native code ended.
//!
//! A crash in native code (a GPU driver, FFmpeg, libwebrtc) ends the process
//! before Rift can write a word, so the session's log just stops, and finding
//! the module it died in meant asking the person to dig it out themselves (a
//! friend's H264 share, Oct 23 2026). What tells a driver's crash from Rift's
//! is now in the log on each platform that has native code:
//!
//! - **Windows** records each crash in its Application log (`Application
//!   Error`, event 1000) with the module, the exception and the offset. Any
//!   user may read it, so each session writes the last few into its own log as
//!   it starts, and a bug report, sent from the session after the crash,
//!   carries them ([windows]). That names only the innermost module, so a
//!   last-chance filter also writes the whole stack as it crashes
//!   ([crash_filter]).
//! - **Linux and Android** catch the signal and write the crash into the
//!   crashing session's own log, then pass it on ([crash_signal]). Android
//!   also keeps why each run ended, which Dart reads (`AppExitReasons`).
//!
//! Parsing is here, as plain functions; reading is per OS.
#[cfg(target_os = "windows")]
mod crash_filter;
#[cfg(any(target_os = "linux", target_os = "android", target_os = "windows"))]
mod crash_line;
#[cfg(any(target_os = "linux", target_os = "android"))]
mod crash_signal;
#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "windows")]
mod windows;

/// Crashes looked back over, and the most written.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
const CRASH_DAYS: u32 = 14;
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
const CRASHES: usize = 5;

/// Once per run, as the log opens: the crash handler where there is one, and
/// the GPUs and Windows' recent crashes written on a thread of their own, so
/// the start does not wait on them.
pub(crate) fn log_once() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        #[cfg(any(target_os = "linux", target_os = "android"))]
        crash_signal::install();
        #[cfg(target_os = "windows")]
        crash_filter::install();
        #[cfg(target_os = "windows")]
        let report: Option<fn()> = Some(windows::log);
        #[cfg(target_os = "linux")]
        let report: Option<fn()> = Some(linux::log);
        #[cfg(not(any(target_os = "windows", target_os = "linux")))]
        let report: Option<fn()> = None;
        if let Some(report) = report {
            let _ = std::thread::Builder::new()
                .name("diagnostics".into())
                .spawn(report);
        }
    });
}

/// One `Application Error` event: Windows' record of a process that died.
#[derive(Debug, PartialEq)]
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
struct Crash {
    when: String,
    app_version: String,
    module: String,
    module_version: String,
    exception: String,
    offset: String,
    pid: Option<u32>,
    module_path: String,
}

#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
impl Crash {
    /// Reads event 1000 as `EvtRender` gives it. Its fields are `<Data>`
    /// elements in a fixed order, named on Windows 11 and unnamed on 10, so
    /// they are taken by position: application, its version and stamp, the
    /// faulting module, its version and stamp, the exception code, the
    /// offset, the process id (hex), its start time, the application's path
    /// and the module's.
    fn from_event_xml(xml: &str) -> Option<Crash> {
        let when = attribute(xml, "TimeCreated", "SystemTime")?;
        let data = data_elements(xml);
        let field = |i: usize| data.get(i).cloned().unwrap_or_default();
        if data.len() < 8 {
            return None;
        }
        let pid = field(8);
        Some(Crash {
            when,
            app_version: field(1),
            module: field(3),
            module_version: field(4),
            exception: hex(&field(6)),
            offset: hex(&field(7)),
            pid: u32::from_str_radix(pid.trim_start_matches("0x"), 16).ok(),
            module_path: field(11),
        })
    }

    /// One log line. The process id is in decimal, as the log files name
    /// theirs, so the crash can be matched to the session it ended.
    fn describe(&self) -> String {
        let pid = self.pid.map_or(String::new(), |pid| format!(", pid {pid}"));
        let path = if self.module_path.is_empty() {
            String::new()
        } else {
            format!(" ({})", self.module_path)
        };
        format!(
            "Rift {}{pid} crashed at {} in {} {}{path}: exception {} at offset {}",
            self.app_version,
            self.when,
            self.module,
            self.module_version,
            self.exception,
            self.offset
        )
    }
}

/// `name="…"` (or `'…'`) on the first `<element`.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
fn attribute(xml: &str, element: &str, name: &str) -> Option<String> {
    let start = xml.find(&format!("<{element} "))?;
    let tag = &xml[start..start + xml[start..].find('>')?];
    let at = tag.find(&format!("{name}="))? + name.len() + 1;
    let quote = tag[at..].chars().next()?;
    let rest = &tag[at + 1..];
    Some(unescape(&rest[..rest.find(quote)?]))
}

/// The text of each `<Data>` element in order, empty for `<Data/>`.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
fn data_elements(xml: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = xml;
    while let Some(start) = rest.find("<Data") {
        rest = &rest[start + 5..];
        // `<DataItem` and the like are other elements.
        if !rest.starts_with(['>', ' ', '/']) {
            continue;
        }
        let Some(close) = rest.find('>') else { break };
        if rest[..close].ends_with('/') {
            out.push(String::new());
            rest = &rest[close + 1..];
            continue;
        }
        rest = &rest[close + 1..];
        let Some(end) = rest.find("</Data>") else {
            break;
        };
        out.push(unescape(&rest[..end]));
        rest = &rest[end..];
    }
    out
}

#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
fn unescape(text: &str) -> String {
    text.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&amp;", "&")
}

/// Windows writes the exception code bare (`c0000005`) and the offset with
/// its `0x`; both read the same way in the log.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
fn hex(value: &str) -> String {
    if value.is_empty() || value.starts_with("0x") {
        value.to_string()
    } else {
        format!("0x{value}")
    }
}

/// A driver's version as DXGI gives it, four 16-bit parts in one number.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
fn driver_version(packed: i64) -> String {
    let part = |shift: u32| (packed >> shift) & 0xffff;
    format!("{}.{}.{}.{}", part(48), part(32), part(16), part(0))
}

/// The version NVIDIA's own pages use, from Windows' for its driver:
/// 31.0.15.5222 is 552.22, the last digit of the third part and all four of
/// the last.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
fn nvidia_version(packed: i64) -> String {
    let number = ((packed >> 16) & 0xffff) % 10 * 10_000 + (packed & 0xffff);
    format!("{}.{:02}", number / 100, number % 100)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A real one, from a friend's Windows 10 (Oct 23 2026; the user's name
    /// changed): the fields unnamed, the offset and process id without `0x`.
    const WINDOWS_10: &str = r#"<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <Provider Name="Application Error" />
    <EventID Qualifiers="0">1000</EventID>
    <Version>0</Version>
    <Level>2</Level>
    <Task>100</Task>
    <Opcode>0</Opcode>
    <Keywords>0x80000000000000</Keywords>
    <TimeCreated SystemTime="2026-10-23T19:06:47.6826659Z" />
    <EventRecordID>17153</EventRecordID>
    <Correlation />
    <Execution ProcessID="0" ThreadID="0" />
    <Channel>Application</Channel>
    <Computer>DESKTOP-RVKBEL6</Computer>
    <Security />
  </System>
  <EventData>
    <Data>RiftChat.exe</Data>
    <Data>1.5.2.40</Data>
    <Data>6adb91f6</Data>
    <Data>ucrtbase.dll</Data>
    <Data>10.0.19041.7802</Data>
    <Data>2bd748bf</Data>
    <Data>c0000005</Data>
    <Data>00000000000488e0</Data>
    <Data>3d1c</Data>
    <Data>01dd63218f3d5d24</Data>
    <Data>C:\Users\Someone\AppData\Local\CodingFries.Rift\current\RiftChat.exe</Data>
    <Data>C:\Windows\System32\ucrtbase.dll</Data>
    <Data>8d8e6c31-3d15-4844-b05c-7270a88f1b4c</Data>
    <Data>
    </Data>
    <Data>
    </Data>
  </EventData>
</Event>"#;

    #[test]
    fn reads_an_unnamed_crash() {
        let crash = Crash::from_event_xml(WINDOWS_10).unwrap();
        assert_eq!(crash.when, "2026-10-23T19:06:47.6826659Z");
        assert_eq!(crash.app_version, "1.5.2.40");
        assert_eq!(crash.module, "ucrtbase.dll");
        assert_eq!(crash.module_version, "10.0.19041.7802");
        assert_eq!(crash.exception, "0xc0000005");
        assert_eq!(crash.offset, "0x00000000000488e0");
        // The session whose log is rift-…-15644.log.
        assert_eq!(crash.pid, Some(15644));
        assert_eq!(crash.module_path, "C:\\Windows\\System32\\ucrtbase.dll");
        assert_eq!(
            crash.describe(),
            "Rift 1.5.2.40, pid 15644 crashed at 2026-10-23T19:06:47.6826659Z in \
             ucrtbase.dll 10.0.19041.7802 (C:\\Windows\\System32\\ucrtbase.dll): \
             exception 0xc0000005 at offset 0x00000000000488e0"
        );
    }

    #[test]
    fn reads_a_named_crash() {
        let xml = "<Event><System><TimeCreated SystemTime=\"2026-10-24T08:00:00.0Z\"/></System><EventData><Data Name=\"AppName\">RiftChat.exe</Data><Data Name=\"AppVersion\">1.5.2.0</Data><Data Name=\"AppTimeStamp\">0</Data><Data Name=\"ModuleName\">rust_lib_rift.dll</Data><Data Name=\"ModuleVersion\">0.0.0.0</Data><Data Name=\"ModuleTimeStamp\">0</Data><Data Name=\"ExceptionCode\">c0000409</Data><Data Name=\"FaultingOffset\">0x10</Data><Data Name=\"ProcessId\">0x1a</Data></EventData></Event>";
        let crash = Crash::from_event_xml(xml).unwrap();
        assert_eq!(crash.module, "rust_lib_rift.dll");
        assert_eq!(crash.exception, "0xc0000409");
        assert_eq!(crash.pid, Some(26));
        assert_eq!(crash.module_path, "");
    }

    #[test]
    fn leaves_out_what_is_not_a_crash() {
        assert_eq!(Crash::from_event_xml("<Event><System/></Event>"), None);
        assert_eq!(
            Crash::from_event_xml(
                "<Event><System><TimeCreated SystemTime='x'/></System><EventData><Data>a</Data></EventData></Event>"
            ),
            None
        );
    }

    #[test]
    fn unescapes_once() {
        assert_eq!(unescape("a &amp;lt; b &amp; c"), "a &lt; b & c");
    }

    #[test]
    fn reads_driver_versions() {
        let packed: i64 = (31 << 48) | (15 << 16) | 5222;
        assert_eq!(driver_version(packed), "31.0.15.5222");
        assert_eq!(nvidia_version(packed), "552.22");
        let older: i64 = (27 << 48) | (21 << 32) | (14 << 16) | 6089;
        assert_eq!(nvidia_version(older), "460.89");
    }
}
