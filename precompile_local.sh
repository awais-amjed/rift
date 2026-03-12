#!/bin/bash
# Script to precompile Rust binaries locally for use without GitHub download

set -e

echo "Building Rust library locally..."

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
RUST_DIR="$PROJECT_ROOT/rust"

# Compute the crate hash
cd "$PROJECT_ROOT/rust_builder/cargokit/build_tool"
CRATE_HASH=$(dart run bin/build_tool.dart 2>&1 | grep -oP 'crate hash \K[a-f0-9]+' || echo "")

if [ -z "$CRATE_HASH" ]; then
    # Alternative: compute hash manually by reading source
    echo "Computing crate hash..."
    # We'll use a temp build to get the hash
    cd "$RUST_DIR"
    cargo build --release --target x86_64-pc-windows-msvc 2>&1 || true
fi

echo "Building for Windows..."
cd "$RUST_DIR"
cargo build --release --target x86_64-pc-windows-msvc

echo "Build completed successfully!"
echo "Binaries are in: $RUST_DIR/target/x86_64-pc-windows-msvc/release/"

