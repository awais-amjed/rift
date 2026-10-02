//! Posting and removing a Windows toast through WinRT. Why Rift does this
//! itself rather than through the notification plugin is in `api::toast`.

use windows::core::HSTRING;
use windows::Data::Xml::Dom::XmlDocument;
use windows::Win32::System::WinRT::{RoInitialize, RO_INIT_MULTITHREADED};
use windows::UI::Notifications::{ToastNotification, ToastNotificationManager};

pub(crate) fn show(app_id: &str, tag: &str, group: &str, xml: &str) -> Result<(), String> {
    init_apartment();
    let doc = XmlDocument::new().map_err(|e| format!("no XML document: {e}"))?;
    doc.LoadXml(&HSTRING::from(xml))
        .map_err(|e| format!("the toast's XML was refused: {e}"))?;
    let toast =
        ToastNotification::CreateToastNotification(&doc).map_err(|e| format!("no toast: {e}"))?;
    toast
        .SetTag(&HSTRING::from(tag))
        .and_then(|_| toast.SetGroup(&HSTRING::from(group)))
        .map_err(|e| format!("could not label the toast: {e}"))?;
    ToastNotificationManager::CreateToastNotifierWithId(&HSTRING::from(app_id))
        .and_then(|notifier| notifier.Show(&toast))
        .map_err(|e| format!("showing the toast failed: {e}"))
}

pub(crate) fn remove(app_id: &str, tag: &str, group: &str) -> Result<(), String> {
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

/// WinRT on whatever thread the bridge runs this on. A thread that already
/// has an apartment answers RPC_E_CHANGED_MODE and keeps it, which serves just
/// as well for these calls.
fn init_apartment() {
    let _ = unsafe { RoInitialize(RO_INIT_MULTITHREADED) };
}
