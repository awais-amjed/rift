#!/usr/bin/env bash
# Builds Rift's FFmpeg encoder library into OUT_DIR: FFmpeg's GPU encoders,
# patched (third_party/ffmpeg/RIFT_PATCHES.md), in a library of their own
# (ffenc.h says why). Each runner's CMake runs it; it can also run by hand.
#
#   native/ffenc/build.sh OUT_DIR
#
# On Linux it makes librift_ffenc.so with the VAAPI encoder, and needs a C
# compiler, make and libva's headers (libva-dev). On Windows it makes
# rift_ffenc.dll with NVIDIA's, Intel's and AMD's encoders, and runs in
# MSYS2's UCRT64 shell with make, MinGW's gcc, CMake, Ninja and pkgconf
# (windows/CMakeLists.txt starts it there). Every download is taken once
# into OUT_DIR, or FFmpeg's from RIFT_FFMPEG_TARBALL, and its sha256 checked
# either way. Nothing is rebuilt while the inputs are the same.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
patches=$here/../../third_party/ffmpeg
out=$(mkdir -p "${1:?usage: native/ffenc/build.sh OUT_DIR}" && cd "$1" && pwd)

version=9.0.2
sha256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
case "$(uname -s)" in
  Linux) os=linux ;;
  MINGW* | MSYS*) os=windows ;;
  *)
    echo "native/ffenc/build.sh: nothing to build on $(uname -s)" >&2
    exit 1
    ;;
esac
if [[ $os == linux ]]; then cc=${CC:-cc}; else cc=${CC:-gcc}; fi

# Only the encoders' own library and its utilities, statically, with nothing
# found on the build machine pulled in behind our back.
configure_flags=(
  --disable-everything --disable-autodetect --disable-programs --disable-doc
  --disable-network --disable-avformat --disable-avfilter --disable-avdevice
  --disable-swscale --disable-swresample --disable-x86asm --disable-debug
  --enable-static --disable-shared --enable-pic
)
if [[ $os == linux ]]; then
  library=$out/librift_ffenc.so
  configure_flags+=(--enable-vaapi --enable-encoder=h264_vaapi)
else
  library=$out/rift_ffenc.dll
  # Each vendor's encoder reaches its driver at run time: NVENC through
  # NVIDIA's API headers (nv-codec-headers), AMF through AMD's (AMF headers),
  # Quick Sync through Intel's dispatcher (libvpl), which finds the runtime
  # Intel's driver installs. Direct3D 11 is how AMF and Quick Sync reach the
  # GPU. All three are MIT; none needs --enable-nonfree.
  configure_flags+=(
    --enable-w32threads --enable-d3d11va
    --enable-ffnvcodec --enable-nvenc --enable-amf --enable-libvpl
    --enable-encoder=h264_nvenc,h264_qsv,h264_amf
    # libvpl is C++, and the pkg-config file it installs leaves its runtime
    # out.
    --pkg-config-flags=--static --extra-libs=-lstdc++
  )
  nv_headers=n11.1.5.4
  nv_headers_sha256=cbad7c68365ae50b03fe4cfbea05975c94406bdcc0a995bd094a3ea355656ffb
  amf_headers=v1.5.2
  amf_headers_sha256=d3c12eb324edf05e214608b6a395a51dd95770ed9d45520185d6c3a206811c99
  libvpl=2.17.0
  libvpl_sha256=4de3e2faf1e8307fb282e4a43f443191810f6a6b0a484fffa7995ba1c814c6ec
fi

