//! DPDFNet in a call, run on a thread of its own rather than on libwebrtc's
//! capture thread. On Windows that thread runs at time-critical priority, as
//! "Pro Audio", so a model run there took its 2 to 8 ms of every 10 ahead of
//! everything else on the computer, a game included: a tester's CS2
//! stuttered whenever they were in a call (bug report, Oct 24).
//!
//! The capture thread now hands each frame over and sleeps until it comes
//! back, for at most [`WAIT`], the time a run of the large model had on the
//! capture thread itself. The model's thread runs at normal priority, the
//! game's own, so a busy computer shares the cores between them rather than
//! putting either first. A frame not
//! back in time goes out unfiltered: a moment of the room in the call, which
//! is the price chosen over a stutter in the game. The large model's frames
//! are timed from the hand-over, so a computer that keeps them waiting moves
//! to DPDFNet-2 as one too slow for it always has.
//!
//! Where the model runs can be switched mid-call ([`Placement`], Settings →
//! Voice, Beta options; on Linux only the capture thread or Normal, since
//! nothing there runs above normal for an ordinary user): testers heard crackle and cut-outs
//! from a Windows friend on beta.9 (Oct 30), and comparing by ear is how to
//! tell whether the thread's priority is why.

use std::cell::UnsafeCell;
use std::sync::atomic::{AtomicU32, AtomicU8, AtomicUsize, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::thread::{self, Thread, ThreadId};
use std::time::{Duration, Instant};

use super::{Model, FRAME, SLOW_FRAME};

/// How long the capture thread waits for a frame.
const WAIT: Duration = SLOW_FRAME;

/// Frames in flight each way. The model's thread only takes the newest, so
/// a frame waits here only while that thread is not getting the CPU.
const SLOTS: usize = 4;

/// Frames that went out unfiltered since the last [`take_unfiltered`]: late,
/// or the model failing on them.
static UNFILTERED: AtomicU32 = AtomicU32::new(0);

/// How many frames went out unfiltered, starting the count again.
pub(super) fn take_unfiltered() -> u32 {
    UNFILTERED.swap(0, Ordering::Relaxed)
}

/// Where the model runs, as chosen in settings.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Placement {
    /// On libwebrtc's capture thread itself, as before beta.5: time-critical
    /// on Windows, and never late, but ahead of a game. On Linux that thread
    /// is at normal like the model's own, so what changes is only the wait.
    CaptureThread,
    /// On its own thread at Windows' highest priority below time-critical.
    Highest,
    /// On its own thread, one step above a game's.
    AboveNormal,
    /// On its own thread at a game's own priority, where it starts.
    Normal,
}

impl Placement {
    fn from_u8(value: u8) -> Placement {
        match value {
            0 => Placement::CaptureThread,
            1 => Placement::Highest,
            2 => Placement::AboveNormal,
            _ => Placement::Normal,
        }
    }

    fn to_u8(self) -> u8 {
        match self {
            Placement::CaptureThread => 0,
            Placement::Highest => 1,
            Placement::AboveNormal => 2,
            Placement::Normal => 3,
        }
    }
}

static PLACEMENT: AtomicU8 = AtomicU8::new(3);

/// Moves the model, from the next frame on.
pub(super) fn place(placement: Placement) {
    PLACEMENT.store(placement.to_u8(), Ordering::Relaxed);
}

fn placement() -> Placement {
    Placement::from_u8(PLACEMENT.load(Ordering::Relaxed))
}

/// A frame as the capture thread handed it over.
#[derive(Clone, Copy)]
struct Handed {
    seq: u64,
    at: Instant,
    /// Start the model over first: the microphone started again.
    reset: bool,
    frame: [f32; FRAME],
}

/// A frame back from the model; `ok` false when the model failed on it.
#[derive(Clone, Copy)]
struct Cleaned {
    seq: u64,
    ok: bool,
    frame: [f32; FRAME],
}

/// Frames from one thread to one other, without a lock: the capture thread
/// must never wait on the model's thread holding one, which on Windows runs
/// below it.
struct Ring<T> {
    slots: [UnsafeCell<T>; SLOTS],
    written: AtomicUsize,
    read: AtomicUsize,
}

