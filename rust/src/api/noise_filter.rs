//! The Rust library's noise models for the microphone filter: DeepFilterNet
//! (`src/deep_filter.rs`) and DPDFNet (`src/dpdfnet.rs`).

/// Where the runner's filter calls a model: the addresses of the frame
/// function and the reset function, for Dart to pass on.
pub struct NoiseModelEntry {
    pub process: usize,
    pub reset: usize,
}

/// Loads DeepFilterNet's model, if it is not loaded already, and says where
/// to call it. On a blocking thread, since loading takes a quarter of a
/// second. Off Windows and Linux there is no model, and this says so.
pub async fn load_deep_filter() -> Result<NoiseModelEntry, String> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        tokio::task::spawn_blocking(crate::deep_filter::load)
            .await
            .map_err(|e| e.to_string())??;
        let (process, reset) = crate::deep_filter::entry_points();
        Ok(NoiseModelEntry { process, reset })
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        Err("DeepFilterNet runs only on Windows and Linux".to_string())
    }
}

/// The same for DPDFNet, which loads in about a tenth of a second.
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
