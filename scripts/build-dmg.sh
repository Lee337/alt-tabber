#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
APP_DIR="$ROOT_DIR/dist/AltTabber.app"
OUTPUT_PATH="$ROOT_DIR/dist/AltTabber-v${VERSION}-macOS.dmg"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/AltTabber-dmg.XXXXXX")"
VOLUME_DIR="$WORK_DIR/AltTabber"

cleanup() {
    /bin/rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
    /bin/zsh "$ROOT_DIR/scripts/build-app.sh"
fi

if [[ ! -d "$APP_DIR" ]]; then
    echo "Missing app bundle: $APP_DIR" >&2
    exit 1
fi

mkdir -p "$VOLUME_DIR"
/usr/bin/ditto "$APP_DIR" "$VOLUME_DIR/AltTabber.app"
/bin/ln -s /Applications "$VOLUME_DIR/Applications"

rm -f "$OUTPUT_PATH"
/usr/bin/hdiutil create \
    -volname "AltTabber $VERSION" \
    -srcfolder "$VOLUME_DIR" \
    -format UDZO \
    -ov \
    "$OUTPUT_PATH"

if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    /usr/bin/codesign --force --sign "$CODE_SIGN_IDENTITY" "$OUTPUT_PATH"
fi

/usr/bin/hdiutil verify "$OUTPUT_PATH"
echo "$OUTPUT_PATH"
