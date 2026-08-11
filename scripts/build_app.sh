#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
APP="packaging/FKeys.app"

# A universal build is driven by xcbuild, which ships with full Xcode and NOT
# with the Command Line Tools. Asking for it on a CLT-only machine fails with
# "xcbuild executable ... does not exist", so only ask when it is present.
# No bash arrays: macOS ships bash 3.2, where expanding an empty array under
# `set -u` aborts.
XCBUILD="/Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild"
if [ -x "$XCBUILD" ]; then
    echo "==> Building universal release binary (arm64 + x86_64)"
    swift build -c release --arch arm64 --arch x86_64
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/FKeys"
else
    echo "==> Building release binary for this machine ($(uname -m))"
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/FKeys"
fi

echo "==> Generating icon"
bash scripts/make_icon.sh >/dev/null

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FKeys"
cp packaging/FKeys.icns "$APP/Contents/Resources/FKeys.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    packaging/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "    note: ad-hoc signing skipped"

echo "==> Built $APP"
/usr/bin/file "$APP/Contents/MacOS/FKeys"
