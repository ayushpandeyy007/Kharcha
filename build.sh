#!/usr/bin/env bash
# Builds Kharcha.app (universal: Apple Silicon + Intel, ad-hoc signed).
# Usage: ./build.sh            build into ./build
#        ./build.sh install    build, copy to /Applications and launch
#        ./build.sh release    build and zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

NAME=Kharcha
APP="build/$NAME.app"
MIN_OS=14.0
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ ! -f Resources/AppIcon.icns ]]; then
  echo "▸ Rendering app icon"
  swift scripts/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

for arch in arm64 x86_64; do
  echo "▸ Compiling $arch"
  swiftc -O -wmo -parse-as-library -swift-version 5 \
    -target "$arch-apple-macos$MIN_OS" \
    -Xlinker -dead_strip \
    Sources/*.swift -o "build/$NAME-$arch"
done

lipo -create "build/$NAME-arm64" "build/$NAME-x86_64" -output "$APP/Contents/MacOS/$NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
rm -f build/$NAME-arm64 build/$NAME-x86_64

echo "✓ Built $APP v$VERSION ($(du -sh "$APP" | cut -f1))"

case "${1:-}" in
  install)
    pkill -x "$NAME" 2>/dev/null || true
    rm -rf "/Applications/$NAME.app"
    ditto "$APP" "/Applications/$NAME.app"
    open "/Applications/$NAME.app"
    echo "✓ Installed to /Applications and launched"
    ;;
  release)
    ZIP="build/$NAME-$VERSION.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    echo "✓ Packaged $ZIP ($(du -h "$ZIP" | cut -f1))"
    ;;
esac
