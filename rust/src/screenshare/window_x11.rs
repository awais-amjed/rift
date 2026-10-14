//! X11: which process and which app a window belongs to, which the
//! capturer's list does not say. Both are the window's own properties:
//! `_NET_WM_PID`, set by its toolkit, and `WM_CLASS`, whose instance names
//! the app much as a desktop file does (`google-chrome`, `firefox`). With
//! them a window share finds the sound that goes with it.
//!
//! libX11 is opened at run time, the way libwebrtc opens it, so a system
//! without it loses only this.
use libloading::Library;
use std::ffi::{c_char, c_int, c_long, c_uchar, c_ulong, c_void, CStr};
use std::ptr;

type Display = c_void;
type Atom = c_ulong;

#[repr(C)]
struct ClassHint {
    name: *mut c_char,
    class: *mut c_char,
}

type OpenDisplay = unsafe extern "C" fn(*const c_char) -> *mut Display;
type CloseDisplay = unsafe extern "C" fn(*mut Display) -> c_int;
type InternAtom = unsafe extern "C" fn(*mut Display, *const c_char, c_int) -> Atom;
type GetWindowProperty = unsafe extern "C" fn(
    *mut Display,
    c_ulong,
    Atom,
    c_long,
    c_long,
    c_int,
    Atom,
    *mut Atom,
    *mut c_int,
    *mut c_ulong,
    *mut c_ulong,
    *mut *mut c_uchar,
) -> c_int;
type GetClassHint = unsafe extern "C" fn(*mut Display, c_ulong, *mut ClassHint) -> c_int;
type Free = unsafe extern "C" fn(*mut c_void) -> c_int;

/// `XA_CARDINAL`, the type `_NET_WM_PID` is stored as.
const CARDINAL: Atom = 6;
const SUCCESS: c_int = 0;

/// A connection to the X server, for asking about windows.
pub(crate) struct Windows {
    // Kept for as long as the functions taken from it are used.
    _library: Library,
    display: *mut Display,
    pid_atom: Atom,
    close: CloseDisplay,
    property: GetWindowProperty,
    class_hint: GetClassHint,
    free: Free,
}

impl Windows {
    /// None without libX11 or an X server to talk to.
    pub(crate) fn open() -> Option<Self> {
        unsafe {
            let library = Library::new("libX11.so.6").ok()?;
            let open = *library.get::<OpenDisplay>(b"XOpenDisplay\0").ok()?;
            let close = *library.get::<CloseDisplay>(b"XCloseDisplay\0").ok()?;
            let intern = *library.get::<InternAtom>(b"XInternAtom\0").ok()?;
            let property = *library
                .get::<GetWindowProperty>(b"XGetWindowProperty\0")
                .ok()?;
            let class_hint = *library.get::<GetClassHint>(b"XGetClassHint\0").ok()?;
            let free = *library.get::<Free>(b"XFree\0").ok()?;
            let display = open(ptr::null());
            if display.is_null() {
                return None;
            }
            let pid_atom = intern(display, c"_NET_WM_PID".as_ptr(), 1);
            Some(Self {
                _library: library,
                display,
                pid_atom,
                close,
                property,
                class_hint,
                free,
            })
        }
    }

    /// The process that drew `window`, if its toolkit said.
    pub(crate) fn pid(&self, window: u64) -> Option<u32> {
        if self.pid_atom == 0 {
            return None;
        }
        let (mut kind, mut format, mut items, mut after) = (0, 0, 0, 0);
        let mut data: *mut c_uchar = ptr::null_mut();
        let status = unsafe {
            (self.property)(
                self.display,
                window as c_ulong,
                self.pid_atom,
                0,
                1,
                0,
                CARDINAL,
                &mut kind,
                &mut format,
                &mut items,
                &mut after,
                &mut data,
            )
        };
        if status != SUCCESS || data.is_null() {
            return None;
        }
        // Format 32 comes back as C longs, whatever their size.
        let pid = (kind == CARDINAL && format == 32 && items == 1)
            .then(|| unsafe { *(data as *const c_long) } as u32);
        unsafe { (self.free)(data.cast()) };
        pid.filter(|&pid| pid != 0)
    }

    /// The app `window` belongs to, by its `WM_CLASS` instance, or empty.
    pub(crate) fn app_id(&self, window: u64) -> String {
        let mut hint = ClassHint {
            name: ptr::null_mut(),
            class: ptr::null_mut(),
        };
        if unsafe { (self.class_hint)(self.display, window as c_ulong, &mut hint) } == 0 {
            return String::new();
        }
        let take = |text: *mut c_char| {
            if text.is_null() {
                return String::new();
            }
            let value = unsafe { CStr::from_ptr(text) }
                .to_string_lossy()
                .into_owned();
            unsafe { (self.free)(text.cast()) };
            value
        };
        let name = take(hint.name);
        let class = take(hint.class);
        if name.is_empty() {
            class
        } else {
            name
        }
    }
}

impl Drop for Windows {
    fn drop(&mut self) {
        unsafe { (self.close)(self.display) };
    }
}
