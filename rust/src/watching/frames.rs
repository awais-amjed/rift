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
//! [`entry_points`], as it finds DPDFNet's.
use livekit::webrtc::prelude::{I420Buffer, VideoBuffer};
use std::collections::HashMap;
use std::sync::Mutex;

/// The runner's "a new picture is waiting" for one texture: it marks the
/// texture so Flutter asks for it on its next frame. Safe from any thread.
pub(crate) type MarkFn = unsafe extern "C" fn(texture: u64);

/// One picture's three planes as the runner uploads them: I420, the chroma
/// planes half the size each way, rounded up.
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
}

/// What a slot holds: anything with three planes. A trait so the slot rules
/// can be tested without a decoder.
pub(crate) trait Picture: Send {
    fn planes(&self) -> WatchPlanes;
}

impl Picture for I420Buffer {
    fn planes(&self) -> WatchPlanes {
        let (y, u, v) = self.data();
        let (stride_y, stride_u, stride_v) = self.strides();
        WatchPlanes {
            width: self.width(),
            height: self.height(),
            y: y.as_ptr(),
            u: u.as_ptr(),
            v: v.as_ptr(),
            stride_y,
            stride_u,
            stride_v,
        }
    }
}

struct Slot<P> {
    newest: Option<P>,
    mark: Option<MarkFn>,
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
        self.slots.insert(texture, Slot { newest: None, mark });
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
        Some(slot.mark)
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

    fn unlock(&mut self, texture: u64) {
        self.lent.remove(&texture);
    }
}

static TABLE: Mutex<Option<Table<I420Buffer>>> = Mutex::new(None);

fn with_table<R>(f: impl FnOnce(&mut Table<I420Buffer>) -> R) -> R {
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

/// Hand the runner a new picture for [texture]. False when nothing watches it.
pub(crate) fn deliver(texture: u64, picture: I420Buffer) -> bool {
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

/// The runner has finished uploading the picture [rift_watch_frame_lock] lent.
#[no_mangle]
pub extern "C" fn rift_watch_frame_unlock(texture: u64) {
    with_table(|t| t.unlock(texture));
}

/// Where the runner finds the two functions above.
pub(crate) fn entry_points() -> (usize, usize) {
    let lock: unsafe extern "C" fn(u64, *mut WatchPlanes) -> i32 = rift_watch_frame_lock;
    let unlock: extern "C" fn(u64) = rift_watch_frame_unlock;
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
            WatchPlanes {
                width: self.id,
                height: 0,
                y: std::ptr::null(),
                u: std::ptr::null(),
                v: std::ptr::null(),
                stride_y: 0,
                stride_u: 0,
                stride_v: 0,
            }
        }
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
        table.unlock(7);
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
