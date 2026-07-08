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

# Ad-hoc sign with a stable identifier so TCC permissions survive rebuilds.
codesign --force --sign - --identifier com.team.openflow "$APP"

echo "Built $APP"
echo "Run: open $APP"
