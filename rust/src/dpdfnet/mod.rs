//! DPDFNet, the third model the microphone filter can run: Ceva's 48 kHz
//! models (Apache-2.0), on Ceva's own runtime for them ([`ceva`]), or on ONNX
//! Runtime ([`onnx`]) where that one cannot run: a CPU without AVX2 and FMA,
//! or a bundle without its library, which is every Linux one so far.
//!
//! It keeps more of the voice than DeepFilterNet, which it grew out of and
//! which Rift offered until Oct 21, for more work. On ONNX Runtime, the only
//! runtime until Nov 12, DPDFNet-8, the one that sounded best, took 3.4 ms a
//! frame on a performance core of an i7-12700H and 7.7 on one of its
//! efficiency cores, where libwebrtc's capture thread sometimes runs: there a
//! call had 6% of its frames late, which is heard as crackle. DPDFNet-2 took
//! 1.2 and 2.8 ms (Oct 14; DeepFilterNet 0.6 on a performance core). So both
//! are loaded, and the large one runs until frames show the computer cannot
//! keep up with it ([`SLOW_FRAME`]), when the small one takes over until the
//! call ends ([`retry_large`]): the large one gets another go with each call,
//! since a computer is often slow only for a while (a game loading, a build),
//! and a slow one costs a second of crackle at the start of a call, not of
//! every unmute.
//!
//! Ceva's runtime does the same frame in a quarter of the time. In a call on
//! that laptop's Windows the capture thread took 5% of a core on DPDFNet-2
//! where ONNX Runtime took 21%, and 12% on DPDFNet-8 where it took 48%, with
//! no frame of DPDFNet-8 over 5 ms where a quarter of them had been (Nov 12,
//! `CALLS.md`, *Rift beside a game*). So there the change-over above should
//! be rare; it stays for the computers that need it.
//!
//! The model runs on libwebrtc's capture thread, left on whichever cores the
//! system gives it, and on Windows that thread is time-critical, so it goes
//! ahead of a game. From Oct 25 to Oct 31 it had a thread of its own at normal
//! priority, because a tester's CS2 stuttered in a call, but on that thread
//! testers heard a Windows friend's voice crackle and cut out, and Time
//! critical sounded best when the owner compared the placements by ear
//! (`CALLS.md`, *Rift beside a game*). On an efficiency core DPDFNet-2 takes
//! over, which still beats RNNoise.
//! tract, which ran DeepFilterNet, runs these too, but its GRU layers took
//! DPDFNet-8 to 12 ms a frame.
//!
//! The runner's filter calls
//! the two C functions here on libwebrtc's capture thread, 10 ms at a time,
//! once Dart has loaded the model ([`load`]) and handed their addresses on.
//! The settings mic test runs a [`Model`] of its own (`mic_test::clean`).

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use df::{Complex32, DFState};

mod ceva;
mod onnx;

/// What libwebrtc hands over: 10 ms at 48 kHz, which is also the models' hop.
pub(crate) const FRAME: usize = 480;

/// The models' window: 20 ms, moved on 10 ms at a time. Its spectrum has
/// this many bins over two.
const WINDOW: usize = 960;
const BINS: usize = WINDOW / 2 + 1;

/// A spectrum as the models take it: each bin's real and imaginary parts
/// side by side.
const SPECTRUM: usize = BINS * 2;

/// libwebrtc's samples are on the 16-bit scale; the model's are on ±1.
const SCALE: f32 = 32768.0;

/// A run of the large model longer than this leaves too little of the 10 ms
/// for the rest of libwebrtc's processing. On a performance core fewer than
/// one frame in a hundred took it; on an efficiency core nearly all did.
const SLOW_FRAME: Duration = Duration::from_millis(7);

