//! A line of the log written from inside a crash, by `crash_signal` and
//! `crash_filter`: made in a buffer on the stack and written whole with one
//! system call to the log file ([crate::logging::file_raw]), without the
//! log's lock, since the crashing thread may hold it, and without allocating,
//! since the heap may be what broke.
use std::fmt::Write;
use std::time::{SystemTime, UNIX_EPOCH};

/// One line in the log's own format, `<UTC time> CRASH native: …`. Past its
/// length it is cut.
pub(super) struct Line {
    bytes: [u8; 1024],
    len: usize,
}

impl Line {
    pub(super) fn start() -> Line {
        let mut line = Line {
            bytes: [0; 1024],
            len: 0,
        };
        // A system call and arithmetic: no lock, no allocation.
        let since = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default();
        let (y, mo, d, h, mi, s) = crate::logging::civil(since.as_secs());
        let _ = write!(
            line,
            "{y:04}-{mo:02}-{d:02} {h:02}:{mi:02}:{s:02}.{:03}Z CRASH native: ",
            since.subsec_millis()
        );
        line
    }

    pub(super) fn bytes(&mut self, bytes: &[u8]) {
        // One byte kept for the newline.
        let room = self.bytes.len() - 1 - self.len;
        let n = bytes.len().min(room);
        self.bytes[self.len..self.len + n].copy_from_slice(&bytes[..n]);
        self.len += n;
    }

    pub(super) fn text(&mut self, text: &str) {
        self.bytes(text.as_bytes());
    }

    /// Writes the line to the log, or to stderr before the log has opened.
    pub(super) fn end(mut self) {
        self.bytes[self.len] = b'\n';
        self.len += 1;
        write_raw(&self.bytes[..self.len]);
    }
}

impl Write for Line {
    fn write_str(&mut self, text: &str) -> std::fmt::Result {
        self.text(text);
        Ok(())
    }
}

#[cfg(unix)]
fn write_raw(bytes: &[u8]) {
    let fd = match crate::logging::file_raw() {
        -1 => libc::STDERR_FILENO,
        fd => fd as libc::c_int,
    };
    // SAFETY: write is async-signal-safe, and the bytes are ours.
    unsafe { libc::write(fd, bytes.as_ptr().cast(), bytes.len()) };
}

#[cfg(windows)]
fn write_raw(bytes: &[u8]) {
    use windows::Win32::Foundation::HANDLE;
    use windows::Win32::Storage::FileSystem::WriteFile;
    use windows::Win32::System::Console::{GetStdHandle, STD_ERROR_HANDLE};
    // SAFETY: the handle is the log's open file, or the process's stderr.
    unsafe {
        let handle = match crate::logging::file_raw() {
            -1 => match GetStdHandle(STD_ERROR_HANDLE) {
                Ok(handle) => handle,
                Err(_) => return,
            },
            raw => HANDLE(raw as *mut std::ffi::c_void),
        };
        // Required without an OVERLAPPED.
        let mut written = 0u32;
        let _ = WriteFile(handle, Some(bytes), Some(&mut written), None);
    }
}
