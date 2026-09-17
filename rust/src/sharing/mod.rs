//! What the two kinds of share have in common.
//!
//! A share — of a screen or of an application's sound — is a *second* LiveKit
//! connection into the call the app is already in. Opening that connection
//! ([`room`]) and capturing an application's audio ([`audio`]) are the same
//! job either way, so they live here rather than inside `screenshare`.
//!
//! Everything here is `cfg(desktop)` (see build.rs): it all talks to LiveKit,
//! and a phone shares through the Dart SDK instead.
pub(crate) mod audio;
pub(crate) mod room;
pub(crate) mod sound;
