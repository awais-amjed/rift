//! No GPU decoder here yet: the watch connection decodes with libwebrtc's own.

use super::super::frames::{Picture, WatchPlanes};
use super::Codec;
use std::convert::Infallible;

pub(super) fn device() -> Result<Gpu, String> {
    Err("not built for this system yet".to_string())
}

#[derive(Debug)]
pub(crate) enum Gpu {}

impl std::fmt::Display for Gpu {
    fn fmt(&self, _: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match *self {}
    }
}

pub(crate) struct Decoder(Infallible);

// Named by the decoding loop, which no decoder here reaches.
#[allow(dead_code)]
pub(crate) enum DecodeError {
    NoGpuDecoder,
    Failed(i32),
}

impl Decoder {
    pub(crate) fn open(_codec: Codec, _gpu: &Gpu) -> Result<Decoder, String> {
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
