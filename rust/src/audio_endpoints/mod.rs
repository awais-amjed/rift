//! Each platform's own account of its audio devices, for when WebRTC's
//! device module gives none. Why the app needs it is in `api::audio_endpoints`.

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "linux")]
pub(crate) use linux::{inputs, outputs};
#[cfg(target_os = "windows")]
pub(crate) use windows::{default_input, default_output, device_by_id, inputs, outputs};
