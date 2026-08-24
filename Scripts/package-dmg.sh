#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_NAME="Codex Remaining"
VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw -o - "${PROJECT_DIR}/Resources/AppInfo.plist")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(plutil -extract CFBundleVersion raw -o - "${PROJECT_DIR}/Resources/AppInfo.plist")}"
DMG_BASENAME="Codex-Remaining-${VERSION}"
DMG_PATH="${PROJECT_DIR}/dist/${DMG_BASENAME}.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-remaining-dmg.XXXXXX")"
VOLUME_ROOT="${STAGING_ROOT}/${APP_NAME}"

cleanup() {
    rm -rf "${STAGING_ROOT}"
}
trap cleanup EXIT

if [[ ! "${VERSION}" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]]; then
    echo "VERSION must contain one to three numeric components: ${VERSION}" >&2
    exit 1
fi

ARCHITECTURES="arm64 x86_64" \
APP_VERSION="${VERSION}" \
BUILD_NUMBER="${BUILD_NUMBER}" \
CODE_SIGN_IDENTITY="-" \
    "${SCRIPT_DIR}/build-app.sh"

mkdir -p "${VOLUME_ROOT}"
ditto "${PROJECT_DIR}/dist/${APP_NAME}.app" "${VOLUME_ROOT}/${APP_NAME}.app"
ln -s /Applications "${VOLUME_ROOT}/Applications"

rm -f "${DMG_PATH}" "${CHECKSUM_PATH}"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${VOLUME_ROOT}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "${DMG_PATH}"

hdiutil verify "${DMG_PATH}"
(
    cd "${PROJECT_DIR}/dist"
    shasum -a 256 "${DMG_BASENAME}.dmg" > "${DMG_BASENAME}.dmg.sha256"
)

echo "Packaged ${DMG_PATH}"
echo "Checksum ${CHECKSUM_PATH}"
