//! A stop asked for while a switch waits on its new source.
//!
//! A switch holds the share while its new capture starts, and under Wayland
//! that is the desktop's picker, which waits on a person for up to ten
//! minutes. A stop waits for the share, so without this it would wait for
//! the picker too, with the old picture still going out.

use std::sync::atomic::{AtomicUsize, Ordering};

use tokio::sync::Notify;

pub(crate) struct Stops {
    /// Stops asked for and not yet through.
    asked: AtomicUsize,
    notify: Notify,
}

impl Stops {
    pub(crate) const fn new() -> Self {
        Self {
            asked: AtomicUsize::new(0),
            notify: Notify::const_new(),
        }
    }

    /// A stop is on its way. Anything waiting in [`asked`](Self::asked) hears
    /// it, and so does whatever starts waiting until the guard is dropped,
    /// which the stop holds until it has the share.
    pub(crate) fn begin(&self) -> StopGuard<'_> {
        self.asked.fetch_add(1, Ordering::SeqCst);
        self.notify.notify_waiters();
        StopGuard(self)
    }

    /// Resolves once a stop is asked for, at once if one already is.
    pub(crate) async fn asked(&self) {
        let notified = self.notify.notified();
        tokio::pin!(notified);
        // Registered before the count is read: a stop between the two is
        // heard either way.
        notified.as_mut().enable();
        if self.asked.load(Ordering::SeqCst) > 0 {
            return;
        }
        notified.await;
    }
}

pub(crate) struct StopGuard<'a>(&'a Stops);

impl Drop for StopGuard<'_> {
    fn drop(&mut self) {
        self.0.asked.fetch_sub(1, Ordering::SeqCst);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    const BRIEFLY: Duration = Duration::from_millis(50);

    async fn heard(stops: &Stops) -> bool {
        tokio::time::timeout(BRIEFLY, stops.asked()).await.is_ok()
    }

    #[tokio::test]
    async fn a_stop_asked_during_the_wait_ends_it() {
        let stops = Stops::new();
        let wait = stops.asked();
        tokio::pin!(wait);
        assert!(tokio::time::timeout(BRIEFLY, wait.as_mut()).await.is_err());
        let _stop = stops.begin();
        assert!(tokio::time::timeout(BRIEFLY, wait).await.is_ok());
    }

    #[tokio::test]
    async fn a_stop_asked_before_the_wait_still_ends_it() {
        let stops = Stops::new();
        let _stop = stops.begin();
        assert!(heard(&stops).await);
    }

    #[tokio::test]
    async fn a_stop_that_is_through_ends_no_later_wait() {
        let stops = Stops::new();
        drop(stops.begin());
        assert!(!heard(&stops).await);
    }
}
