#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app="$PWD/dist/SpeakWay.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/SpeakWay" "$app/Contents/MacOS/SpeakWay"
cp Resources/Info.plist "$app/Contents/Info.plist"
# macOS pins Accessibility grants to the signature. An ad hoc signature changes on every
# build, so prefer a stable certificate and fall back to ad hoc only when none exists.
identity="${SPEAKWAY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ { print $2; exit }')}"
codesign --force --sign "${identity:--}" --entitlements Resources/SpeakWay.entitlements "$app"
printf 'Built %s (signed: %s)\n' "$app" "${identity:-ad hoc}"
