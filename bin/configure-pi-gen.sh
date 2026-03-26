#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_GEN_DIR="${ROOT_DIR}/pi-gen"
CONFIG_FILE="${PI_GEN_DIR}/config"
VENDORED_FILE="${ROOT_DIR}/VENDORED_PI_GEN"

PI_GEN_RELEASE="vendored"
if [ -f "${VENDORED_FILE}" ]; then
    PI_GEN_RELEASE="$(awk -F= '/^SOURCE_TAG=/{print $2}' "${VENDORED_FILE}")"
fi

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
Usage: $0 [options]

Options:
  --pi-gen-release <value>                   (default: ${PI_GEN_RELEASE})
  --stage-list <value>                       (default: ${STAGE_LIST})
  --pigen-docker-opts <value>                (default: ${PIGEN_DOCKER_OPTS})
  --img-name <value>                         (default: ${IMG_NAME})
  --timezone-default <value>                 (default: ${TIMEZONE_DEFAULT})
  --keyboard-keymap <value>                  (default: ${KEYBOARD_KEYMAP})
  --keyboard-layout <value>                  (default: ${KEYBOARD_LAYOUT})
  --locale-default <value>                   (default: ${LOCALE_DEFAULT})
  --first-user-name <value>                  (default: ${FIRST_USER_NAME})
  --first-user-pass <value>                  (default: ${FIRST_USER_PASS})
  --disable-first-boot-user-rename <0|1>     (default: ${DISABLE_FIRST_BOOT_USER_RENAME})
  --wpa-country <value>                      (default: ${WPA_COUNTRY})
  --enable-ssh <0|1>                         (default: ${ENABLE_SSH})
  --deploy-compression <value>               (default: ${DEPLOY_COMPRESSION})
  --enable-hotspot                           (default: enabled)
  --disable-hotspot
  --hotspot-ssid <value>                     (default: ${HOTSPOT_SSID})
  --hotspot-password <value>                 (default: ${HOTSPOT_PASSWORD})
  --hotspot-interface <value>                (default: ${HOTSPOT_INTERFACE})
  --image-size <value>                       Override image size in MB
  -h, --help                                 Show this help text
EOF
}

require_pi_gen_tree() {
    if [ ! -d "${PI_GEN_DIR}" ] || [ ! -x "${PI_GEN_DIR}/build-docker.sh" ]; then
        echo "Expected a pi-gen release at ${PI_GEN_DIR}." >&2
        echo "Download or extract pi-gen there before running this script." >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --pi-gen-release)
        PI_GEN_RELEASE="$2"
        shift 2
        ;;
    --stage-list)
        STAGE_LIST="$2"
        shift 2
        ;;
    --pigen-docker-opts)
        PIGEN_DOCKER_OPTS="$2"
        shift 2
        ;;
    --img-name)
        IMG_NAME="$2"
        shift 2
        ;;
    --timezone-default)
        TIMEZONE_DEFAULT="$2"
        shift 2
        ;;
    --keyboard-keymap)
        KEYBOARD_KEYMAP="$2"
        shift 2
        ;;
    --keyboard-layout)
        KEYBOARD_LAYOUT="$2"
        shift 2
        ;;
    --locale-default)
        LOCALE_DEFAULT="$2"
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
    --disable-first-boot-user-rename)
        DISABLE_FIRST_BOOT_USER_RENAME="$2"
        shift 2
        ;;
    --wpa-country)
        WPA_COUNTRY="$2"
        shift 2
        ;;
    --enable-ssh)
        ENABLE_SSH="$2"
        shift 2
        ;;
    --deploy-compression)
        DEPLOY_COMPRESSION="$2"
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
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
done

require_pi_gen_tree

if [[ "${DISABLE_FIRST_BOOT_USER_RENAME}" == "1" && -z "${FIRST_USER_PASS}" ]]; then
    echo "FIRST_USER_PASS must be set when first-boot user rename is disabled." >&2
    exit 1
fi

if [[ "${ENABLE_HOTSPOT}" == "1" ]]; then
    if [[ ${#HOTSPOT_PASSWORD} -lt 8 || ${#HOTSPOT_PASSWORD} -gt 63 ]]; then
        echo "Hotspot password must be between 8 and 63 characters." >&2
        exit 1
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

echo "Wrote ${CONFIG_FILE}"
cat "${CONFIG_FILE}"
