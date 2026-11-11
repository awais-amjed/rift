//! No chat video player on this platform yet: opening one fails, and the
//! app offers the file to save instead (`super::AVAILABLE`).

pub(crate) struct Clip;

impl Clip {
    pub(super) fn open(
        _bytes: Vec<u8>,
        _texture: u64,
        _output: Option<String>,
    ) -> Result<Clip, String> {
        Err("Videos do not play here yet".to_string())
    }

    pub(crate) fn play(&self) -> Result<(), String> {
        Ok(())
    }

    pub(crate) fn pause(&self) -> Result<(), String> {
        Ok(())
    }

    pub(crate) fn seek(&self, _position_ms: u64) -> Result<(), String> {
        Ok(())
    }

    pub(crate) fn set_volume(&self, _volume: f64) {}

    pub(crate) fn time(&self) -> (Option<u64>, Option<u64>) {
        (None, None)
    }
}
