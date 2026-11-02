//! Watching a share through Rust instead of the call's own connection.
//!
//! A desktop watcher opens a second, receive-only LiveKit connection into the
//! call (`<user>~<device>_watch`, minted by the server only while that device's
//! voice connection is in the room), subscribes to the shares it watches and
//! nothing else, plays their sound, and hands each picture to the runner, which draws it into a
//! texture with a shader on the GPU. The call's connection, in flutter_webrtc,
//! decoded the picture, converted it to RGBA on the CPU and uploaded that,
//! which is most of what watching cost a player (`docs/gpu-codecs/STEP3_PLAN.md`).
//!
//! [`session`] is the connection; [`decode`] decodes its pictures on the GPU
//! where it can; [`frames`] is where a picture waits for the runner; [`sound`]
//! plays the share's sound. Desktop only (`cfg(desktop)`, build.rs), as everything that talks to
//! LiveKit from Rust is.
pub(crate) mod decode;
pub(crate) mod frames;
#[cfg(test)]
mod live_test;
pub(crate) mod session;
pub(crate) mod sound;
