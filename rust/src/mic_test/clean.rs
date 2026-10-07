//! What the call does to the microphone, done to the mic test's: libwebrtc's
//! own processing, then the noise model, then the mic volume. The test is
//! where you go to hear how you sound, so it has to sound like the call.
//!
//! The call's runs inside libwebrtc (`native/noise_filter`), which the test
//! does not go through (why is in `api::mic_test`). The same three steps run
//! here instead, 10 ms at a time:
//!
//! - **libwebrtc's processing**, from LiveKit's build of it: the high-pass
//!   filter, its noise suppressor under [`Noise::Standard`], and gain control
//!   when it is on. Not echo cancellation: the test plays you back, and an echo
//!   canceller handed your own voice as the far end takes it out of the near
//!   end too. In a call it only acts while someone else is talking.
//! - **The model**: RNNoise from the runner, whose addresses Dart passes on
//!   ([`set_rnnoise`]), or DeepFilterNet. Each a state of its own, apart from
//!   the call's, so a call muted under the test never shares what a model has
//!   heard with it.
//! - **The mic volume** ([`Boost`]).
//!
//! A change to any of them reaches a test already running, so you can flip
//! between models and hear the difference.

use super::Boost;
use crate::deep_filter::{self, FRAME};
use livekit::webrtc::native::apm::AudioProcessingModule;
use std::ffi::c_void;
use std::sync::Mutex;

/// What the models and libwebrtc work in: 10 ms at 48 kHz.
pub(super) const SAMPLE_RATE: u32 = 48_000;

/// Which noise filter runs. Dart resolves the choice in settings to what this
/// device can run, as it does for the call.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Noise {
    Off,
    Standard,
    Rnnoise,
    DeepFilter,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Settings {
    pub noise: Noise,
    pub auto_gain: bool,
}

static SETTINGS: Mutex<Settings> = Mutex::new(Settings {
    noise: Noise::Off,
    auto_gain: false,
});

/// The runner's `rift_noise_filter_rnnoise_create`, `_process` and `_destroy`.
static RNNOISE: Mutex<Option<RnnoiseEntry>> = Mutex::new(None);

/// A DeepFilterNet kept from one test to the next: loading one takes a quarter
/// of a second, and flipping to it should not.
static SPARE_DEEP_FILTER: Mutex<Option<deep_filter::Model>> = Mutex::new(None);

pub(crate) fn set(settings: Settings) {
    *SETTINGS.lock().unwrap() = settings;
}

fn settings() -> Settings {
    *SETTINGS.lock().unwrap()
}

/// Where the runner's RNNoise is. Addresses of zero are ignored.
pub(crate) fn set_rnnoise(create: usize, process: usize, destroy: usize) {
    if create == 0 || process == 0 || destroy == 0 {
        return;
    }
    // SAFETY: Dart looked these up by name in the runner, which declares them
    // with exactly these signatures (`native/noise_filter/noise_filter.h`).
    let entry = unsafe {
        RnnoiseEntry {
            create: std::mem::transmute::<usize, unsafe extern "C" fn() -> *mut c_void>(create),
            process: std::mem::transmute::<usize, unsafe extern "C" fn(*mut c_void, *mut f32)>(
                process,
            ),
            destroy: std::mem::transmute::<usize, unsafe extern "C" fn(*mut c_void)>(destroy),
        }
    };
    *RNNOISE.lock().unwrap() = Some(entry);
}

#[derive(Clone, Copy)]
struct RnnoiseEntry {
    create: unsafe extern "C" fn() -> *mut c_void,
    process: unsafe extern "C" fn(*mut c_void, *mut f32),
    destroy: unsafe extern "C" fn(*mut c_void),
}

/// One RNNoise state from the runner, freed with it.
struct Rnnoise {
    entry: RnnoiseEntry,
    state: *mut c_void,
}

