//! A call clip made into a file (`crate::call_clip`): the trim view's Save
//! and Add to soundboard.

/// `pcm` (interleaved 16-bit) as a WAV file.
pub fn call_clip_wav(pcm: Vec<i16>, rate: u32, channels: u16) -> Vec<u8> {
    crate::call_clip::wav(&pcm, rate, channels)
}

/// `pcm` (interleaved 16-bit) as a constant-rate MP3 at `kbps` (128, 160,
/// 192, 256 or 320), for the soundboard. Windows and Linux only, where clips
/// are made.
pub fn call_clip_mp3(pcm: Vec<i16>, rate: u32, channels: u16, kbps: u32) -> Result<Vec<u8>, String> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        crate::call_clip::mp3(&pcm, rate, channels, kbps)
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        let _ = (pcm, rate, channels, kbps);
        Err("MP3 clips are made on Windows and Linux".to_string())
    }
}
