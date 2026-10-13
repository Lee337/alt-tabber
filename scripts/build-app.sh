#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/dist/AltTabber.app"
CONTENTS_DIR="$APP_DIR/Contents"
cd "$ROOT_DIR"
/bin/zsh scripts/swift.sh build -c release
BIN_DIR="$(/bin/zsh scripts/swift.sh build -c release --show-bin-path)"

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/AltTabber" "$CONTENTS_DIR/MacOS/AltTabber"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/Assets.car" "$CONTENTS_DIR/Resources/Assets.car"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/AppIcon.png" "$CONTENTS_DIR/Resources/AppIcon.png"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    # Give local ad-hoc builds a stable designated requirement. Without this,
    # codesign uses the executable hash and macOS treats every rebuild as a new
    # Screen Recording/Accessibility client.
    codesign \
        --force \
        --deep \
        --sign - \
        --requirements '=designated => identifier "com.local.AltTabber"' \
        "$APP_DIR"
else
    codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi

# Finder displays the app bundle directory's modification date. Reusing the
# bundle leaves that timestamp stale even though its executable was replaced.
/usr/bin/touch "$APP_DIR"

echo "$APP_DIR"
