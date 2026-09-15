#!/bin/bash
# Build rodroid il2cpp_dumper for iOS arm64 (requires rustup + Xcode SDK).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${IL2CPP_DUMPER_RS_SRC:-/tmp/il2cpp-dumper-rs-master}"
CARGO="${CARGO:-$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

if [[ ! -f "$SRC/Cargo.toml" ]]; then
  echo "Clone https://github.com/rodroidmods/il2cpp-dumper-rs into $SRC first."
  exit 1
fi

export RUSTFLAGS="-C link-arg=-isysroot -C link-arg=$SDK -C link-arg=-miphoneos-version-min=16.0"
cd "$SRC"
"$CARGO" build --release --target aarch64-apple-ios

OUT="$SRC/target/aarch64-apple-ios/release/il2cpp_dumper"
DEST="$ROOT/FluckDumper/iOS-Dump/il2cpp_dumper"
cp "$OUT" "$DEST"
chmod +x "$DEST"
echo "Installed: $DEST"
