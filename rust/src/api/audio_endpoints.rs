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
//!
//! The same lists stand in for WebRTC's whenever its device module answers
//! nothing: on Windows outside a call, and on Linux once a call has ended
//! (leaving shuts the module down until the next call). On Linux they come
//! from PulseAudio, under the ids WebRTC gives the same devices.

#[cfg(any(target_os = "windows", target_os = "linux"))]
use crate::audio_endpoints;
#[cfg(target_os = "linux")]
use crate::device_watch;
use crate::frb_generated::StreamSink;

/// One endpoint, and the format the system hands a shared client for it.
pub struct AudioEndpoint {
    /// The id WebRTC lists the same device under, so the two lists can be
    /// matched up: the endpoint id on Windows, the description on Linux.
    pub device_id: String,
    pub name: String,
    pub channels: u32,
    pub sample_rate: u32,
    /// Whether Windows accepts any of the formats WebRTC's device module asks
    /// for. Asked of Windows rather than inferred from the mix format: inside
    /// Rift's own process a 2 channel endpoint has been seen reporting an 8
    /// channel mix, which the module opened without trouble. Always true on
    /// Linux, where PulseAudio converts any format.
    pub opens: bool,
}

/// Every active render endpoint. Empty off Windows and Linux, and empty
/// rather than failing if the audio service cannot be reached: callers treat "nothing
/// known" as "do not filter", which keeps a broken probe from hiding devices
/// that would have worked.
pub fn list_output_endpoints() -> Vec<AudioEndpoint> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        audio_endpoints::outputs()
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        Vec::new()
    }
}

/// Every active capture endpoint. See [`list_output_endpoints`].
pub fn list_input_endpoints() -> Vec<AudioEndpoint> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        audio_endpoints::inputs()
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        Vec::new()
    }
}

/// The id of the render endpoint Windows plays to by default, in the same
/// form as [`AudioEndpoint::device_id`]. None off Windows, and None when there
/// is no default or the audio service cannot be reached.
///
/// WebRTC's device module cannot be told "the default" by the plugin, only a
/// device by its place in the list, so choosing "System default" has to be
/// turned into a concrete endpoint first. Linux needs no such lookup: WebRTC
/// lists the default there as an entry of its own.
pub fn default_output_endpoint() -> Option<String> {
    #[cfg(target_os = "windows")]
    {
        audio_endpoints::default_output()
    }
    #[cfg(not(target_os = "windows"))]
    {
        None
    }
}

/// The id of the capture endpoint Windows records from by default. See
/// [`default_output_endpoint`].
pub fn default_input_endpoint() -> Option<String> {
    #[cfg(target_os = "windows")]
    {
        audio_endpoints::default_input()
    }
    #[cfg(not(target_os = "windows"))]
    {
        None
    }
}

/// Sends an event whenever an audio device is added or removed or the system
/// default changes, until Dart stops listening.
///
/// Linux only. WebRTC's PulseAudio module never reports a change (its device
/// observer is not implemented there, so `ondevicechange` never fires), and a
/// headset plugged in while settings were open stayed missing from the list.
/// Elsewhere WebRTC reports changes itself, and the stream ends at once.
pub fn audio_device_changes(sink: StreamSink<()>) {
    #[cfg(target_os = "linux")]
    device_watch::start(sink);
    #[cfg(not(target_os = "linux"))]
    drop(sink);
}
