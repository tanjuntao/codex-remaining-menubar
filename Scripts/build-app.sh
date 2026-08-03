#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Codex Remaining"
APP_BUNDLE="${PROJECT_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

cd "${PROJECT_DIR}"
swift build -c "${CONFIGURATION}"
BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"

mkdir -p "${MACOS_DIR}"
install -m 755 "${BIN_DIR}/CodexRemainingMenuBar" "${MACOS_DIR}/CodexRemainingMenuBar"
install -m 644 "${PROJECT_DIR}/Resources/AppInfo.plist" "${CONTENTS_DIR}/Info.plist"

plutil -lint "${CONTENTS_DIR}/Info.plist"
codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "${APP_BUNDLE}"

echo "Built ${APP_BUNDLE}"
