//! A sound decoded whole by Windows' Media Foundation, for the cue player to
//! play on a device it opens (`crate::cue`): a soundboard clip, in whatever
//! format it was uploaded. A Source Reader reads it from memory through the
//! same stream a chat video is read through ([`super::pulled_stream`]) and
//! hands back 16-bit PCM at the file's own rate. The cue player's stream
//! converts the rate; more than two channels are cut to the first two here,
//! and one is widened by the player.
use super::media_engine::{startup, Com};
use super::pulled_stream::PulledStream;
use super::source::Source;
use super::Pcm;
use std::sync::Arc;
use windows::Win32::Media::MediaFoundation::{
    IMFSample, MFAudioFormat_PCM, MFCreateMFByteStreamOnStream, MFCreateMediaType,
    MFCreateSourceReaderFromByteStream, MFMediaType_Audio, MF_MT_AUDIO_BITS_PER_SAMPLE,
    MF_MT_AUDIO_NUM_CHANNELS, MF_MT_AUDIO_SAMPLES_PER_SECOND, MF_MT_MAJOR_TYPE, MF_MT_SUBTYPE,
    MF_SOURCE_READERF_ENDOFSTREAM, MF_SOURCE_READER_ALL_STREAMS,
    MF_SOURCE_READER_FIRST_AUDIO_STREAM,
};

/// [file]'s sound, at most [max_ms] of it.
pub(super) fn decode(file: Arc<Source>, max_ms: u32) -> Result<Pcm, String> {
    let _com = Com::enter();
    startup()?;
    let result = read(file.clone(), max_ms);
    file.close();
    result
}

fn read(file: Arc<Source>, max_ms: u32) -> Result<Pcm, String> {
    let fail = |what: &'static str| move |e: windows::core::Error| format!("{what}: {e}");
    let audio = MF_SOURCE_READER_FIRST_AUDIO_STREAM.0 as u32;
    // SAFETY: plain Media Foundation calls on this thread, with COM up and
    // Media Foundation started; every pointer handed in is a local.
    unsafe {
        let byte_stream = MFCreateMFByteStreamOnStream(&PulledStream::new(file))
            .map_err(fail("No byte stream"))?;
        let reader = MFCreateSourceReaderFromByteStream(&byte_stream, None)
            .map_err(fail("The sound would not open"))?;
        reader
            .SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS.0 as u32, false)
            .map_err(fail("No streams"))?;
        reader
            .SetStreamSelection(audio, true)
            .map_err(fail("No sound in the file"))?;
        let wanted = MFCreateMediaType().map_err(fail("No media type"))?;
        wanted
            .SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Audio)
            .map_err(fail("No media type"))?;
        wanted
            .SetGUID(&MF_MT_SUBTYPE, &MFAudioFormat_PCM)
            .map_err(fail("No media type"))?;
        wanted
            .SetUINT32(&MF_MT_AUDIO_BITS_PER_SAMPLE, 16)
            .map_err(fail("No media type"))?;
        reader
            .SetCurrentMediaType(audio, None, &wanted)
            .map_err(fail("Windows cannot decode this sound"))?;
        let actual = reader
            .GetCurrentMediaType(audio)
            .map_err(fail("No media type"))?;
        let channels = actual
            .GetUINT32(&MF_MT_AUDIO_NUM_CHANNELS)
            .map_err(fail("No channel count"))?
            .max(1) as usize;
        let rate = actual
            .GetUINT32(&MF_MT_AUDIO_SAMPLES_PER_SECOND)
            .map_err(fail("No rate"))?;
        let kept = channels.min(2);
        let most = (u64::from(rate) * u64::from(max_ms) / 1000) as usize * kept;

        let mut samples: Vec<i16> = Vec::new();
        while samples.len() < most {
            let mut flags = 0u32;
            let mut sample: Option<IMFSample> = None;
            reader
                .ReadSample(audio, 0, None, Some(&mut flags), None, Some(&mut sample))
                .map_err(fail("The sound could not be read"))?;
            if let Some(sample) = sample {
                let buffer = sample
                    .ConvertToContiguousBuffer()
                    .map_err(fail("The sound could not be read"))?;
                let mut data = std::ptr::null_mut();
                let mut length = 0u32;
                buffer
                    .Lock(&mut data, None, Some(&mut length))
                    .map_err(fail("The sound could not be read"))?;
                let bytes = std::slice::from_raw_parts(data, length as usize);
                let frames = bytes.chunks_exact(2 * channels);
                for frame in frames {
                    for side in frame.chunks_exact(2).take(kept) {
                        samples.push(i16::from_le_bytes([side[0], side[1]]));
                    }
                }
                let _ = buffer.Unlock();
            }
            if flags & MF_SOURCE_READERF_ENDOFSTREAM.0 as u32 != 0 {
                break;
            }
        }
        samples.truncate(most);
        if samples.is_empty() {
            return Err("No sound in the file".to_string());
        }
        Ok(Pcm {
            samples,
            channels: kept as u16,
            rate,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// ```text
    /// RIFT_SOUND_TEST=<a sound file> cargo test --release live_sound -- --ignored --nocapture
    /// ```
    #[test]
    #[ignore = "needs a sound file; see above"]
    fn live_sound_decodes() {
        let bytes = std::fs::read(std::env::var("RIFT_SOUND_TEST").unwrap()).unwrap();
        let started = std::time::Instant::now();
        let pcm = decode(Source::memory(bytes), 30_000).unwrap();
        let seconds = pcm.samples.len() as f64 / f64::from(pcm.channels) / f64::from(pcm.rate);
        println!(
            "{seconds:.2} s of sound, {} channels at {} Hz, in {:?}",
            pcm.channels,
            pcm.rate,
            started.elapsed()
        );
        assert!(pcm.samples.iter().any(|&s| s != 0), "not all silence");
    }
}
