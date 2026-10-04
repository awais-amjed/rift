//! DeepFilterNet, the second model the microphone filter can run.
//!
//! The filter itself lives in the runner (`native/noise_filter`), inside
//! libwebrtc's processing of the microphone, and calls the two C functions
//! here on libwebrtc's capture thread, 10 ms at a time. Dart loads the model
//! first ([`load`], off the UI thread, since it takes about a quarter of a
//! second) and hands the runner these functions' addresses.

use std::sync::Mutex;

use df::tract::{DfParams, DfTract, RuntimeParams};
use ndarray::{ArrayView2, ArrayViewMut2};

/// What libwebrtc hands over: 10 ms at 48 kHz, which is also DFN3's hop.
const FRAME: usize = 480;

/// libwebrtc's samples are on the 16-bit scale; the model's are on ±1.
const SCALE: f32 = 32768.0;

struct Model {
    df: DfTract,
    noisy: Vec<f32>,
    enhanced: Vec<f32>,
}

// SAFETY: DfTract is not Send only because tract's run state keeps its
// tensors behind `Rc`. Those Rcs are all inside this one model and never
// handed out, and the model is only ever reached through [`MODEL`]'s lock, so
// no two threads touch their counts at once and each sees the last one's
// writes. It is made on one thread and used on the capture thread, in turn.
unsafe impl Send for Model {}

/// Locked by the capture thread for each frame. Nothing else takes it once
/// the model is in, so the lock is never waited on there.
static MODEL: Mutex<Option<Model>> = Mutex::new(None);

/// Loads the built-in model once; later calls return straight away.
pub(crate) fn load() -> Result<(), String> {
    if MODEL.lock().map_err(|e| e.to_string())?.is_some() {
        return Ok(());
    }
    // The post-filter takes a little more off what the model leaves between
    // words, at the strength DeepFilterNet's own command line uses.
    let params = RuntimeParams::default_with_ch(1).with_post_filter(0.02);
    let df = DfTract::new(DfParams::default(), &params)
        .map_err(|e| format!("DeepFilterNet would not load: {e}"))?;
    if df.hop_size != FRAME || df.sr != 48000 {
        return Err(format!(
            "DeepFilterNet works on {} samples at {} Hz, not 10 ms at 48 kHz",
            df.hop_size, df.sr
        ));
    }
    log::info!("DeepFilterNet loaded");
    *MODEL.lock().map_err(|e| e.to_string())? = Some(Model {
        df,
        noisy: vec![0.0; FRAME],
        enhanced: vec![0.0; FRAME],
    });
    Ok(())
}

/// Filters `count` samples at `samples` in place. Returns 0, or -1 when the
/// frame went through untouched (no model, a frame that is not 10 ms at
/// 48 kHz, or the model failing).
///
/// # Safety
/// `samples` must point to `count` floats, writable and not shared with
/// anything else for the length of the call.
#[no_mangle]
pub unsafe extern "C" fn rift_deep_filter_process(samples: *mut f32, count: i32) -> i32 {
    if samples.is_null() || count as usize != FRAME {
        return -1;
    }
    let Ok(mut guard) = MODEL.try_lock() else {
        return -1;
    };
    let Some(model) = guard.as_mut() else {
        return -1;
    };
    // SAFETY: the caller promises `count` writable floats.
    let frame = unsafe { std::slice::from_raw_parts_mut(samples, FRAME) };
    for (to, from) in model.noisy.iter_mut().zip(frame.iter()) {
        *to = *from / SCALE;
    }
    let (Ok(noisy), Ok(enhanced)) = (
        ArrayView2::from_shape((1, FRAME), model.noisy.as_slice()),
        ArrayViewMut2::from_shape((1, FRAME), model.enhanced.as_mut_slice()),
    ) else {
        return -1;
    };
    if model.df.process(noisy, enhanced).is_err() {
        return -1;
    }
    for (to, from) in frame.iter_mut().zip(model.enhanced.iter()) {
        *to = *from * SCALE;
    }
    0
}

/// Clears what the model has heard, for when it is switched back on or the
/// microphone starts again.
#[no_mangle]
pub extern "C" fn rift_deep_filter_reset() {
    if let Ok(mut guard) = MODEL.try_lock() {
        if let Some(model) = guard.as_mut() {
            if let Err(e) = model.df.init() {
                log::warn!("DeepFilterNet reset failed: {e}");
            }
        }
    }
}

/// Where the runner finds the two functions above.
pub(crate) fn entry_points() -> (usize, usize) {
    let process: unsafe extern "C" fn(*mut f32, i32) -> i32 = rift_deep_filter_process;
    let reset: extern "C" fn() = rift_deep_filter_reset;
    (process as usize, reset as usize)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_frame_that_is_not_10_ms_passes_through() {
        let mut frame = [1000.0f32; 160];
        let ok = unsafe { rift_deep_filter_process(frame.as_mut_ptr(), 160) };
        assert_eq!(ok, -1);
        assert!(frame.iter().all(|&s| s == 1000.0));
    }

    #[test]
    fn loaded_it_quietens_noise() {
        load().unwrap();
        // A second of a steady, noise-like signal on the 16-bit scale.
        let mut seed = 1u32;
        let mut energy_in = 0.0f64;
        let mut energy_out = 0.0f64;
        for i in 0..100 {
            let mut frame = [0.0f32; FRAME];
            for s in frame.iter_mut() {
                seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                *s = ((seed >> 16) as f32 / 65536.0 - 0.5) * 2000.0;
            }
            if i >= 50 {
                energy_in += frame.iter().map(|&s| (s as f64).powi(2)).sum::<f64>();
            }
            let ok = unsafe { rift_deep_filter_process(frame.as_mut_ptr(), FRAME as i32) };
            assert_eq!(ok, 0);
            if i >= 50 {
                energy_out += frame.iter().map(|&s| (s as f64).powi(2)).sum::<f64>();
            }
        }
        let reduction_db = 10.0 * (energy_in / energy_out.max(1e-9)).log10();
        assert!(reduction_db > 20.0, "only {reduction_db:.1} dB quieter");
    }
}
