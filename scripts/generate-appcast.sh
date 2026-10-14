#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CHANNEL="${1:-stable}"
[[ "$CHANNEL" == stable || "$CHANNEL" == nightly ]] || { echo 'Channel must be stable or nightly.' >&2; exit 2; }
: "${ALT_TABBER_UPDATE_DOWNLOAD_PREFIX:?Set the HTTPS URL prefix for this channel's release archives.}"
: "${ALT_TABBER_UPDATE_KEY_FILE:?Set the path to the AltTabber EdDSA private key file.}"
[[ "$ALT_TABBER_UPDATE_DOWNLOAD_PREFIX" == https://* ]] || { echo 'Download prefix must use HTTPS.' >&2; exit 2; }
TOOLS_DIR="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
OUTPUT_DIR="$ROOT_DIR/dist/updates/$CHANNEL"
mkdir -p "$OUTPUT_DIR"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
[[ -f "$ROOT_DIR/dist/AltTabber-v${VERSION}-macOS.zip" ]] || { echo 'Run make release-artifacts first.' >&2; exit 2; }
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT_DIR/dist/AltTabber.app/Contents/Info.plist" 2>/dev/null || true)"
[[ -n "$PUBLIC_KEY" ]] || { echo 'Build release artifacts with ALT_TABBER_UPDATE_PUBLIC_KEY before generating a signed feed.' >&2; exit 2; }
python3 - "$ROOT_DIR/dist/AltTabber-v${VERSION}-macOS.zip" "$PUBLIC_KEY" <<'PY'
import plistlib
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    bundled_key = plistlib.loads(archive.read('AltTabber.app/Contents/Info.plist')).get('SUPublicEDKey')
if bundled_key != sys.argv[2]:
    raise SystemExit('The release ZIP does not contain the configured AltTabber update public key.')
PY
cp "$ROOT_DIR/dist/AltTabber-v${VERSION}-macOS.zip" "$OUTPUT_DIR/"
"$TOOLS_DIR/generate_appcast" --ed-key-file "$ALT_TABBER_UPDATE_KEY_FILE" --download-url-prefix "$ALT_TABBER_UPDATE_DOWNLOAD_PREFIX" "$OUTPUT_DIR"
python3 - "$OUTPUT_DIR/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
feed = ET.parse(sys.argv[1]).getroot()
signature = '{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'
items = feed.findall('./channel/item/enclosure')
if not items or any(not item.get(signature) for item in items):
    raise SystemExit('Sparkle did not sign every appcast enclosure. Check the bundled public key and signing key.')
PY
echo "$OUTPUT_DIR/appcast.xml"
