#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail

REPO_ROOT="${SENSOS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEPLOY_DIR="${REPO_ROOT}/pi-gen/deploy"

log() {
    printf '[burn-image] %s\n' "$*"
}

die() {
    printf '[burn-image] ERROR: %s\n' "$*" >&2
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

prompt_for_value() {
    local current_value="$1"
    local option_name="$2"
    local prompt_text="$3"

    if [[ -n "${current_value}" ]]; then
        printf '%s\n' "${current_value}"
        return
    fi

    if ! is_interactive; then
        die "missing required value: ${option_name}. Run interactively to be prompted, or pass ${option_name} explicitly. On macOS this is usually a raw disk like /dev/rdisk2."
    fi

    read -r -p "${prompt_text}: " current_value
    [[ -n "${current_value}" ]] || die "missing required value: ${option_name}"
    printf '%s\n' "${current_value}"
}

canonical_disk_device() {
    local device="$1"

    device="${device#/dev/r}"

    case "${device}" in
    disk*)
        device="${device%%s*}"
        ;;
    mmcblk*p*)
        device="${device%p*}"
        ;;
    nvme*n*p*)
        device="${device%p*}"
        ;;
    sd[a-z][0-9]*)
        device="${device%%[0-9]*}"
        ;;
    esac

    printf '/dev/%s\n' "${device}"
}

print_device_hints() {
    if command -v diskutil >/dev/null 2>&1; then
        printf 'Current disks from diskutil:\n\n'
        diskutil list
    else
        printf 'Current disks from lsblk:\n\n'
        lsblk
    fi
    printf '\n'
}

select_image_interactively() {
    local index

    printf 'Available images:\n'
    for i in "${!img_files[@]}"; do
        printf "%2d: %s\n" "${i}" "${img_files[$i]}"
    done
    printf '\n'

    read -r -p "Enter the number of the image to flash: " index
    case "${index}" in
    ''|*[!0-9]*)
        die "invalid selection"
        ;;
    esac
    if [ "${index}" -lt 0 ] || [ "${index}" -ge "${#img_files[@]}" ]; then
        die "invalid selection"
    fi
    printf '%s\n' "${img_files[$index]}"
}

DEVICE=""
IMAGE=""
YES=false
while [[ $# -gt 0 ]]; do
    case "$1" in
    --device)
        DEVICE="$2"
        shift 2
        ;;
    --image)
        IMAGE="$2"
        shift 2
        ;;
    --yes)
        YES=true
        shift
        ;;
    -h|--help)
        cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --device <path>   Target block device to flash
  --image <path>    Image file to flash; defaults to prompting or auto-selecting from ${DEPLOY_DIR}
  --yes             Skip the final destructive confirmation prompt
  -h, --help        Show this help text
EOF
        exit 0
        ;;
    *)
        die "unknown option: $1"
        ;;
    esac
done

if [ -z "${DEVICE}" ]; then
    if is_interactive; then
        print_device_hints
        DEVICE="$(prompt_for_value "${DEVICE}" "--device" "Device to erase and flash (for example /dev/rdisk2)")"
    else
        die "missing required value: --device. On macOS this is usually a raw disk like /dev/rdisk2."
    fi
fi

TARGET_DISK="$(canonical_disk_device "${DEVICE}")"
ROOT_DISK="$(canonical_disk_device "$(df / | awk 'NR==2 {print $1}')")"

case "${TARGET_DISK}" in
/dev/sda|/dev/disk0)
    die "refusing to write to likely system disk: ${DEVICE}"
    ;;
esac

if [ "${TARGET_DISK}" = "${ROOT_DISK}" ]; then
    die "refusing to write to the root disk: ${DEVICE}"
fi

cd "${DEPLOY_DIR}"

img_files=()
for f in *.img; do
    [ -e "${f}" ] || continue
    img_files+=("${f}")
done

if [ "${#img_files[@]}" -eq 0 ]; then
    die "no .img files found in ${DEPLOY_DIR}"
fi

if [ -n "${IMAGE}" ]; then
    [ -f "${IMAGE}" ] || die "image file not found: ${IMAGE}"
elif [ "${#img_files[@]}" -eq 1 ]; then
    IMAGE="${img_files[0]}"
    log "one image found: ${IMAGE}"
else
    if ! is_interactive; then
        die "missing required value: --image. Multiple images are available in ${DEPLOY_DIR}; pass --image explicitly."
    fi
    IMAGE="$(select_image_interactively)"
fi

if ! confirm_yes_no "This will erase ${DEVICE} and write ${IMAGE}. Proceed?" false; then
    die "aborted"
fi

log "unmounting ${DEVICE}"
if command -v diskutil >/dev/null 2>&1; then
    diskutil unmountDisk "${DEVICE}"
else
    sudo umount "${DEVICE}"* || true
fi

log "writing ${IMAGE} to ${DEVICE}"
sudo dd if="${IMAGE}" of="${DEVICE}" bs=4M status=progress conv=sync

log "ejecting ${DEVICE}"
if command -v diskutil >/dev/null 2>&1; then
    diskutil eject "${DEVICE}"
else
    sudo eject "${DEVICE}" || true
fi

log "done"
