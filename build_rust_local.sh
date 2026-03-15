#!/bin/bash
# Script to build Rust library locally on Linux

set -e

echo "Building Rust library for Linux..."
echo ""

echo "Generating Flutter Rust Bridge bindings..."
flutter_rust_bridge_codegen generate

echo ""
cd rust

# Build for the current platform (Linux x64)
echo "Building for x86_64-unknown-linux-gnu (release mode)..."
cargo build --release --target x86_64-unknown-linux-gnu

cd ..


echo ""
echo "========================================"
echo "Build completed successfully!"
echo "========================================"
echo ""
echo "Binaries are located in:"
echo "  rust/target/x86_64-unknown-linux-gnu/release/"
echo ""
echo "The Flutter build will now use these precompiled binaries"
echo "instead of building from scratch each time."
echo ""

