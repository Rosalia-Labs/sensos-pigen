#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail

REPO_ROOT="${SENSOS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PI_GEN_DIR="${REPO_ROOT}/pi-gen"
CONFIG_FILE="${PI_GEN_DIR}/config"
STAGE_SRC="${REPO_ROOT}/custom-stage/00-sensos-hotspot"
STAGE_DST="${PI_GEN_DIR}/stage2/04-sensos-hotspot"
VENDORED_FILE="${REPO_ROOT}/VENDORED_PI_GEN"
CLIENT_ARCHIVE_NAME="sensos-client.tar.gz"
TMP_STAGE_ROOT=""
DEFAULT_CLIENT_REPO_URL="https://github.com/Rosalia-Labs/sensos-client.git"
DEFAULT_CLIENT_REF="main"

CONTINUE_BUILD=false
REMOVE_DEPLOY=false
YES=false
INCLUDE_CLIENT_TARBALL=true
CLIENT_REPO_URL="${SENSOS_CLIENT_REPO_URL:-${DEFAULT_CLIENT_REPO_URL}}"
CLIENT_REF="${SENSOS_CLIENT_REF:-${DEFAULT_CLIENT_REF}}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --remove-existing              Delete previously built images from pi-gen/deploy
  --continue                     Continue a previously interrupted build
  --client-repo-url <url>        Git URL to clone for the bundled sensos-client tarball
                                 (default: ${CLIENT_REPO_URL})
  --client-ref <ref>             Branch, tag, or ref to clone for the bundled tarball
                                 (default: ${CLIENT_REF})
  --no-client-tarball            Skip bundling a sensos-client tarball into /home/sensos
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

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

prepare_generated_files_dir() {
    require_command mktemp

    TMP_STAGE_ROOT="$(mktemp -d /tmp/sensos-pigen-build.XXXXXX)"
    mkdir -p "${TMP_STAGE_ROOT}/generated"
}

build_client_tarball() {
    local archive_path="${TMP_STAGE_ROOT}/generated/${CLIENT_ARCHIVE_NAME}"
    local clone_dir="${TMP_STAGE_ROOT}/sensos-client"

    require_command git
    require_command tar

    log "cloning ${CLIENT_REPO_URL} (${CLIENT_REF})"
    git clone --depth 1 --branch "${CLIENT_REF}" "${CLIENT_REPO_URL}" "${clone_dir}"

    [ -f "${clone_dir}/README.md" ] || die "cloned sensos-client repo at ${clone_dir} does not look valid"

    log "creating ${archive_path} from ${CLIENT_REPO_URL} (${CLIENT_REF})"
    tar -C "${clone_dir}" -czf "${archive_path}" .
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
    --client-repo-url)
        CLIENT_REPO_URL="$2"
        shift 2
        ;;
    --client-ref)
        CLIENT_REF="$2"
        shift 2
        ;;
    --no-client-tarball)
        INCLUDE_CLIENT_TARBALL=false
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
    if [ -n "${TMP_STAGE_ROOT}" ]; then
        rm -rf "${TMP_STAGE_ROOT}"
    fi
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

prepare_generated_files_dir
if [ "${INCLUDE_CLIENT_TARBALL}" = true ]; then
    build_client_tarball
fi

rm -rf "${STAGE_DST}"
cp -R "${STAGE_SRC}" "${STAGE_DST}"
if [ -d "${TMP_STAGE_ROOT}/generated" ]; then
    mkdir -p "${STAGE_DST}/files/generated"
    cp -R "${TMP_STAGE_ROOT}/generated/." "${STAGE_DST}/files/generated/"
fi

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
