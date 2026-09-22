#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x RewindButFast >/dev/null; then
    printf 'Quit Seen Completely before replacing the app. Use Option-Command-Q.\n' >&2
    exit 1
fi
swift build -c release
app="$PWD/dist/Seen.app"
if [[ ! -d "$app" && -d "$PWD/dist/Rewind But Fast.app" ]]; then
    mv "$PWD/dist/Rewind But Fast.app" "$app"
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/RewindButFast "$app/Contents/MacOS/RewindButFast"
cp scripts/Info.plist "$app/Contents/Info.plist"
iconset="$PWD/.build/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning | awk '/Apple Development:/ {print $2; exit}')"
fi
codesign --force --sign "${identity:--}" "$app"
printf 'Built %s\n' "$app"
