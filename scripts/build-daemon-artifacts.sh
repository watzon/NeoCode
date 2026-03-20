#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
OUTPUT_DIR="${2:-${ROOT_DIR}/dist/daemon}"
SIGN_IDENTITY="${DAEMON_CODESIGN_IDENTITY:-Developer ID Application}"

if [ -z "${VERSION}" ]; then
  echo "Usage: $0 VERSION [output-dir]"
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

build_one() {
  local goarch="$1"
  local asset_arch="$2"
  local stage_dir="${WORK_DIR}/${asset_arch}"
  local binary_path="${stage_dir}/neocoded"
  local asset_name="neocoded-v${VERSION}-darwin-${asset_arch}.tar.gz"
  local asset_path="${OUTPUT_DIR}/${asset_name}"

  mkdir -p "${stage_dir}"
  (
    cd "${ROOT_DIR}/server"
    CGO_ENABLED=0 GOOS=darwin GOARCH="${goarch}" go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o "${binary_path}" ./cmd/neocoded
  )

  chmod 755 "${binary_path}"
  if [ -n "${SIGN_IDENTITY}" ]; then
    codesign --force --timestamp --options runtime --sign "${SIGN_IDENTITY}" "${binary_path}"
  fi

  tar -C "${stage_dir}" -czf "${asset_path}" neocoded
}

build_one arm64 arm64
build_one amd64 amd64

(
  cd "${OUTPUT_DIR}"
  shasum -a 256 neocoded-v${VERSION}-darwin-arm64.tar.gz neocoded-v${VERSION}-darwin-amd64.tar.gz > "neocoded-v${VERSION}-checksums.txt"
)

echo "Daemon artifacts written to ${OUTPUT_DIR}"
