#!/bin/bash
# Creates a stable self-signed code-signing certificate ("Mumble Dev") in the
# login keychain, once. A stable signing identity keeps the app's designated
# requirement constant across rebuilds, so macOS Accessibility / Microphone /
# Speech permissions granted once survive every future `./build-app.sh`.
#
# Ad-hoc signing (codesign -s -) changes the code hash on every build, which
# silently invalidates those TCC grants — this fixes that for good.
#
# Run once per machine:  ./setup-signing.sh
set -euo pipefail

CERT_NAME="Mumble Dev"

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "Signing identity \"$CERT_NAME\" already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Self-signed cert with a code-signing EKU (codesign requires this; the cert
# does NOT need to be in the system trust store to sign locally).
openssl req -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" \
    -x509 -days 3650 -out "$TMP/cert.pem" \
    -subj "/CN=$CERT_NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# A non-empty password is required for the PKCS12 MAC to verify on import.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:mumble -name "$CERT_NAME"

# -A lets codesign use the private key without a keychain prompt on every build.
security import "$TMP/cert.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "mumble" -T /usr/bin/codesign -A

echo "Created signing identity \"$CERT_NAME\"."
echo "Now run ./build-app.sh and grant permissions once — they'll persist."
