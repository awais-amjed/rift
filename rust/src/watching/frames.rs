//! The newest picture of each watched share, waiting for the runner to draw it.
//!
//! Rust receives a share's pictures on its own thread. The runner draws them on
//! Flutter's raster thread, when Flutter asks (`FlTextureGL::populate` on
//! Linux). Between the two sits one slot per texture holding only the newest
//! picture: one the runner has not drawn yet is replaced, never queued, so a
//! slow draw shows the latest picture rather than falling behind.
//!
//! The runner reads a picture where it lies, in the decoder's own buffer, so it
//! is lent rather than copied: [`rift_watch_frame_lock`] hands out its planes
//! and keeps the picture alive until [`rift_watch_frame_unlock`], whatever
//! happens to the slot meanwhile. The runner finds the two through
//! [`entry_points`], as it finds DPDFNet's. A picture is libwebrtc's, three
//! planes in memory, or one decoded on the GPU ([`super::decode`]): two
//! DMA-BUF layers the runner imports, or CUDA's memory, which the runner has
//! the decoder's library copy into its GL textures, or on Windows a slice of
//! the D3D11 decoder's texture array, on the runner's own device.
//!
//! A picture the runner cannot draw is handed back saying so, and the app
//! then watches through the call instead ([`super::session::lost`]):
//! otherwise the share would stay black for as long as it is watched. On
//! Linux that is a GPU picture that would not import; on Windows any picture,
//! once the runner's device is lost.
use livekit::webrtc::prelude::{I420Buffer, VideoBuffer};
use std::collections::HashMap;
use std::ffi::c_void;
use std::sync::Mutex;

/// The runner's "a new picture is waiting" for one texture: it marks the
/// texture so Flutter asks for it on its next frame. Safe from any thread.
pub(crate) type MarkFn = unsafe extern "C" fn(texture: u64);

/// [`WatchPlanes::kind`] for a picture in memory: I420's three planes, the
/// chroma planes half the size each way, rounded up.
pub(crate) const IN_MEMORY: u32 = 0;
/// [`WatchPlanes::kind`] for a picture on the GPU: NV12 as two DMA-BUF layers,
/// Y as DRM's R8 and interleaved UV as GR88 at half the size each way.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) const ON_GPU: u32 = 1;
/// [`WatchPlanes::kind`] for a picture in CUDA's memory, NV12, which
/// [`WatchPlanes::copy_to_gl`] copies into the runner's textures.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub(crate) const IN_CUDA: u32 = 2;
/// [`WatchPlanes::kind`] for a slice of a D3D11 decoder's NV12 texture array
/// ([`WatchPlanes::texture`] and [`WatchPlanes::slice`]), on the runner's
/// device, coded at the decoder's aligned size: the picture is its top left.
#[cfg_attr(not(windows), allow(dead_code))]
pub(crate) const IN_D3D11: u32 = 3;

/// `rift_ffdec_copy_to_gl` (`native/ffenc/ffdec.h`): the picture, the
/// runner's two textures, and its registration of them, kept between calls.
pub(crate) type CopyToGl = unsafe extern "C" fn(
    picture: *const c_void,
    textures: *const u32,
    link: *mut *mut c_void,
) -> i32;
/// `rift_ffdec_gl_close`: lets the registration go before the textures do.
pub(crate) type GlClose = unsafe extern "C" fn(link: *mut c_void);