impl Rnnoise {
    fn new() -> Option<Self> {
        let entry = (*RNNOISE.lock().unwrap())?;
        // SAFETY: see `set_rnnoise`.
        let state = unsafe { (entry.create)() };
        (!state.is_null()).then_some(Self { entry, state })
    }

    fn process(&mut self, frame: &mut [f32; FRAME]) {
        // SAFETY: a live state, and 480 writable floats.
        unsafe { (self.entry.process)(self.state, frame.as_mut_ptr()) }
    }
}

impl Drop for Rnnoise {
    fn drop(&mut self) {
        // SAFETY: made by this entry's `create`, and freed once.
        unsafe { (self.entry.destroy)(self.state) }
    }
}

/// DeepFilterNet, handed back to [`SPARE_DEEP_FILTER`] once done with.
struct DeepFilter(Option<deep_filter::Model>);

impl Drop for DeepFilter {
    fn drop(&mut self) {
        if let Some(model) = self.0.take() {
            *SPARE_DEEP_FILTER.lock().unwrap() = Some(model);
        }
    }
}

enum Model {
    None,
    Rnnoise(Rnnoise),
    DeepFilter(Box<DeepFilter>),
}

impl Model {
    /// The model `noise` asks for, started afresh. DeepFilterNet that will not
    /// load falls back to RNNoise, as the call's does.
    fn for_noise(noise: Noise) -> Model {
        match noise {
            Noise::Off | Noise::Standard => Model::None,
            Noise::Rnnoise => Self::rnnoise(),
            Noise::DeepFilter => {
                let spare = SPARE_DEEP_FILTER.lock().unwrap().take();
                match spare.map(Ok).unwrap_or_else(deep_filter::Model::new) {
                    Ok(mut model) => {
                        model.reset();
                        Model::DeepFilter(Box::new(DeepFilter(Some(model))))
                    }
                    Err(message) => {
                        log::warn!("mic test: {message}");
                        Self::rnnoise()
                    }
                }
            }
        }
    }

    fn rnnoise() -> Model {
        match Rnnoise::new() {
            Some(rnnoise) => Model::Rnnoise(rnnoise),
            None => {
                log::warn!("mic test: no RNNoise from the runner");
                Model::None
            }
        }
    }

    fn process(&mut self, frame: &mut [f32; FRAME]) {
        match self {
            Model::None => {}
            Model::Rnnoise(rnnoise) => rnnoise.process(frame),
            // Leaves the frame as it was if the model cannot take it.
            Model::DeepFilter(deep_filter) => {
                if let Some(model) = deep_filter.0.as_mut() {
                    model.process(frame);
                }
            }
        }
    }
}

/// One test's processing, fed whatever the device hands over and giving back
/// whole 10 ms frames, cleaned.
pub(super) struct Cleaner {
    pending: Vec<i16>,
    built: Option<Settings>,
    apm: Option<AudioProcessingModule>,
    model: Model,
    boost: Boost,
    frame: [f32; FRAME],
}

impl Cleaner {
    pub(super) fn new() -> Self {
        Self {
            pending: Vec::with_capacity(FRAME * 4),
            built: None,
            apm: None,
            model: Model::None,
            boost: Boost::new(SAMPLE_RATE),
            frame: [0.0; FRAME],
        }
    }

    /// `samples` (mono, 16-bit, [`SAMPLE_RATE`]) cleaned, as many whole frames
    /// as there are; the rest is kept for the next call. Empty until a frame
    /// is complete.
    pub(super) fn clean(&mut self, samples: &[i16]) -> Vec<i16> {
        self.pending.extend_from_slice(samples);
        let whole = self.pending.len() / FRAME * FRAME;
        if whole == 0 {
            return Vec::new();
        }
        let settings = settings();
        if self.built != Some(settings) {
            self.rebuild(settings);
        }
        let mut out: Vec<i16> = self.pending.drain(..whole).collect();
        for chunk in out.chunks_exact_mut(FRAME) {
            self.clean_frame(chunk);
        }
        out
    }

