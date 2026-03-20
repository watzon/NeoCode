#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

APP_NAME="NeoCode"
APP_BUNDLE="${REPO_ROOT}/DerivedData/Build/Products/Release/${APP_NAME}.app"
DMG_DIR="${REPO_ROOT}/dist"
DMG_PATH="${DMG_DIR}/${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"
VOLICON="${APP_BUNDLE}/Contents/Resources/${APP_NAME}.icns"
BACKGROUND_GENERATOR="${SCRIPT_DIR}/generate-dmg-background.py"
BACKGROUND_PATH="${SCRIPT_DIR}/assets/dmg-background.png"
APPLICATIONS_LINK_NAME="Applications"

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
mkdir -p "$(dirname "${BACKGROUND_PATH}")"

python3 "${BACKGROUND_GENERATOR}" "${BACKGROUND_PATH}"

STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.dmg.XXXXXX")
trap 'rm -rf "${STAGING_DIR}"' EXIT

cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/${APPLICATIONS_LINK_NAME}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_BUNDLE}/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP_BUNDLE}/Contents/Info.plist")

CREATE_DMG_ARGS=(
    --volname "${VOLUME_NAME}"
    --window-pos 200 120
    --window-size 640 420
    --background "${BACKGROUND_PATH}"
    --text-size 16
    --icon-size 104
    --icon "${APP_NAME}.app" 170 210
    --hide-extension "${APP_NAME}.app"
    --icon "${APPLICATIONS_LINK_NAME}" 470 210
    --no-internet-enable
)

if [ -f "${VOLICON}" ]; then
    CREATE_DMG_ARGS+=(--volicon "${VOLICON}")
fi

echo "Creating DMG for ${APP_NAME} v${VERSION} (${BUILD})"
create-dmg "${CREATE_DMG_ARGS[@]}" "${DMG_PATH}" "${STAGING_DIR}"

echo "DMG created at ${DMG_PATH}"
