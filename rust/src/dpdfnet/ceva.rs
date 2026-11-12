//! DPDFNet on Ceva's own runtime: the code the models' maker wrote for
//! exactly these two, where ONNX Runtime ([`super::onnx`]) runs them as a
//! graph of some 470 small steps. Its matrix products are done in 8-bit
//! whole numbers, in AVX2 assembly (AVX-VNNI where the CPU has it); what the
//! models remember between frames stays in floats.
//!
//! The runner bundles it as a library of its own, with the weights inside
//! (`native/dpdfnet`, where `rift_dpdfnet.h` says why it is not part of this
//! one), and it is opened here the first time a model loads. A computer it
//! does not open on, or whose CPU has no AVX2 and FMA, runs the models on
//! ONNX Runtime instead, and [`runtime`] writes why to the log.

use std::ffi::{c_void, CString};
use std::path::PathBuf;
use std::ptr::NonNull;
use std::sync::OnceLock;

use libloading::Library;

use super::{Size, SPECTRUM};

/// The library's interface version this crate was written against
/// (`RIFT_DPDFNET_ABI` in `rift_dpdfnet.h`).
const ABI: i32 = 1;

/// The library's name: in the bundle's `lib` folder on Linux, beside the app
/// on Windows.
#[cfg(target_os = "linux")]
const LIBRARY: &str = "lib/librift_dpdfnet.so";
#[cfg(target_os = "windows")]
const LIBRARY: &str = "rift_dpdfnet.dll";

/// What a test points at a library built elsewhere.
const LIBRARY_ENV: &str = "RIFT_DPDFNET_LIB";

/// Set to anything, this keeps the library shut, so the models run on ONNX
/// Runtime: for hearing or timing one against the other on one computer.
const SHUT_ENV: &str = "RIFT_DPDFNET_ONNX";

/// The library, open, and its functions as `rift_dpdfnet.h` declares them.
struct Runtime {
    open: unsafe extern "C" fn(i32) -> *mut c_void,
    run: unsafe extern "C" fn(*mut c_void, *mut f32) -> i32,
    reset: unsafe extern "C" fn(*mut c_void),
    close: unsafe extern "C" fn(*mut c_void),
    /// Kept open for as long as the functions above may be called: for good.
    _library: Library,
}

/// The library, opened once and kept open; or why this computer does not
/// have it, which goes to the log the first time.
fn runtime() -> Result<&'static Runtime, String> {
    static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();
    RUNTIME
        .get_or_init(|| {
            let opened = open();
            if let Err(why) = &opened {
                log::info!("DPDFNet runs on ONNX Runtime: {why}");
            }
            opened
        })
        .as_ref()
        .map_err(Clone::clone)
}

fn open() -> Result<Runtime, String> {
    if std::env::var_os(SHUT_ENV).is_some() {
        return Err(format!("{SHUT_ENV} is set"));
    }
    let path = match std::env::var_os(LIBRARY_ENV) {
        Some(path) => PathBuf::from(path),
        None => std::env::current_exe()
            .map_err(|e| e.to_string())?
            .parent()
            .ok_or("the app has no folder")?
            .join(LIBRARY),
    };
    // SAFETY: the library is Rift's own, built from native/dpdfnet, and runs
    // no code on load.
    let library = unsafe { Library::new(&path) }
        .map_err(|e| format!("Ceva's runtime did not load from {}: {e}", path.display()))?;
    // SAFETY: each symbol is looked up with the type rift_dpdfnet.h gives it,
    // and the version check refuses a library built for another interface.
    unsafe {
        let abi: unsafe extern "C" fn() -> i32 = symbol(&library, "rift_dpdfnet_abi")?;
        if abi() != ABI {
            return Err(format!("Ceva's runtime is version {}, not {ABI}", abi()));
        }
        let supported: unsafe extern "C" fn() -> i32 =
            symbol(&library, "rift_dpdfnet_model_supported")?;
        if supported() == 0 {
            return Err("Ceva's runtime needs AVX2 and FMA, which this CPU lacks".to_string());
        }
        Ok(Runtime {
            open: symbol(&library, "rift_dpdfnet_model_open")?,
            run: symbol(&library, "rift_dpdfnet_model_run")?,
            reset: symbol(&library, "rift_dpdfnet_model_reset")?,
            close: symbol(&library, "rift_dpdfnet_model_close")?,
            _library: library,
        })
    }
}

/// One of the library's functions.
///
/// # Safety
/// `T` must be the function's type as `rift_dpdfnet.h` declares it.
unsafe fn symbol<T: Copy>(library: &Library, name: &str) -> Result<T, String> {
    let name = CString::new(name).map_err(|e| e.to_string())?;
    library
        .get::<T>(name.as_bytes_with_nul())
        .map(|symbol| *symbol)
        .map_err(|e| format!("Ceva's runtime has no {}: {e}", name.to_string_lossy()))
}

/// One of the two models, and what it carries from one frame to the next,
/// which the library keeps.
pub(super) struct Net {
    runtime: &'static Runtime,
    model: NonNull<c_void>,
}

// SAFETY: the library's model is plain memory with no tie to the thread that
// opened it, and `&mut self` on every call keeps it to one call at a time,
// which is all the library asks.
unsafe impl Send for Net {}

impl Net {
    pub(super) fn load(size: Size) -> Result<Net, String> {
        let runtime = runtime()?;
        let size = match size {
            Size::Large => 8,
            Size::Small => 2,
        };
        // SAFETY: the library's own function, with a size it knows.
        let model = unsafe { (runtime.open)(size) };
        NonNull::new(model)
            .map(|model| Net { runtime, model })
            .ok_or_else(|| format!("Ceva's runtime did not open DPDFNet-{size}"))
    }

    /// One step, in place: the spectrum in, the cleaned one out. False, with
    /// the spectrum as it was, if the library refused it.
    pub(super) fn run(&mut self, spectrum: &mut [f32; SPECTRUM]) -> bool {
        // SAFETY: a live model, and the floats one spectrum is.
        unsafe { (self.runtime.run)(self.model.as_ptr(), spectrum.as_mut_ptr()) == 0 }
    }

    pub(super) fn reset(&mut self) {
        // SAFETY: a live model.
        unsafe { (self.runtime.reset)(self.model.as_ptr()) }
    }
}

impl Drop for Net {
    fn drop(&mut self) {
        // SAFETY: opened by this library, and closed once.
        unsafe { (self.runtime.close)(self.model.as_ptr()) }
    }
}
