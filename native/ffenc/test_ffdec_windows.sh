#!/usr/bin/env bash
# Builds rift_ffenc.dll into OUT_DIR (build.sh) and runs its D3D11 decoder
# test (test_ffdec_d3d11.c) on every GPU in the computer. Windows, in MSYS2's
# UCRT64 shell, with FFmpeg's command-line ffmpeg (with libvpx) on the path,
# which makes the VP9 streams the library has no encoder for.
#
#   native/ffenc/test_ffdec_windows.sh OUT_DIR
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out=$(mkdir -p "${1:?usage: native/ffenc/test_ffdec_windows.sh OUT_DIR}" && cd "$1" && pwd)
command -v ffmpeg >/dev/null || {
  echo "test_ffdec_windows.sh: needs ffmpeg on the path, to encode VP9" >&2
  exit 1
}

"$here/build.sh" "$out"
"${CC:-gcc}" -O1 -g -Wall -I"$here" "$here/test_ffdec_d3d11.c" \
  -o "$out/test_ffdec_d3d11.exe" -L"$out" -lrift_ffenc -ld3d11 -ldxgi -ldxguid
export PATH="$out:$PATH"

# The same four quarters as the H264, eight pictures of them, flagged as
# BT.601 limited the way libwebrtc's VP9 is, and the same stream relabelled
# BT.709 full range, its pictures untouched: the decoder must say what the
# stream says.
"$out/test_ffdec_d3d11.exe" --yuv "$out/quarters.yuv"
ffmpeg -loglevel error -y -f rawvideo -pix_fmt yuv420p -s 1920x1080 -r 30 \
  -stream_loop 7 -i "$out/quarters.yuv" -c:v libvpx-vp9 -deadline realtime \
  -cpu-used 8 -b:v 4M -g 600 -colorspace bt470bg -color_range tv \
  "$out/quarters_vp9.ivf"
ffmpeg -loglevel error -y -i "$out/quarters_vp9.ivf" -c copy \
  -bsf:v vp9_metadata=color_space=bt709:color_range=pc \
  "$out/quarters_vp9_709_full.ivf"

"$out/test_ffdec_d3d11.exe" "$out"