/// The small model takes over once this many of the last [`WATCHED`] frames
/// were slow, where a lone slow frame (the thread put aside for a moment) is
/// no reason to. A slow frame holds up the microphone, heard as crackle, so a
/// computer under this keeps DPDFNet-8 and lets them through: paced as a call
/// is, on the i7's efficiency cores DPDFNet-8 went over 7 ms on 4 to 11 frames
/// in 500, and DPDFNet-2 on none (Oct 25). It was 10 until Oct 25, when
/// DPDFNet-8 stayed and let them through, then 3 until Nov 6, when the owner
/// settled on 5.
const SLOW_LIMIT: u32 = 5;
const WATCHED: usize = 100;

/// Set when the person chose DPDFNet-2 in settings ([`choose_small`]), for
/// the call's model and the mic test's alike.
static SMALL_CHOSEN: AtomicBool = AtomicBool::new(false);

/// Moved on at the end of each call ([`retry_large`]). A model that sees it
/// move forgets that the computer was too slow for the large model: one
/// count for the call's model and the mic test's, which each read it
/// themselves.
static RETRIES: AtomicU32 = AtomicU32::new(0);

/// Frames of the call that went out unfiltered, for Dart to log after it, as
/// [`FELL_BACK`] is.
static UNFILTERED: AtomicU32 = AtomicU32::new(0);

/// Set when a model went over to DPDFNet-2, for Dart to write to the log
/// after the call ([`take_fell_back`]): the capture thread never writes to
/// the log itself.
static FELL_BACK: AtomicBool = AtomicBool::new(false);

/// Which of the two models: DPDFNet-8 or DPDFNet-2.
#[derive(Clone, Copy)]
enum Size {
    Large,
    Small,
}

/// One of the two models, on the runtime this computer has for it, and what
/// it carries from one frame to the next.
enum Net {
    Ceva(ceva::Net),
    Onnx(onnx::Net),
}

impl Net {
    /// On Ceva's runtime where it opens, on ONNX Runtime where it does not.
    fn load(size: Size) -> Result<Net, String> {
        match ceva::Net::load(size) {
            Ok(net) => Ok(Net::Ceva(net)),
            Err(_) => onnx::Net::load(size).map(Net::Onnx),
        }
    }

    /// One step, in place: a spectrum as a plain FFT gives it in, the
    /// cleaned one out, and the state carried on. False if the model failed.
    fn run(&mut self, spectrum: &mut [f32; SPECTRUM]) -> bool {
        match self {
            Net::Ceva(net) => net.run(spectrum),
            Net::Onnx(net) => net.run(spectrum).is_ok(),
        }
    }

    fn reset(&mut self) {
        match self {
            Net::Ceva(net) => net.reset(),
            Net::Onnx(net) => net.reset(),
        }
    }

    /// For the log.
    fn runtime(&self) -> &'static str {
        match self {
            Net::Ceva(_) => "Ceva's runtime",
            Net::Onnx(_) => "ONNX Runtime",
        }
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
    /// `spec` as the model takes it, and as it hands it back.
    spectrum: [f32; SPECTRUM],
    samples: [f32; FRAME],
}

impl Model {
    pub(crate) fn new() -> Result<Model, String> {
        Ok(Model::of(Net::load(Size::Large)?, Net::load(Size::Small)?))
    }

    fn of(large: Net, small: Net) -> Model {
        let mut model = Model {
            large,
            small,
            slow: false,
            retries_seen: RETRIES.load(Ordering::Relaxed),
            ran_large: true,
            watch: Watch::new(),
            stft: DFState::new(48000, WINDOW, FRAME, 32, 1),
            spec: vec![Complex32::default(); BINS],
            spectrum: [0.0; SPECTRUM],
            samples: [0.0; FRAME],
        };
        model.warm_up();
        model
    }

    /// A model's first runs set up what later ones reuse and take several
    /// times as long, which is no measure of the computer.
    fn warm_up(&mut self) {
        let mut silence = [0.0; FRAME];
        for _ in 0..3 {
            self.process_with(&mut silence, true);
            self.process_with(&mut silence, false);
        }
        self.reset();
    }

