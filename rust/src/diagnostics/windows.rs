//! Windows: the GPUs from DXGI, and Rift's crashes from the Application log.
use windows::core::{Interface, HSTRING};
use windows::Win32::Graphics::Dxgi::{
    CreateDXGIFactory1, IDXGIDevice, IDXGIFactory1, DXGI_ADAPTER_FLAG_SOFTWARE,
};
use windows::Win32::System::EventLog::{
    EvtClose, EvtNext, EvtQuery, EvtQueryChannelPath, EvtQueryReverseDirection, EvtRender,
    EvtRenderEventXml, EVT_HANDLE,
};

use super::{driver_version, nvidia_version, Crash, CRASHES, CRASH_DAYS};

const NVIDIA: u32 = 0x10de;

pub(super) fn log() {
    log_gpus();
    log_crashes();
}

fn log_gpus() {
    // SAFETY: plain DXGI calls on interfaces that live for the loop.
    unsafe {
        let factory: IDXGIFactory1 = match CreateDXGIFactory1() {
            Ok(factory) => factory,
            Err(e) => {
                log::info!("gpu: DXGI did not answer: {e}");
                return;
            }
        };
        let mut index = 0;
        while let Ok(adapter) = factory.EnumAdapters1(index) {
            index += 1;
            let Ok(desc) = adapter.GetDesc1() else {
                continue;
            };
            if desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE.0 as u32 != 0 {
                continue;
            }
            let name = String::from_utf16_lossy(&desc.Description);
            let name = name.trim_end_matches('\0');
            let driver = match adapter.CheckInterfaceSupport(&IDXGIDevice::IID) {
                Ok(packed) if desc.VendorId == NVIDIA => format!(
                    "driver {} (NVIDIA {})",
                    driver_version(packed),
                    nvidia_version(packed)
                ),
                Ok(packed) => format!("driver {}", driver_version(packed)),
                Err(_) => "driver unknown".to_string(),
            };
            log::info!(
                "gpu: {name}, {driver}, {} MB",
                desc.DedicatedVideoMemory / (1024 * 1024)
            );
        }
    }
}

fn log_crashes() {
    let Some(exe) = std::env::current_exe().ok().and_then(|path| {
        path.file_name()
            .map(|name| name.to_string_lossy().into_owned())
    }) else {
        return;
    };
    let query = format!(
        "*[System[Provider[@Name='Application Error'] and (EventID=1000) and \
         TimeCreated[timediff(@SystemTime) <= {}]]] and *[EventData[Data='{exe}']]",
        u64::from(CRASH_DAYS) * 24 * 60 * 60 * 1000
    );
    let crashes = match read_events(&query) {
        Ok(events) => events
            .iter()
            .filter_map(|xml| Crash::from_event_xml(xml))
            .collect::<Vec<_>>(),
        Err(e) => {
            log::info!("crash: could not read Windows' Application log: {e}");
            return;
        }
    };
    if crashes.is_empty() {
        log::info!("crash: Windows saw no crash of Rift in the last {CRASH_DAYS} days");
        return;
    }
    log::info!(
        "crash: Windows saw Rift crash {} time(s) in the last {CRASH_DAYS} days{}",
        crashes.len(),
        if crashes.len() == CRASHES {
            " (or more)"
        } else {
            ""
        }
    );
    for crash in &crashes {
        log::warn!("crash: {}", crash.describe());
    }
}

/// The newest [CRASHES] events of the Application log matching `query`, as
/// XML.
fn read_events(query: &str) -> windows::core::Result<Vec<String>> {
    // SAFETY: each handle is closed once, after its last use, and every
    // buffer is as long as said.
    unsafe {
        let results = EvtQuery(
            None,
            &HSTRING::from("Application"),
            &HSTRING::from(query),
            EvtQueryChannelPath.0 | EvtQueryReverseDirection.0,
        )?;
        let mut handles = [0isize; CRASHES];
        let mut returned = 0u32;
        // No more events is an error here, with nothing returned.
        let _ = EvtNext(results, &mut handles, 2000, 0, &mut returned);
        let mut events = Vec::new();
        for &raw in &handles[..returned as usize] {
            let event = EVT_HANDLE(raw);
            if let Some(xml) = render(event) {
                events.push(xml);
            }
            let _ = EvtClose(event);
        }
        let _ = EvtClose(results);
        Ok(events)
    }
}

/// # Safety
/// `event` must be a live event handle.
unsafe fn render(event: EVT_HANDLE) -> Option<String> {
    let mut used = 0u32;
    let mut count = 0u32;
    // Asked with no buffer first, it says how many bytes the XML takes.
    let _ = EvtRender(
        None,
        event,
        EvtRenderEventXml.0,
        0,
        None,
        &mut used,
        &mut count,
    );
    if used == 0 {
        return None;
    }
    let mut buffer = vec![0u16; (used as usize).div_ceil(2)];
    EvtRender(
        None,
        event,
        EvtRenderEventXml.0,
        (buffer.len() * 2) as u32,
        Some(buffer.as_mut_ptr().cast()),
        &mut used,
        &mut count,
    )
    .ok()?;
    let text = String::from_utf16_lossy(&buffer);
    Some(text.trim_end_matches('\0').to_string())
}
