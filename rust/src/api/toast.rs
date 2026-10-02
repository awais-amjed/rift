//! A Windows notification that can be taken down again.
//!
//! flutter_local_notifications cancels a shown toast only for an app with
//! package identity (an MSIX install): it calls `History().Remove(tag)`,
//! which needs one. Rift is installed unpackaged, so its cancels did nothing
//! and a call's "is calling" toast stayed on screen after the call was
//! answered or over. Without identity a toast can only be removed by tag,
//! group *and* app id, and the plugin gives its toasts no group, so the ones
//! Rift has to take down are posted here instead. They go out under the same
//! app id, so a press still reaches the plugin's activator.

/// Shows the toast in `xml` for the app `app_id` (the AUMID the plugin was
/// initialised with), tagged `tag` in `group`. A toast already there with the
/// same tag and group is replaced. Windows only; elsewhere it fails.
pub fn show_windows_toast(
    app_id: String,
    tag: String,
    group: String,
    xml: String,
) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        use windows::core::HSTRING;
        use windows::Data::Xml::Dom::XmlDocument;
        use windows::UI::Notifications::{ToastNotification, ToastNotificationManager};

        init_apartment();
        let doc = XmlDocument::new().map_err(|e| format!("no XML document: {e}"))?;
        doc.LoadXml(&HSTRING::from(xml))
            .map_err(|e| format!("the toast's XML was refused: {e}"))?;
        let toast = ToastNotification::CreateToastNotification(&doc)
            .map_err(|e| format!("no toast: {e}"))?;
        toast
            .SetTag(&HSTRING::from(tag))
            .and_then(|_| toast.SetGroup(&HSTRING::from(group)))
            .map_err(|e| format!("could not label the toast: {e}"))?;
        ToastNotificationManager::CreateToastNotifierWithId(&HSTRING::from(app_id))
            .and_then(|notifier| notifier.Show(&toast))
            .map_err(|e| format!("showing the toast failed: {e}"))
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (app_id, tag, group, xml);
        Err("Windows toasts exist only on Windows".to_string())
    }
}

/// Removes the toast [show_windows_toast] posted as `tag` in `group` for
/// `app_id`, from the screen and the notification centre. Nothing if it is
/// already gone. Windows only; elsewhere it does nothing.
pub fn remove_windows_toast(app_id: String, tag: String, group: String) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        use windows::core::HSTRING;
        use windows::UI::Notifications::ToastNotificationManager;

        init_apartment();
        ToastNotificationManager::History()
            .and_then(|history| {
                history.RemoveGroupedTagWithId(
                    &HSTRING::from(tag),
                    &HSTRING::from(group),
                    &HSTRING::from(app_id),
                )
            })
            .map_err(|e| format!("removing the toast failed: {e}"))
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (app_id, tag, group);
        Ok(())
    }
}

/// WinRT on whatever thread the bridge runs this on. A thread that already
/// has an apartment answers RPC_E_CHANGED_MODE and keeps it, which serves just
/// as well for these calls.
#[cfg(target_os = "windows")]
fn init_apartment() {
    use windows::Win32::System::WinRT::{RoInitialize, RO_INIT_MULTITHREADED};
    let _ = unsafe { RoInitialize(RO_INIT_MULTITHREADED) };
}
