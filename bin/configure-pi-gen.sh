#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail

REPO_ROOT="${SENSOS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PI_GEN_DIR="${REPO_ROOT}/pi-gen"
CONFIG_FILE="${PI_GEN_DIR}/config"
PI_GEN_RELEASE="SensOS reference"

STAGE_LIST="stage0 stage1 stage2"
PIGEN_DOCKER_OPTS=""
IMG_NAME="sensos"
TIMEZONE_DEFAULT="UTC"
KEYBOARD_KEYMAP="us"
KEYBOARD_LAYOUT="English (US)"
LOCALE_DEFAULT="C.UTF-8"
FIRST_USER_NAME="sensos"
FIRST_USER_PASS="sensos"
DISABLE_FIRST_BOOT_USER_RENAME="1"
WPA_COUNTRY="US"
ENABLE_SSH="1"
DEPLOY_COMPRESSION="none"
ENABLE_HOTSPOT="1"
HOTSPOT_SSID="sensos"
HOTSPOT_PASSWORD="sensossensos"
HOTSPOT_INTERFACE="wlan0"
IMAGE_SIZE=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --img-name <value>                         (default: ${IMG_NAME})
  --first-user-name <value>                  (default: ${FIRST_USER_NAME})
  --first-user-pass <value>                  (default: ${FIRST_USER_PASS})
  --enable-hotspot                           (default: enabled)
  --disable-hotspot
  --hotspot-ssid <value>                     (default: ${HOTSPOT_SSID})
  --hotspot-password <value>                 (default: ${HOTSPOT_PASSWORD})
  --hotspot-interface <value>                (default: ${HOTSPOT_INTERFACE})
  --image-size <value>                       Override image size in MB
  -h, --help                                 Show this help text
EOF
}

log() {
    printf '[configure-pi-gen] %s\n' "$*"
}

die() {
    printf '[configure-pi-gen] ERROR: %s\n' "$*" >&2
    exit 1
}

require_pi_gen_tree() {
    if [ ! -d "${PI_GEN_DIR}" ] || [ ! -x "${PI_GEN_DIR}/build-docker.sh" ]; then
        die "expected a pi-gen release at ${PI_GEN_DIR}; download or install pi-gen there before running this script"
    fi

    if ! grep -Eq '^export ARCH=arm64$' "${PI_GEN_DIR}/build.sh"; then
        die "expected an arm64 pi-gen tree at ${PI_GEN_DIR}; reinstall with ./bin/install-pi-gen.sh --force"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --img-name)
        IMG_NAME="$2"
        shift 2
        ;;
    --first-user-name)
        FIRST_USER_NAME="$2"
        shift 2
        ;;
    --first-user-pass)
        FIRST_USER_PASS="$2"
        shift 2
        ;;
    --enable-hotspot)
        ENABLE_HOTSPOT="1"
        shift
        ;;
    --disable-hotspot)
        ENABLE_HOTSPOT="0"
        shift
        ;;
    --hotspot-ssid)
        HOTSPOT_SSID="$2"
        shift 2
        ;;
    --hotspot-password)
        HOTSPOT_PASSWORD="$2"
        shift 2
        ;;
    --hotspot-interface)
        HOTSPOT_INTERFACE="$2"
        shift 2
        ;;
    --image-size)
        IMAGE_SIZE="$2"
        shift 2
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

require_pi_gen_tree

if [[ "${DISABLE_FIRST_BOOT_USER_RENAME}" == "1" && -z "${FIRST_USER_PASS}" ]]; then
    die "FIRST_USER_PASS must be set when first-boot user rename is disabled"
fi

if [[ "${ENABLE_HOTSPOT}" == "1" ]]; then
    if [[ ${#HOTSPOT_PASSWORD} -lt 8 || ${#HOTSPOT_PASSWORD} -gt 63 ]]; then
        die "hotspot password must be between 8 and 63 characters"
    fi
fi

cat > "${CONFIG_FILE}" <<EOF
PI_GEN_RELEASE="${PI_GEN_RELEASE}"
STAGE_LIST="${STAGE_LIST}"
PIGEN_DOCKER_OPTS="${PIGEN_DOCKER_OPTS}"
IMG_NAME="${IMG_NAME}"
TIMEZONE_DEFAULT="${TIMEZONE_DEFAULT}"
KEYBOARD_KEYMAP="${KEYBOARD_KEYMAP}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT}"
LOCALE_DEFAULT="${LOCALE_DEFAULT}"
FIRST_USER_NAME="${FIRST_USER_NAME}"
FIRST_USER_PASS="${FIRST_USER_PASS}"
DISABLE_FIRST_BOOT_USER_RENAME="${DISABLE_FIRST_BOOT_USER_RENAME}"
WPA_COUNTRY="${WPA_COUNTRY}"
ENABLE_SSH="${ENABLE_SSH}"
DEPLOY_COMPRESSION="${DEPLOY_COMPRESSION}"
ENABLE_HOTSPOT="${ENABLE_HOTSPOT}"
HOTSPOT_SSID="${HOTSPOT_SSID}"
HOTSPOT_PASSWORD="${HOTSPOT_PASSWORD}"
HOTSPOT_INTERFACE="${HOTSPOT_INTERFACE}"
EOF

if [ -n "${IMAGE_SIZE}" ]; then
    echo "IMG_SIZE=\"$((IMAGE_SIZE * 1048576))\"" >> "${CONFIG_FILE}"
fi

log "wrote ${CONFIG_FILE}"
