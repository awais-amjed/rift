#!/usr/bin/env bash
# Builds the Linux release and packs it as
# build/release/rift-<version>-linux-x64.tar.gz.
#
# The Rust crate is built first, on purpose: cargokit otherwise copies
# whatever rust/target already holds into the bundle, and a library older than
# the Dart bindings crashes at launch on a content-hash mismatch.
#
# The archive runs on systems whose glibc is at least as new as the one it was
# built against, so build it on the oldest system it should run on. The
# release workflow builds in Ubuntu 24.04; the last line says what the result
# needs.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/^version: //p' pubspec.yaml)
version=${version%%+*}
name=rift-$version-linux-x64

(cd rust && cargo build --release --target x86_64-unknown-linux-gnu)
flutter build linux --release

mkdir -p build/release
rm -rf "build/release/$name" "build/release/$name.tar.gz"
cp -r build/linux/x64/release/bundle "build/release/$name"
tar -C build/release -czf "build/release/$name.tar.gz" "$name"
rm -rf "build/release/$name"

glibc=$(objdump -T build/linux/x64/release/bundle/rift build/linux/x64/release/bundle/lib/*.so |
  grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)
echo "build/release/$name.tar.gz (needs ${glibc/_/ } or newer)"
