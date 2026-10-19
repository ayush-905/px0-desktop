#!/bin/bash
# Builds "px0 Desktop.app" with the Xcode Command Line Tools; no Xcode project needed.
#   ./build.sh           build into build/
#   ./build.sh install   build, then copy the app to /Applications (or $INSTALL_DIR)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/px0 Desktop.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# One binary for both Apple Silicon and Intel Macs.
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos12.0" -o "build/px0-desktop-$arch" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/px0-desktop" build/px0-desktop-arm64 build/px0-desktop-x86_64
cp Info.plist "$APP/Contents/Info.plist"
# Extra px0 themes, added to every px0 page (see Sources/ThemeScript.swift).
cp -R Themes "$APP/Contents/Resources/Themes"

# The icon is drawn once; delete build/AppIcon.icns to draw it again.
if [ ! -f build/AppIcon.icns ]; then
  swiftc -O -o build/make-icon scripts/make-icon.swift
  build/make-icon build/icon.png
  rm -rf build/AppIcon.iconset
  mkdir build/AppIcon.iconset
  for size in 16 32 128 256 512; do
    sips -z $size $size build/icon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) build/icon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# An ad-hoc signature is all a locally built app needs to run.
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  DEST="${INSTALL_DIR:-/Applications}"
  if pgrep -xq px0-desktop; then
    echo "Quit px0 Desktop first, then run ./build.sh install again." >&2
    exit 1
  fi
  rm -rf "$DEST/px0 Desktop.app"
  cp -R "$APP" "$DEST/"
  echo "Installed $DEST/px0 Desktop.app"
fi
