#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail

REPO_ROOT="${SENSOS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TARGET_DIR="${REPO_ROOT}/pi-gen"
VENDORED_FILE="${REPO_ROOT}/VENDORED_PI_GEN"
REPO_URL="https://github.com/RPi-Distro/pi-gen.git"
TAG_PATTERN="-arm64"

TAG=""
FORCE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Install the latest tagged RPi-Distro/pi-gen arm64 release into ${TARGET_DIR}.

Options:
  --tag <tag>                    Install a specific tag instead of the latest one
  --tag-pattern <value>          Match tags containing this string (default: ${TAG_PATTERN})
  --repo-url <url>               Override the pi-gen git remote
  --force                        Replace an existing non-empty pi-gen directory
  -h, --help                     Show this help text
EOF
}

log() {
    printf '[install-pi-gen] %s\n' "$*"
}

die() {
    printf '[install-pi-gen] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

is_interactive() {
    [[ -t 0 ]]
}

confirm_yes_no() {
    local prompt="$1"
    local default_yes="${2:-false}"
    local answer

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
        die "unable to resolve a matching tag from ${REPO_URL} (tag pattern: ${TAG_PATTERN})"
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
        usage >&2
        die "unknown option: $1"
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
    if is_interactive && confirm_yes_no "${TARGET_DIR} already exists and will be replaced. Continue?" false; then
        FORCE=true
    else
        die "${TARGET_DIR} already exists and is not empty; re-run with --force to replace it"
    fi
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

log "installing pi-gen tag ${TAG} from ${REPO_URL}"
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

log "installed pi-gen at ${TARGET_DIR}"
log "recorded version metadata in ${VENDORED_FILE}"
