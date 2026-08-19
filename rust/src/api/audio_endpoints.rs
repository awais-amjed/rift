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
use wasapi::{DeviceEnumerator, DeviceState, Direction};

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
        list_endpoints(Direction::Render)
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
        list_endpoints(Direction::Capture)
    }
    #[cfg(not(target_os = "windows"))]
    {
        Vec::new()
    }
}

#[cfg(target_os = "windows")]
fn list_endpoints(direction: Direction) -> Vec<AudioEndpoint> {
    // The thread this lands on may or may not have COM up already. A thread
    // that is on an apartment answers RPC_E_CHANGED_MODE and keeps the
    // apartment it has, which serves just as well for reading properties, so
    // the result is deliberately not checked.
    let _ = wasapi::initialize_mta().ok();

    let enumerator = match DeviceEnumerator::new() {
        Ok(enumerator) => enumerator,
        Err(e) => {
            log::warn!("audio endpoints: no device enumerator: {e:?}");
            return Vec::new();
        }
    };
    let collection = match enumerator.get_device_collection(&direction) {
        Ok(collection) => collection,
        Err(e) => {
            log::warn!("audio endpoints: no device collection: {e:?}");
            return Vec::new();
        }
    };
    let count = collection.get_nbr_devices().unwrap_or(0);

    let mut endpoints = Vec::new();
    for index in 0..count {
        let Ok(device) = collection.get_device_at_index(index) else {
            continue;
        };
        // Disabled and unplugged endpoints enumerate too, and are of no use to
        // anyone choosing one.
        if !matches!(device.get_state(), Ok(DeviceState::Active)) {
            continue;
        }
        let Ok(device_id) = device.get_id() else {
            continue;
        };
        // Opening a client does not start anything; it is the only way to ask
        // what format the shared mixer is running this endpoint at.
        let Ok(client) = device.get_iaudioclient() else {
            continue;
        };
        let Ok(format) = client.get_mixformat() else {
            continue;
        };
        endpoints.push(AudioEndpoint {
            device_id,
            name: device.get_friendlyname().unwrap_or_default(),
            channels: u32::from(format.get_nchannels()),
            sample_rate: format.get_samplespersec(),
        });
    }
    endpoints
}
