//! Which GPU encodes a Wayland share. The picture is on the GPU that draws the
//! screen, so that is the one to encode on: NVIDIA's only when it draws alone.
//! On a hybrid laptop Intel or AMD drives the screen, and VAAPI there keeps
//! coming first (`ffmpeg.rs`, `candidates`).

const NVIDIA: u16 = 0x10de;
const INTEL: u16 = 0x8086;
const AMD: u16 = 0x1002;

/// One card, as the kernel lists it.
pub(crate) struct DrmCard {
    pub vendor: u16,
    pub connected: bool,
    pub render_node: Option<String>,
}

/// Where a Wayland share's DMA-BUFs go.
pub(crate) struct DmabufTarget {
    pub render_node: String,
    /// Offer the modifiers EGL imports only as external too, which NVENC's GL
    /// path samples and VAAPI's import cannot take.
    pub external_modifiers: bool,
}

/// Where an encoder's DMA-BUFs go, if it takes them at all: an NVENC whose GL
/// side failed still has its node, and takes none.
pub(crate) fn target_for(
    render_node: Option<&str>,
    nvenc: bool,
    takes_dmabuf: bool,
) -> Option<DmabufTarget> {
    if !takes_dmabuf {
        return None;
    }
    Some(DmabufTarget {
        render_node: render_node?.to_owned(),
        external_modifiers: nvenc,
    })
}

/// The NVIDIA card's render node when it has a connected display and no Intel
/// or AMD card does. `None` keeps today's order.
pub(crate) fn nvidia_draws_the_screen(cards: &[DrmCard]) -> Option<&str> {
    let other_draws = cards
        .iter()
        .any(|card| card.connected && matches!(card.vendor, INTEL | AMD));
    if other_draws {
        return None;
    }
    cards
        .iter()
        .find(|card| card.vendor == NVIDIA && card.connected)?
        .render_node
        .as_deref()
}

/// The cards in `/sys/class/drm`.
pub(crate) fn read_cards() -> Vec<DrmCard> {
    let Ok(entries) = std::fs::read_dir("/sys/class/drm") else {
        return Vec::new();
    };
    let names: Vec<String> = entries
        .flatten()
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect();
    let is_card = |name: &&String| {
        name.strip_prefix("card")
            .is_some_and(|rest| !rest.is_empty() && rest.bytes().all(|b| b.is_ascii_digit()))
    };
    names
        .iter()
        .filter(is_card)
        .filter_map(|card| {
            let device = format!("/sys/class/drm/{card}/device");
            let vendor = std::fs::read_to_string(format!("{device}/vendor")).ok()?;
            let vendor = u16::from_str_radix(vendor.trim().trim_start_matches("0x"), 16).ok()?;
            let connector = format!("{card}-");
            let connected = names
                .iter()
                .filter(|name| name.starts_with(&connector))
                .any(|name| {
                    std::fs::read_to_string(format!("/sys/class/drm/{name}/status"))
                        .is_ok_and(|status| status.trim() == "connected")
                });
            let render_node = std::fs::read_dir(format!("{device}/drm"))
                .ok()?
                .flatten()
                .filter_map(|entry| entry.file_name().into_string().ok())
                .find(|name| name.starts_with("renderD"))
                .map(|name| format!("/dev/dri/{name}"));
            Some(DrmCard {
                vendor,
                connected,
                render_node,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_encoder_taking_dmabufs_names_its_gpu() {
        let vaapi = target_for(Some("/dev/dri/renderD129"), false, true).unwrap();
        assert_eq!(vaapi.render_node, "/dev/dri/renderD129");
        assert!(!vaapi.external_modifiers);
        let nvenc = target_for(Some("/dev/dri/renderD128"), true, true).unwrap();
        assert_eq!(nvenc.render_node, "/dev/dri/renderD128");
        assert!(nvenc.external_modifiers);
    }

    #[test]
    fn an_encoder_taking_no_dmabufs_has_no_target() {
        // An NVENC whose GL side failed still has its node.
        assert!(target_for(Some("/dev/dri/renderD128"), true, false).is_none());
        // An NVENC on a screen another GPU draws has none.
        assert!(target_for(None, true, false).is_none());
    }

    fn card(vendor: u16, connected: bool, node: Option<&str>) -> DrmCard {
        DrmCard {
            vendor,
            connected,
            render_node: node.map(str::to_owned),
        }
    }

    const NODE: &str = "/dev/dri/renderD129";

    #[test]
    fn gpu_choice_nvidia_alone() {
        let cards = [card(NVIDIA, true, Some(NODE))];
        assert_eq!(nvidia_draws_the_screen(&cards), Some(NODE));
    }

    #[test]
    fn gpu_choice_an_idle_igpu_beside_it_does_not_matter() {
        let cards = [
            card(INTEL, false, Some("/dev/dri/renderD128")),
            card(NVIDIA, true, Some(NODE)),
        ];
        assert_eq!(nvidia_draws_the_screen(&cards), Some(NODE));
    }

    #[test]
    fn gpu_choice_intel_or_amd_with_a_display_keeps_todays_order() {
        for other in [INTEL, AMD] {
            let both = [card(other, true, None), card(NVIDIA, true, Some(NODE))];
            assert_eq!(nvidia_draws_the_screen(&both), None);
        }
        let hybrid = [
            card(INTEL, true, Some("/dev/dri/renderD128")),
            card(NVIDIA, false, Some(NODE)),
        ];
        assert_eq!(nvidia_draws_the_screen(&hybrid), None);
    }

    #[test]
    fn gpu_choice_needs_a_render_node() {
        let cards = [card(NVIDIA, true, None)];
        assert_eq!(nvidia_draws_the_screen(&cards), None);
    }

    #[test]
    fn gpu_choice_ignores_an_unknown_card() {
        let cards = [card(0x1234, true, None), card(NVIDIA, true, Some(NODE))];
        assert_eq!(nvidia_draws_the_screen(&cards), Some(NODE));
    }

    #[test]
    fn gpu_choice_no_cards() {
        assert_eq!(nvidia_draws_the_screen(&[]), None);
    }

    #[test]
    fn gpu_choice_takes_the_card_with_the_display() {
        let cards = [
            card(NVIDIA, false, Some("/dev/dri/renderD128")),
            card(NVIDIA, true, Some(NODE)),
        ];
        assert_eq!(nvidia_draws_the_screen(&cards), Some(NODE));
    }
}
