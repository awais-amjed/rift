//! No player of the share's sound here yet: it stays with the call.

use super::Gain;
use std::sync::mpsc::Receiver;

pub(crate) const PLAYS: bool = false;

pub(super) fn run(_frames: Receiver<Vec<i16>>, _gain: &Gain) -> Result<(), String> {
    Ok(())
}
