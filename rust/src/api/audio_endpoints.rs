//! What Windows reports about each audio endpoint's shared-mode format.
//!
//! WebRTC's Windows audio device module opens an endpoint by asking
//! `IAudioClient::Initialize` for 16-bit PCM, mono or stereo, at one of six
//! sample rates, and gives up if the endpoint accepts none of them. An
//! endpoint whose shared mix format is something like 8 channels at 96 kHz —
//! which is how the virtual devices created by audio routing software often
//! present themselves — refuses every one of those, and playout dies with
//! `AUDCLNT_E_UNSUPPORTED_FORMAT`.
//!
//! That alone would only cost the one device, but the device module is then
//! left stopped, and its own device-change path only restarts playout when it
//! was already playing. So a single failed switch takes the audio out until
//! the call is rejoined, however many working devices are picked afterwards.
//!
//! Which means the choice has to be filtered before the device module is asked
//! to make it, and the mix format can only be read from Windows directly.

#[cfg(target_os = "windows")]
use crate::audio_endpoints;

/// One endpoint, and the format Windows hands a shared-mode client for it.
pub struct AudioEndpoint {
    /// The endpoint id, in the same form WebRTC reports as a device's guid, so
    /// the two lists can be matched up.
    pub device_id: String,
    pub name: String,
    pub channels: u32,
    pub sample_rate: u32,
}

/// Every active render endpoint. Empty off Windows, and empty rather than
/// failing if the audio service cannot be reached: callers treat "nothing
/// known" as "do not filter", which keeps a broken probe from hiding devices
/// that would have worked.
pub fn list_output_endpoints() -> Vec<AudioEndpoint> {
    #[cfg(target_os = "windows")]
    {
        audio_endpoints::outputs()
    }
    #[cfg(not(target_os = "windows"))]
    {
        Vec::new()
    }
}

/// Every active capture endpoint. See [`list_output_endpoints`].
pub fn list_input_endpoints() -> Vec<AudioEndpoint> {
    #[cfg(target_os = "windows")]
    {
        audio_endpoints::inputs()
    }
    #[cfg(not(target_os = "windows"))]
    {
        Vec::new()
    }
}