// SAFETY: one thread pushes and one pops (`Handoff` is behind a mutex on the
// capture side, and the model's thread is the only other), and a slot is
// written only while the reader cannot reach it.
unsafe impl<T: Send> Sync for Ring<T> {}

impl<T: Copy> Ring<T> {
    fn new(fill: T) -> Ring<T> {
        Ring {
            slots: std::array::from_fn(|_| UnsafeCell::new(fill)),
            written: AtomicUsize::new(0),
            read: AtomicUsize::new(0),
        }
    }

    /// False, with nothing added, when the ring is full.
    fn push(&self, item: T) -> bool {
        let written = self.written.load(Ordering::Relaxed);
        if written - self.read.load(Ordering::Acquire) == SLOTS {
            return false;
        }
        // SAFETY: the reader stops short of `written`, so this slot is ours.
        unsafe { *self.slots[written % SLOTS].get() = item };
        self.written.store(written + 1, Ordering::Release);
        true
    }

    fn pop(&self) -> Option<T> {
        let read = self.read.load(Ordering::Relaxed);
        if read == self.written.load(Ordering::Acquire) {
            return None;
        }
        // SAFETY: the writer finished this slot before moving `written` past
        // it, and leaves it alone until `read` moves on.
        let item = unsafe { *self.slots[read % SLOTS].get() };
        self.read.store(read + 1, Ordering::Release);
        Some(item)
    }
}

struct Shared {
    /// Run by the model's thread, or by the capture thread while the model
    /// is placed there; each takes it only then, so neither waits for it but
    /// for a frame at the moment of a switch.
    model: Mutex<Model>,
    handed: Ring<Handed>,
    cleaned: Ring<Cleaned>,
    /// The capture thread, for the model's thread to wake when a frame is
    /// back. libwebrtc makes a new one when the microphone changes.
    waiter: Mutex<Option<Thread>>,
}

/// The capture thread's side.
pub(super) struct Handoff {
    shared: Arc<Shared>,
    worker: Thread,
    seq: u64,
    reset: bool,
    /// The last frame as it came in, which goes out in place of a late one:
    /// the model's window holds the voice back a frame, so this is the one
    /// its output would have matched.
    previous: [f32; FRAME],
    waiter: Option<ThreadId>,
    /// Whether the last frame ran here, on the capture thread.
    ran_here: bool,
}

impl Handoff {
    /// Moves `model` onto a thread of its own.
    pub(super) fn start(model: Model) -> Result<Handoff, String> {
        let silence = [0.0; FRAME];
        let shared = Arc::new(Shared {
            model: Mutex::new(model),
            handed: Ring::new(Handed {
                seq: 0,
                at: Instant::now(),
                reset: false,
                frame: silence,
            }),
            cleaned: Ring::new(Cleaned {
                seq: 0,
                ok: false,
                frame: silence,
            }),
            waiter: Mutex::new(None),
        });
        let theirs = Arc::clone(&shared);
        let (ready, warmed) = mpsc::channel();
        let worker = thread::Builder::new()
            .name("rift-dpdfnet".to_string())
            .spawn(move || run(&theirs, ready))
            .map_err(|e| format!("DPDFNet's thread did not start: {e}"))?;
        // Not handed a frame before it has warmed up, or the call's first
        // few go out unfiltered.
        warmed
            .recv()
            .map_err(|_| "DPDFNet's thread stopped".to_string())?;
        Ok(Handoff {
            shared,
            worker: worker.thread().clone(),
            seq: 0,
            reset: true,
            previous: silence,
            waiter: None,
            ran_here: false,
        })
    }

    /// Filters `frame`, or when the model's frame is late puts the last one
    /// as it came in there instead. True when the model's frame went out.
    pub(super) fn process(&mut self, frame: &mut [f32; FRAME]) -> bool {
        let here = placement() == Placement::CaptureThread;
        if here != self.ran_here {
            // The model missed what went past while the other thread had
            // it, and carries on from what it heard before.
            self.ran_here = here;
            self.reset = true;
        }
        if here {
            return self.process_here(frame);
        }
        let at = Instant::now();
        self.note_waiter();
        self.seq += 1;
        let handed = Handed {
            seq: self.seq,
            at,
            reset: self.reset,
            frame: *frame,
        };
        // Full only when the model's thread is far behind; the gap it finds
        // starts the model over.
        if self.shared.handed.push(handed) {
            self.reset = false;
        }
        self.worker.unpark();
        let raw = *frame;
        let back = self.wait(at + WAIT, frame);
        if !back {
            *frame = self.previous;
            UNFILTERED.fetch_add(1, Ordering::Relaxed);
        }
        self.previous = raw;
        back
    }

