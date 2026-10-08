#!/usr/bin/env bash
# Builds librift_ffenc.so into OUT_DIR: FFmpeg's VAAPI encoders, patched
# (third_party/ffmpeg/RIFT_PATCHES.md), in a library of their own (ffenc.h
# says why). The Linux runner's CMake runs it; it can also run by hand.
#
#   native/ffenc/build.sh OUT_DIR
#
# Needs a C compiler, make and libva's headers (libva-dev). The FFmpeg tarball
# is downloaded once into OUT_DIR, or taken from RIFT_FFMPEG_TARBALL, and its
# sha256 checked either way. Nothing is rebuilt while the inputs are the same.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
patches=$here/../../third_party/ffmpeg
out=$(mkdir -p "${1:?usage: native/ffenc/build.sh OUT_DIR}" && cd "$1" && pwd)

version=9.0.2
sha256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
cc=${CC:-cc}

# Only the encoders' own library and its utilities, statically, with nothing
# found on the build machine pulled in behind our back.
configure_flags=(
  --disable-everything --disable-autodetect --disable-programs --disable-doc
  --disable-network --disable-avformat --disable-avfilter --disable-avdevice
  --disable-swscale --disable-swresample --disable-x86asm --disable-debug
  --enable-static --disable-shared --enable-pic
  --enable-vaapi --enable-encoder=h264_vaapi
)

stamp=$(
  {
    echo "$version $sha256 $cc ${configure_flags[*]}"
    cat "$patches"/*.patch "$here/ffenc.c" "$here/ffenc.h" "$0"
  } | sha256sum | cut -d' ' -f1
)
library=$out/librift_ffenc.so
if [[ -f $library && -f $out/.stamp && $(<"$out/.stamp") == "$stamp" ]]; then
  exit 0
fi

tarball=${RIFT_FFMPEG_TARBALL:-$out/ffmpeg-$version.tar.xz}
if [[ ! -f $tarball ]]; then
  curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" -o "$tarball.part"
  mv "$tarball.part" "$tarball"
fi
echo "$sha256  $tarball" | sha256sum -c --quiet

src=$out/ffmpeg-$version
prefix=$out/prefix
rm -rf "$src" "$prefix"
tar -C "$out" -xf "$tarball"
for patch in "$patches"/*.patch; do
  patch -d "$src" -p1 --quiet <"$patch"
done
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
(
  cd "$src"
  quietly "$out/build.log" ./configure --prefix="$prefix" --cc="$cc" "${configure_flags[@]}"
  quietly "$out/build.log" make -j"$(nproc)"
  quietly "$out/build.log" make install
)

# Every FFmpeg symbol hidden and bound inside the library, so neither
# libwebrtc's FFmpeg nor any other copy in the process can take their place.
"$cc" -shared -fPIC -O2 -fvisibility=hidden -I"$prefix/include" \
  "$here/ffenc.c" -o "$library.part" \
  "$prefix/lib/libavcodec.a" "$prefix/lib/libavutil.a" \
  -lva -lva-drm -lm -pthread \
  -Wl,--exclude-libs,ALL -Wl,-Bsymbolic -Wl,-z,defs
mv "$library.part" "$library"
rm -rf "$src"
echo "$stamp" >"$out/.stamp"
