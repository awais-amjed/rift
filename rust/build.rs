//! One `desktop` cfg instead of `any(windows, linux, macos)` on every item,
//! and one `gpu_encoder` for the two of them where Rift encodes on the GPU.
//!
//! libwebrtc's desktop capturer exists on exactly those three targets, and so
//! does everything in this crate that touches LiveKit (see Cargo.toml). The
//! bridge functions exist everywhere; what sits behind them is `cfg(desktop)`.
fn main() {
    println!("cargo:rustc-check-cfg=cfg(desktop)");
    println!("cargo:rustc-check-cfg=cfg(gpu_encoder)");
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if matches!(os.as_str(), "windows" | "linux" | "macos") {
        println!("cargo:rustc-cfg=desktop");
    }
    // Where Rift encodes a share's H264 on the GPU itself and hands LiveKit
    // the frames (`src/screenshare/encoder/`): Media Foundation on Windows,
    // NVENC on Linux. macOS has the OS's own encoder inside LiveKit.
    if matches!(os.as_str(), "windows" | "linux") {
        println!("cargo:rustc-cfg=gpu_encoder");
    }

    // libwebrtc m150 reaches the XDG desktop portal over GDBus, so the
    // prebuilt archive now carries undefined glib symbols. webrtc-sys probes
    // those libraries with `cargo_metadata(false)` — it takes their headers
    // and deliberately emits no link flags — on the assumption that whatever
    // links the final binary is a GTK app that already has them. The Flutter
    // bundle is; a `cargo test` binary is not, and links with nothing.
    if os == "linux" {
        for lib in ["glib-2.0", "gobject-2.0", "gio-2.0"] {
            println!("cargo:rustc-link-lib=dylib={lib}");
        }
    }
    println!("cargo:rerun-if-changed=build.rs");
}
