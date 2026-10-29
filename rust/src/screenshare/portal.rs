//! The ScreenCast portal, for a Wayland share on Rift's own PipeWire stream
//! (`docs/gpu-codecs/STEP2_LINUX.md`).
//!
//! A window share keeps Dart's picker (`WindowSharePortal`): it hands over the
//! restore token of the window picked there, and the session started here
//! with it shows no second picker. A screen share gets the picker here, where
//! libwebrtc's capturer ran it before. Tokens are never logged.
// Used by the share from Task 5 of the step 2 plan (capture_pw.rs).
#![allow(dead_code)]

use std::os::fd::OwnedFd;

use ashpd::desktop::screencast::{
    CursorMode, Screencast, SelectSourcesOptions, SourceType, StartCastOptions,
};
use ashpd::desktop::{CreateSessionOptions, PersistMode, ResponseError, Session};
use ashpd::enumflags2::BitFlags;

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
    pub restore_token: Option<String>,
    session: Option<Session<Screencast>>,
}

impl Drop for PortalSession {
    fn drop(&mut self) {
        let Some(session) = self.session.take() else {
            return;
        };
        // Closing is a D-Bus call; it goes on the runtime that opened it, or
        // on a thread of its own when there is none.
        let close = async move {
            if let Err(e) = session.close().await {
                log::warn!("portal: the ScreenCast session did not close: {e}");
            }
        };
        match tokio::runtime::Handle::try_current() {
            Ok(runtime) => {
                runtime.spawn(close);
            }
            Err(_) => {
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

/// Starts a ScreenCast session: the picker, unless `restore_token` restores
/// an earlier choice. The cursor is drawn into the picture by the compositor
/// when `cursor`, and left out otherwise.
pub(crate) async fn open(
    kind: PortalKind,
    restore_token: Option<&str>,
    cursor: bool,
) -> Result<PortalSession, PortalError> {
    // A given token is renewed: GNOME forgets a saved choice once its token
    // is used, and returns a new one only when asked to keep it.
    open_keeping(kind, restore_token, cursor, restore_token.is_some()).await
}

/// `open`, asking the portal to keep the choice when `keep`.
async fn open_keeping(
    kind: PortalKind,
    restore_token: Option<&str>,
    cursor: bool,
    keep: bool,
) -> Result<PortalSession, PortalError> {
    let screencast = Screencast::new().await.map_err(error_of)?;
    let session = screencast
        .create_session(CreateSessionOptions::default())
        .await
        .map_err(error_of)?;
    let sources: BitFlags<SourceType> = match kind {
        PortalKind::Screen => SourceType::Monitor.into(),
        PortalKind::Window => SourceType::Window.into(),
    };
    let persist = if keep {
        PersistMode::ExplicitlyRevoked
    } else {
        PersistMode::DoNot
    };
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
    let (streams, fd) = match started {
        Ok(started) => started,
        Err(e) => {
            // Closed here: no PortalSession owns it yet.
            let _ = session.close().await;
            return Err(error_of(e));
        }
    };
    let Some(stream) = streams.streams().first() else {
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
            .block_on(open_keeping(PortalKind::Screen, None, true, true))
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
            .block_on(open(PortalKind::Screen, Some(token.trim()), true))
            .expect("the portal restores the screen");
        check(&session);
        let renewed = session.restore_token.as_deref().expect("a new token");
        std::fs::write(std::env::var("RIFT_PORTAL_TOKEN_OUT").unwrap(), renewed).unwrap();
    }
}
