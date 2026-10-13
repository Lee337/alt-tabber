#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
APP_DIR="$ROOT_DIR/dist/AltTabber.app"
OUTPUT_PATH="$ROOT_DIR/dist/AltTabber-v${VERSION}-macOS.pkg"

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
    /bin/zsh "$ROOT_DIR/scripts/build-app.sh"
fi

if [[ ! -d "$APP_DIR" ]]; then
    echo "Missing app bundle: $APP_DIR" >&2
    exit 1
fi

PACKAGE_ARGUMENTS=(
    --component "$APP_DIR"
    --install-location /Applications
    --identifier com.local.AltTabber.installer
    --version "$VERSION"
)

if [[ -n "${INSTALLER_SIGNING_IDENTITY:-}" ]]; then
    PACKAGE_ARGUMENTS+=(--sign "$INSTALLER_SIGNING_IDENTITY")
fi

rm -f "$OUTPUT_PATH"
/usr/bin/pkgbuild "${PACKAGE_ARGUMENTS[@]}" "$OUTPUT_PATH"

echo "$OUTPUT_PATH"
