#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="${ROOT_DIR}/pi-gen/deploy"

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

print_device_hints_and_exit() {
    echo "No --device specified."
    echo
    if command -v diskutil >/dev/null 2>&1; then
        echo "Current disks from diskutil:"
        echo
        diskutil list
    else
        echo "Current disks from lsblk:"
        echo
        lsblk
    fi
    echo
    echo "Re-run with: ./bin/burn-image.sh --device /dev/rdiskN"
    exit 1
}

DEVICE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
    --device)
        DEVICE="$2"
        shift 2
        ;;
    -h|--help)
        echo "Usage: $0 --device /dev/rdiskN"
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
done

if [ -z "${DEVICE}" ]; then
    print_device_hints_and_exit
fi

TARGET_DISK="$(canonical_disk_device "${DEVICE}")"
ROOT_DISK="$(canonical_disk_device "$(df / | awk 'NR==2 {print $1}')")"

case "${TARGET_DISK}" in
/dev/sda|/dev/disk0)
    echo "Refusing to write to likely system disk: ${DEVICE}" >&2
    exit 1
    ;;
esac

if [ "${TARGET_DISK}" = "${ROOT_DISK}" ]; then
    echo "Refusing to write to the root disk: ${DEVICE}" >&2
    exit 1
fi

cd "${DEPLOY_DIR}"

img_files=()
for f in *.img; do
    [ -e "${f}" ] || continue
    img_files+=("${f}")
done

if [ "${#img_files[@]}" -eq 0 ]; then
    echo "No .img files found in ${DEPLOY_DIR}" >&2
    exit 1
fi

if [ "${#img_files[@]}" -eq 1 ]; then
    IMAGE="${img_files[0]}"
    echo "One image found: ${IMAGE}"
else
    echo "Available images:"
    for i in "${!img_files[@]}"; do
        printf "%2d: %s\n" "${i}" "${img_files[$i]}"
    done
    echo
    read -r -p "Enter the number of the image to flash: " index
    case "${index}" in
    ''|*[!0-9]*)
        echo "Invalid selection." >&2
        exit 1
        ;;
    esac
    if [ "${index}" -lt 0 ] || [ "${index}" -ge "${#img_files[@]}" ]; then
        echo "Invalid selection." >&2
        exit 1
    fi
    IMAGE="${img_files[$index]}"
fi

echo
read -r -p "This will erase ${DEVICE}. Proceed? [y/N] " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Aborted."
    exit 1
fi

echo "Unmounting ${DEVICE}..."
if command -v diskutil >/dev/null 2>&1; then
    diskutil unmountDisk "${DEVICE}"
else
    sudo umount "${DEVICE}"* || true
fi

echo "Writing ${IMAGE} to ${DEVICE}..."
sudo dd if="${IMAGE}" of="${DEVICE}" bs=4M status=progress conv=sync

echo "Ejecting ${DEVICE}..."
if command -v diskutil >/dev/null 2>&1; then
    diskutil eject "${DEVICE}"
else
    sudo eject "${DEVICE}" || true
fi

echo "Done."
