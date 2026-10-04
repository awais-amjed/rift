//! DeepFilterNet for the microphone filter (`src/deep_filter.rs`).

/// Where the runner's filter calls the model: the addresses of the frame
/// function and the reset function, for Dart to pass on.
pub struct DeepFilterEntry {
    pub process: usize,
    pub reset: usize,
}

/// Loads DeepFilterNet's model, if it is not loaded already, and says where
/// to call it. On a blocking thread, since loading takes a quarter of a
/// second. Off Windows and Linux there is no model, and this says so.
pub async fn load_deep_filter() -> Result<DeepFilterEntry, String> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        tokio::task::spawn_blocking(crate::deep_filter::load)
            .await
            .map_err(|e| e.to_string())??;
        let (process, reset) = crate::deep_filter::entry_points();
        Ok(DeepFilterEntry { process, reset })
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        Err("DeepFilterNet runs only on Windows and Linux".to_string())
    }
}
