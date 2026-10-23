//! Linux: the GPUs, from sysfs. Their names would need the PCI id list, which
//! not every system has; the ids and the driver say which card it is, and the
//! encoder's own lines name the VAAPI driver.
use std::fs;
use std::path::Path;

pub(super) fn log() {
    let Ok(cards) = fs::read_dir("/sys/class/drm") else {
        return;
    };
    let mut names: Vec<String> = cards
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        // `card0`, not its outputs (`card0-DP-1`).
        .filter(|name| name.starts_with("card") && name[4..].chars().all(|c| c.is_ascii_digit()))
        .collect();
    names.sort();
    for name in names {
        let device = Path::new("/sys/class/drm").join(&name).join("device");
        let id = |file: &str| {
            fs::read_to_string(device.join(file))
                .map(|id| id.trim().trim_start_matches("0x").to_string())
                .unwrap_or_default()
        };
        let driver = fs::read_link(device.join("driver"))
            .ok()
            .and_then(|link| {
                link.file_name()
                    .map(|name| name.to_string_lossy().into_owned())
            })
            .unwrap_or_else(|| "no driver".to_string());
        // NVIDIA's module says its version; the kernel's own drivers do not.
        let version = fs::read_to_string(format!("/sys/module/{driver}/version"))
            .map(|version| format!(" {}", version.trim()))
            .unwrap_or_default();
        log::info!(
            "gpu: {name} {}:{}, {driver}{version}",
            id("vendor"),
            id("device")
        );
    }
}
