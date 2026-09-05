//! Where `log::` output goes. Called once from the bridge's init hook.
//!
//! flutter_rust_bridge installs a logger for Android, iOS and macOS but has
//! none for Linux or Windows, where it would otherwise be silently dropped.
pub fn init() {
    flutter_rust_bridge::setup_default_user_utils();
    #[cfg(any(target_os = "linux", target_os = "windows"))]
    {
        let _ = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
            .try_init();
    }
}
