//! One `desktop` cfg instead of `any(windows, linux, macos)` on every item.
//!
//! libwebrtc's desktop capturer exists on exactly those three targets, and so
//! does everything in this crate that touches LiveKit (see Cargo.toml). The
//! bridge functions exist everywhere; what sits behind them is `cfg(desktop)`.
fn main() {
    println!("cargo:rustc-check-cfg=cfg(desktop)");
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if matches!(os.as_str(), "windows" | "linux" | "macos") {
        println!("cargo:rustc-cfg=desktop");
    }
    println!("cargo:rerun-if-changed=build.rs");
}
