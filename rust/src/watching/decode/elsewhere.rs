//! No GPU decoder here yet: the watch connection decodes with libwebrtc's own.

use super::super::frames::{Picture, WatchPlanes};
use super::Codec;
use std::convert::Infallible;

pub(super) fn device() -> Result<String, String> {
    Err("not built for this system yet".to_string())
}

pub(crate) struct Decoder(Infallible);

pub(crate) enum DecodeError {
    NoGpuDecoder,
    Failed(i32),
}

impl Decoder {
    pub(crate) fn open(_codec: Codec, _device: &str) -> Result<Decoder, String> {
        Err("no GPU decoder on this system".to_string())
    }

    pub(crate) fn driver(&self) -> String {
        match self.0 {}
    }

    pub(crate) fn decode(&mut self, _: &[u8], _: i64) -> Result<Vec<Decoded>, DecodeError> {
        match self.0 {}
    }
}

pub(crate) enum Decoded {}

impl Decoded {
    pub(crate) fn size(&self) -> (u32, u32) {
        match *self {}
    }
}

impl Picture for Decoded {
    fn planes(&self) -> WatchPlanes {
        match *self {}
    }
}