/// One picture as the runner draws it. `linux/runner/stream_texture.cc` and
/// `windows/runner/stream_draw.h` have the same fields in the same order.
#[repr(C)]
pub struct WatchPlanes {
    pub width: u32,
    pub height: u32,
    pub y: *const u8,
    pub u: *const u8,
    pub v: *const u8,
    pub stride_y: u32,
    pub stride_u: u32,
    pub stride_v: u32,
    /// [`IN_MEMORY`], with the planes above, or [`ON_GPU`], with the layers
    /// below: their fds, the picture's until it is handed back.
    pub kind: u32,
    pub formats: [u32; 2],
    pub fds: [i32; 2],
    pub offsets: [u32; 2],
    pub pitches: [u32; 2],
    pub modifiers: [u64; 2],
    /// The colour's matrix (`RiftFfdecMatrix`: BT.601, 709 or 2020), and 1
    /// for full range. BT.601 limited, 0 and 0, for libwebrtc's pictures,
    /// which flutter_webrtc always drew that way.
    pub matrix: u32,
    pub full_range: u32,
    /// [`IN_CUDA`]: the decoder's picture, valid while lent, and the
    /// library's functions the runner calls on it with its GL context
    /// current.
    pub picture: *const c_void,
    pub copy_to_gl: Option<CopyToGl>,
    pub gl_close: Option<GlClose>,
    /// [`IN_D3D11`]: the decoder's `ID3D11Texture2D` array and the picture's
    /// slice in it, both valid while lent.
    pub texture: *mut c_void,
    pub slice: u32,
}

impl WatchPlanes {
    /// A picture of `width` by `height` with nothing filled in yet.
    pub(crate) fn sized(width: u32, height: u32) -> WatchPlanes {
        WatchPlanes {
            width,
            height,
            y: std::ptr::null(),
            u: std::ptr::null(),
            v: std::ptr::null(),
            stride_y: 0,
            stride_u: 0,
            stride_v: 0,
            kind: IN_MEMORY,
            formats: [0; 2],
            fds: [-1; 2],
            offsets: [0; 2],
            pitches: [0; 2],
            modifiers: [0; 2],
            matrix: 0,
            full_range: 0,
            picture: std::ptr::null(),
            copy_to_gl: None,
            gl_close: None,
            texture: std::ptr::null_mut(),
            slice: 0,
        }
    }
}

/// What a slot holds: anything the runner can draw. A trait so the slot rules
/// can be tested without a decoder.
pub(crate) trait Picture: Send {
    fn planes(&self) -> WatchPlanes;
}

impl Picture for I420Buffer {
    fn planes(&self) -> WatchPlanes {
        let (y, u, v) = self.data();
        let (stride_y, stride_u, stride_v) = self.strides();
        WatchPlanes {
            y: y.as_ptr(),
            u: u.as_ptr(),
            v: v.as_ptr(),
            stride_y,
            stride_u,
            stride_v,
            ..WatchPlanes::sized(self.width(), self.height())
        }
    }
}

impl Picture for Box<dyn Picture> {
    fn planes(&self) -> WatchPlanes {
        (**self).planes()
    }
}

struct Slot<P> {
    newest: Option<P>,
    mark: Option<MarkFn>,
    /// The runner could not draw one of its pictures, and was answered.
    failed: bool,
    /// A picture has come since the slot opened.
    came: bool,
}

/// The slots, and the pictures lent out of them.
pub(crate) struct Table<P> {
    slots: HashMap<u64, Slot<P>>,
    lent: HashMap<u64, P>,
}

impl<P: Picture> Table<P> {
    fn new() -> Self {
        Table {
            slots: HashMap::new(),
            lent: HashMap::new(),
        }
    }

    fn open(&mut self, texture: u64, mark: Option<MarkFn>) {
        self.slots.insert(
            texture,
            Slot {
                newest: None,
                mark,
                failed: false,
                came: false,
            },
        );
    }

    /// Nothing more is delivered to [texture]. A picture already lent stays
    /// alive until the runner hands it back.
    fn close(&mut self, texture: u64) {
        self.slots.remove(&texture);
    }

    /// Puts [picture] in its slot, over any the runner has not taken, and
    /// answers the runner's mark to call; none when nothing watches [texture].
    fn deliver(&mut self, texture: u64, picture: P) -> Option<Option<MarkFn>> {
        let slot = self.slots.get_mut(&texture)?;
        slot.newest = Some(picture);
        slot.came = true;
        Some(slot.mark)
    }

    /// Whether any picture has come for [texture] since it was opened.
    fn delivered(&self, texture: u64) -> bool {
        self.slots.get(&texture).is_some_and(|slot| slot.came)
    }

    /// The newest picture, lent until [unlock]; none when nothing new came.
    fn lock(&mut self, texture: u64) -> Option<WatchPlanes> {
        let picture = self.slots.get_mut(&texture)?.newest.take()?;
        let planes = picture.planes();
        // The one lent before is handed back with it, so a runner that forgot
        // an unlock holds one picture, not every one since.
        self.lent.insert(texture, picture);
        Some(planes)
    }

