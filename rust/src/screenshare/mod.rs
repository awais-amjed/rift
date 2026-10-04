//! Desktop screen sharing: the machinery behind `crate::api::screenshare`.
//!
//! Kept out of `api` so the bridge generator, which scans that module tree,
//! never sees any of it. Everything here is `cfg(desktop)` (see build.rs)
//! except the pure helpers, which are compiled and tested everywhere.
#[cfg(desktop)]
pub(crate) mod capture;
#[cfg(desktop)]
mod encoder;
#[cfg(desktop)]
mod frames;
mod pixels;
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

#[cfg(all(test, desktop))]
mod bench_test;
#[cfg(all(test, desktop))]
mod live_test;