    /// Filters 10 ms in place; false, with the frame untouched, if the model
    /// failed on it.
    pub(crate) fn process(&mut self, frame: &mut [f32; FRAME]) -> bool {
        self.process_as_chosen(frame, SMALL_CHOSEN.load(Ordering::Relaxed))
    }

    fn process_as_chosen(&mut self, frame: &mut [f32; FRAME], small_chosen: bool) -> bool {
        let began = Instant::now();
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
        let ok = self.process_with(frame, large);
        if large && self.watch.add(began.elapsed()) {
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
        let (pairs, _) = self.spectrum.as_chunks_mut::<2>();
        for (pair, bin) in pairs.iter_mut().zip(&self.spec) {
            *pair = [bin.re * WINDOW as f32, bin.im * WINDOW as f32];
        }
        let net = if large {
            &mut self.large
        } else {
            &mut self.small
        };
        if !net.run(&mut self.spectrum) {
            return false;
        }
        let (pairs, _) = self.spectrum.as_chunks::<2>();
        for (bin, pair) in self.spec.iter_mut().zip(pairs) {
            *bin = Complex32::new(pair[0], pair[1]) / WINDOW as f32;
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

/// How many frames of the call went out unfiltered since the last call,
/// because the model failed on them, which starts the count again.
pub(crate) fn take_unfiltered() -> u32 {
    UNFILTERED.swap(0, Ordering::Relaxed)
}

/// Locked by the capture thread for each frame. Nothing else takes it once
/// the model is in, so the lock is never waited on there.
static MODEL: Mutex<Option<CallModel>> = Mutex::new(None);

/// The call's model, run on the capture thread.
struct CallModel {
    model: Model,
    /// The last frame as it came in, which goes out in place of one the model
    /// failed on: the model's window holds the voice back a frame, so this is
    /// the one its output would have matched.
    previous: [f32; FRAME],
}

impl CallModel {
    fn new(model: Model) -> CallModel {
        CallModel {
            model,
            previous: [0.0; FRAME],
        }
    }

    /// True when the model's frame went out.
    fn process(&mut self, frame: &mut [f32; FRAME]) -> bool {
        let raw = *frame;
        let ok = self.model.process(frame);
        if !ok {
            *frame = self.previous;
            UNFILTERED.fetch_add(1, Ordering::Relaxed);
        }
        self.previous = raw;
        ok
    }

    fn reset(&mut self) {
        self.model.reset();
        self.previous = [0.0; FRAME];
    }
}

/// Loads the built-in model once; later calls return straight away.
pub(crate) fn load() -> Result<(), String> {
    if MODEL.lock().map_err(|e| e.to_string())?.is_some() {
        return Ok(());
    }
    let model = CallModel::new(Model::new()?);
    log::info!("DPDFNet loaded, on {}", model.model.large.runtime());
    *MODEL.lock().map_err(|e| e.to_string())? = Some(model);
    Ok(())
}

/// Filters `count` samples at `samples` in place. Returns 0, or -1 when the
/// frame went out unfiltered (no model, a frame that is not 10 ms at
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
        // Four in a hundred, and the oldest ages out before the fifth.
        for i in 0..1000 {
            assert!(!watch.add(if i % 25 == 0 { slow } else { fast }));
        }
        let tripped = (0..WATCHED).position(|_| watch.add(slow));
        assert!(tripped.is_some_and(|i| i < SLOW_LIMIT as usize));
    }

    #[test]
    fn the_window_holds_the_voice_back_one_frame() {
        // What goes out in place of a late frame is the one before it as it
        // came in, which only lines up if the model's window, analysed and
        // put back together untouched, gives the voice back a frame late.
        let mut stft = DFState::new(48000, WINDOW, FRAME, 32, 1);
        let mut spec = vec![Complex32::default(); BINS];
        let frames = noise(8, &mut 1);
        let mut out = Vec::new();
        for frame in &frames {
            let input = frame.map(|s| s / SCALE);
            let mut samples = [0.0f32; FRAME];
            stft.analysis(&input, &mut spec);
            stft.synthesis(&mut spec, &mut samples);
            out.push(samples.map(|s| s * SCALE));
        }
        for i in 2..frames.len() {
            let worst = out[i]
                .iter()
                .zip(&frames[i - 1])
                .map(|(a, b)| (a - b).abs())
                .fold(0.0f32, f32::max);
            assert!(worst < 0.5, "frame {i} is {worst} off the one before it");
        }
    }

    #[test]
    fn a_frame_that_is_not_10_ms_passes_through() {
        let mut frame = [1000.0f32; 160];
        let ok = unsafe { rift_dpdfnet_process(frame.as_mut_ptr(), 160) };
        assert_eq!(ok, -1);
        assert!(frame.iter().all(|&s| s == 1000.0));
    }

    // The model's tests need a runtime, and neither is part of the crate.
    // They run on Ceva's with RIFT_DPDFNET_LIB=<path to librift_dpdfnet.so>,
    // or without it on ONNX Runtime with RIFT_ONNXRUNTIME=<path to
    // libonnxruntime.so>: cargo test --release dpdfnet -- --ignored
    #[test]
    #[ignore = "needs a runtime, at RIFT_DPDFNET_LIB or RIFT_ONNXRUNTIME"]
    fn loaded_it_quietens_noise() {
        load().unwrap();
        let mut seed = 1u32;
        let (mut energy_in, mut energy_out) = (0.0f64, 0.0f64);
        let mut back = 0;
        let mut previous = [0.0f32; FRAME];
        // Handed over back to back, not 10 ms apart, and beside the other
        // tests' models: some frames are late, as on a busy computer.
        for (i, mut frame) in noise(100, &mut seed).into_iter().enumerate() {
            let raw = frame;
            let ok = unsafe { rift_dpdfnet_process(frame.as_mut_ptr(), FRAME as i32) };
            if ok != 0 {
                assert!(frame == previous, "late frame {i} is not the one before it");
            } else if i >= 50 {
                back += 1;
                energy_in += raw.iter().map(|&s| (s as f64).powi(2)).sum::<f64>();
                energy_out += frame.iter().map(|&s| (s as f64).powi(2)).sum::<f64>();
            }
            previous = raw;
        }
        assert!(back >= 40, "only {back} of 50 frames back in time");
        let reduction_db = 10.0 * (energy_in / energy_out.max(1e-9)).log10();
        assert!(reduction_db > 20.0, "only {reduction_db:.1} dB quieter");
    }

    /// A voice of sorts on the 16-bit scale, in a hiss: pulses at a falling
    /// pitch through three resonances that move from vowel to vowel, in
    /// syllables with gaps between. The models take it for speech and keep
    /// it, where they take a steady tone for noise.
    fn voice(frames: usize, seed: &mut u32) -> Vec<[f32; FRAME]> {
        const VOWELS: [[f32; 3]; 4] = [
            [730.0, 1090.0, 2440.0],
            [270.0, 2290.0, 3010.0],
            [300.0, 870.0, 2240.0],
            [530.0, 1840.0, 2480.0],
        ];
        let mut hiss = noise(frames, seed).into_iter();
        let mut until_pulse = 0.0f32;
        // Each resonance's last two outputs.
        let mut rings = [[0.0f32; 2]; 3];
        (0..frames)
            .map(|i| {
                let mut frame = hiss.next().unwrap();
                for (j, s) in frame.iter_mut().enumerate() {
                    let t = (i * FRAME + j) as f32 / 48000.0;
                    // A syllable every 250 ms, sounding for 180 of them.
                    let within = t % 0.25;
                    let loud = if within < 0.18 {
                        (std::f32::consts::PI * within / 0.18).sin()
                    } else {
                        0.0
                    };
                    let pitch = 150.0 - 40.0 * (t % 1.0);
                    until_pulse -= 1.0;
                    let pulse = if until_pulse <= 0.0 {
                        until_pulse += 48000.0 / pitch;
                        1.0
                    } else {
                        0.0
                    };
                    let from = VOWELS[(t / 0.25) as usize % 4];
                    let to = VOWELS[((t / 0.25) as usize + 1) % 4];
                    let mut out = 0.0;
                    for (k, ring) in rings.iter_mut().enumerate() {
                        let formant = from[k] + (to[k] - from[k]) * within / 0.25;
                        let r = (-std::f32::consts::PI * 90.0 / 48000.0).exp();
                        let turn = std::f32::consts::TAU * formant / 48000.0;
                        let y = pulse + 2.0 * r * turn.cos() * ring[0] - r * r * ring[1];
                        *ring = [y, ring[0]];
                        out += y / (k + 1) as f32;
                    }
                    *s = *s * 0.3 + out * loud * 600.0;
                }
                frame
            })
            .collect()
    }

    #[test]
    #[ignore = "needs both runtimes, at RIFT_DPDFNET_LIB and RIFT_ONNXRUNTIME"]
    fn both_runtimes_give_the_same_sound() {
        // Ceva's runtime rounds the models' weights to 7 bits and what flows
        // between their layers to 8. What comes out has to stay what the
        // models as published give: the two apart by 30 dB under the sound
        // or more, as they were on recorded speech in noise (31 to 46 dB,
        // Nov 12).
        let ceva = |size| Net::Ceva(ceva::Net::load(size).unwrap());
        let onnx = |size| Net::Onnx(onnx::Net::load(size).unwrap());
        let mut ours = Model::of(ceva(Size::Large), ceva(Size::Small));
        let mut theirs = Model::of(onnx(Size::Large), onnx(Size::Small));
        for large in [true, false] {
            let (mut sound, mut apart, mut raw) = (0.0f64, 0.0f64, 0.0f64);
            for (i, frame) in voice(400, &mut 3).into_iter().enumerate() {
                let (mut a, mut b) = (frame, frame);
                assert!(ours.process_with(&mut a, large));
                assert!(theirs.process_with(&mut b, large));
                if i < 100 {
                    continue;
                }
                for ((a, b), r) in a.iter().zip(&b).zip(&frame) {
                    sound += (*b as f64).powi(2);
                    apart += ((a - b) as f64).powi(2);
                    raw += (*r as f64).powi(2);
                }
            }
            let kept_db = 10.0 * (sound / raw).log10();
            let apart_db = 10.0 * (sound / apart.max(1e-9)).log10();
            println!("large {large}: kept {kept_db:.1} dB of the input, apart by {apart_db:.1} dB");
            assert!(kept_db > -10.0, "the model kept too little to compare");
            assert!(apart_db > 30.0, "only {apart_db:.1} dB apart");
        }
    }

    #[test]
    #[ignore = "needs a runtime, at RIFT_DPDFNET_LIB or RIFT_ONNXRUNTIME"]
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
    #[ignore = "needs a runtime, at RIFT_DPDFNET_LIB or RIFT_ONNXRUNTIME"]
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
    #[ignore = "needs a runtime, at RIFT_DPDFNET_LIB or RIFT_ONNXRUNTIME"]
    fn the_calls_model_filters_every_frame_where_it_is_called() {
        let mut call = CallModel::new(Model::new().unwrap());
        let mut alone = Model::new().unwrap();
        let mut seed = 7u32;
        for (i, frame) in noise(100, &mut seed).into_iter().enumerate() {
            let (mut here, mut there) = (frame, frame);
            assert!(call.process(&mut here), "frame {i} went out unfiltered");
            assert!(alone.process(&mut there));
            assert!(here == there, "frame {i} is not what the model gives");
        }
        assert_eq!(take_unfiltered(), 0);
    }

    #[test]
    #[ignore = "needs a runtime, at RIFT_DPDFNET_LIB or RIFT_ONNXRUNTIME"]
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
