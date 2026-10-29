//! Desktop screen sharing: the machinery behind `crate::api::screenshare`.
//!
//! Kept out of `api` so the bridge generator, which scans that module tree,
//! never sees any of it. Everything here is `cfg(desktop)` (see build.rs)
//! except the pure helpers, which are compiled and tested everywhere.
#[cfg(desktop)]
pub(crate) mod capture;
#[cfg(target_os = "linux")]
mod capture_pw;
#[cfg(desktop)]
pub(crate) mod encoder;
#[cfg(desktop)]
mod frames;
#[cfg(gpu_encoder)]
mod gpu_feed;
#[cfg_attr(not(desktop), allow(dead_code))]
mod latest;
mod pixels;
#[cfg(target_os = "linux")]
pub(crate) mod portal;
#[cfg(target_os = "linux")]
pub(crate) mod pw_stream;
#[cfg(gpu_encoder)]
mod rate_gate;
pub(crate) mod resolution;
#[cfg(desktop)]
pub(crate) mod session;
#[cfg(desktop)]
pub(crate) mod sources;
#[cfg(target_os = "windows")]
pub(crate) mod thumbnail;
#[cfg(desktop)]
mod track;
#[cfg(target_os = "windows")]
mod window_win;
#[cfg(target_os = "linux")]
mod window_x11;

#[cfg(all(test, desktop))]
mod bench_test;
#[cfg(all(test, gpu_encoder))]
mod gpu_live_test;
#[cfg(all(test, desktop))]
pub(crate) mod live_test;
