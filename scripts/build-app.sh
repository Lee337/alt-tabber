#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/dist/AltTabber.app"
CONTENTS_DIR="$APP_DIR/Contents"
cd "$ROOT_DIR"
BUILD_ARGUMENTS=(-c release)
if [[ "${ALT_TABBER_DISABLE_SANDBOX:-0}" == "1" ]]; then
    BUILD_ARGUMENTS+=(--disable-sandbox)
fi
if [[ "${ALT_TABBER_UNIVERSAL:-1}" == "1" ]]; then
    BUILD_ARGUMENTS+=(--arch arm64 --arch x86_64)
fi
/bin/zsh scripts/swift.sh build "${BUILD_ARGUMENTS[@]}"
BIN_DIR="$(/bin/zsh scripts/swift.sh build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/AltTabber" "$CONTENTS_DIR/MacOS/AltTabber"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
python3 - "$CONTENTS_DIR/Info.plist" <<'PYMETA'
import os, plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as stream:
    info = plistlib.load(stream)
for env, key in [('ALT_TABBER_UPDATE_PUBLIC_KEY', 'SUPublicEDKey'),
                 ('ALT_TABBER_STABLE_FEED_URL', 'SUFeedURL'),
                 ('ALT_TABBER_NIGHTLY_FEED_URL', 'AltTabberNightlyFeedURL'),
                 ('ALT_TABBER_BUILD_NUMBER', 'CFBundleVersion')]:
    if os.environ.get(env):
        info[key] = os.environ[env]
info['SUEnableAutomaticChecks'] = False
info['SUAutomaticallyUpdate'] = False
with open(path, 'wb') as stream:
    plistlib.dump(info, stream)
PYMETA
mkdir -p "$CONTENTS_DIR/Frameworks"
/usr/bin/ditto "$BIN_DIR/Sparkle.framework" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$CONTENTS_DIR/MacOS/AltTabber"
cp "$ROOT_DIR/Resources/Assets.car" "$CONTENTS_DIR/Resources/Assets.car"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/AppIcon.png" "$CONTENTS_DIR/Resources/AppIcon.png"
cp "$ROOT_DIR/Resources/AltTabber.sdef" "$CONTENTS_DIR/Resources/AltTabber.sdef"
mkdir -p "$CONTENTS_DIR/Resources/bin"
cp "$ROOT_DIR/scripts/alttabber" "$CONTENTS_DIR/Resources/bin/alttabber"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGNING_ARGUMENTS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    SIGNING_ARGUMENTS+=(--options runtime)
fi
SPARKLE_VERSION_DIR="$CONTENTS_DIR/Frameworks/Sparkle.framework/Versions/B"
codesign "${SIGNING_ARGUMENTS[@]}" "$SPARKLE_VERSION_DIR/Autoupdate"
codesign "${SIGNING_ARGUMENTS[@]}" "$SPARKLE_VERSION_DIR/Updater.app"
codesign "${SIGNING_ARGUMENTS[@]}" "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
codesign "${SIGNING_ARGUMENTS[@]}" "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
codesign "${SIGNING_ARGUMENTS[@]}" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    # Give local ad-hoc builds a stable designated requirement. Without this,
    # codesign uses the executable hash and macOS treats every rebuild as a new
    # Screen Recording/Accessibility client.
    codesign \
        --force \
        --sign - \
        --requirements '=designated => identifier "com.local.AltTabber"' \
        "$APP_DIR"
else
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"

# Finder displays the app bundle directory's modification date. Reusing the
# bundle leaves that timestamp stale even though its executable was replaced.
/usr/bin/touch "$APP_DIR"

echo "$APP_DIR"
