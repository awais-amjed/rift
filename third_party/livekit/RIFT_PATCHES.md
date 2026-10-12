# livekit, kept here and patched

LiveKit's `livekit` 0.9.1, as published on crates.io (from
[livekit/rust-sdks](https://github.com/livekit/rust-sdks), commit `2ff180e4`,
Apache-2.0 — `LICENSE` is the repository's, which the published crate leaves
out). The whole crate is kept, less cargo's `.cargo-ok` marker.
`rust/Cargo.toml` swaps it in with `[patch.crates-io]`, beside the patched
`webrtc-sys` (`../webrtc-sys/RIFT_PATCHES.md`).

The one change is marked `RIFT PATCH`; `git diff` against the commit that
brought the copy in shows it.

## Why

A share's sound is captured in two channels, but every listener heard it in
mono. The LiveKit server writes `stereo=1` into its answer for an audio track
only when the track's `AddTrackRequest` lists `TF_STEREO`, and takes it out
otherwise; without it, Opus encodes one channel. The browser SDK lists
`TF_STEREO` for a stereo track. The Rust SDK never does: the only feature it
sends is the preconnect buffer, so no track published from Rust can be stereo
(livekit/rust-sdks issue #1018, open since April 2026).

An unencrypted connection in single peer connection mode gets stereo anyway,
because the SDK writes `stereo=1` into its own offer; an encrypted one, which
every Rift call is, does not. Measured Oct 12 2026 against the local stack's
LiveKit with `live_share_sound_reaches_a_listener_in_stereo`: without the
change, a tone in one ear came out at the same level in both.

## The patch

1. **`publish_track` lists `TF_STEREO` for an audio track whose source has two
   or more channels** (`src/room/participant/local_participant.rs`). The same
   change as LiveKit rust-sdks PR #1023, open since April 2026.

A stereo track also needs a stereo bitrate, which is the caller's to choose:
`rust/src/sharing/audio/mod.rs` publishes at `MUSIC_HIGH_QUALITY_STEREO`.

## When to remove it

When a `livekit` release lists `TF_STEREO` for a stereo source (#1023 or an
equivalent): bump to it, delete this folder and its `[patch.crates-io]` line.
Until then, a `livekit` upgrade needs this copy replaced with the new version
and the change put back, or cargo ignores the patch and warns that it is
unused.
