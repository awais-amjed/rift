//! A soundboard clip in Ogg, decoded here rather than by the system.
//!
//! Windows has no Ogg reader for a desktop app: Media Foundation answered
//! every Ogg clip with no byte stream handler, Vorbis and Opus alike, even with
//! Microsoft's Web Media Extensions installed, and the app's own player goes
//! through Media Foundation too. So a clip uploaded as `.ogg` played for
//! everybody but those on Windows, who heard nothing (Nov 19 2026). Vorbis is
//! decoded by lewton, in pure Rust. Opus by libopus, already in the build
//! inside libwebrtc, which decodes a call's voice with it: nothing more ships.
//!
//! Linux could read these through GStreamer, but takes this path too, so a
//! clip sounds the same on both and does not depend on the distribution's
//! plugins.

use super::Pcm;
use std::io::Cursor;
use std::os::raw::{c_int, c_void};

/// Opus decodes at 48 kHz, whatever rate the file says it was made from.
const OPUS_RATE: u32 = 48_000;

/// The longest Opus packet: 120 ms at 48 kHz.
const OPUS_MOST_FRAMES: usize = 5_760;

// libopus, from libwebrtc (webrtc-sys links it into this library).
unsafe extern "C" {
    fn opus_multistream_decoder_create(
        rate: i32,
        channels: c_int,
        streams: c_int,
        coupled_streams: c_int,
        mapping: *const u8,
        error: *mut c_int,
    ) -> *mut c_void;
    fn opus_multistream_decode(
        decoder: *mut c_void,
        data: *const u8,
        len: i32,
        pcm: *mut i16,
        frame_size: c_int,
        decode_fec: c_int,
    ) -> c_int;
    fn opus_multistream_decoder_destroy(decoder: *mut c_void);
}

/// Whether [bytes] is an Ogg file: every page starts with this.
pub(super) fn is_ogg(bytes: &[u8]) -> bool {
    bytes.starts_with(b"OggS")
}

/// [bytes]' sound, at most [max_ms] of it, as one or two channels: a clip
/// with more is mixed down to one.
pub(super) fn decode(bytes: &[u8], max_ms: u32) -> Result<Pcm, String> {
    let mut packets = ogg::PacketReader::new(Cursor::new(bytes));
    let first = packets
        .read_packet()
        .map_err(|e| format!("Not a readable Ogg file: {e}"))?
        .ok_or("An empty Ogg file")?;
    if first.data.starts_with(b"\x01vorbis") {
        vorbis(bytes, max_ms)
    } else if first.data.starts_with(b"OpusHead") {
        let head = OpusHead::parse(&first.data)?;
        opus(packets, first.stream_serial(), &head, max_ms)
    } else {
        Err("An Ogg file in neither Vorbis nor Opus".to_string())
    }
}

fn vorbis(bytes: &[u8], max_ms: u32) -> Result<Pcm, String> {
    let fail = |e: lewton::VorbisError| format!("The Vorbis sound could not be read: {e}");
    let mut reader = lewton::inside_ogg::OggStreamReader::new(Cursor::new(bytes)).map_err(fail)?;
    let channels = usize::from(reader.ident_hdr.audio_channels).max(1);
    let rate = reader.ident_hdr.audio_sample_rate;
    let most = most_frames(rate, max_ms);
    let mut samples = Vec::new();
    while samples.len() / channels < most {
        match reader.read_dec_packet_itl().map_err(fail)? {
            Some(packet) => samples.extend(packet),
            None => break,
        }
    }
    finish(samples, channels, rate, most)
}

/// What an Opus stream's first packet says about it (RFC 7845, section 5.1).
#[derive(Debug, PartialEq)]
struct OpusHead {
    channels: u8,
    /// Frames at the start that are the encoder's warm-up, not the sound.
    pre_skip: u16,
    /// The gain to apply, in 1/256 dB.
    gain: i16,
    streams: u8,
    coupled: u8,
    mapping: Vec<u8>,
}

impl OpusHead {
    fn parse(data: &[u8]) -> Result<OpusHead, String> {
        let short = || "A damaged Opus header".to_string();
        if data.len() < 19 || data[8] >> 4 != 0 {
            return Err(short());
        }
        let channels = data[9];
        if channels == 0 {
            return Err(short());
        }
        let pre_skip = u16::from_le_bytes([data[10], data[11]]);
        let gain = i16::from_le_bytes([data[16], data[17]]);
        let (streams, coupled, mapping) = match data[18] {
            // One stream, mono or stereo.
            0 if channels <= 2 => (1, channels - 1, (0..channels).collect()),
            0 => return Err(short()),
            _ => {
                let table = data.get(19..21 + usize::from(channels)).ok_or_else(short)?;
                (table[0], table[1], table[2..].to_vec())
            }
        };
        if streams == 0 || coupled > streams {
            return Err(short());
        }
        Ok(OpusHead {
            channels,
            pre_skip,
            gain,
            streams,
            coupled,
            mapping,
        })
    }
}

