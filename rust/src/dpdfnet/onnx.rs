//! DPDFNet on ONNX Runtime: Ceva's models as they publish them, run as a
//! graph by Microsoft's runtime. How every computer ran the model until
//! Nov 12, and how one still does that Ceva's own runtime ([`super::ceva`])
//! cannot run on: it takes four times as long over the same frame, but asks
//! nothing of the CPU. The two models and the runtime were in the app until
//! Nov 2026; now Dart downloads them on such a computer only ([`set_files`]).

use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use ort::session::{builder::GraphOptimizationLevel, Session};
use ort::value::TensorRef;

use super::{Size, BINS, SPECTRUM};

/// What a test points at a copy of ONNX Runtime with.
const RUNTIME_ENV: &str = "RIFT_ONNXRUNTIME";

/// DPDFNet-8's and DPDFNet-2's `.onnx` files at 48 kHz, as Ceva publishes
/// them (huggingface.co/Ceva-IP/DPDFNet), and ONNX Runtime from Microsoft's
/// release, once Dart has them.
struct Files {
    large: PathBuf,
    small: PathBuf,
    runtime: PathBuf,
}

static FILES: Mutex<Option<Files>> = Mutex::new(None);

/// Names the downloaded models and runtime, for every model loaded after.
pub(crate) fn set_files(large: PathBuf, small: PathBuf, runtime: PathBuf) {
    *FILES.lock().unwrap_or_else(|e| e.into_inner()) = Some(Files {
        large,
        small,
        runtime,
    });
}

/// One model's file: in a test, the copy in this repository (`models/`);
/// in the app, the one Dart downloaded.
fn model_path(size: Size) -> Result<PathBuf, String> {
    let name = match size {
        Size::Large => "dpdfnet8_48khz_hr.onnx",
        Size::Small => "dpdfnet2_48khz_hr.onnx",
    };
    if cfg!(test) {
        return Ok(PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("models")
            .join(name));
    }
    let files = FILES.lock().unwrap_or_else(|e| e.into_inner());
    let files = files
        .as_ref()
        .ok_or("DPDFNet's ONNX models are not downloaded yet")?;
    Ok(match size {
        Size::Large => files.large.clone(),
        Size::Small => files.small.clone(),
    })
}

/// One of the two models, and what it carries from one frame to the next.
pub(super) struct Net {
    session: Session,
    /// Everything the model keeps between frames, in one tensor.
    state: Vec<f32>,
    /// The state it starts from: zeros, but for the running means its
    /// normalisation begins at, which the model file says.
    initial: Vec<f32>,
}

impl Net {
    pub(super) fn load(size: Size) -> Result<Net, String> {
        open_runtime()?;
        let session =
            session(&model_path(size)?).map_err(|e| format!("DPDFNet would not load: {e}"))?;
        let initial = initial_state(&session)?;
        Ok(Net {
            session,
            state: initial.clone(),
            initial,
        })
    }

    /// One step, in place: the spectrum in, the cleaned one out, and the
    /// state carried on. An error leaves both as they were.
    pub(super) fn run(&mut self, spectrum: &mut [f32; SPECTRUM]) -> ort::Result<()> {
        let outputs = self.session.run(ort::inputs![
            "spec" => TensorRef::from_array_view(([1usize, 1, BINS, 2], spectrum.as_slice()))?,
            "state_in" => TensorRef::from_array_view(([self.state.len()], self.state.as_slice()))?,
        ])?;
        let (_, cleaned) = outputs["spec_e"].try_extract_tensor::<f32>()?;
        let (_, state) = outputs["state_out"].try_extract_tensor::<f32>()?;
        if cleaned.len() != spectrum.len() || state.len() != self.state.len() {
            return Err(ort::Error::new("the model's outputs changed size"));
        }
        spectrum.copy_from_slice(cleaned);
        self.state.copy_from_slice(state);
        Ok(())
    }

    pub(super) fn reset(&mut self) {
        self.state.copy_from_slice(&self.initial);
    }
}

/// Opens ONNX Runtime once it is downloaded, and once only: a computer it
/// will not open on still runs the app, without this model.
fn open_runtime() -> Result<(), String> {
    static OPENED: OnceLock<Result<(), String>> = OnceLock::new();
    if let Some(opened) = OPENED.get() {
        return opened.clone();
    }
    let path = match std::env::var_os(RUNTIME_ENV) {
        Some(path) => PathBuf::from(path),
        None => FILES
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|files| files.runtime.clone())
            // Not kept: it opens once the download lands.
            .ok_or("ONNX Runtime is not downloaded yet")?,
    };
    OPENED
        .get_or_init(|| {
            ort::init_from(&path)
                .map_err(|e| format!("ONNX Runtime did not open: {e}"))?
                .commit();
            Ok(())
        })
        .clone()
}

/// One thread: the model's own runs it, and a frame is too small to share
/// out.
fn session(onnx: &std::path::Path) -> Result<Session, String> {
    Session::builder()
        .map_err(|e| e.to_string())?
        .with_optimization_level(GraphOptimizationLevel::Level3)
        .map_err(|e| e.to_string())?
        .with_intra_threads(1)
        .map_err(|e| e.to_string())?
        .with_inter_threads(1)
        .map_err(|e| e.to_string())?
        .commit_from_file(onnx)
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
