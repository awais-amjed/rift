//! DPDFNet, the third model the microphone filter can run: Ceva's 48 kHz
//! models (Apache-2.0, `models/`), on ONNX Runtime, which is opened from
//! beside the app the first time the model loads ([`RUNTIME`]).
//!
//! It keeps more of the voice than DeepFilterNet, which it grew out of, for
//! more work. DPDFNet-8, the one that sounded best, took 3.4 ms a frame on a
//! performance core of an i7-12700H and 7.7 on one of its efficiency cores,
//! where libwebrtc's capture thread sometimes runs: there a call had 6% of its
//! frames late, which is heard as crackle. DPDFNet-2 took 1.2 and 2.8 ms
//! (Oct 14; DeepFilterNet 0.6 on a performance core). So both are loaded, and
//! the large one runs until frames show the computer cannot keep up with it
//! ([`SLOW_FRAME`]), when the small one takes over until the call ends
//! ([`retry_large`]): the large one gets another go with each call, since a
//! computer is often slow only for a while (a game loading, a build), and a
//! slow one costs a second of crackle at the start of a call, not of every
//! unmute.
//! Before either runs, the thread is moved onto the performance cores
//! (`fast_core`), which on that i7 kept DPDFNet-8 for the whole call.
//! tract, which runs DeepFilterNet, runs these too, but its GRU layers took
//! DPDFNet-8 to 12 ms a frame.
//!
//! Wired up as DeepFilterNet is (`deep_filter.rs`): the runner's filter calls
//! the two C functions here on libwebrtc's capture thread, 10 ms at a time,
//! once Dart has loaded the model ([`load`]) and handed their addresses on.
//! The settings mic test runs a [`Model`] of its own (`mic_test::clean`).

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use df::{Complex32, DFState};
use ort::session::{builder::GraphOptimizationLevel, Session};
use ort::value::TensorRef;

use crate::deep_filter::FRAME;

/// DPDFNet-8 and DPDFNet-2 at 48 kHz, from huggingface.co/Ceva-IP/DPDFNet
/// (`onnx/dpdfnet8_48khz_hr.onnx`, `onnx/dpdfnet2_48khz_hr.onnx`).
static LARGE: &[u8] = include_bytes!("../models/dpdfnet8_48khz_hr.onnx");
static SMALL: &[u8] = include_bytes!("../models/dpdfnet2_48khz_hr.onnx");

/// The models' window: 20 ms, moved on 10 ms at a time. Its spectrum has
/// this many bins over two.
const WINDOW: usize = 960;
const BINS: usize = WINDOW / 2 + 1;

/// libwebrtc's samples are on the 16-bit scale; the model's are on ±1.
const SCALE: f32 = 32768.0;

/// A run of the large model longer than this leaves too little of the 10 ms
/// for the rest of libwebrtc's processing. On a performance core fewer than
/// one frame in a hundred took it; on an efficiency core nearly all did.
const SLOW_FRAME: Duration = Duration::from_millis(7);

/// The small model takes over once this many of the last [`WATCHED`] frames
/// were slow: a second of them, where a lone slow frame (the thread put aside
/// for a moment) is no reason to.
const SLOW_LIMIT: u32 = 10;
const WATCHED: usize = 100;

/// Set when the person chose DPDFNet-2 in settings ([`choose_small`]), for
/// the call's model and the mic test's alike.
static SMALL_CHOSEN: AtomicBool = AtomicBool::new(false);

/// Moved on at the end of each call ([`retry_large`]). A model that sees it
/// move forgets that the computer was too slow for the large model: one
/// count for the call's model and the mic test's, which each read it
/// themselves.
static RETRIES: AtomicU32 = AtomicU32::new(0);

/// Set when a model went over to DPDFNet-2, for Dart to write to the log
/// after the call ([`take_fell_back`]): the capture thread never writes to
/// the log itself.
static FELL_BACK: AtomicBool = AtomicBool::new(false);

/// ONNX Runtime, from Microsoft's release, which the runner's CMake bundles
/// (`native/onnxruntime`).
#[cfg(target_os = "linux")]
const RUNTIME: &str = "lib/libonnxruntime.so";
#[cfg(target_os = "windows")]
const RUNTIME: &str = "onnxruntime.dll";