    /// Runs the model on this thread. Its thread may still be finishing a
    /// frame from before the switch; this one then goes out unfiltered, as
    /// a late one would.
    fn process_here(&mut self, frame: &mut [f32; FRAME]) -> bool {
        let raw = *frame;
        let ok = match self.shared.model.try_lock() {
            Ok(mut model) => {
                if self.reset {
                    model.reset();
                    self.reset = false;
                }
                model.process(frame)
            }
            Err(_) => false,
        };
        if !ok {
            *frame = self.previous;
            UNFILTERED.fetch_add(1, Ordering::Relaxed);
        }
        self.previous = raw;
        ok
    }

    /// For when the microphone starts again: the model starts from nothing.
    pub(super) fn reset(&mut self) {
        self.reset = true;
        self.previous = [0.0; FRAME];
    }

    /// Waits for this frame from the model's thread, asleep. Frames for
    /// earlier ones, too late to use, are dropped on the way.
    fn wait(&self, until: Instant, frame: &mut [f32; FRAME]) -> bool {
        loop {
            while let Some(cleaned) = self.shared.cleaned.pop() {
                if cleaned.seq == self.seq {
                    if cleaned.ok {
                        *frame = cleaned.frame;
                    }
                    return cleaned.ok;
                }
            }
            let now = Instant::now();
            if now >= until {
                return false;
            }
            thread::park_timeout(until - now);
        }
    }

    /// Tells the model's thread which thread to wake, when that changed. It
    /// never waits for the lock: missed, this frame waits out [`WAIT`] and
    /// the next one tries again.
    fn note_waiter(&mut self) {
        let me = thread::current();
        if self.waiter == Some(me.id()) {
            return;
        }
        if let Ok(mut waiter) = self.shared.waiter.try_lock() {
            self.waiter = Some(me.id());
            *waiter = Some(me);
        }
    }
}

/// The model's thread: runs the newest frame handed over, and skips the
/// rest, which could not be back in time anyway.
fn run(shared: &Shared, ready: mpsc::Sender<()>) {
    let mut priority = placement();
    set_priority(priority);
    if let Ok(mut model) = shared.model.lock() {
        model.warm_up();
    }
    let _ = ready.send(());
    let mut last = 0;
    loop {
        let Some(mut handed) = newest(&shared.handed) else {
            thread::park();
            continue;
        };
        let now = placement();
        if now != priority {
            priority = now;
            set_priority(priority);
        }
        let Ok(mut model) = shared.model.lock() else {
            return;
        };
        // A skipped frame leaves a hole in what the model has heard, which
        // it would carry on from.
        if handed.reset || handed.seq != last + 1 {
            model.reset();
        }
        last = handed.seq;
        let ok = model.process_handed(&mut handed.frame, handed.at);
        drop(model);
        let _ = shared.cleaned.push(Cleaned {
            seq: handed.seq,
            ok,
            frame: handed.frame,
        });
        if let Ok(waiter) = shared.waiter.lock() {
            if let Some(waiter) = waiter.as_ref() {
                waiter.unpark();
            }
        }
    }
}

fn newest(ring: &Ring<Handed>) -> Option<Handed> {
    let mut newest = ring.pop()?;
    let mut reset = newest.reset;
    while let Some(next) = ring.pop() {
        reset |= next.reset;
        newest = next;
    }
    newest.reset = reset;
    Some(newest)
}

