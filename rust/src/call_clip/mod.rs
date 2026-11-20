//! A call clip as a file: WAV for saving (exactly what was kept), MP3 for the
//! soundboard (CALLS.md, *Clipping a call*).

/// `pcm` (interleaved 16-bit) as a WAV file: a 44-byte header and the
/// samples as they are.
pub(crate) fn wav(pcm: &[i16], rate: u32, channels: u16) -> Vec<u8> {
    let data_len = (pcm.len() * 2) as u32;
    let block = channels as u32 * 2;
    let mut out = Vec::with_capacity(44 + pcm.len() * 2);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data_len).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&channels.to_le_bytes());
    out.extend_from_slice(&rate.to_le_bytes());
    out.extend_from_slice(&(rate * block).to_le_bytes());
    out.extend_from_slice(&(block as u16).to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data_len.to_le_bytes());
    for sample in pcm {
        out.extend_from_slice(&sample.to_le_bytes());
    }
    out
}

/// `pcm` (interleaved 16-bit, 1 or 2 channels) as a constant-rate MP3 at
/// `kbps`, by LAME. Constant rather than variable so the size the trim view
/// shows before encoding is the size it gets.
#[cfg(any(target_os = "windows", target_os = "linux"))]
pub(crate) fn mp3(pcm: &[i16], rate: u32, channels: u16, kbps: u32) -> Result<Vec<u8>, String> {
    use mp3lame_encoder::{Bitrate, Builder, FlushNoGap, InterleavedPcm, MonoPcm, Quality};

    if channels != 1 && channels != 2 {
        return Err(format!("{channels} channels; a clip has 1 or 2"));
    }
    if pcm.is_empty() || pcm.len() % channels as usize != 0 {
        return Err("no whole frames to encode".to_string());
    }
    let bitrate = match kbps {
        128 => Bitrate::Kbps128,
        160 => Bitrate::Kbps160,
        192 => Bitrate::Kbps192,
        256 => Bitrate::Kbps256,
        320 => Bitrate::Kbps320,
        other => return Err(format!("no MP3 rate of {other} kbps here")),
    };
    let fail = |what: &str, e: &dyn std::fmt::Debug| format!("MP3 {what}: {e:?}");
    let mut builder = Builder::new().ok_or("LAME would not start")?;
    builder.set_num_channels(channels as u8).map_err(|e| fail("channels", &e))?;
    builder.set_sample_rate(rate).map_err(|e| fail("rate", &e))?;
    builder.set_brate(bitrate).map_err(|e| fail("bitrate", &e))?;
    builder.set_quality(Quality::Good).map_err(|e| fail("quality", &e))?;
    let mut encoder = builder.build().map_err(|e| fail("encoder", &e))?;

    let frames = pcm.len() / channels as usize;
    let mut out = Vec::with_capacity(mp3lame_encoder::max_required_buffer_size(frames) + 7200);
    if channels == 2 {
        encoder.encode_to_vec(InterleavedPcm(pcm), &mut out)
    } else {
        encoder.encode_to_vec(MonoPcm(pcm), &mut out)
    }
    .map_err(|e| fail("encoding", &e))?;
    encoder
        .flush_to_vec::<FlushNoGap>(&mut out)
        .map_err(|e| fail("ending", &e))?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(frames: usize, rate: u32, channels: u16) -> Vec<i16> {
        let mut out = Vec::with_capacity(frames * channels as usize);
        for i in 0..frames {
            let t = i as f64 / rate as f64;
            let v = (8000.0 * (2.0 * std::f64::consts::PI * 440.0 * t).sin()) as i16;
            for _ in 0..channels {
                out.push(v);
            }
        }
        out
    }

    #[test]
    fn wav_has_its_header_and_the_samples() {
        let pcm = tone(4800, 48_000, 2);
        let wav = wav(&pcm, 48_000, 2);
        assert_eq!(wav.len(), 44 + pcm.len() * 2);
        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(u32::from_le_bytes(wav[4..8].try_into().unwrap()), (36 + pcm.len() * 2) as u32);
        assert_eq!(&wav[8..16], b"WAVEfmt ");
        assert_eq!(u16::from_le_bytes(wav[20..22].try_into().unwrap()), 1); // PCM
        assert_eq!(u16::from_le_bytes(wav[22..24].try_into().unwrap()), 2);
        assert_eq!(u32::from_le_bytes(wav[24..28].try_into().unwrap()), 48_000);
        assert_eq!(u32::from_le_bytes(wav[28..32].try_into().unwrap()), 48_000 * 4);
        assert_eq!(u16::from_le_bytes(wav[32..34].try_into().unwrap()), 4);
        assert_eq!(u16::from_le_bytes(wav[34..36].try_into().unwrap()), 16);
        assert_eq!(&wav[36..40], b"data");
        assert_eq!(u32::from_le_bytes(wav[40..44].try_into().unwrap()), (pcm.len() * 2) as u32);
        let back: Vec<i16> = wav[44..]
            .chunks_exact(2)
            .map(|b| i16::from_le_bytes([b[0], b[1]]))
            .collect();
        assert_eq!(back, pcm);
    }

    #[cfg(any(target_os = "windows", target_os = "linux"))]
    #[test]
    fn mp3_decodes_back_to_stereo_at_its_length() {
        let pcm = tone(48_000, 48_000, 2);
        let mp3 = mp3(&pcm, 48_000, 2, 192).expect("encodes");
        assert!(
            (20_000..=30_000).contains(&mp3.len()),
            "1 s at 192 kbps should be about 24 KB, was {}",
            mp3.len()
        );
        let decoded = nanomp3::decode_all::<i16>(&mp3);
        assert!(matches!(decoded.channels, Some(nanomp3::Channels::Stereo)));
        assert_eq!(decoded.sample_rate, 48_000);
        let frames = decoded.samples.len() / 2;
        assert!(
            (47_000..=50_400).contains(&frames),
            "1 s give or take a frame of padding, was {frames} frames"
        );
    }

    #[cfg(any(target_os = "windows", target_os = "linux"))]
    #[test]
    fn mp3_refuses_nothing_to_encode() {
        assert!(mp3(&[], 48_000, 2, 192).is_err());
        assert!(mp3(&[1, 2, 3], 48_000, 2, 192).is_err()); // half a frame
        assert!(mp3(&[0; 4], 48_000, 3, 192).is_err());
    }
}