/// What a test points at a copy of it elsewhere.
const RUNTIME_ENV: &str = "RIFT_ONNXRUNTIME";

/// One of the two models, and what it carries from one frame to the next.
struct Net {
    session: Session,
    /// Everything the model keeps between frames, in one tensor.
    state: Vec<f32>,
    /// The state it starts from: zeros, but for the running means its
    /// normalisation begins at, which the model file says.
    initial: Vec<f32>,
}

impl Net {
    fn load(onnx: &[u8]) -> Result<Net, String> {
        let session = session(onnx).map_err(|e| format!("DPDFNet would not load: {e}"))?;
        let initial = initial_state(&session)?;
        Ok(Net {
            session,
            state: initial.clone(),
            initial,
        })
    }

    /// One step: `input` in, the cleaned spectrum out to `spec` (scaled back
    /// for libDF's inverse transform), and the state carried on.
    fn run(&mut self, input: &[f32], spec: &mut [Complex32]) -> ort::Result<()> {
        let outputs = self.session.run(ort::inputs![
            "spec" => TensorRef::from_array_view(([1usize, 1, BINS, 2], input))?,
            "state_in" => TensorRef::from_array_view(([self.state.len()], self.state.as_slice()))?,
        ])?;
        let (_, cleaned) = outputs["spec_e"].try_extract_tensor::<f32>()?;
        for (bin, pair) in spec.iter_mut().zip(cleaned.chunks_exact(2)) {
            *bin = Complex32::new(pair[0], pair[1]) / WINDOW as f32;
        }
        let (_, state) = outputs["state_out"].try_extract_tensor::<f32>()?;
        if state.len() != self.state.len() {
            return Err(ort::Error::new("the state changed size"));
        }
        self.state.copy_from_slice(state);
        Ok(())
    }

    fn reset(&mut self) {
        self.state.copy_from_slice(&self.initial);
    }
}

/// Which of the last [`WATCHED`] frames of the large model were slow, as a
/// ring, and how many.
struct Watch {
    recent: [bool; WATCHED],
    next: usize,
    slow_frames: u32,
}

impl Watch {
    const fn new() -> Watch {
        Watch {
            recent: [false; WATCHED],
            next: 0,
            slow_frames: 0,
        }
    }

    /// Counts a frame that took `took`; true once too many were slow.
    fn add(&mut self, took: Duration) -> bool {
        let slow = took > SLOW_FRAME;
        self.slow_frames -= u32::from(self.recent[self.next]);
        self.slow_frames += u32::from(slow);
        self.recent[self.next] = slow;
        self.next = (self.next + 1) % WATCHED;
        self.slow_frames >= SLOW_LIMIT
    }
}

pub(crate) struct Model {
    large: Net,
    small: Net,
    /// Whether this computer was too slow for the large model. Kept through
    /// a reset, which push to talk does on every press, until the call ends.
    slow: bool,
    /// The [`RETRIES`] count `slow` belongs to.
    retries_seen: u32,
    /// Which of the two ran the last frame.
    ran_large: bool,
    watch: Watch,
    /// The window and transforms: libDF's, the same vorbis window over 960
    /// samples that DPDFNet was trained with.
    stft: DFState,
    spec: Vec<Complex32>,
    /// `spec` as the model takes it: real and imaginary side by side.
    input: Vec<f32>,
    samples: [f32; FRAME],
}

impl Model {
    pub(crate) fn new() -> Result<Model, String> {
        open_runtime()?;
        let mut model = Model {
            large: Net::load(LARGE)?,
            small: Net::load(SMALL)?,
            slow: false,
            retries_seen: RETRIES.load(Ordering::Relaxed),
            ran_large: true,
            watch: Watch::new(),
            stft: DFState::new(48000, WINDOW, FRAME, 32, 1),
            spec: vec![Complex32::default(); BINS],
            input: vec![0.0; BINS * 2],
            samples: [0.0; FRAME],
        };
        // A model's first run sets up what later ones reuse and takes several
        // times as long, which is no measure of the computer.
        let mut silence = [0.0; FRAME];
        model.process_with(&mut silence, true);
        model.process_with(&mut silence, false);
        model.reset();
        Ok(model)
    }

