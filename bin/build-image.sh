#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_GEN_DIR="${ROOT_DIR}/pi-gen"
CONFIG_FILE="${PI_GEN_DIR}/config"
STAGE_SRC="${ROOT_DIR}/custom-stage/00-sensos-hotspot"
STAGE_DST="${PI_GEN_DIR}/stage2/04-sensos-hotspot"
VENDORED_FILE="${ROOT_DIR}/VENDORED_PI_GEN"

CONTINUE_BUILD=false
REMOVE_DEPLOY=false

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --remove-existing              Delete previously built images from pi-gen/deploy
  --continue                     Continue a previously interrupted build
  -h, --help                     Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --remove-existing)
        REMOVE_DEPLOY=true
        shift
        ;;
    --continue)
        CONTINUE_BUILD=true
        shift
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
done

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Missing ${CONFIG_FILE}. Run bin/configure-pi-gen.sh first." >&2
    exit 1
fi

if [ ! -d "${PI_GEN_DIR}" ] || [ ! -x "${PI_GEN_DIR}/build-docker.sh" ]; then
    echo "pi-gen tree is missing or incomplete at ${PI_GEN_DIR}." >&2
    exit 1
fi

if ! grep -Eq '^export ARCH=arm64$' "${PI_GEN_DIR}/build.sh"; then
    echo "This repo expects an arm64 pi-gen tree at ${PI_GEN_DIR}." >&2
    echo "Reinstall with: ./bin/install-pi-gen.sh --force" >&2
    exit 1
fi

if [ ! -d "${STAGE_SRC}" ]; then
    echo "Missing custom stage at ${STAGE_SRC}." >&2
    exit 1
fi

cleanup() {
    rm -rf "${STAGE_DST}"
}
trap cleanup EXIT

if [ -f "${VENDORED_FILE}" ]; then
    echo "Installed pi-gen release:"
    cat "${VENDORED_FILE}"
    echo
fi

echo "Building image using config:"
cat "${CONFIG_FILE}"
echo

rm -rf "${STAGE_DST}"
cp -R "${STAGE_SRC}" "${STAGE_DST}"

cd "${PI_GEN_DIR}"

if [ "${REMOVE_DEPLOY}" = true ]; then
    rm -rf ./deploy/*
fi

if [ "${CONTINUE_BUILD}" = true ]; then
    echo "Continuing previous build..."
    CONTINUE=1 ./build-docker.sh
else
    echo "Starting fresh build..."
    docker rm -v pigen_work >/dev/null 2>&1 || true
    ./build-docker.sh
fi

echo "Build complete."
