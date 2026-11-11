//! A chat video's first picture, as a small JPEG for its card to show
//! before it plays: Windows' Media Engine ([`super::media_engine`]) opens the
//! file from memory, silent, on a device of its own, and draws its first
//! picture already shrunk into a texture, which is read back and encoded.
use super::media_engine::{failure, own_device, Com, Engine, EVENT_ERROR};
use super::source::Source;
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};
use windows::Win32::Foundation::RECT;
use windows::Win32::Graphics::Direct3D11::{
    ID3D11Texture2D, D3D11_BIND_RENDER_TARGET, D3D11_CPU_ACCESS_READ, D3D11_MAPPED_SUBRESOURCE,
    D3D11_MAP_READ, D3D11_TEXTURE2D_DESC, D3D11_USAGE_DEFAULT, D3D11_USAGE_STAGING,
};
use windows::Win32::Graphics::Dxgi::Common::{DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_SAMPLE_DESC};

/// How long the first picture may take before there is no poster: long
/// enough for a big file's index and first picture to be fetched.
const PATIENCE: Duration = Duration::from_secs(30);
/// How long a paused engine is given to show its first picture before it is
/// played, silent, to make one.
const NUDGE_AFTER: Duration = Duration::from_millis(1500);

/// Closes the file it holds when it goes.
struct ClosedOnDrop(Arc<Source>);

impl Drop for ClosedOnDrop {
    fn drop(&mut self) {
        self.0.close();
    }
}

