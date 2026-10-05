//! The processing thread: ARGB to I420, scale to the target size, hand to
//! LiveKit. Kept off the capture thread so a slow conversion delays frames
//! rather than the capture clock.
use super::capture::{Feed, VideoSlot};
#[cfg(target_os = "windows")]
use super::gpu_feed::Picture;
use super::pixels::copy_plane;
use super::resolution::{letterbox, Size};
use livekit::webrtc::desktop_capturer::DesktopFrame;
use livekit::webrtc::native::yuv_helper;
use livekit::webrtc::prelude::{I420Buffer, VideoBuffer, VideoFrame, VideoRotation};
use std::sync::mpsc::Receiver;
use std::thread::{self, JoinHandle};

/// A `DesktopFrame` on its way to another thread.
///
/// libwebrtc marks the frame `!Send` because it holds a raw pointer to the
/// C++ buffer, not because the buffer is thread-affine: it is a plain heap
/// allocation owned by this frame alone. The capture thread hands each frame
/// over and never touches it again, so exactly one thread ever reads it.
pub(crate) struct SendableFrame(pub DesktopFrame);
unsafe impl Send for SendableFrame {}

pub(crate) fn spawn_processing(
    frame_rx: Receiver<SendableFrame>,
    source_slot: VideoSlot,
) -> JoinHandle<()> {
    thread::spawn(move || run(frame_rx, source_slot))
}

fn run(frame_rx: Receiver<SendableFrame>, source_slot: VideoSlot) {
    // Reused across frames; reallocated only if the capture size changes.
    // `VideoFrame::new` rather than a struct literal: libwebrtc keeps adding
    // fields to this (0.3.48 added `frame_metadata`), and a literal has to be
    // edited for every one of them.
    let mut native = VideoFrame::new(VideoRotation::VideoRotation0, I420Buffer::new(2, 2));

    while let Ok(SendableFrame(frame)) = frame_rx.recv() {
        let width = frame.width();
        let height = frame.height();
        let size = Size {
            width: width as u32,
            height: height as u32,
        };
        // Asked on every frame, because the session swaps in a new source
        // when the size is changed mid-share. One uncontended lock a frame.
        let Some((feed, target)) = source_slot.feed(size) else {
            continue;
        };

        // The GPU encoder takes NV12, straight from the capture when it is
        // already the target size.
        #[cfg(target_os = "windows")]
        if let Feed::Gpu(gpu) = &feed {
            if target == size {
                gpu.send(
                    Picture::Argb {
                        data: frame.data(),
                        stride: frame.stride(),
                    },
                    target,
                    now_us(),
                );
                continue;
            }
        }

        if native.buffer.width() != size.width || native.buffer.height() != size.height {
            native.buffer = I420Buffer::new(size.width, size.height);
        }
        let (stride_y, stride_u, stride_v) = native.buffer.strides();
        let (y, u, v) = native.buffer.data_mut();
        yuv_helper::argb_to_i420(
            frame.data(),
            frame.stride(),
            y,
            stride_y,
            u,
            stride_u,
            v,
            stride_v,
            width,
            height,
        );

        // `scale` allocates a fresh buffer every call (about 3 MB at 1080p)
        // and libwebrtc exposes no scale-into variant, so skip it whenever
        // the capture is already the target size.
        match feed {
            Feed::Raw(source) if target == size => {
                source.capture_frame(&native);
            }
            Feed::Raw(source) => {
                let scaled = VideoFrame::new(
                    VideoRotation::VideoRotation0,
                    fit(&mut native.buffer, size, target),
                );
                source.capture_frame(&scaled);
            }
            #[cfg(target_os = "windows")]
            Feed::Gpu(gpu) => {
                let scaled = fit(&mut native.buffer, size, target);
                gpu.send(Picture::I420(&scaled), target, now_us());
            }
        }
    }
}

