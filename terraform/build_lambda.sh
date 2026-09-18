#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to the repo root regardless of the caller's cwd
# (this runs inside a container with the repo mounted at /workspace, or
# locally from anywhere).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ARCH="${ARCH:-arm64}"
PYTHON_VERSION="${PYTHON_VERSION:-3.13}"

BUILD_DIR="${SCRIPT_DIR}/build"
PACKAGE_DIR="${BUILD_DIR}/package"
ZIP_PATH="${BUILD_DIR}/lambda.zip"

case "${ARCH}" in
  arm64)  UV_PYTHON_PLATFORM="aarch64-manylinux2014" ;;
  x86_64) UV_PYTHON_PLATFORM="x86_64-manylinux2014" ;;
  *)
    echo "Unsupported ARCH: ${ARCH} (expected arm64 or x86_64)" >&2
    exit 1
    ;;
esac

cd "${REPO_ROOT}"

rm -rf "${PACKAGE_DIR}" "${ZIP_PATH}"
mkdir -p "${PACKAGE_DIR}"

uv export --frozen --no-dev --no-editable -o "${BUILD_DIR}/requirements.txt"

uv pip install \
  --no-installer-metadata \
  --no-compile-bytecode \
  --python-platform "${UV_PYTHON_PLATFORM}" \
  --python "${PYTHON_VERSION}" \
  --target "${PACKAGE_DIR}" \
  -r "${BUILD_DIR}/requirements.txt"

rm -f "${BUILD_DIR}/requirements.txt"

cp -r "${REPO_ROOT}/src/cyber_car_washer_be" "${PACKAGE_DIR}/"

(cd "${PACKAGE_DIR}" && zip -r -X "${ZIP_PATH}" . -x '*.dist-info/RECORD')
