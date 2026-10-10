//! Windows' ducking: whether it lowers other apps during a call, and when it
//! does. The listening is `crate::ducking`'s; elsewhere nothing ducks.
#[cfg(target_os = "windows")]
use crate::ducking;
use crate::frb_generated::StreamSink;

/// Windows lowered other apps (`ducked`) or let them back up.
pub struct DuckingEvent {
    pub ducked: bool,
    /// Whether this process's call caused it. Another app's call ducks too,
    /// and is not Rift's to explain.
    pub by_rift: bool,
    /// The file name of the program whose call it is.
    pub app: String,
}

/// Sends a [DuckingEvent] each time Windows ducks or unducks, for the life
/// of the process. Windows only; elsewhere it fails, and nothing is sent.
pub fn ducking_events(sink: StreamSink<DuckingEvent>) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        ducking::watch(sink)
    }
    #[cfg(not(target_os = "windows"))]
    {
        drop(sink);
        Err("Only Windows ducks other apps".to_string())
    }
}

/// What Windows does to other sounds during a call: 0 mutes them, 1 lowers
/// them by 80% (also when the user never chose), 2 by 50%, 3 does nothing.
/// Read each time, since the user changes it in Windows' own Sound window.
/// Null off Windows.
#[flutter_rust_bridge::frb(sync)]
pub fn ducking_preference() -> Option<u32> {
    #[cfg(target_os = "windows")]
    {
        Some(ducking::preference())
    }
    #[cfg(not(target_os = "windows"))]
    {
        None
    }
}