/// `frame`, captured at `size`, as a picture of `target`'s size: scaled to
/// fill it, or, once its shape no longer matches — a shared window resized
/// mid-share — scaled to fit and centred on black, so the viewer sees it
/// with bars rather than stretched.
///
/// A new buffer each time, as `scale` already makes: LiveKit holds on to
/// the one it is handed rather than copying it.
fn fit(frame: &mut I420Buffer, size: Size, target: Size) -> I420Buffer {
    let Some(rect) = letterbox(size, target) else {
        return frame.scale(target.width as i32, target.height as i32);
    };
    let scaled = frame.scale(rect.width as i32, rect.height as i32);
    let mut canvas = I420Buffer::new_black(target.width, target.height);
    let (from_y, from_u, from_v) = scaled.strides();
    let (to_y, to_u, to_v) = canvas.strides();
    let (src_y, src_u, src_v) = scaled.data();
    let (dst_y, dst_u, dst_v) = canvas.data_mut();
    let (x, y) = (rect.x as usize, rect.y as usize);
    let (width, height) = (rect.width as usize, rect.height as usize);
    copy_plane(
        src_y,
        from_y as usize,
        dst_y,
        to_y as usize,
        (x, y),
        (width, height),
    );
    let half = ((x / 2, y / 2), (width / 2, height / 2));
    copy_plane(src_u, from_u as usize, dst_u, to_u as usize, half.0, half.1);
    copy_plane(src_v, from_v as usize, dst_v, to_v as usize, half.0, half.1);
    canvas
}

/// The capture time an encoded frame carries: the wall clock, as libwebrtc
/// stamps a raw frame that comes without one.
#[cfg(target_os = "windows")]
fn now_us() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |since| since.as_micros() as i64)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A flat picture: every luma sample 200, every chroma sample 90.
    fn flat(width: u32, height: u32) -> I420Buffer {
        let mut buffer = I420Buffer::new(width, height);
        let (y, u, v) = buffer.data_mut();
        y.fill(200);
        u.fill(90);
        v.fill(90);
        buffer
    }

    fn luma(buffer: &I420Buffer, x: u32, y: u32) -> u8 {
        let (stride, _, _) = buffer.strides();
        buffer.data().0[(y * stride + x) as usize]
    }

    fn chroma(buffer: &I420Buffer, x: u32, y: u32) -> u8 {
        let (_, stride, _) = buffer.strides();
        buffer.data().1[(y / 2 * stride + x / 2) as usize]
    }

    #[test]
    fn a_frame_of_the_published_shape_fills_the_picture() {
        let target = Size {
            width: 640,
            height: 360,
        };
        let fitted = fit(
            &mut flat(1280, 720),
            Size {
                width: 1280,
                height: 720,
            },
            target,
        );
        assert_eq!((fitted.width(), fitted.height()), (640, 360));
        assert_eq!(luma(&fitted, 0, 180), 200);
        assert_eq!(luma(&fitted, 639, 180), 200);
    }

    #[test]
    fn a_narrower_window_is_centred_between_black_bars() {
        // 400x300 at 360 rows is 480 wide: bars of 80 either side.
        let fitted = fit(
            &mut flat(400, 300),
            Size {
                width: 400,
                height: 300,
            },
            Size {
                width: 640,
                height: 360,
            },
        );
        assert_eq!((fitted.width(), fitted.height()), (640, 360));
        for x in [0, 79, 560, 639] {
            assert_eq!(luma(&fitted, x, 180), 0, "luma at x={x}");
            assert_eq!(chroma(&fitted, x, 180), 128, "chroma at x={x}");
        }
        for x in [80, 320, 559] {
            assert_eq!(luma(&fitted, x, 180), 200, "luma at x={x}");
            assert_eq!(chroma(&fitted, x, 180), 90, "chroma at x={x}");
        }
        assert_eq!(luma(&fitted, 320, 0), 200);
        assert_eq!(luma(&fitted, 320, 359), 200);
    }
}
