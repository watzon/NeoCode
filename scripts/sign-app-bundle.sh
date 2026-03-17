#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:-}"
SIGN_IDENTITY="${2:--}"

if [ -z "${APP_BUNDLE}" ]; then
    echo "Missing app bundle path."
    echo "Usage: $0 /path/to/NeoCode.app [identity]"
    exit 1
fi

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "App bundle not found: ${APP_BUNDLE}"
    exit 1
fi

SPARKLE_FRAMEWORK="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"

echo "Signing app bundle with identity: ${SIGN_IDENTITY}"

if [ -d "${SPARKLE_FRAMEWORK}" ]; then
    echo "Signing nested Sparkle executables..."
    while IFS= read -r executable; do
        [ -n "${executable}" ] || continue
        codesign --force --sign "${SIGN_IDENTITY}" "${executable}"
    done < <(find "${SPARKLE_FRAMEWORK}" -type f -perm -111 | sort)

    echo "Signing nested Sparkle bundles..."
    while IFS= read -r nested_bundle; do
        [ -n "${nested_bundle}" ] || continue
        codesign --force --sign "${SIGN_IDENTITY}" "${nested_bundle}"
    done < <(find "${SPARKLE_FRAMEWORK}" -type d \( -name "*.xpc" -o -name "*.app" -o -name "*.framework" \) | sort -r)

    echo "Signing Sparkle.framework..."
    codesign --force --sign "${SIGN_IDENTITY}" "${SPARKLE_FRAMEWORK}"
fi

echo "Signing main app bundle..."
codesign --force --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

echo "Verifying strict deep signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
