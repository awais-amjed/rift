//! The processing thread: ARGB to I420, scale to the target size, hand to
//! LiveKit. Kept off the capture thread so a slow conversion delays frames
//! rather than the capture clock.
use super::capture::VideoSlot;
use super::resolution::Size;
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
        let Some((source, target)) = source_slot.feed(size) else {
            continue;
        };

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
        if target == size {
            source.capture_frame(&native);
        } else {
            let scaled = VideoFrame::new(
                VideoRotation::VideoRotation0,
                native
                    .buffer
                    .scale(target.width as i32, target.height as i32),
            );
            source.capture_frame(&scaled);
        }
    }
}
