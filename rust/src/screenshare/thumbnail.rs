//! A JPEG preview of one capture source. Windows only: there the capturer
//! delivers a frame synchronously inside `capture_frame`, which is what makes
//! a one-shot grab possible without a thread.
use super::pixels::thumbnail_rgb;
use super::sources;
use livekit::webrtc::desktop_capturer::{DesktopCapturer, DesktopCapturerOptions};
use std::sync::{Arc, Mutex};

const THUMBNAIL_WIDTH: u32 = 320;

/// None for a minimised window: there is nothing on screen to take a
/// picture of, and the picker says so instead.
pub(crate) fn capture(capture_full_screen: bool, source_index: u32) -> Option<Vec<u8>> {
    let source_type = sources::source_type(capture_full_screen);
    let chosen = sources::listed(source_type, source_index)?;
    if chosen.minimised {
        return None;
    }
    let mut capturer = DesktopCapturer::new(DesktopCapturerOptions::new(source_type))?;
    let source = capturer
        .get_source_list()
        .into_iter()
        .find(|source| source.id() == chosen.id)?;

    // The callback is 'static, so it writes the result back through a shared slot.
    let result: Arc<Mutex<Option<Vec<u8>>>> = Arc::new(Mutex::new(None));
    let slot = Arc::clone(&result);
    capturer.start_capture(Some(source), move |frame| {
        if let Ok(frame) = frame {
            let encoded = thumbnail_rgb(
                frame.data(),
                frame.width() as u32,
                frame.height() as u32,
                frame.stride() as u32,
                THUMBNAIL_WIDTH,
            )
            .and_then(|(rgb, w, h)| encode_jpeg(rgb, w, h));
            *slot.lock().unwrap() = encoded;
        }
    });
    capturer.capture_frame();

    let thumbnail = result.lock().unwrap().take();
    thumbnail
}

fn encode_jpeg(rgb: Vec<u8>, width: u32, height: u32) -> Option<Vec<u8>> {
    let image = image::RgbImage::from_raw(width, height, rgb)?;
    let mut bytes = Vec::new();
    image::DynamicImage::ImageRgb8(image)
        .write_to(
            &mut std::io::Cursor::new(&mut bytes),
            image::ImageFormat::Jpeg,
        )
        .ok()?;
    Some(bytes)
}
