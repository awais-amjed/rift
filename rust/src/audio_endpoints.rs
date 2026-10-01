//! Reading each endpoint's shared-mode mix format from WASAPI. Why the app
//! needs it is in `api::audio_endpoints`.

use crate::api::audio_endpoints::AudioEndpoint;
use wasapi::{
    AudioClient, DeviceEnumerator, DeviceState, Direction, SampleType, ShareMode, WaveFormat,
};

/// The rates WebRTC's Windows device module tries, in its order. It asks for
/// 16-bit PCM in stereo, then mono, at each, in shared mode and without
/// automatic conversion, and gives up when Windows accepts none of them.
const DEVICE_MODULE_RATES: [usize; 6] = [48000, 44100, 16000, 96000, 32000, 8000];

pub(crate) fn outputs() -> Vec<AudioEndpoint> {
    list(Direction::Render)
}

pub(crate) fn inputs() -> Vec<AudioEndpoint> {
    list(Direction::Capture)
}

/// Whether Windows accepts a format the device module will ask for: the same
/// `IsFormatSupported` question, in the same plain `WAVEFORMATEX` form.
fn device_module_can_open(client: &AudioClient) -> bool {
    DEVICE_MODULE_RATES.iter().any(|&rate| {
        [2, 1].iter().any(|&channels| {
            WaveFormat::new(16, 16, &SampleType::Int, rate, channels, None)
                .to_waveformatex()
                .ok()
                .is_some_and(|format| {
                    matches!(client.is_supported(&format, &ShareMode::Shared), Ok(None))
                })
        })
    })
}

pub(crate) fn default_output() -> Option<String> {
    default_id(Direction::Render)
}

pub(crate) fn default_input() -> Option<String> {
    default_id(Direction::Capture)
}

/// The console-role default, which is what Windows' Sound settings call the
/// default device.
fn default_id(direction: Direction) -> Option<String> {
    // See `list` on why the result is not checked.
    let _ = wasapi::initialize_mta().ok();
    let enumerator = DeviceEnumerator::new()
        .map_err(|e| log::warn!("audio endpoints: no device enumerator: {e:?}"))
        .ok()?;
    let device = enumerator
        .get_default_device(&direction)
        .map_err(|e| log::warn!("audio endpoints: no default {direction:?} device: {e:?}"))
        .ok()?;
    device.get_id().ok()
}

fn list(direction: Direction) -> Vec<AudioEndpoint> {
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
            opens: device_module_can_open(&client),
        });
    }
    endpoints
}
