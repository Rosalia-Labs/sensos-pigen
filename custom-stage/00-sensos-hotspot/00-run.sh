#!/bin/bash -e

[ -f /config ] && source /config

FILES_DIR="files"
ENV_FILE="${ROOTFS_DIR}/etc/default/sensos-hotspot"
API_PASSWORD_SRC="${FILES_DIR}/keys/api_password"
API_PASSWORD_DST="${ROOTFS_DIR}/sensos/keys/api_password"

install -D -m 0755 "${FILES_DIR}/sensos-start-hotspot" "${ROOTFS_DIR}/usr/local/sbin/sensos-start-hotspot"
install -D -m 0755 "${FILES_DIR}/sensos-stop-hotspot" "${ROOTFS_DIR}/usr/local/sbin/sensos-stop-hotspot"
install -D -m 0755 "${FILES_DIR}/sensos-clone-client" "${ROOTFS_DIR}/usr/local/bin/sensos-clone-client"
install -D -m 0644 "${FILES_DIR}/sensos-hotspot.service" "${ROOTFS_DIR}/etc/systemd/system/sensos-hotspot.service"

if [ -f "${API_PASSWORD_SRC}" ]; then
    install -D -m 0600 "${API_PASSWORD_SRC}" "${API_PASSWORD_DST}"
fi

mkdir -p "$(dirname "${ENV_FILE}")"
{
    printf 'HOTSPOT_ENABLED=%q\n' "${ENABLE_HOTSPOT:-1}"
    printf 'HOTSPOT_CONNECTION_NAME=%q\n' "sensos-hotspot"
    printf 'HOTSPOT_INTERFACE=%q\n' "${HOTSPOT_INTERFACE:-wlan0}"
    printf 'HOTSPOT_SSID=%q\n' "${HOTSPOT_SSID:-sensos}"
    printf 'HOTSPOT_PASSWORD=%q\n' "${HOTSPOT_PASSWORD:-sensossensos}"
} > "${ENV_FILE}"

if [ "${ENABLE_HOTSPOT:-1}" = "1" ]; then
    on_chroot <<'EOF'
systemctl enable sensos-hotspot.service
EOF
else
    on_chroot <<'EOF'
systemctl disable sensos-hotspot.service || true
EOF
fi
