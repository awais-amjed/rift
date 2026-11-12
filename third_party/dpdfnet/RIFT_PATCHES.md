# Ceva's runtime for DPDFNet, patched

Ceva's own inference runtime for the two DPDFNet models Rift runs on the
microphone, `dpdfnet2_48khz_hr` and `dpdfnet8_48khz_hr` (Apache-2.0): the
folder `optimized_inference` on the branch `optimized-inference` of
`https://github.com/ceva-ip/DPDFNet`, at commit
`98df76589cdf7787553b9e05a112d5820e6c8db6` (Nov 6 2026, the latest there on
Nov 12 2026). It is C with AVX2 and AVX-VNNI assembly, on one thread, with
nothing under it but the C library, and it carries the models' weights
(`models/<model>/weights.f32`, made by Ceva from the same ONNX files that are
in `rust/models`: each `manifest.json` names its file's sha256, and they
match). Only the patch is kept here. `native/dpdfnet/build.sh` downloads the
commit's archive and checks its sha256 before every build, and the weights'
against Ceva's `models/SHA256SUMS`.

It is built into a library of its own, `rift_dpdfnet.dll` on Windows
(`native/dpdfnet`, which says why and what it measures), with the weights
inside and only Rift's few functions leaving it. The build compiles the files
Ceva's `CMakeLists.txt` does with the flags it gives each, rather than running
that CMake, which refuses anything but Linux. Not taken: the compiler profile
Ceva's release build trains for DPDFNet-8, so every build of one compiler
gives the same library.

Ceva builds and supports it on Linux x86-64 with GCC only, and it is new: the
measurements in its own docs are from October 2026. So the build is checked
each time it matters with `native/dpdfnet/test.sh`, which runs Ceva's own contract tests
on the objects the library is linked from, on Windows too. They passed there
on Nov 12 2026 (an i7-12700H, MSYS2's GCC 16.2), the AVX-VNNI ones included.

On Linux it is `librift_dpdfnet.so`, built with gcc and no patch needed beyond
the one below. `test.sh` passed there on Nov 13 2026 with GCC 16.2 (the same
i7-12700H) and with Ubuntu 24.04's GCC 13.3, which the Linux release builds
with; the library needs glibc 2.27.

## `sysv-kernels.patch`

The assembly kernels take their arguments as Linux hands them over (the System
V calling convention: RDI, RSI, RDX, and so on). Windows hands them over in
other registers, and expects RSI, RDI and XMM6 to XMM15 back unchanged, which
System V does not. The patch marks the kernels' five prototypes
`__attribute__((sysv_abi))`, and the three in Ceva's tests that name the same
kernels. GCC then calls them the System V way from Windows code and saves
those registers round the call. On Linux the attribute says what is already
so.

The kernels themselves are untouched: leaf functions that never move the
stack pointer, so they need nothing else from Windows. `test.sh` checks the
saving on the real models (`test_registers.S`): the Rust library is built by
MSVC and counts on those registers across every frame.

## Not a patch: the ELF directives

On Windows `build.sh` deletes, with `sed`, the lines of each `.S` file that
only an ELF object can carry (`.hidden`, `.type`, `.size`, `.cfi_startproc`,
`.cfi_endproc`, the `.note.GNU-stack` section). They hold no code.
