# RNNoise in Rift

RNNoise 0.2 (Jean-Marc Valin, Xiph.Org; BSD-3-Clause, see `COPYING`), from
the release tarball `rnnoise-0.2.tar.gz` (sha256
`90fce4b00b9ff24c08dbfe31b82ffd43bae383d85c5535676d28b0a2b11c0d37`), which
carries the trained model as `src/rnnoise_data.c`. The git repository leaves
the model out and downloads it at build time, which is why the tarball.

**No patches.** It is here, rather than fetched, so a build needs no network
and the model is the one that was measured. Only the library is kept: the
demo, the training tools and the x86 run-time dispatch are left out, apart
from `src/x86/x86_arch_macros.h`, which `vec.h` includes on every build.

`native/noise_filter/CMakeLists.txt` builds it as plain C with no SIMD flags,
so it takes the SSE2 path every x64 compiler but MSVC turns on by itself; MSVC
is told to. (The fully generic path includes `os_support.h`, which the
tarball does not ship.) A 10 ms frame takes well under a tenth of a
millisecond, about 2% of one core.

To update: replace these files from a newer release tarball, keep the list
above true, and replace `assets/licenses/rnnoise.txt` with its `COPYING`.
