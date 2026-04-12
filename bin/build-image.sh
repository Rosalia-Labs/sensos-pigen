#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail

REPO_ROOT="${SENSOS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PI_GEN_DIR="${REPO_ROOT}/pi-gen"
CONFIG_FILE="${PI_GEN_DIR}/config"
STAGE_SRC="${REPO_ROOT}/custom-stage/00-sensos-hotspot"
STAGE_DST="${PI_GEN_DIR}/stage2/04-sensos-hotspot"
VENDORED_FILE="${REPO_ROOT}/VENDORED_PI_GEN"

CONTINUE_BUILD=false
REMOVE_DEPLOY=false
YES=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --remove-existing              Delete previously built images from pi-gen/deploy
  --continue                     Continue a previously interrupted build
  --yes                          Skip interactive confirmation prompts
  -h, --help                     Show this help text
EOF
}

log() {
    printf '[build-image] %s\n' "$*"
}

die() {
    printf '[build-image] ERROR: %s\n' "$*" >&2
    exit 1
}

is_interactive() {
    [[ -t 0 ]]
}

confirm_yes_no() {
    local prompt="$1"
    local default_yes="${2:-false}"
    local answer

    if [[ "${YES}" == "true" ]]; then
        return 0
    fi

    if ! is_interactive; then
        return 1
    fi

    if [[ "${default_yes}" == "true" ]]; then
        read -r -p "${prompt} [Y/n] " answer
        [[ -z "${answer}" || "${answer}" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
        return
    fi

    read -r -p "${prompt} [y/N] " answer
    [[ "${answer}" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
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
    --yes)
        YES=true
        shift
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        die "unknown option: $1"
        ;;
    esac
done

if [ ! -f "${CONFIG_FILE}" ]; then
    die "missing ${CONFIG_FILE}; run bin/configure-pi-gen.sh first"
fi

if [ ! -d "${PI_GEN_DIR}" ] || [ ! -x "${PI_GEN_DIR}/build-docker.sh" ]; then
    die "pi-gen tree is missing or incomplete at ${PI_GEN_DIR}"
fi

if ! grep -Eq '^export ARCH=arm64$' "${PI_GEN_DIR}/build.sh"; then
    die "this repo expects an arm64 pi-gen tree at ${PI_GEN_DIR}; reinstall with ./bin/install-pi-gen.sh --force"
fi

if [ ! -d "${STAGE_SRC}" ]; then
    die "missing custom stage at ${STAGE_SRC}"
fi

cleanup() {
    rm -rf "${STAGE_DST}"
}
trap cleanup EXIT

if [ -f "${VENDORED_FILE}" ]; then
    log "installed pi-gen release:"
    cat "${VENDORED_FILE}"
    printf '\n'
fi

log "building image using config:"
cat "${CONFIG_FILE}"
printf '\n'

rm -rf "${STAGE_DST}"
cp -R "${STAGE_SRC}" "${STAGE_DST}"

cd "${PI_GEN_DIR}"

if [ "${REMOVE_DEPLOY}" = true ]; then
    if ! confirm_yes_no "Delete existing images from ${PI_GEN_DIR}/deploy before building?" false; then
        die "refusing to remove existing images without confirmation; re-run interactively or pass --yes"
    fi
    rm -rf ./deploy/*
fi

if [ "${CONTINUE_BUILD}" = true ]; then
    log "continuing previous build"
    CONTINUE=1 ./build-docker.sh
else
    log "starting fresh build"
    docker rm -v pigen_work >/dev/null 2>&1 || true
    ./build-docker.sh
fi

log "build complete"
