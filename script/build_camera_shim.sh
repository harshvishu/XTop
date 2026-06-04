#!/usr/bin/env bash
# Builds XTopCameraShim.dylib as a universal arm64 + x86_64 iOS-simulator
# library, ad-hoc signs it, and copies it into XTop/Resources/ so the
# synchronized file group picks it up as a bundled resource.
#
# Re-run whenever XTopCameraShim/*.m changes. The result is committed to
# the repo so the macOS build does not need to re-invoke clang.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT_DIR/XTopCameraShim/XTopCameraShim.m"
OUT_DIR="$ROOT_DIR/XTop/Resources"
# Use `.bin` so the macOS host app does NOT try to link this iOS-simulator
# dylib at build time. simctl's DYLD_INSERT_LIBRARIES is extension-agnostic.
OUT="$OUT_DIR/XTopCameraShim.bin"
BUILD_DIR="$ROOT_DIR/.build/camera-shim"

if [[ ! -f "$SRC" ]]; then
    echo "error: shim source not found at $SRC" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR" "$OUT_DIR"

ARM64_OUT="$BUILD_DIR/XTopCameraShim.arm64.dylib"
X86_OUT="$BUILD_DIR/XTopCameraShim.x86_64.dylib"

COMMON_FLAGS=(
    -dynamiclib
    -fobjc-arc
    -fmodules
    -fvisibility=hidden
    -framework Foundation
    -framework AVFoundation
    -framework CoreMedia
    -framework CoreVideo
    -framework Network
    -O2
)

echo "→ compiling arm64 slice"
xcrun -sdk iphonesimulator clang \
    -target arm64-apple-ios15.0-simulator \
    "${COMMON_FLAGS[@]}" \
    -o "$ARM64_OUT" \
    "$SRC"

echo "→ compiling x86_64 slice"
xcrun -sdk iphonesimulator clang \
    -target x86_64-apple-ios15.0-simulator \
    "${COMMON_FLAGS[@]}" \
    -o "$X86_OUT" \
    "$SRC"

echo "→ lipo into universal binary"
xcrun lipo -create "$ARM64_OUT" "$X86_OUT" -output "$OUT"

echo "→ ad-hoc signing"
xcrun codesign --force --sign - "$OUT"

echo "→ verifying"
xcrun lipo -info "$OUT"
xcrun codesign -dv "$OUT" 2>&1 | head -5

echo "✓ wrote $OUT"
