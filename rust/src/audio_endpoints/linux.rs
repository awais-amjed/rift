//! Listing PulseAudio's sinks and sources under the ids WebRTC gives them.
//!
//! WebRTC's PulseAudio module answers nothing once it has been shut down,
//! which happens when the last call ends, and only starts again with the
//! next one. The pickers then read the server directly. A device's id is its
//! description, as it is in WebRTC's own list, so a pick made here is one the
//! next call finds. PulseAudio converts any format, so every device opens.

use crate::api::audio_endpoints::AudioEndpoint;
use crate::pulse::{self, Connection, Device};

pub(crate) fn outputs() -> Vec<AudioEndpoint> {
    list(pulse::sinks)
}

pub(crate) fn inputs() -> Vec<AudioEndpoint> {
    list(pulse::sources)
}

fn list(read: fn(&mut Connection) -> Vec<Device>) -> Vec<AudioEndpoint> {
    let Some(mut connection) = Connection::open("rift-audio-endpoints") else {
        return Vec::new();
    };
    read(&mut connection).into_iter().map(endpoint).collect()
}

fn endpoint(device: Device) -> AudioEndpoint {
    AudioEndpoint {
        device_id: device.description.clone(),
        name: device.description,
        channels: u32::from(device.channels),
        sample_rate: device.rate,
        opens: true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_device_is_known_by_its_description() {
        let endpoint = endpoint(Device {
            name: "bluez_output.28_9A.1".to_string(),
            description: "Arctis Nova Pro Wireless".to_string(),
            channels: 1,
            rate: 16_000,
        });
        assert_eq!(endpoint.device_id, "Arctis Nova Pro Wireless");
        assert_eq!(endpoint.name, "Arctis Nova Pro Wireless");
        assert_eq!((endpoint.channels, endpoint.sample_rate), (1, 16_000));
        assert!(endpoint.opens);
    }
}
