# RNNoise in Rift

RNNoise (Jean-Marc Valin, Xiph.Org; BSD-3-Clause, see `COPYING`) at commit
`70f1d256acd4b34a572f999a05c87bf00b67730d` (Feb 22 2025) of
https://gitlab.xiph.org/xiph/rnnoise, the latest there on Oct 5 2026. It is
newer than the last release, 0.2 (Apr 2024), by a network whose output reads
all three of its recurrent layers, a model trained for it on more noise
(Jan 2025), and a fix that stops noise leaking through when it gets suddenly
louder, such as a key being struck.

The repository leaves the trained model out and downloads it at build time
(`download_model.sh`). Here it is `src/rnnoise_data.c` and `.h`, from
`rnnoise_data-0a8755f8e2d834eff6a54714ecc7d75f9932e845df35f8b59bc52a7cfe6e8b37.tar.gz`
on media.xiph.org (named for its sha256, which was checked). That is the
default model, not the "little" one in the same archive.

**One change:** `rnnoise_data.c` has its `#ifndef DISABLE_DEBUG_FLOAT` blocks
removed. They hold float copies of the weights for debugging, which a build with
`DISABLE_DEBUG_FLOAT` leaves out anyway, and which made the file 78 MB instead
of 16. The library built from this file and from the original with
`DISABLE_DEBUG_FLOAT` gave identical output, sample for sample. The build
defines it too (`native/noise_filter/CMakeLists.txt`).

It is here, rather than fetched, so a build needs no network and the model is
the one that was measured. Only the library is kept: the demo, the training
tools and the x86 run-time dispatch are left out, apart from
`src/x86/x86_arch_macros.h` and `src/x86/x86cpu.h`, which the SSE2 path
includes.

`native/noise_filter/CMakeLists.txt` builds it as plain C with no SIMD flags,
so it takes the SSE2 path, which every x64 compiler but MSVC turns on by
itself; MSVC is told to. A 10 ms frame takes under 0.2 ms.

Measured against 0.2 before the update (Oct 5 2026, offline, 48 kHz, noise at
−30 dBFS under speech at −21):
- Real speech (DeepFilterNet's `clean_freesound_33711` and ALSA's
  `Front_Center`) came through as well as before: 0.993 against 0.994.
- Two real noise recordings were left at −64 and −70 dBFS, against −60 and −46.
- Keyboard-like clicks were left at −102 dBFS, against −56.
- Steady pink noise was left at −72 dBFS, against −84. Both are far below
  hearing.
- CPU: 0.17 ms a frame against 0.10. The binary grew by about 2 MB.

To update: replace these files from the repository at a newer commit and its
`model_version`'s model, strip the debug floats again, keep the list above
true, and replace `assets/licenses/rnnoise.txt` with its `COPYING` if that
changed.