    fn rebuild(&mut self, settings: Settings) {
        // The model is started over only when it changes: gain control going
        // on or off is no reason to forget what it has heard.
        if self.built.map(|b| b.noise) != Some(settings.noise) {
            self.model = Model::None;
            self.model = Model::for_noise(settings.noise);
        }
        self.apm = Some(AudioProcessingModule::new(
            false,
            settings.auto_gain,
            true,
            settings.noise == Noise::Standard,
        ));
        self.built = Some(settings);
    }

    fn clean_frame(&mut self, chunk: &mut [i16]) {
        if let Some(apm) = self.apm.as_mut() {
            if let Err(e) = apm.process_stream(chunk, SAMPLE_RATE as i32, 1) {
                log::warn!("mic test: {}", e.message);
            }
        }
        if !matches!(self.model, Model::None) {
            for (to, from) in self.frame.iter_mut().zip(chunk.iter()) {
                *to = f32::from(*from);
            }
            self.model.process(&mut self.frame);
            for (to, from) in chunk.iter_mut().zip(self.frame.iter()) {
                *to = from.round().clamp(f32::from(i16::MIN), f32::from(i16::MAX)) as i16;
            }
        }
        self.boost.apply(chunk);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Noise-like samples on the 16-bit scale.
    fn noise(len: usize, seed: &mut u32) -> Vec<i16> {
        (0..len)
            .map(|_| {
                *seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                (((*seed >> 16) as f32 / 65536.0 - 0.5) * 2000.0) as i16
            })
            .collect()
    }

    fn energy(samples: &[i16]) -> f64 {
        samples.iter().map(|&s| f64::from(s).powi(2)).sum()
    }

    /// Two seconds of steady noise through a cleaner set to `noise`, and how
    /// much quieter the second second came out, in dB.
    fn reduction(noise_kind: Noise) -> f64 {
        set(Settings {
            noise: noise_kind,
            auto_gain: false,
        });
        let mut cleaner = Cleaner::new();
        let mut seed = 7;
        let mut energy_in = 0.0;
        let mut energy_out = 0.0;
        for i in 0..200 {
            let input = noise(FRAME, &mut seed);
            let output = cleaner.clean(&input);
            if i >= 100 {
                energy_in += energy(&input);
                energy_out += energy(&output);
            }
        }
        10.0 * (energy_in / energy_out.max(1e-9)).log10()
    }

    // One test, so the shared settings are not raced by another. In release
    // only: tract will not build DeepFilterNet's model in a debug build.
    #[cfg(not(debug_assertions))]
    #[test]
    fn each_choice_cleans_as_the_call_would() {
        // Off leaves noise alone below about 12 kHz, where libwebrtc's
        // processing stops passing much (as the call's does): half the
        // energy of white noise, 3 dB, and no more.
        let off = reduction(Noise::Off);
        assert!(off < 4.0, "off took {off:.1} dB");
        // libwebrtc's own suppressor takes it well down.
        assert!(reduction(Noise::Standard) > off + 6.0);
        // DeepFilterNet, a model of the test's own.
        assert!(reduction(Noise::DeepFilter) > off + 20.0);
        // No runner here, so no RNNoise: the test runs without a model rather
        // than failing.
        assert!((reduction(Noise::Rnnoise) - off).abs() < 0.5);
    }

    #[test]
    fn frames_come_out_whole_and_nothing_is_lost() {
        let mut cleaner = Cleaner::new();
        let mut seed = 1;
        // 25 ms, then 5 ms: two frames, then a third.
        assert_eq!(cleaner.clean(&noise(1200, &mut seed)).len(), 2 * FRAME);
        assert_eq!(cleaner.clean(&noise(240, &mut seed)).len(), FRAME);
        assert!(cleaner.clean(&noise(100, &mut seed)).is_empty());
    }
}