/// [file]'s first picture, its longer side at most [longest], as a JPEG.
pub(crate) fn poster(file: Arc<Source>, longest: u32) -> Result<Vec<u8>, String> {
    let _com = Com::enter();
    let longest = longest.clamp(16, 4096);
    let device = own_device()?;
    let (notes, heard) = mpsc::channel();
    let engine = Engine::new(&device, DXGI_FORMAT_B8G8R8A8_UNORM, None, notes)?;
    // SAFETY: a plain call on a live engine.
    let _ = unsafe { engine.engine.SetMuted(true) };
    // Declared after the engine, so dropped before it: its reads are woken
    // before the engine is shut down, which waits for them.
    let _closing = ClosedOnDrop(file.clone());
    engine.load(file)?;

    let started = Instant::now();
    let mut nudged = false;
    loop {
        while let Ok(note) = heard.try_recv() {
            if note.event == EVENT_ERROR {
                return Err(failure(note.param1, note.param2).1);
            }
        }
        if engine.has_video() && engine.new_picture() {
            break;
        }
        if started.elapsed() > PATIENCE {
            return Err("No first picture in time".to_string());
        }
        if !nudged && started.elapsed() > NUDGE_AFTER {
            nudged = true;
            // SAFETY: a plain call on a live engine.
            let _ = unsafe { engine.engine.Play() };
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    // SAFETY: a plain call on a live engine.
    let _ = unsafe { engine.engine.Pause() };
    let (_, shown) = engine.sizes().ok_or("The video has no size")?;
    let (w, h) = within(shown, longest);

    let texture = |staging: bool| {
        let desc = D3D11_TEXTURE2D_DESC {
            Width: w,
            Height: h,
            MipLevels: 1,
            ArraySize: 1,
            Format: DXGI_FORMAT_B8G8R8A8_UNORM,
            SampleDesc: DXGI_SAMPLE_DESC {
                Count: 1,
                Quality: 0,
            },
            Usage: if staging {
                D3D11_USAGE_STAGING
            } else {
                D3D11_USAGE_DEFAULT
            },
            BindFlags: if staging {
                0
            } else {
                D3D11_BIND_RENDER_TARGET.0 as u32
            },
            CPUAccessFlags: if staging {
                D3D11_CPU_ACCESS_READ.0 as u32
            } else {
                0
            },
            MiscFlags: 0,
        };
        let mut texture: Option<ID3D11Texture2D> = None;
        // SAFETY: a plain call with a local description and out-pointer.
        unsafe { device.CreateTexture2D(&desc, None, Some(&mut texture)) }
            .map_err(|e| format!("No texture for the poster: {e}"))?;
        texture.ok_or_else(|| "No texture for the poster".to_string())
    };
    let target = texture(false)?;
    let staging = texture(true)?;
    let whole = RECT {
        left: 0,
        top: 0,
        right: w as i32,
        bottom: h as i32,
    };
    // SAFETY: plain calls on live objects; the mapping is read within its
    // pitch and height and unmapped before it goes.
    let rgb = unsafe {
        engine
            .engine
            .TransferVideoFrame(&target, None, &whole, None)
            .map_err(|e| format!("The first picture was not drawn: {e}"))?;
        let context = device
            .GetImmediateContext()
            .map_err(|e| format!("No context: {e}"))?;
        context.CopyResource(&staging, &target);
        let mut mapped = D3D11_MAPPED_SUBRESOURCE::default();
        context
            .Map(&staging, 0, D3D11_MAP_READ, 0, Some(&mut mapped))
            .map_err(|e| format!("The first picture could not be read: {e}"))?;
        let pitch = mapped.RowPitch as usize;
        let bgra = std::slice::from_raw_parts(mapped.pData as *const u8, pitch * h as usize);
        let rgb = rgb_of(bgra, pitch, w, h);
        context.Unmap(&staging, 0);
        rgb
    };
    drop(engine);
    jpeg(rgb, w, h)
}

/// [shown] shrunk to fit [longest] on its longer side, never grown.
fn within((w, h): (u32, u32), longest: u32) -> (u32, u32) {
    let longer = w.max(h);
    if longer <= longest {
        return (w.max(1), h.max(1));
    }
    let scale = |side: u32| {
        ((side as u64 * longest as u64 + longer as u64 / 2) / longer as u64).max(1) as u32
    };
    (scale(w), scale(h))
}

/// BGRA rows [pitch] apart as packed RGB.
fn rgb_of(bgra: &[u8], pitch: usize, w: u32, h: u32) -> Vec<u8> {
    let mut rgb = Vec::with_capacity(w as usize * h as usize * 3);
    for row in 0..h as usize {
        for px in bgra[row * pitch..row * pitch + w as usize * 4].chunks_exact(4) {
            rgb.extend_from_slice(&[px[2], px[1], px[0]]);
        }
    }
    rgb
}

fn jpeg(rgb: Vec<u8>, w: u32, h: u32) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 80)
        .encode(&rgb, w, h, image::ExtendedColorType::Rgb8)
        .map_err(|e| format!("The poster could not be encoded: {e}"))?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shrinks_to_fit_and_never_grows() {
        assert_eq!(within((1280, 720), 440), (440, 248));
        assert_eq!(within((720, 1280), 440), (248, 440));
        assert_eq!(within((320, 180), 440), (320, 180));
    }

    #[test]
    fn bgra_rows_become_rgb() {
        // 1x2, rows 8 apart.
        let bgra = [1, 2, 3, 255, 0, 0, 0, 0, 4, 5, 6, 255, 0, 0, 0, 0];
        assert_eq!(rgb_of(&bgra, 8, 1, 2), [3, 2, 1, 6, 5, 4]);
    }

    /// ```text
    /// RIFT_CLIP_TEST=<a video> cargo test --release live_poster -- --ignored --nocapture
    /// ```
    #[test]
    #[ignore = "needs a video; see above"]
    fn live_poster_is_a_small_jpeg() {
        let path = std::env::var("RIFT_CLIP_TEST").unwrap();
        let bytes = std::fs::read(&path).unwrap();
        let started = Instant::now();
        let jpeg = super::poster(super::Source::memory(bytes), 440).unwrap();
        println!("{} bytes in {:?}", jpeg.len(), started.elapsed());
        assert_eq!(&jpeg[..2], &[0xff, 0xd8], "a JPEG");
        if let Ok(out) = std::env::var("RIFT_POSTER_OUT") {
            std::fs::write(out, &jpeg).unwrap();
        }
    }
}
