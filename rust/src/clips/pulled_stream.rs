//! A chat video's [`Source`] as a COM `IStream`, which Media Foundation
//! wraps in the byte stream the Media Engine reads from
//! (`MFCreateMFByteStreamOnStream`). Media Foundation reads it on its own
//! work queue threads, so a read may wait there while the app fetches what
//! it has not got.
use super::source::{ReadError, Source};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use windows::core::{implement, Ref, Result, HRESULT};
use windows::Win32::Foundation::{
    E_NOTIMPL, STG_E_ACCESSDENIED, STG_E_INVALIDFUNCTION, STG_E_INVALIDPOINTER, STG_E_READFAULT,
    S_FALSE, S_OK,
};
use windows::Win32::System::Com::{
    ISequentialStream_Impl, IStream, IStream_Impl, LOCKTYPE, STATFLAG, STATSTG, STGC, STGTY_STREAM,
    STREAM_SEEK, STREAM_SEEK_CUR, STREAM_SEEK_END, STREAM_SEEK_SET,
};

#[implement(IStream)]
pub(super) struct PulledStream {
    file: Arc<Source>,
    position: AtomicU64,
}

impl PulledStream {
    pub(super) fn new(file: Arc<Source>) -> IStream {
        PulledStream {
            file,
            position: AtomicU64::new(0),
        }
        .into()
    }
}

impl ISequentialStream_Impl for PulledStream_Impl {
    /// Fills all [cb] bytes unless the file ends first, which is what a
    /// short read means to a stream's reader.
    fn Read(&self, pv: *mut core::ffi::c_void, cb: u32, pcbread: *mut u32) -> HRESULT {
        if pv.is_null() {
            return STG_E_INVALIDPOINTER;
        }
        let mut done = 0usize;
        let wanted = cb as usize;
        let start = self.position.load(Ordering::SeqCst);
        let mut failed = None;
        while done < wanted {
            match self.file.read_at(start + done as u64, wanted - done) {
                Ok(span) if span.is_empty() => break,
                Ok(span) => {
                    // SAFETY: the caller's buffer holds [cb] bytes, and
                    // [done] + the span stays within them.
                    unsafe {
                        std::ptr::copy_nonoverlapping(
                            span.as_ref().as_ptr(),
                            (pv as *mut u8).add(done),
                            span.len(),
                        );
                    }
                    done += span.len();
                }
                Err(ReadError::Closed) => {
                    failed = Some(STG_E_ACCESSDENIED);
                    break;
                }
                Err(ReadError::Failed(why)) => {
                    log::warn!("Chat video read failed: {why}");
                    failed = Some(STG_E_READFAULT);
                    break;
                }
            }
        }
        self.position.store(start + done as u64, Ordering::SeqCst);
        if !pcbread.is_null() {
            // SAFETY: checked non-null; the caller's out.
            unsafe { *pcbread = done as u32 };
        }
        match failed {
            Some(error) if done == 0 => error,
            _ if done < wanted => S_FALSE,
            _ => S_OK,
        }
    }

    fn Write(&self, _pv: *const core::ffi::c_void, _cb: u32, _written: *mut u32) -> HRESULT {
        STG_E_ACCESSDENIED
    }
}

impl IStream_Impl for PulledStream_Impl {
    fn Seek(&self, distance: i64, origin: STREAM_SEEK, new_position: *mut u64) -> Result<()> {
        let base = match origin {
            STREAM_SEEK_SET => 0i128,
            STREAM_SEEK_CUR => self.position.load(Ordering::SeqCst) as i128,
            STREAM_SEEK_END => self.file.len() as i128,
            _ => return Err(STG_E_INVALIDFUNCTION.into()),
        };
        let to = base + distance as i128;
        if to < 0 {
            return Err(STG_E_INVALIDFUNCTION.into());
        }
        let to = to as u64;
        self.position.store(to, Ordering::SeqCst);
        if !new_position.is_null() {
            // SAFETY: checked non-null; the caller's out.
            unsafe { *new_position = to };
        }
        Ok(())
    }

    fn SetSize(&self, _size: u64) -> Result<()> {
        Err(STG_E_ACCESSDENIED.into())
    }

    fn CopyTo(&self, _to: Ref<IStream>, _cb: u64, _read: *mut u64, _written: *mut u64) -> Result<()> {
        Err(E_NOTIMPL.into())
    }

    fn Commit(&self, _flags: &STGC) -> Result<()> {
        Ok(())
    }

    fn Revert(&self) -> Result<()> {
        Ok(())
    }

    fn LockRegion(&self, _offset: u64, _cb: u64, _kind: &LOCKTYPE) -> Result<()> {
        Err(STG_E_INVALIDFUNCTION.into())
    }

    fn UnlockRegion(&self, _offset: u64, _cb: u64, _kind: u32) -> Result<()> {
        Err(STG_E_INVALIDFUNCTION.into())
    }

    fn Stat(&self, stat: *mut STATSTG, _flag: &STATFLAG) -> Result<()> {
        if stat.is_null() {
            return Err(STG_E_INVALIDPOINTER.into());
        }
        // SAFETY: checked non-null; the caller's out. No name is given, so
        // there is nothing for the caller to free.
        unsafe {
            *stat = STATSTG {
                r#type: STGTY_STREAM.0 as u32,
                cbSize: self.file.len(),
                ..Default::default()
            };
        }
        Ok(())
    }

    fn Clone(&self) -> Result<IStream> {
        let copy = PulledStream {
            file: self.file.clone(),
            position: AtomicU64::new(self.position.load(Ordering::SeqCst)),
        };
        Ok(copy.into())
    }
}
