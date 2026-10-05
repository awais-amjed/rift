# webrtc-sys, kept here and patched

LiveKit's `webrtc-sys` 0.3.45, as published on crates.io (from
[livekit/rust-sdks](https://github.com/livekit/rust-sdks), commit `2ff180e4`,
Apache-2.0 — see `LICENSE`). The whole crate is kept, less cargo's `.cargo-ok`
marker. `rust/Cargo.toml` swaps it in with `[patch.crates-io]`, so `livekit`
and `libwebrtc` stay on crates.io. The prebuilt libwebrtc it downloads is
unchanged; only LiveKit's own C++ wrappers are compiled from here, which the
published crate already does.

The one change is marked `RIFT PATCH`; `git diff` against the commit that
brought the copy in shows it.

## Why

A Windows screen share's H264 is encoded on the GPU and handed to LiveKit
already encoded (`ARCHITECTURE.md`, "Encoding a share on the GPU"). WebRTC's frame dropper still acts on those
frames: LiveKit's pass-through encoder does not say its rate controller can be
trusted, so whenever the stream runs above WebRTC's target for a moment — a
keyframe, motion starting, the link's estimate dipping — WebRTC drops encoded
frames on the way out. A dropped H264 delta frame breaks every frame after it
until the next keyframe: the viewer freezes, asks for a keyframe, and that
keyframe overshoots again.

Measured Oct 5 2026 on Windows with `gpu_live_test.rs`: without the change
WebRTC dropped 4 to 7 frames a run and 2 runs in 6 stalled (after a size
change, or a viewer joining late); with it, none dropped and 6 runs in 6
passed. The encoder already follows WebRTC's targets, which is what the change
asks of it.

## The patch

1. **`PassthroughVideoEncoder::GetEncoderInfo` sets
   `has_trusted_rate_controller`** (`src/passthrough_video_encoder.cpp`). The
   same line as LiveKit rust-sdks PR #1459, open since Sep 23 2026 and
   confirmed there by two people encoding with Media Foundation.

## When to remove it

When a `webrtc-sys` with #1459 (or an equivalent) is released: bump
`livekit` to the version that uses it, delete this folder and the
`[patch.crates-io]` entry. Until then, a `livekit` upgrade that moves
`webrtc-sys` past 0.3.45 needs this copy replaced with the new version and the
line put back, or cargo ignores the patch and warns that it is unused.