    /// Filters 10 ms in place; false, with the frame untouched, if the model
    /// failed on it.
    pub(crate) fn process(&mut self, frame: &mut [f32; FRAME]) -> bool {
        self.process_as_chosen(frame, SMALL_CHOSEN.load(Ordering::Relaxed))
    }

    fn process_as_chosen(&mut self, frame: &mut [f32; FRAME], small_chosen: bool) -> bool {
        crate::fast_core::keep_on_fast_cores();
        let retries = RETRIES.load(Ordering::Relaxed);
        if retries != self.retries_seen {
            self.retries_seen = retries;
            self.slow = false;
            self.watch = Watch::new();
        }
        let large = !self.slow && !small_chosen;
        // The one taking over stood still meanwhile, and would carry on from
        // what it heard back then. It starts from nothing instead, so the
        // voice is thin for a moment.
        if large != self.ran_large {
            if large {
                self.large.reset();
            } else {
                self.small.reset();
            }
            self.ran_large = large;
        }
        let started = Instant::now();
        let ok = self.process_with(frame, large);
        if large && self.watch.add(started.elapsed()) {
            self.slow = true;
            FELL_BACK.store(true, Ordering::Relaxed);
        }
        ok
    }

    fn process_with(&mut self, frame: &mut [f32; FRAME], large: bool) -> bool {
        for (to, from) in self.samples.iter_mut().zip(frame.iter()) {
            *to = *from / SCALE;
        }
        self.stft.analysis(&self.samples, &mut self.spec);
        // libDF scales its spectrum by 1 / WINDOW; the models take it as a
        // plain FFT gives it.
        for (pair, bin) in self.input.chunks_exact_mut(2).zip(&self.spec) {
            pair[0] = bin.re * WINDOW as f32;
            pair[1] = bin.im * WINDOW as f32;
        }
        let net = if large {
            &mut self.large
        } else {
            &mut self.small
        };
        if net.run(&self.input, &mut self.spec).is_err() {
            return false;
        }
        self.stft.synthesis(&mut self.spec, &mut self.samples);
        for (to, from) in frame.iter_mut().zip(self.samples.iter()) {
            *to = *from * SCALE;
        }
        true
    }

    /// Forgets everything heard since loading, but not that the computer was
    /// too slow for the large model.
    pub(crate) fn reset(&mut self) {
        self.large.reset();
        self.small.reset();
        self.stft.reset();
        self.watch = Watch::new();
    }
}

/// Runs DPDFNet-2 alone when `small`, as the person chose in settings, or
/// DPDFNet-8 until the computer proves too slow for it.
pub(crate) fn choose_small(small: bool) {
    SMALL_CHOSEN.store(small, Ordering::Relaxed);
}

/// Gives DPDFNet-8 another go, on a computer it was too slow on: at the end
/// of a call, so the next one starts on it. Not on a mute, which a slow
/// computer would answer with a second of crackle on every unmute, just as
/// the person starts to speak.
pub(crate) fn retry_large() {
    RETRIES.fetch_add(1, Ordering::Relaxed);
}

/// Whether a model went over to DPDFNet-2 since the last call, which starts
/// the count again.
pub(crate) fn take_fell_back() -> bool {
    FELL_BACK.swap(false, Ordering::Relaxed)
}

/// Opens ONNX Runtime once. A computer it will not open on still runs the
/// app, without this model.
fn open_runtime() -> Result<(), String> {
    static OPENED: OnceLock<Result<(), String>> = OnceLock::new();
    OPENED
        .get_or_init(|| {
            let path = match std::env::var_os(RUNTIME_ENV) {
                Some(path) => PathBuf::from(path),
                None => std::env::current_exe()
                    .map_err(|e| e.to_string())?
                    .parent()
                    .ok_or("the app has no folder")?
                    .join(RUNTIME),
            };
            ort::init_from(&path)
                .map_err(|e| format!("ONNX Runtime did not open: {e}"))?
                .commit();
            Ok(())
        })
        .clone()
}

