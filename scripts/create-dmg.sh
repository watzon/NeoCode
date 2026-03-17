#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NeoCode"
APP_BUNDLE="DerivedData/Build/Products/Release/${APP_NAME}.app"
DMG_DIR="dist"
DMG_PATH="${DMG_DIR}/${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"
VOLICON="${APP_BUNDLE}/Contents/Resources/${APP_NAME}.icns"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "App bundle not found at ${APP_BUNDLE}"
    exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "create-dmg not found. Install it with: brew install create-dmg"
    exit 1
fi

mkdir -p "${DMG_DIR}"
rm -f "${DMG_PATH}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_BUNDLE}/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP_BUNDLE}/Contents/Info.plist")

CREATE_DMG_ARGS=(
    --volname "${VOLUME_NAME}"
    --window-pos 200 120
    --window-size 640 420
    --icon-size 104
    --icon "${APP_NAME}.app" 170 200
    --hide-extension "${APP_NAME}.app"
    --app-drop-link 470 200
    --no-internet-enable
)

if [ -f "${VOLICON}" ]; then
    CREATE_DMG_ARGS+=(--volicon "${VOLICON}")
fi

echo "Creating DMG for ${APP_NAME} v${VERSION} (${BUILD})"
create-dmg "${CREATE_DMG_ARGS[@]}" "${DMG_PATH}" "${APP_BUNDLE}"

echo "DMG created at ${DMG_PATH}"
