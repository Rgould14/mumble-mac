#!/bin/bash
# Builds OpenFlow.app from the SwiftPM executable (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/OpenFlow"
APP="dist/OpenFlow.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenFlow"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Sign with the stable self-signed "OpenFlow Dev" identity if present, so the
# app's designated requirement (and therefore Accessibility/Mic/Speech grants)
# survives rebuilds. Falls back to ad-hoc — which resets permissions on every
# build. Run ./setup-signing.sh once to create the identity.
if codesign --force --sign "OpenFlow Dev" --identifier com.team.openflow "$APP" 2>/dev/null; then
    echo "Signed with stable 'OpenFlow Dev' identity — permissions persist across rebuilds."
else
    codesign --force --sign - --identifier com.team.openflow "$APP"
    echo "WARNING: ad-hoc signed — permissions reset each build. Run ./setup-signing.sh."
fi

echo "Built $APP"
echo "Run: open $APP"
