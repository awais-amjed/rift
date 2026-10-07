//! DeepFilterNet, the second model the microphone filter can run.
//!
//! The filter itself lives in the runner (`native/noise_filter`), inside
//! libwebrtc's processing of the microphone, and calls the two C functions
//! here on libwebrtc's capture thread, 10 ms at a time. Dart loads the model
//! first ([`load`], off the UI thread, since it takes about a quarter of a
//! second) and hands the runner these functions' addresses.
//!
//! The settings mic test reads the microphone here in the library rather than
//! through libwebrtc, and runs a [`Model`] of its own (`mic_test::clean`).

use std::sync::Mutex;

use df::tract::{DfParams, DfTract, RuntimeParams};
use ndarray::{ArrayView2, ArrayViewMut2};

/// What libwebrtc hands over: 10 ms at 48 kHz, which is also DFN3's hop.
pub(crate) const FRAME: usize = 480;

/// libwebrtc's samples are on the 16-bit scale; the model's are on ±1.
const SCALE: f32 = 32768.0;

pub(crate) struct Model {
    df: DfTract,
    /// The model as it loaded, copied back over `df` to start it afresh.
    /// libDF's own `init` cannot do that: it refills one of its rolling
    /// buffers without emptying it, so each call adds 50 ms of old frames to
    /// what the deep filter reads, and the voice comes back as an echo
    /// (DeepFilterNet up to d375b2d, Oct 2024, its latest).
    fresh: DfTract,
    noisy: Vec<f32>,
    enhanced: Vec<f32>,
}

// SAFETY: DfTract is not Send only because tract's run state keeps its
// tensors behind `Rc`. Those Rcs are all inside this one model, shared at
// most between `df` and `fresh`, and never handed out; the model is only ever
// reached through [`MODEL`]'s lock, so no two threads touch their counts at
// once and each sees the last one's writes. It is made on one thread and used
// on the capture thread, in turn.
unsafe impl Send for Model {}

impl Model {
    pub(crate) fn new() -> Result<Model, String> {
        // The post-filter takes a little more off what the model leaves
        // between words, at the strength DeepFilterNet's own command line uses.
        let params = RuntimeParams::default_with_ch(1).with_post_filter(0.02);
        let df = DfTract::new(DfParams::default(), &params)
            .map_err(|e| format!("DeepFilterNet would not load: {e}"))?;
        if df.hop_size != FRAME || df.sr != 48000 {
            return Err(format!(
                "DeepFilterNet works on {} samples at {} Hz, not 10 ms at 48 kHz",
                df.hop_size, df.sr
            ));
        }
        Ok(Model {
            fresh: df.clone(),
            df,
            noisy: vec![0.0; FRAME],
            enhanced: vec![0.0; FRAME],
        })
    }

    /// Filters 10 ms in place; false, with the frame untouched, if the model
    /// failed on it.
    pub(crate) fn process(&mut self, frame: &mut [f32; FRAME]) -> bool {
        for (to, from) in self.noisy.iter_mut().zip(frame.iter()) {
            *to = *from / SCALE;
        }
        let (Ok(noisy), Ok(enhanced)) = (
            ArrayView2::from_shape((1, FRAME), self.noisy.as_slice()),
            ArrayViewMut2::from_shape((1, FRAME), self.enhanced.as_mut_slice()),
        ) else {
            return false;
        };
        if self.df.process(noisy, enhanced).is_err() {
            return false;
        }
        for (to, from) in frame.iter_mut().zip(self.enhanced.iter()) {
            *to = *from * SCALE;
        }
        true
    }

    /// Forgets everything heard since loading.
    pub(crate) fn reset(&mut self) {
        self.df.clone_from(&self.fresh);
    }
}

/// Locked by the capture thread for each frame. Nothing else takes it once
/// the model is in, so the lock is never waited on there.
static MODEL: Mutex<Option<Model>> = Mutex::new(None);

/// Loads the built-in model once; later calls return straight away.
pub(crate) fn load() -> Result<(), String> {
    if MODEL.lock().map_err(|e| e.to_string())?.is_some() {
        return Ok(());
    }
    let model = Model::new()?;
    log::info!("DeepFilterNet loaded");
    *MODEL.lock().map_err(|e| e.to_string())? = Some(model);
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
    // SAFETY: the caller promises `count` writable floats, and `count` is
    // FRAME.
    let frame = unsafe { &mut *samples.cast::<[f32; FRAME]>() };
    if model.process(frame) {
        0
    } else {
        -1
    }
}

/// Clears what the model has heard, for when it is switched back on or the
/// microphone starts again: push to talk does that on every press.
#[no_mangle]
pub extern "C" fn rift_deep_filter_reset() {
    if let Ok(mut guard) = MODEL.try_lock() {
        if let Some(model) = guard.as_mut() {
            model.reset();
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

    /// Something voice-like: a 150 Hz buzz with its harmonics, rising and
    /// falling in syllables, over a little noise.
    fn voice(frames: usize, seed: &mut u32) -> Vec<[f32; FRAME]> {
        (0..frames)
            .map(|f| {
                let mut frame = [0.0f32; FRAME];
                for (i, s) in frame.iter_mut().enumerate() {
                    let t = (f * FRAME + i) as f32 / 48000.0;
                    let syllable = (std::f32::consts::PI * 4.0 * t).sin().max(0.0);
                    let buzz: f32 = (1..8)
                        .map(|h| (std::f32::consts::TAU * 150.0 * h as f32 * t).sin() / h as f32)
                        .sum();
                    *seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                    let noise = ((*seed >> 16) as f32 / 65536.0 - 0.5) * 100.0;
                    *s = buzz * syllable * 4000.0 + noise;
                }
                frame
            })
            .collect()
    }

    #[test]
    fn a_reset_starts_the_model_over() {
        let mut used = Model::new().unwrap();
        let mut seed = 1u32;
        for mut frame in voice(100, &mut seed) {
            assert!(used.process(&mut frame));
        }
        // Twice, as push to talk does: each of libDF's own resets made
        // the echo 50 ms later.
        used.reset();
        used.reset();
        let mut fresh = Model::new().unwrap();
        for (i, frame) in voice(100, &mut seed).into_iter().enumerate() {
            let (mut a, mut b) = (frame, frame);
            assert!(used.process(&mut a));
            assert!(fresh.process(&mut b));
            assert!(a == b, "frame {i} differs from a newly loaded model's");
        }
    }
}