/// Normal, a game's own priority, unless settings place it higher; said
/// outright rather than left to the default. Below normal, a game holding
/// every core would keep the model from its frames, and the room would come
/// through when the game is busiest; above it, the model takes its turn
/// ahead of the game again. While the model is on the capture thread, its
/// own thread has nothing to run and keeps the priority it had. Linux gives
/// the capture thread no such priority to begin with, and the thread is left
/// as it starts.
#[cfg(target_os = "windows")]
fn set_priority(placement: Placement) {
    use windows::Win32::System::Threading::{
        GetCurrentThread, SetThreadPriority, THREAD_PRIORITY_ABOVE_NORMAL, THREAD_PRIORITY_HIGHEST,
        THREAD_PRIORITY_NORMAL,
    };
    let priority = match placement {
        Placement::CaptureThread => return,
        Placement::Highest => THREAD_PRIORITY_HIGHEST,
        Placement::AboveNormal => THREAD_PRIORITY_ABOVE_NORMAL,
        Placement::Normal => THREAD_PRIORITY_NORMAL,
    };
    // SAFETY: this thread's own pseudo-handle. A refusal leaves it as it is.
    let _ = unsafe { SetThreadPriority(GetCurrentThread(), priority) };
}

#[cfg(not(target_os = "windows"))]
fn set_priority(_: Placement) {}

#[cfg(test)]
mod tests {
    use super::*;

    /// Back to Normal however the test ends, for the other model tests.
    struct PlacedBack;

    impl Drop for PlacedBack {
        fn drop(&mut self) {
            place(Placement::Normal);
        }
    }

    /// A steady, noise-like signal on the 16-bit scale.
    fn noise(seed: &mut u32) -> [f32; FRAME] {
        let mut frame = [0.0f32; FRAME];
        for s in frame.iter_mut() {
            *seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            *s = ((*seed >> 16) as f32 / 65536.0 - 0.5) * 2000.0;
        }
        frame
    }

    // RIFT_ONNXRUNTIME=<path to libonnxruntime.so> cargo test --release
    // dpdfnet -- --ignored --test-threads=1
    #[test]
    #[ignore = "needs ONNX Runtime at RIFT_ONNXRUNTIME"]
    fn placed_on_the_capture_thread_it_filters_every_frame_there() {
        let _back = PlacedBack;
        let mut handoff = Handoff::start(Model::new().unwrap()).unwrap();
        let mut alone = Model::new().unwrap();
        let mut seed = 7u32;
        place(Placement::CaptureThread);
        for i in 0..100 {
            let (mut here, mut there) = (noise(&mut seed), [0.0; FRAME]);
            there.copy_from_slice(&here);
            assert!(handoff.process(&mut here), "frame {i} went out unfiltered");
            assert!(alone.process(&mut there));
            assert!(here == there, "frame {i} is not what the model gives");
        }
        assert_eq!(handoff.seq, 0, "frames were handed to the model's thread");

        place(Placement::Normal);
        let back = (0..50)
            .filter(|_| handoff.process(&mut noise(&mut seed)))
            .count();
        assert_eq!(handoff.seq, 50);
        assert!(back >= 40, "only {back} of 50 frames back from its thread");
    }

    #[test]
    fn each_placement_reads_back_as_itself() {
        for placement in [
            Placement::CaptureThread,
            Placement::Highest,
            Placement::AboveNormal,
            Placement::Normal,
        ] {
            assert_eq!(Placement::from_u8(placement.to_u8()), placement);
        }
    }

    #[test]
    fn a_ring_hands_frames_over_in_order_until_full() {
        let ring = Ring::new(0u32);
        for i in 1..=SLOTS as u32 {
            assert!(ring.push(i));
        }
        assert!(!ring.push(99));
        assert_eq!(ring.pop(), Some(1));
        assert!(ring.push(5));
        assert_eq!(
            std::iter::from_fn(|| ring.pop()).collect::<Vec<_>>(),
            vec![2, 3, 4, 5]
        );
    }

    #[test]
    fn the_model_takes_the_newest_frame_and_keeps_a_reset() {
        let ring = Ring::new(Handed {
            seq: 0,
            at: Instant::now(),
            reset: false,
            frame: [0.0; FRAME],
        });
        for seq in 1..=3 {
            ring.push(Handed {
                seq,
                at: Instant::now(),
                reset: seq == 1,
                frame: [seq as f32; FRAME],
            });
        }
        let taken = newest(&ring).unwrap();
        assert_eq!(taken.seq, 3);
        assert!(taken.reset);
        assert_eq!(taken.frame[0], 3.0);
        assert!(newest(&ring).is_none());
    }
}
