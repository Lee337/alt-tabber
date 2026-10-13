#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
APP_DIR="$ROOT_DIR/dist/AltTabber.app"
ZIP_PATH="$ROOT_DIR/dist/AltTabber-v${VERSION}-macOS.zip"
CHECKSUM_PATH="$ROOT_DIR/dist/AltTabber-v${VERSION}-SHA256SUMS.txt"

/bin/zsh "$ROOT_DIR/scripts/build-app.sh"

rm -f "$ZIP_PATH" "$CHECKSUM_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
SKIP_APP_BUILD=1 /bin/zsh "$ROOT_DIR/scripts/build-installer.sh"
SKIP_APP_BUILD=1 /bin/zsh "$ROOT_DIR/scripts/build-dmg.sh"

cd "$ROOT_DIR/dist"
/usr/bin/shasum -a 256 \
    "AltTabber-v${VERSION}-macOS.dmg" \
    "AltTabber-v${VERSION}-macOS.pkg" \
    "AltTabber-v${VERSION}-macOS.zip" \
    > "$CHECKSUM_PATH"

echo "Release artifacts:"
echo "$ROOT_DIR/dist/AltTabber-v${VERSION}-macOS.dmg"
echo "$ROOT_DIR/dist/AltTabber-v${VERSION}-macOS.pkg"
echo "$ROOT_DIR/dist/AltTabber-v${VERSION}-macOS.zip"
echo "$CHECKSUM_PATH"
