#!/usr/bin/env bash
# Builds and runs the clip store's tests under ThreadSanitizer, without
# libwebrtc: the store is plain C++ and the glue to libwebrtc is call_clip.cc.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${TMPDIR:-/tmp}/rift_clip_store_test"
c++ -std=c++17 -O1 -g -fsanitize=thread -Wall -Wextra \
  "$here/test/clip_store_test.cc" "$here/clip_store.cc" \
  "$here/../noise_filter/rate_converter.cc" -o "$out"
"$out"