stamp=$(
  {
    echo "$version $sha256 $cc ${configure_flags[*]}"
    cat "$patches"/*.patch "$here/ffenc.c" "$here/ffenc.h" "$0"
  } | sha256sum | cut -d' ' -f1
)
if [[ -f $library && -f $out/.stamp && $(<"$out/.stamp") == "$stamp" ]]; then
  exit 0
fi

# A download kept in OUT_DIR, checked against its sha256 every time.
fetch() {
  local file=$1 url=$2 sum=$3
  if [[ ! -f $file ]]; then
    curl -fsSL "$url" -o "$file.part"
    mv "$file.part" "$file"
  fi
  echo "$sum  $file" | sha256sum -c --quiet
}

# FFmpeg's own output, warnings included, goes to a log that is shown only if
# a step fails.
quietly() {
  local log=$1
  shift
  if ! "$@" >>"$log" 2>&1; then
    tail -n 40 "$log" >&2
    exit 1
  fi
}
rm -f "$out/build.log"
prefix=$out/prefix
rm -rf "$prefix"

# The headers and dispatcher Windows' encoders build against, into PREFIX
# where FFmpeg's configure finds them through pkg-config.
if [[ $os == windows ]]; then
  deps=$out/deps
  rm -rf "$deps"
  mkdir -p "$deps" "$prefix/include"

  fetch "$out/nv-codec-headers-$nv_headers.tar.gz" \
    "https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/$nv_headers.tar.gz" \
    "$nv_headers_sha256"
  tar -C "$deps" -xzf "$out/nv-codec-headers-$nv_headers.tar.gz"
  quietly "$out/build.log" make -C "$deps/nv-codec-headers-$nv_headers" \
    PREFIX="$prefix" install

  fetch "$out/AMF-headers-$amf_headers.tar.gz" \
    "https://github.com/GPUOpen-LibrariesAndSDKs/AMF/releases/download/$amf_headers/AMF-headers-$amf_headers.tar.gz" \
    "$amf_headers_sha256"
  tar -C "$deps" -xzf "$out/AMF-headers-$amf_headers.tar.gz"
  cp -r "$deps/amf-headers-$amf_headers/AMF" "$prefix/include/"

  fetch "$out/libvpl-$libvpl.tar.gz" \
    "https://github.com/intel/libvpl/archive/refs/tags/v$libvpl.tar.gz" \
    "$libvpl_sha256"
  tar -C "$deps" -xzf "$out/libvpl-$libvpl.tar.gz"
  # Its stand-ins for old MSVC's missing wcscpy_s and wcscat_s are guarded
  # by `_MSC_VER < 1400`, which is also true where _MSC_VER is undefined, so
  # under MinGW they replace the real ones and break Windows' own headers.
  sed -i 's/^#if _MSC_VER < 1400$/#if defined(_MSC_VER) \&\& _MSC_VER < 1400/' \
    "$deps/libvpl-$libvpl/libvpl/src/windows/mfx_dispatcher_defs.h"
  quietly "$out/build.log" cmake -S "$deps/libvpl-$libvpl" -B "$deps/libvpl-build" \
    -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF \
    -DINSTALL_EXAMPLES=OFF
  quietly "$out/build.log" cmake --build "$deps/libvpl-build"
  quietly "$out/build.log" cmake --install "$deps/libvpl-build"
  export PKG_CONFIG_PATH=$prefix/lib/pkgconfig
fi

fetch "${RIFT_FFMPEG_TARBALL:-$out/ffmpeg-$version.tar.xz}" \
  "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" "$sha256"
src=$out/ffmpeg-$version
rm -rf "$src"
tar -C "$out" -xf "${RIFT_FFMPEG_TARBALL:-$out/ffmpeg-$version.tar.xz}"
for patch in "$patches"/*.patch; do
  patch -d "$src" -p1 --quiet <"$patch"
done
(
  cd "$src"
  quietly "$out/build.log" ./configure --prefix="$prefix" --cc="$cc" \
    --extra-cflags="-I$prefix/include" "${configure_flags[@]}"
  quietly "$out/build.log" make -j"$(nproc)"
  quietly "$out/build.log" make install
)

# Every FFmpeg symbol hidden and bound inside the library, so neither
# libwebrtc's FFmpeg nor any other copy in the process can take their place.
if [[ $os == linux ]]; then
  "$cc" -shared -fPIC -O2 -fvisibility=hidden -I"$prefix/include" \
    "$here/ffenc.c" -o "$library.part" \
    "$prefix/lib/libavcodec.a" "$prefix/lib/libavutil.a" \
    -lva -lva-drm -lm -pthread \
    -Wl,--exclude-libs,ALL -Wl,-Bsymbolic -Wl,-z,defs
else
  # A DLL exports only what is marked to (RIFT_FFENC_EXPORT), and carries
  # MinGW's own runtime inside it, so it needs nothing the app does not ship:
  # only Windows' DLLs, which `objdump -p` lists.
  "$cc" -shared -O2 -I"$prefix/include" \
    "$here/ffenc.c" -o "$library.part" \
    "$prefix/lib/libavcodec.a" "$prefix/lib/libavutil.a" "$prefix/lib/libvpl.a" \
    -static-libgcc -static-libstdc++ \
    -Wl,-Bstatic -lstdc++ -lwinpthread -Wl,-Bdynamic \
    -lole32 -luuid -ld3d11 -ldxgi -lbcrypt -lshlwapi -luser32 -ladvapi32 \
    -Wl,--exclude-libs,ALL
fi
mv "$library.part" "$library"
rm -rf "$src" "${deps:-}"
echo "$stamp" >"$out/.stamp"