    /// The runner is done with the lent picture, having drawn it or not.
    /// True the first time it could not, for as long as [texture] is open:
    /// the one time to give up on drawing it.
    fn unlock(&mut self, texture: u64, drawn: bool) -> bool {
        self.lent.remove(&texture);
        match self.slots.get_mut(&texture) {
            Some(slot) if !drawn && !slot.failed => {
                slot.failed = true;
                true
            }
            _ => false,
        }
    }
}

static TABLE: Mutex<Option<Table<Box<dyn Picture>>>> = Mutex::new(None);

fn with_table<R>(f: impl FnOnce(&mut Table<Box<dyn Picture>>) -> R) -> R {
    let mut guard = TABLE.lock().unwrap_or_else(|e| e.into_inner());
    f(guard.get_or_insert_with(Table::new))
}

/// Start taking pictures for [texture], telling the runner through [mark].
pub(crate) fn open(texture: u64, mark: MarkFn) {
    with_table(|t| t.open(texture, Some(mark)));
}

/// Stop: once this returns, [texture]'s mark is not called again, so the
/// runner may let the texture go.
pub(crate) fn close(texture: u64) {
    with_table(|t| t.close(texture));
}

/// Whether any picture has come for [texture] since it was opened.
pub(crate) fn delivered(texture: u64) -> bool {
    with_table(|t| t.delivered(texture))
}

/// Hand the runner a new picture for [texture]. False when nothing watches it.
pub(crate) fn deliver(texture: u64, picture: impl Picture + 'static) -> bool {
    let picture: Box<dyn Picture> = Box::new(picture);
    // The mark is called under the lock, which is what makes [close] a fence:
    // it takes the same lock, so no mark is still running once it returns.
    // Marking only posts to Flutter's engine and never waits for a draw, and
    // a draw takes this lock without holding any of the engine's, so the two
    // cannot wait on each other.
    let mut guard = TABLE.lock().unwrap_or_else(|e| e.into_inner());
    let table = guard.get_or_insert_with(Table::new);
    match table.deliver(texture, picture) {
        Some(Some(mark)) => {
            // SAFETY: the runner gave this address for this texture, and keeps
            // the texture until [close] has returned.
            unsafe { mark(texture) };
            true
        }
        Some(None) => true,
        None => false,
    }
}

/// The runner, drawing: the newest picture for [texture] into [out], lent
/// until [rift_watch_frame_unlock]. Answers 1 with a new picture, and 0, with
/// [out] untouched, when none came since the last, so the runner shows what it
/// drew before.
///
/// # Safety
/// [out] points at a `WatchPlanes` the caller owns.
#[no_mangle]
pub unsafe extern "C" fn rift_watch_frame_lock(texture: u64, out: *mut WatchPlanes) -> i32 {
    if out.is_null() {
        return 0;
    }
    match with_table(|t| t.lock(texture)) {
        Some(planes) => {
            // SAFETY: checked non-null; the caller owns it.
            unsafe { out.write(planes) };
            1
        }
        None => 0,
    }
}

/// The runner has finished with the picture [rift_watch_frame_lock] lent:
/// [drawn] is 1, or 0 when it could not draw it: a GPU picture that would not
/// import or copy, or any picture once the runner's device is lost. The first
/// time, the app watches through the call instead.
#[no_mangle]
pub extern "C" fn rift_watch_frame_unlock(texture: u64, drawn: i32) {
    if with_table(|t| t.unlock(texture, drawn != 0)) {
        log::warn!("watching: the window could not draw a picture");
        super::session::lost("the window could not draw a picture");
    }
}

