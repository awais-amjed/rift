//! A one-slot mailbox between a thread making pictures and the one using
//! them. A newer picture replaces the one waiting, since a picture that waited
//! behind a newer one is only delay. Shaped like `mpsc`: dropping the putter
//! is what ends the taker's loop.
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

struct Slot<T> {
    item: Option<T>,
    /// Either side is gone. Nothing is handed over after this.
    closed: bool,
}

type Shared<T> = Arc<(Mutex<Slot<T>>, Condvar)>;

/// The side that leaves items.
pub(crate) struct Putter<T> {
    shared: Shared<T>,
}

/// The side that takes them.
pub(crate) struct Taker<T> {
    shared: Shared<T>,
}

/// One waiting item, replaced by each newer one: for pictures, where an older
/// one waiting is only delay.
pub(crate) fn channel<T>() -> (Putter<T>, Taker<T>) {
    let shared = Arc::new((
        Mutex::new(Slot {
            item: None,
            closed: false,
        }),
        Condvar::new(),
    ));
    (
        Putter {
            shared: shared.clone(),
        },
        Taker { shared },
    )
}

impl<T> Putter<T> {
    /// Leave `item` for the taker. Hands back what it replaced, or `item`
    /// itself once the taker is gone, so the caller can recycle its buffer.
    pub(crate) fn put(&self, item: T) -> Option<T> {
        let (slot, ready) = &*self.shared;
        let mut slot = slot.lock().unwrap();
        if slot.closed {
            return Some(item);
        }
        let replaced = slot.item.replace(item);
        ready.notify_one();
        replaced
    }
}

impl<T> Drop for Putter<T> {
    fn drop(&mut self) {
        let (slot, ready) = &*self.shared;
        slot.lock().unwrap().closed = true;
        ready.notify_one();
    }
}

impl<T> Taker<T> {
    /// The waiting item, waiting for one. `None` once the putter is gone,
    /// even with an item still waiting: it is dropped with the mailbox.
    pub(crate) fn take(&self) -> Option<T> {
        let (slot, ready) = &*self.shared;
        let mut slot = slot.lock().unwrap();
        loop {
            if slot.closed {
                return None;
            }
            if let Some(item) = slot.item.take() {
                return Some(item);
            }
            slot = ready.wait(slot).unwrap();
        }
    }

    /// `take`, waiting no longer than `wait`: `None` when nothing came in
    /// time, as well as once the putter is gone ([`closed`](Self::closed)
    /// tells the two apart).
    pub(crate) fn take_timeout(&self, wait: Duration) -> Option<T> {
        let deadline = Instant::now() + wait;
        let (slot, ready) = &*self.shared;
        let mut slot = slot.lock().unwrap();
        loop {
            if slot.closed {
                return None;
            }
            if let Some(item) = slot.item.take() {
                return Some(item);
            }
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return None;
            }
            slot = ready.wait_timeout(slot, left).unwrap().0;
        }
    }

    /// Whether the putter is gone, so nothing more will come.
    pub(crate) fn closed(&self) -> bool {
        self.shared.0.lock().unwrap().closed
    }
}

impl<T> Drop for Taker<T> {
    fn drop(&mut self) {
        let (slot, _) = &*self.shared;
        let mut slot = slot.lock().unwrap();
        slot.closed = true;
        // Dropped here rather than whenever the putter goes.
        slot.item = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;
    use std::thread;
    use std::time::{Duration, Instant};

    #[test]
    fn the_newest_picture_replaces_the_one_waiting() {
        let (putter, taker) = channel();
        assert_eq!(putter.put(1), None);
        assert_eq!(putter.put(2), Some(1));
        assert_eq!(taker.take(), Some(2));
    }

    #[test]
    fn take_waits_for_a_picture() {
        let (putter, taker) = channel();
        let started = Instant::now();
        let put = thread::spawn(move || {
            thread::sleep(Duration::from_millis(20));
            putter.put(7);
            putter
        });
        assert_eq!(taker.take(), Some(7));
        assert!(started.elapsed() >= Duration::from_millis(20));
        drop(put.join().unwrap());
    }

    #[test]
    fn dropping_the_putter_ends_a_waiting_take() {
        let (putter, taker) = channel::<u32>();
        let (done_tx, done_rx) = mpsc::channel();
        let waiting = thread::spawn(move || done_tx.send(taker.take()).unwrap());
        thread::sleep(Duration::from_millis(20));
        drop(putter);
        let taken = done_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("take hung after the putter went");
        assert_eq!(taken, None);
        waiting.join().unwrap();
    }

    #[test]
    fn a_closed_mailbox_drops_what_waits_in_it() {
        let (putter, taker) = channel();
        putter.put(1);
        drop(putter);
        assert_eq!(taker.take(), None);
    }

    #[test]
    fn take_timeout_returns_none_when_quiet() {
        let (putter, taker) = channel();
        let started = Instant::now();
        assert_eq!(taker.take_timeout(Duration::from_millis(30)), None);
        assert!(started.elapsed() >= Duration::from_millis(30));
        assert!(!taker.closed());
        putter.put(5);
        assert_eq!(taker.take_timeout(Duration::from_millis(30)), Some(5));
        drop(putter);
        assert_eq!(taker.take_timeout(Duration::from_millis(30)), None);
        assert!(taker.closed());
    }

    #[test]
    fn a_put_after_the_taker_went_comes_back() {
        let (putter, taker) = channel();
        drop(taker);
        assert_eq!(putter.put(3), Some(3));
    }
}
