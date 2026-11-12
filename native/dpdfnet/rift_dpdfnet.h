// DPDFNet on Ceva's own runtime: the two 48 kHz models Rift runs on the
// microphone, in the code their maker wrote for exactly these two
// (third_party/dpdfnet/RIFT_PATCHES.md), where ONNX Runtime ran them as a
// graph of some 470 small steps. It takes a quarter of the time: in a call
// on an i7-12700H the microphone's thread took 5% of a core on DPDFNet-2 and
// 12% on DPDFNet-8, against 21% and 48% (Nov 12 2026, Windows). The sound
// measured the same on recorded speech in noise, the two runtimes' outputs
// 31 to 46 dB apart under the voice, and the owner heard no difference.
//
// A library of its own, which the Rust crate opens at run time
// (rust/src/dpdfnet/ceva.rs), because it is built with GCC: its kernels are
// GNU assembly, written to the System V calling convention, and the Rust
// library on Windows is built with MSVC. It needs a CPU with AVX2 and FMA. On
// one without, or where the library is missing, the crate runs the same
// models on ONNX Runtime as before.
//
// The weights are inside the library (weights.S), so there is nothing to find
// at run time, and what was checked when it was built is what runs.
#ifndef RIFT_DPDFNET_H_
#define RIFT_DPDFNET_H_

#if defined(_WIN32)
#define RIFT_DPDFNET_EXPORT __declspec(dllexport)
#else
#define RIFT_DPDFNET_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Raised whenever a function here changes, so the Rust crate refuses a
// library built for another version of it (ABI in rust/src/dpdfnet/ceva.rs).
#define RIFT_DPDFNET_ABI 1
RIFT_DPDFNET_EXPORT int rift_dpdfnet_abi(void);

// One model, and what it carries from one frame to the next.
typedef struct rift_dpdfnet_model rift_dpdfnet_model;

// How many floats a spectrum is: 481 bins, real and imaginary side by side.
#define RIFT_DPDFNET_SPECTRUM 962

// Whether this CPU can run the models here: AVX2 and FMA, and a system that
// keeps their registers.
RIFT_DPDFNET_EXPORT int rift_dpdfnet_model_supported(void);

// DPDFNet-2 for `size` 2, DPDFNet-8 for 8, ready for its first frame. NULL
// for any other size, a CPU that cannot run it, or no memory. Not for the
// thread the sound is on: it packs ten megabytes of weights.
RIFT_DPDFNET_EXPORT rift_dpdfnet_model *rift_dpdfnet_model_open(int size);

// One 10 ms step, in place: the spectrum of a 960-sample window as a plain
// FFT gives it, RIFT_DPDFNET_SPECTRUM floats, in, the cleaned one out.
// Returns 0, or -1 with the spectrum untouched. Allocates nothing. One call
// at a time for each model.
RIFT_DPDFNET_EXPORT int rift_dpdfnet_model_run(rift_dpdfnet_model *model,
                                               float *spectrum);

// Forgets everything heard, as a newly opened model.
RIFT_DPDFNET_EXPORT void rift_dpdfnet_model_reset(rift_dpdfnet_model *model);

// NULL is allowed.
RIFT_DPDFNET_EXPORT void rift_dpdfnet_model_close(rift_dpdfnet_model *model);

#ifdef __cplusplus
}
#endif

#endif  // RIFT_DPDFNET_H_
