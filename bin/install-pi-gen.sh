#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${ROOT_DIR}/pi-gen"
VENDORED_FILE="${ROOT_DIR}/VENDORED_PI_GEN"
REPO_URL="https://github.com/RPi-Distro/pi-gen.git"
TAG_PATTERN="-arm64"

TAG=""
FORCE=false

usage() {
    cat <<EOF
Usage: $0 [options]

Install the latest tagged RPi-Distro/pi-gen arm64 release into ${TARGET_DIR}.

Options:
  --tag <tag>                    Install a specific tag instead of the latest one
  --tag-pattern <value>          Match tags containing this string (default: ${TAG_PATTERN})
  --repo-url <url>               Override the pi-gen git remote
  --force                        Replace an existing non-empty pi-gen directory
  -h, --help                     Show this help text
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

resolve_latest_tag() {
    local ref

    ref="$(
        git ls-remote --refs --tags --sort='-version:refname' "${REPO_URL}" \
        | awk -v pattern="${TAG_PATTERN}" '
            {
                sub(/^refs\/tags\//, "", $2)
                if (pattern == "" || index($2, pattern) > 0) {
                    print $2
                    exit
                }
            }
        '
    )"

    if [ -z "${ref}" ]; then
        echo "Unable to resolve a matching tag from ${REPO_URL}" >&2
        echo "Tag pattern: ${TAG_PATTERN}" >&2
        exit 1
    fi

    printf '%s\n' "${ref}"
}

pi_gen_dir_is_nonempty() {
    [ -d "${TARGET_DIR}" ] && find "${TARGET_DIR}" -mindepth 1 ! -name '.gitkeep' -print -quit | grep -q .
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --tag)
        TAG="$2"
        shift 2
        ;;
    --tag-pattern)
        TAG_PATTERN="$2"
        shift 2
        ;;
    --repo-url)
        REPO_URL="$2"
        shift 2
        ;;
    --force)
        FORCE=true
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

require_command git
require_command mktemp
require_command rm
require_command mv
require_command date

if [ -z "${TAG}" ]; then
    TAG="$(resolve_latest_tag)"
fi

if pi_gen_dir_is_nonempty && [ "${FORCE}" != true ]; then
    echo "${TARGET_DIR} already exists and is not empty." >&2
    echo "Re-run with --force to replace it." >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "Installing pi-gen tag ${TAG} from ${REPO_URL}"
git clone --depth 1 --branch "${TAG}" "${REPO_URL}" "${TMP_DIR}/pi-gen"

COMMIT="$(git -C "${TMP_DIR}/pi-gen" rev-parse --short=7 HEAD)"
rm -rf "${TMP_DIR}/pi-gen/.git"

rm -rf "${TARGET_DIR}"
mv "${TMP_DIR}/pi-gen" "${TARGET_DIR}"

cat > "${VENDORED_FILE}" <<EOF
SOURCE_PATH=${REPO_URL}
SOURCE_TAG=${TAG}
SOURCE_COMMIT=${COMMIT}
VENDORED_AT=$(date +%F)
EOF

echo "Installed pi-gen at ${TARGET_DIR}"
echo "Recorded version metadata in ${VENDORED_FILE}"
