#!/bin/bash
# Builds Mumble.app from the SwiftPM executable (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Mumble"
APP="dist/Mumble.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Mumble"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Design-system resources: app icon, logos, Goodly fonts.
cp Support/Assets/AppIcon.icns "$APP/Contents/Resources/"
cp Support/Assets/logo-navy.png Support/Assets/logo-horizontal.png "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Fonts"
cp Support/Assets/Fonts/*.otf "$APP/Contents/Resources/Fonts/"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM's resource bundle (e.g. Mumble_Mumble.bundle, holding MenuBarIcon.png) is built
# alongside the binary — Bundle.module looks for it next to the executable at runtime, so
# it has to land in Contents/Resources, not just .build.
for bundle in ".build/$CONFIG"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Sign with the stable self-signed "Mumble Dev" identity if present, so the
# app's designated requirement (and therefore Accessibility/Mic/Speech grants)
# survives rebuilds. Falls back to ad-hoc — which resets permissions on every
# build. Run ./setup-signing.sh once to create the identity.
if codesign --force --sign "Mumble Dev" --identifier com.team.mumble "$APP" 2>/dev/null; then
    echo "Signed with stable 'Mumble Dev' identity — permissions persist across rebuilds."
else
    codesign --force --sign - --identifier com.team.mumble "$APP"
    echo "WARNING: ad-hoc signed — permissions reset each build. Run ./setup-signing.sh."
fi

echo "Built $APP"
echo "Run: open $APP"