/// Where the runner finds the two functions above.
pub(crate) fn entry_points() -> (usize, usize) {
    let lock: unsafe extern "C" fn(u64, *mut WatchPlanes) -> i32 = rift_watch_frame_lock;
    let unlock: extern "C" fn(u64, i32) = rift_watch_frame_unlock;
    (lock as usize, unlock as usize)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    /// A picture that counts how many of its kind are alive.
    struct Fake {
        id: u32,
        alive: Arc<AtomicUsize>,
    }

    impl Fake {
        fn new(id: u32, alive: &Arc<AtomicUsize>) -> Fake {
            alive.fetch_add(1, Ordering::SeqCst);
            Fake {
                id,
                alive: alive.clone(),
            }
        }
    }

    impl Drop for Fake {
        fn drop(&mut self) {
            self.alive.fetch_sub(1, Ordering::SeqCst);
        }
    }

    impl Picture for Fake {
        fn planes(&self) -> WatchPlanes {
            WatchPlanes::sized(self.id, 0)
        }
    }

    #[test]
    fn a_slot_knows_whether_any_picture_came() {
        let alive = Arc::new(AtomicUsize::new(0));
        let mut table = Table::new();
        table.open(7, None);
        assert!(!table.delivered(7));
        table.deliver(7, Fake::new(1, &alive));
        assert!(table.lock(7).is_some());
        table.unlock(7, true);
        assert!(table.delivered(7), "taken and drawn, still came");
        table.open(7, None);
        assert!(!table.delivered(7), "opened again, nothing yet");
        assert!(!table.delivered(8), "nothing watches it");
    }

    #[test]
    fn a_slow_draw_gets_the_newest_picture_and_the_rest_are_let_go() {
        let alive = Arc::new(AtomicUsize::new(0));
        let mut table = Table::new();
        table.open(7, None);
        for id in 1..=5 {
            table.deliver(7, Fake::new(id, &alive));
        }
        assert_eq!(alive.load(Ordering::SeqCst), 1, "replaced, never queued");
        assert_eq!(table.lock(7).map(|p| p.width), Some(5));
        assert!(table.lock(7).is_none(), "nothing new since");
    }

    #[test]
    fn a_lent_picture_outlives_its_slot_until_handed_back() {
        let alive = Arc::new(AtomicUsize::new(0));
        let mut table = Table::new();
        table.open(7, None);
        table.deliver(7, Fake::new(1, &alive));
        assert!(table.lock(7).is_some());
        table.close(7);
        assert_eq!(alive.load(Ordering::SeqCst), 1, "still being uploaded");
        table.unlock(7, true);
        assert_eq!(alive.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn nothing_is_kept_for_a_texture_nobody_watches() {
        let alive = Arc::new(AtomicUsize::new(0));
        let mut table = Table::new();
        assert!(table.deliver(9, Fake::new(1, &alive)).is_none());
        assert_eq!(alive.load(Ordering::SeqCst), 0);
        assert!(table.lock(9).is_none());
        table.open(9, None);
        table.close(9);
        assert!(table.deliver(9, Fake::new(2, &alive)).is_none());
    }

    #[test]
    fn a_picture_the_runner_cannot_draw_gives_up_once() {
        let alive = Arc::new(AtomicUsize::new(0));
        let mut table = Table::new();
        table.open(7, None);
        table.deliver(7, Fake::new(1, &alive));
        assert!(table.lock(7).is_some());
        assert!(!table.unlock(7, true), "drawn");
        for (id, answer) in [(2, true), (3, false)] {
            table.deliver(7, Fake::new(id, &alive));
            assert!(table.lock(7).is_some());
            assert_eq!(table.unlock(7, false), answer, "picture {id}");
        }
        assert_eq!(alive.load(Ordering::SeqCst), 0, "handed back all the same");
        // Watched again, it may give up again.
        table.open(7, None);
        table.deliver(7, Fake::new(4, &alive));
        assert!(table.lock(7).is_some());
        assert!(table.unlock(7, false));
        // A texture already closed has nothing to give up.
        table.close(7);
        assert!(!table.unlock(7, false));
    }

    #[test]
    fn a_forgotten_unlock_holds_one_picture_not_every_one() {
        let alive = Arc::new(AtomicUsize::new(0));
        let mut table = Table::new();
        table.open(7, None);
        for id in 1..=3 {
            table.deliver(7, Fake::new(id, &alive));
            assert!(table.lock(7).is_some());
        }
        assert_eq!(alive.load(Ordering::SeqCst), 1);
    }
}