/// A libopus decoder, let go of when dropped.
struct OpusDecoder(*mut c_void);

impl OpusDecoder {
    fn new(head: &OpusHead) -> Result<OpusDecoder, String> {
        let mut error: c_int = 0;
        // SAFETY: the mapping holds one entry per channel, as libopus reads
        // it, and lives past the call.
        let decoder = unsafe {
            opus_multistream_decoder_create(
                OPUS_RATE as i32,
                c_int::from(head.channels),
                c_int::from(head.streams),
                c_int::from(head.coupled),
                head.mapping.as_ptr(),
                &mut error,
            )
        };
        if decoder.is_null() || error != 0 {
            return Err(format!("libopus would not open the sound ({error})"));
        }
        Ok(OpusDecoder(decoder))
    }

    /// Decodes [packet] into [out], answering the frames it wrote.
    fn decode(&mut self, packet: &[u8], out: &mut [i16], channels: usize) -> Result<usize, String> {
        // SAFETY: the decoder is live, and `out` has room for the frame size
        // given, in every channel.
        let frames = unsafe {
            opus_multistream_decode(
                self.0,
                packet.as_ptr(),
                packet.len() as i32,
                out.as_mut_ptr(),
                (out.len() / channels) as c_int,
                0,
            )
        };
        usize::try_from(frames).map_err(|_| format!("libopus could not read the sound ({frames})"))
    }
}

impl Drop for OpusDecoder {
    fn drop(&mut self) {
        // SAFETY: made by `opus_multistream_decoder_create`, let go of once.
        unsafe { opus_multistream_decoder_destroy(self.0) }
    }
}

fn opus(
    mut packets: ogg::PacketReader<Cursor<&[u8]>>,
    serial: u32,
    head: &OpusHead,
    max_ms: u32,
) -> Result<Pcm, String> {
    let channels = usize::from(head.channels);
    let most = most_frames(OPUS_RATE, max_ms);
    let skip = usize::from(head.pre_skip);
    let mut decoder = OpusDecoder::new(head)?;
    let mut out = vec![0i16; OPUS_MOST_FRAMES * channels];
    let mut samples = Vec::new();
    // Where the stream says it ends, counted from its start with the
    // warm-up in: the last packet's frames run past it.
    let mut ends_at: Option<u64> = None;
    // The second packet is the tags.
    let mut tags = true;
    while samples.len() / channels < most + skip {
        let packet = match packets.read_packet() {
            Ok(Some(packet)) => packet,
            Ok(None) => break,
            Err(e) => return Err(format!("The Opus sound could not be read: {e}")),
        };
        if packet.stream_serial() != serial {
            continue;
        }
        if std::mem::take(&mut tags) {
            continue;
        }
        let frames = decoder.decode(&packet.data, &mut out, channels)?;
        samples.extend_from_slice(&out[..frames * channels]);
        if packet.last_in_stream() {
            ends_at = Some(packet.absgp_page());
            break;
        }
    }
    if let Some(end) = ends_at {
        let end = usize::try_from(end).unwrap_or(usize::MAX);
        samples.truncate(end.saturating_mul(channels));
    }
    let samples = samples.split_off((skip * channels).min(samples.len()));
    let samples = with_gain(samples, head.gain);
    finish(samples, channels, OPUS_RATE, most)
}

/// [samples] turned up or down by [gain], in 1/256 dB.
fn with_gain(mut samples: Vec<i16>, gain: i16) -> Vec<i16> {
    if gain == 0 {
        return samples;
    }
    let scale = 10f32.powf(f32::from(gain) / (20.0 * 256.0));
    for sample in &mut samples {
        *sample = (f32::from(*sample) * scale).clamp(-32768.0, 32767.0) as i16;
    }
    samples
}

fn most_frames(rate: u32, max_ms: u32) -> usize {
    (u64::from(rate) * u64::from(max_ms) / 1000) as usize
}