/// One thread: the capture thread runs it, and a frame is too small to share
/// out.
fn session(onnx: &[u8]) -> Result<Session, String> {
    Session::builder()
        .map_err(|e| e.to_string())?
        .with_optimization_level(GraphOptimizationLevel::Level3)
        .map_err(|e| e.to_string())?
        .with_intra_threads(1)
        .map_err(|e| e.to_string())?
        .with_inter_threads(1)
        .map_err(|e| e.to_string())?
        .commit_from_memory(onnx)
        .map_err(|e| e.to_string())
}

/// The state DPDFNet starts from, from the model file's metadata: the size of
/// the one tensor it keeps everything in, and where its two normalisations'
/// running means begin.
fn initial_state(session: &Session) -> Result<Vec<f32>, String> {
    let meta = session.metadata().map_err(|e| e.to_string())?;
    let read = |key: &str| {
        meta.custom(key)
            .ok_or_else(|| format!("DPDFNet's model has no {key}"))
    };
    let size = |key: &str| {
        read(key)?
            .parse::<usize>()
            .map_err(|e| format!("DPDFNet's {key}: {e}"))
    };
    let values = |key: &str| -> Result<Vec<f32>, String> {
        read(key)?
            .split(',')
            .map(|v| {
                v.trim()
                    .parse::<f32>()
                    .map_err(|e| format!("DPDFNet's {key}: {e}"))
            })
            .collect()
    };
    let mut state = vec![0.0; size("state_size")?];
    let erb = values("erb_norm_init")?;
    let spec = values("spec_norm_init")?;
    if erb.len() != size("erb_norm_state_size")?
        || spec.len() != size("spec_norm_state_size")?
        || erb.len() + spec.len() > state.len()
    {
        return Err("DPDFNet's model does not add up".to_string());
    }
    state[..erb.len()].copy_from_slice(&erb);
    state[erb.len()..erb.len() + spec.len()].copy_from_slice(&spec);
    Ok(state)
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
    log::info!("DPDFNet loaded");
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
pub unsafe extern "C" fn rift_dpdfnet_process(samples: *mut f32, count: i32) -> i32 {
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
/// microphone starts again.
#[no_mangle]
pub extern "C" fn rift_dpdfnet_reset() {
    if let Ok(mut guard) = MODEL.try_lock() {
        if let Some(model) = guard.as_mut() {
            model.reset();
        }
    }
}

/// Where the runner finds the two functions above.
pub(crate) fn entry_points() -> (usize, usize) {
    let process: unsafe extern "C" fn(*mut f32, i32) -> i32 = rift_dpdfnet_process;
    let reset: extern "C" fn() = rift_dpdfnet_reset;
    (process as usize, reset as usize)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A steady, noise-like signal on the 16-bit scale.
    fn noise(frames: usize, seed: &mut u32) -> Vec<[f32; FRAME]> {
        (0..frames)
            .map(|_| {
                let mut frame = [0.0f32; FRAME];
                for s in frame.iter_mut() {
                    *seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                    *s = ((*seed >> 16) as f32 / 65536.0 - 0.5) * 2000.0;
                }
                frame
            })
            .collect()
    }

    #[test]
    fn a_lone_slow_frame_keeps_the_large_model() {
        let (fast, slow) = (Duration::from_millis(4), Duration::from_millis(9));
        let mut watch = Watch::new();
        // One slow frame a second, for a minute: the thread put aside now
        // and then, not a computer too slow for the model.
        for i in 0..6000 {
            assert!(!watch.add(if i % 100 == 0 { slow } else { fast }));
        }
    }

    #[test]
    fn a_run_of_slow_frames_moves_to_the_small_model() {
        let (fast, slow) = (Duration::from_millis(4), Duration::from_millis(9));
        let mut watch = Watch::new();
        // Nine in a hundred, and the oldest ages out before the tenth.
        for i in 0..300 {
            assert!(!watch.add(if i % 12 == 0 { slow } else { fast }));
        }
        let tripped = (0..WATCHED).position(|_| watch.add(slow));
        assert!(tripped.is_some_and(|i| i < SLOW_LIMIT as usize));
    }

    #[test]
    fn a_frame_that_is_not_10_ms_passes_through() {
        let mut frame = [1000.0f32; 160];
        let ok = unsafe { rift_dpdfnet_process(frame.as_mut_ptr(), 160) };
        assert_eq!(ok, -1);
        assert!(frame.iter().all(|&s| s == 1000.0));
    }

    // The model's tests need ONNX Runtime, which is not part of the crate:
    // RIFT_ONNXRUNTIME=<path to libonnxruntime.so> cargo test --release
    // dpdfnet -- --ignored
    #[test]
    #[ignore = "needs ONNX Runtime at RIFT_ONNXRUNTIME"]
    fn loaded_it_quietens_noise() {
        load().unwrap();
        let mut seed = 1u32;
        let (mut energy_in, mut energy_out) = (0.0f64, 0.0f64);
        for (i, mut frame) in noise(100, &mut seed).into_iter().enumerate() {
            if i >= 50 {
                energy_in += frame.iter().map(|&s| (s as f64).powi(2)).sum::<f64>();
            }
            let ok = unsafe { rift_dpdfnet_process(frame.as_mut_ptr(), FRAME as i32) };
            assert_eq!(ok, 0);
            if i >= 50 {
                energy_out += frame.iter().map(|&s| (s as f64).powi(2)).sum::<f64>();
            }
        }
        let reduction_db = 10.0 * (energy_in / energy_out.max(1e-9)).log10();
        assert!(reduction_db > 20.0, "only {reduction_db:.1} dB quieter");
    }

    #[test]
    #[ignore = "needs ONNX Runtime at RIFT_ONNXRUNTIME"]
    fn choosing_dpdfnet_2_runs_it_from_the_start() {
        let mut seed = 1u32;
        let before = noise(50, &mut seed);
        let after = noise(50, &mut seed);
        let mut switched = Model::new().unwrap();
        let mut fresh = Model::new().unwrap();
        for frame in &before {
            let (mut a, mut b) = (*frame, *frame);
            assert!(switched.process_as_chosen(&mut a, false));
            // The same window history, and a DPDFNet-2 that has heard none
            // of it.
            assert!(fresh.process_with(&mut b, true));
        }
        for (i, frame) in after.iter().enumerate() {
            let (mut a, mut b) = (*frame, *frame);
            assert!(switched.process_as_chosen(&mut a, true));
            assert!(fresh.process_with(&mut b, false));
            assert!(a == b, "frame {i} differs from a DPDFNet-2 started afresh");
        }
    }

    #[test]
    #[ignore = "needs ONNX Runtime at RIFT_ONNXRUNTIME"]
    fn the_large_model_comes_back_with_the_next_call_only() {
        let mut model = Model::new().unwrap();
        let mut seed = 1u32;
        let mut run = |model: &mut Model| {
            for mut frame in noise(5, &mut seed) {
                assert!(model.process_as_chosen(&mut frame, false));
            }
        };
        model.slow = true;
        run(&mut model);
        assert!(!model.ran_large);
        // Push to talk resets the model on every press: still too slow.
        model.reset();
        run(&mut model);
        assert!(!model.ran_large);
        retry_large();
        run(&mut model);
        assert!(model.ran_large);
    }

    #[test]
    #[ignore = "needs ONNX Runtime at RIFT_ONNXRUNTIME"]
    fn a_reset_starts_the_model_over() {
        let mut used = Model::new().unwrap();
        let mut seed = 1u32;
        for mut frame in noise(50, &mut seed) {
            assert!(used.process(&mut frame));
        }
        used.reset();
        let mut fresh = Model::new().unwrap();
        for (i, frame) in noise(50, &mut seed).into_iter().enumerate() {
            let (mut a, mut b) = (frame, frame);
            assert!(used.process(&mut a));
            assert!(fresh.process(&mut b));
            assert!(a == b, "frame {i} differs from a newly loaded model's");
        }
    }
}
