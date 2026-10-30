//! The Rust library's noise model for the microphone filter: DPDFNet
//! (`src/dpdfnet.rs`).

/// Where the runner's filter calls a model: the addresses of the frame
/// function and the reset function, for Dart to pass on.
pub struct NoiseModelEntry {
    pub process: usize,
    pub reset: usize,
}

/// Loads DPDFNet's models, if they are not loaded already, and says where to
/// call them. On a blocking thread, since loading takes about a tenth of a
/// second. Off Windows and Linux there is no model, and this says so.
pub async fn load_dpdfnet() -> Result<NoiseModelEntry, String> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        tokio::task::spawn_blocking(crate::dpdfnet::load)
            .await
            .map_err(|e| e.to_string())??;
        let (process, reset) = crate::dpdfnet::entry_points();
        Ok(NoiseModelEntry { process, reset })
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        Err("DPDFNet runs only on Windows and Linux".to_string())
    }
}

/// Whether DPDFNet went over to its small model since the last call, because
/// this computer was too slow for the large one; Dart writes it to the log
/// after a call. Starts the count again.
#[flutter_rust_bridge::frb(sync)]
pub fn take_dpdfnet_fell_back() -> bool {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        crate::dpdfnet::take_fell_back()
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        false
    }
}

/// How many frames DPDFNet sent unfiltered since the last call, because this
/// computer kept it from them in time; Dart writes it to the log after a
/// call. Starts the count again.
#[flutter_rust_bridge::frb(sync)]
pub fn take_dpdfnet_unfiltered() -> u32 {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        crate::dpdfnet::take_unfiltered()
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        0
    }
}

/// Gives DPDFNet-8 another go in the next call, on a computer that was too
/// slow for it in this one.
#[flutter_rust_bridge::frb(sync)]
pub fn retry_large_dpdfnet() {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    crate::dpdfnet::retry_large();
}

/// Runs DPDFNet-2 alone when `small`, as chosen in settings, in calls and the
/// mic test; otherwise DPDFNet-8, until this computer proves too slow for it.
#[flutter_rust_bridge::frb(sync)]
pub fn set_dpdfnet_small(small: bool) {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    crate::dpdfnet::choose_small(small);
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    let _ = small;
}

/// Where DPDFNet runs in a call, a beta option: on libwebrtc's capture
/// thread, as before beta.5, or on its own thread at one of three priorities,
/// which Linux leaves all at normal. Takes effect from the next frame,
/// mid-call too.
pub enum NoiseModelPlacement {
    CaptureThread,
    Highest,
    AboveNormal,
    Normal,
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_dpdfnet_placement(placement: NoiseModelPlacement) {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        use crate::dpdfnet::Placement;
        crate::dpdfnet::place(match placement {
            NoiseModelPlacement::CaptureThread => Placement::CaptureThread,
            NoiseModelPlacement::Highest => Placement::Highest,
            NoiseModelPlacement::AboveNormal => Placement::AboveNormal,
            NoiseModelPlacement::Normal => Placement::Normal,
        });
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    let _ = placement;
}

/// Holds Windows' 1 ms timer and unthrottled running while `hold`, a beta
/// option for calls: Dart holds it from a call's start to its end. Nothing
/// off Windows.
#[flutter_rust_bridge::frb(sync)]
pub fn hold_precise_timing_for_call(hold: bool) {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    crate::precise_timing::hold_for_call(hold);
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    let _ = hold;
}