/// [samples] cut to [most] frames, with more than two channels mixed to one.
fn finish(samples: Vec<i16>, channels: usize, rate: u32, most: usize) -> Result<Pcm, String> {
    let (mut samples, channels) = if channels > 2 {
        let mixed = samples
            .chunks_exact(channels)
            .map(|frame| {
                let sum: i32 = frame.iter().map(|&s| i32::from(s)).sum();
                (sum / channels as i32) as i16
            })
            .collect();
        (mixed, 1)
    } else {
        (samples, channels)
    };
    samples.truncate(most * channels);
    if samples.is_empty() {
        return Err("No sound in the file".to_string());
    }
    Ok(Pcm {
        samples,
        channels: channels as u16,
        rate,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // Rift's join sound (2.09 s, 44.1 kHz stereo) made into Ogg by FFmpeg:
    // libvorbis at -q:a 0, and libopus at 48 kbps stereo and 24 kbps mono.
    // Kept outside `src`, whose every file cargokit reads as text.
    const VORBIS: &[u8] = include_bytes!("../../testdata/join_vorbis.ogg");
    const OPUS: &[u8] = include_bytes!("../../testdata/join_opus.ogg");
    const OPUS_MONO: &[u8] = include_bytes!("../../testdata/join_opus_mono.ogg");

    fn ms(pcm: &Pcm) -> u64 {
        let frames = pcm.samples.len() as u64 / u64::from(pcm.channels);
        frames * 1000 / u64::from(pcm.rate)
    }

    fn loudest(pcm: &Pcm) -> i16 {
        pcm.samples.iter().map(|s| s.saturating_abs()).max().unwrap()
    }

    #[test]
    fn knows_an_ogg_file_by_its_first_bytes() {
        assert!(is_ogg(VORBIS) && is_ogg(OPUS));
        assert!(!is_ogg(include_bytes!("../../../assets/audio/join.mp3")));
    }

    #[test]
    fn decodes_vorbis_at_its_own_rate() {
        let pcm = decode(VORBIS, 30_000).unwrap();
        assert_eq!((pcm.channels, pcm.rate), (2, 44_100));
        // Within one Vorbis block of the 2090 ms it was made from.
        assert!((2_080..=2_100).contains(&ms(&pcm)), "{} ms", ms(&pcm));
        assert!(loudest(&pcm) > 3_000);
    }

    #[test]
    fn decodes_opus_without_its_warm_up_or_its_last_packets_padding() {
        let pcm = decode(OPUS, 30_000).unwrap();
        assert_eq!((pcm.channels, pcm.rate), (2, 48_000));
        // As many frames as FFmpeg decodes from it: the mp3's 92160 at
        // 44.1 kHz, made 48 kHz.
        assert_eq!(pcm.samples.len(), 100_311 * 2);
        assert!(loudest(&pcm) > 3_000);
    }

    #[test]
    fn decodes_mono_opus_as_one_channel() {
        let pcm = decode(OPUS_MONO, 30_000).unwrap();
        assert_eq!((pcm.channels, pcm.rate), (1, 48_000));
        assert_eq!(pcm.samples.len(), 100_311);
    }

    #[test]
    fn stops_at_the_longest_a_clip_may_play() {
        assert_eq!(ms(&decode(OPUS, 500).unwrap()), 500);
        assert_eq!(ms(&decode(VORBIS, 500).unwrap()), 500);
    }

    #[test]
    fn refuses_what_it_cannot_read() {
        assert!(decode(b"OggS", 30_000).is_err());
        assert!(decode(&OPUS[..200], 30_000).is_err());
        assert!(OpusHead::parse(b"OpusHead\x01\x00").is_err());
    }

    #[test]
    fn reads_an_opus_header() {
        // Version 1, stereo, 312 frames of warm-up, 48 kHz, -1 dB, family 0.
        let mut data = b"OpusHead\x01\x02".to_vec();
        data.extend(312u16.to_le_bytes());
        data.extend(48_000u32.to_le_bytes());
        data.extend((-256i16).to_le_bytes());
        data.push(0);
        let head = OpusHead::parse(&data).unwrap();
        assert_eq!(
            head,
            OpusHead {
                channels: 2,
                pre_skip: 312,
                gain: -256,
                streams: 1,
                coupled: 1,
                mapping: vec![0, 1],
            }
        );
    }

    #[test]
    fn mixes_more_than_two_channels_to_one() {
        let pcm = finish(vec![300, 0, 0, -300, 600, 0], 3, 48_000, 10).unwrap();
        assert_eq!((pcm.channels, pcm.samples), (1, vec![100, 100]));
    }

    #[test]
    fn applies_the_headers_gain() {
        let louder = with_gain(vec![1_000, -1_000, 30_000], 6 * 256);
        assert!((1_990..=2_000).contains(&louder[0]), "{}", louder[0]);
        assert_eq!(louder[2], 32_767);
    }
}
