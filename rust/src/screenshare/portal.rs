//! The ScreenCast portal, for a Wayland share on Rift's own PipeWire stream
//! (`docs/gpu-codecs/STEP2_LINUX.md`).
//!
//! A window share keeps Dart's picker (`WindowSharePortal`): it hands over the
//! restore token of the window picked there, and the session started here
//! with it shows no second picker. A screen share gets the picker here, where
//! libwebrtc's capturer ran it before. Tokens are never logged.
use std::os::fd::OwnedFd;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use futures_util::StreamExt;

use ashpd::desktop::screencast::{
    CursorMode, Screencast, SelectSourcesOptions, SourceType, StartCastOptions,
};
use ashpd::desktop::{CreateSessionOptions, PersistMode, ResponseError, Session};
use ashpd::enumflags2::BitFlags;
use ashpd::AppID;

use super::resolution::Size;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum PortalKind {
    Screen,
    Window,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum PortalError {
    /// The picker was closed without a choice.
    Cancelled,
    /// No portal, or it refused; the share runs on libwebrtc's capturer.
    Unavailable(String),
}

/// A started ScreenCast session: the PipeWire remote and the stream on it.
/// Dropping it closes the session, which ends the stream.
pub(crate) struct PortalSession {
    pub fd: OwnedFd,
    pub node_id: u32,
    /// The stream's size as the portal reports it, when it does.
    pub size: Option<Size>,
    /// The token to restore this choice with, when one was asked for.
    #[cfg_attr(not(test), allow(dead_code))]
    pub restore_token: Option<String>,
    session: Option<Arc<Session<Screencast>>>,
    /// The runtime that opened it, which drives ashpd's one D-Bus
    /// connection: the close goes there.
    runtime: Option<tokio::runtime::Handle>,
    /// Set when the desktop closes the session, which GNOME does when the
    /// shared window closes: the stream itself only pauses.
    closed: Arc<AtomicBool>,
    listening: Option<tokio::task::JoinHandle<()>>,
}

impl PortalSession {
    /// Whether the desktop has closed the session.
    pub(crate) fn closed(&self) -> bool {
        self.closed.load(Ordering::Relaxed)
    }

    /// A node on PipeWire's own socket rather than one the portal opened,
    /// for a test to stand in for a compositor.
    #[cfg(test)]
    pub(crate) fn of_node(fd: OwnedFd, node_id: u32) -> PortalSession {
        PortalSession {
            fd,
            node_id,
            size: None,
            restore_token: None,
            session: None,
            runtime: None,
            closed: Arc::new(AtomicBool::new(false)),
            listening: None,
        }
    }
}

impl Drop for PortalSession {
    fn drop(&mut self) {
        if let Some(listening) = self.listening.take() {
            listening.abort();
        }
        // A session the desktop closed is gone already.
        let Some(session) = self.session.take().filter(|_| !self.closed()) else {
            return;
        };
        // Closing is a D-Bus call; it goes on the runtime that opened it, or
        // on a thread of its own when there is none.
        let close = async move {
            if let Err(e) = session.close().await {
                log::warn!("portal: the ScreenCast session did not close: {e}");
            }
        };
        match self
            .runtime
            .take()
            .or_else(|| tokio::runtime::Handle::try_current().ok())
        {
            Some(runtime) => {
                runtime.spawn(close);
            }
            None => {
                std::thread::spawn(move || {
                    if let Ok(runtime) = tokio::runtime::Builder::new_current_thread()
                        .enable_all()
                        .build()
                    {
                        runtime.block_on(close);
                    }
                });
            }
        }
    }
}

/// What a portal failure means for the share.
pub(crate) fn error_of(error: ashpd::Error) -> PortalError {
    match error {
        ashpd::Error::Response(ResponseError::Cancelled) => PortalError::Cancelled,
        other => PortalError::Unavailable(other.to_string()),
    }
}

/// Rift's application id: `APPLICATION_ID` in `linux/CMakeLists.txt`, which
/// GTK registers for the app's main connection and Dart's picker for its own.
const APP_ID: &str = "com.codingfries.rift";

/// Names ashpd's connection to the portal as Rift, once per process. A pick
/// Dart's picker saved is saved for Rift and found only from a connection of
/// that name: unnamed, GNOME showed its picker a second time, as "An app".
/// Never fatal, as in Dart's `PortalRequests.register`: a sandboxed app or a
/// portal older than 1.20 goes on without it, and a second call is refused,
/// so a refusal is not asked again.
async fn register() {
    static REGISTERED: tokio::sync::OnceCell<()> = tokio::sync::OnceCell::const_new();
    REGISTERED
        .get_or_init(|| async {
            let registered = match AppID::try_from(APP_ID) {
                Ok(app_id) => ashpd::register_host_app(app_id).await,
                Err(e) => Err(e),
            };
            if let Err(e) = registered {
                log::info!("portal: not registered as {APP_ID}, going on: {e}");
            }
        })
        .await;
}

/// How long the portal is asked to keep a choice. A restored one is kept
/// while Rift runs, as libwebrtc's capturer asks: KDE ignores a restore
/// asked not to persist and shows its picker again (found Oct 30 in the KDE
/// VM; GNOME restores either way).
fn persist_mode(keep: bool, restoring: bool) -> PersistMode {
    if keep {
        PersistMode::ExplicitlyRevoked
    } else if restoring {
        PersistMode::Application
    } else {
        PersistMode::DoNot
    }
}

/// Starts a ScreenCast session: the picker, unless `restore_token` restores
/// an earlier choice. The cursor is drawn into the picture by the compositor
/// when `cursor`, and left out otherwise. With `keep` the portal is asked to
/// keep the choice, and hands back a token for it; GNOME forgets a saved
/// choice once its token is used, so a token is renewed only this way.
pub(crate) async fn open(
    kind: PortalKind,
    restore_token: Option<&str>,
    cursor: bool,
    keep: bool,
) -> Result<PortalSession, PortalError> {
    register().await;
    let screencast = Screencast::new().await.map_err(error_of)?;
    let session = Arc::new(
        screencast
            .create_session(CreateSessionOptions::default())
            .await
            .map_err(error_of)?,
    );
    // Listening before the session starts, so a close is not missed. The
    // signal's stream borrows the session, so the task holds it too.
    let closed = Arc::new(AtomicBool::new(false));
    let (listening_tx, listening_rx) = tokio::sync::oneshot::channel();
    let listening = {
        let session = session.clone();
        let closed = closed.clone();
        tokio::spawn(async move {
            let closing = session.receive_closed().await;
            let _ = listening_tx.send(());
            let closing = match closing {
                Ok(closing) => closing,
                Err(e) => {
                    log::warn!("portal: not told when the session closes: {e}");
                    return;
                }
            };
            // Boxed: `pin!` expands to `super let`, which the bridge generator cannot parse.
            let mut closing = Box::pin(closing);
            if closing.next().await.is_some() {
                log::info!("portal: the desktop closed the ScreenCast session");
                closed.store(true, Ordering::Relaxed);
            }
        })
    };
    let _ = listening_rx.await;
    let sources: BitFlags<SourceType> = match kind {
        PortalKind::Screen => SourceType::Monitor.into(),
        PortalKind::Window => SourceType::Window.into(),
    };
    let persist = persist_mode(keep, restore_token.is_some());
    let options = SelectSourcesOptions::default()
        .set_cursor_mode(if cursor {
            CursorMode::Embedded
        } else {
            CursorMode::Hidden
        })
        .set_sources(sources)
        .set_multiple(false)
        .set_persist_mode(persist)
        .set_restore_token(restore_token);
    let started = async {
        screencast
            .select_sources(&session, options)
            .await?
            .response()?;
        let streams = screencast
            .start(&session, None, StartCastOptions::default())
            .await?
            .response()?;
        let fd = screencast
            .open_pipe_wire_remote(&session, Default::default())
            .await?;
        Ok::<_, ashpd::Error>((streams, fd))
    }
    .await;
    // Closed here on a failure: no PortalSession owns it yet.
    let (streams, fd) = match started {
        Ok(started) => started,
        Err(e) => {
            listening.abort();
            let _ = session.close().await;
            return Err(error_of(e));
        }
    };
    let Some(stream) = streams.streams().first() else {
        listening.abort();
        let _ = session.close().await;
        return Err(PortalError::Unavailable("the portal gave no stream".into()));
    };
    let size = stream.size().and_then(|(w, h)| {
        (w > 0 && h > 0).then_some(Size {
            width: w as u32,
            height: h as u32,
        })
    });
    Ok(PortalSession {
        fd,
        node_id: stream.pipe_wire_node_id(),
        size,
        restore_token: streams.restore_token().map(str::to_owned),
        session: Some(session),
        runtime: tokio::runtime::Handle::try_current().ok(),
        closed,
        listening: Some(listening),
    })
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    #[test]
    fn a_cancelled_picker_is_cancelled() {
        assert_eq!(
            error_of(ashpd::Error::Response(ResponseError::Cancelled)),
            PortalError::Cancelled
        );
    }

    #[test]
    fn a_restored_pick_persists_while_the_app_runs() {
        // KDE shows its picker again for a restore asked not to persist.
        assert_eq!(persist_mode(false, true), PersistMode::Application);
        assert_eq!(persist_mode(false, false), PersistMode::DoNot);
        assert_eq!(persist_mode(true, true), PersistMode::ExplicitlyRevoked);
        assert_eq!(persist_mode(true, false), PersistMode::ExplicitlyRevoked);
    }

    #[test]
    fn a_missing_portal_is_unavailable() {
        let missing = ashpd::Error::Zbus(ashpd::zbus::Error::FDO(Box::new(
            ashpd::zbus::fdo::Error::ServiceUnknown("org.freedesktop.portal.Desktop".into()),
        )));
        assert!(matches!(error_of(missing), PortalError::Unavailable(_)));
        assert!(matches!(
            error_of(ashpd::Error::Response(ResponseError::Other)),
            PortalError::Unavailable(_)
        ));
    }

    /// The one runtime every live portal test runs on. ashpd keeps a single
    /// D-Bus connection for the process, driven by the runtime that opened
    /// it, so a second test on a runtime of its own would wait on a
    /// connection nothing drives. The app has one runtime for its life.
    pub(crate) fn live_runtime() -> &'static tokio::runtime::Runtime {
        static RUNTIME: std::sync::OnceLock<tokio::runtime::Runtime> = std::sync::OnceLock::new();
        RUNTIME.get_or_init(|| tokio::runtime::Runtime::new().unwrap())
    }

    fn check(session: &PortalSession) {
        use std::os::fd::AsRawFd;
        assert!(session.node_id > 0);
        assert!(session.fd.as_raw_fd() >= 0);
    }

    /// Shows the picker once, to make a token for `live_portal_restores_a_screen`,
    /// written to `RIFT_PORTAL_TOKEN_OUT` (never printed).
    #[test]
    #[ignore]
    fn live_portal_seed_token() {
        let session = live_runtime()
            .block_on(open(PortalKind::Screen, None, true, true))
            .expect("the portal opens");
        check(&session);
        let token = session.restore_token.as_deref().expect("a token");
        std::fs::write(std::env::var("RIFT_PORTAL_TOKEN_OUT").unwrap(), token).unwrap();
    }

    /// Restores the token in the file `RIFT_PORTAL_TOKEN` names, with no
    /// picker, and writes the renewed one to `RIFT_PORTAL_TOKEN_OUT`.
    #[test]
    #[ignore]
    fn live_portal_restores_a_screen() {
        let token = std::fs::read_to_string(std::env::var("RIFT_PORTAL_TOKEN").unwrap()).unwrap();
        let session = live_runtime()
            .block_on(open(PortalKind::Screen, Some(token.trim()), true, true))
            .expect("the portal restores the screen");
        check(&session);
        let renewed = session.restore_token.as_deref().expect("a new token");
        std::fs::write(std::env::var("RIFT_PORTAL_TOKEN_OUT").unwrap(), renewed).unwrap();
    }
}
