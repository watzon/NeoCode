#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${HOME}/.local/bin"
TARGET_PATH="${TARGET_DIR}/neocoded"

VERSION="$(${ROOT_DIR}/scripts/read-version.sh)"

mkdir -p "${TARGET_DIR}"

cd "${ROOT_DIR}/server"
go build -ldflags "-X main.version=${VERSION}" -o neocoded ./cmd/neocoded

ln -sf "${ROOT_DIR}/server/neocoded" "${TARGET_PATH}"

echo "Installed neocoded -> ${TARGET_PATH}"
echo "Make sure ${TARGET_DIR} is on your PATH."
