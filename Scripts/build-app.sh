#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${CONFIGURATION:-release}"
ARCHITECTURES="${ARCHITECTURES:-}"
MINIMUM_MACOS_VERSION="13.0"
APP_NAME="Codex Remaining"
APP_BUNDLE="${PROJECT_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
EXECUTABLE_NAME="CodexRemainingMenuBar"
INFO_PLIST="${PROJECT_DIR}/Resources/AppInfo.plist"
APP_VERSION="${APP_VERSION:-$(plutil -extract CFBundleShortVersionString raw -o - "${INFO_PLIST}")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(plutil -extract CFBundleVersion raw -o - "${INFO_PLIST}")}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

if [[ ! "${APP_VERSION}" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]]; then
    echo "APP_VERSION must contain one to three numeric components: ${APP_VERSION}" >&2
    exit 1
fi

if [[ ! "${BUILD_NUMBER}" =~ '^[0-9]+$' ]]; then
    echo "BUILD_NUMBER must be numeric: ${BUILD_NUMBER}" >&2
    exit 1
fi

cd "${PROJECT_DIR}"

BUILT_BINARIES=()
if [[ -n "${ARCHITECTURES}" ]]; then
    for architecture in ${=ARCHITECTURES}; do
        case "${architecture}" in
            arm64|x86_64) ;;
            *)
                echo "Unsupported architecture: ${architecture}" >&2
                exit 1
                ;;
        esac

        triple="${architecture}-apple-macosx${MINIMUM_MACOS_VERSION}"
        scratch_path="${PROJECT_DIR}/.build/${CONFIGURATION}-${architecture}"
        build_arguments=(
            -c "${CONFIGURATION}"
            --product "${EXECUTABLE_NAME}"
            --triple "${triple}"
            --scratch-path "${scratch_path}"
        )
        swift build "${build_arguments[@]}"
        bin_dir="$(swift build "${build_arguments[@]}" --show-bin-path)"
        BUILT_BINARIES+=("${bin_dir}/${EXECUTABLE_NAME}")
    done
else
    swift build -c "${CONFIGURATION}" --product "${EXECUTABLE_NAME}"
    bin_dir="$(swift build -c "${CONFIGURATION}" --product "${EXECUTABLE_NAME}" --show-bin-path)"
    BUILT_BINARIES+=("${bin_dir}/${EXECUTABLE_NAME}")
fi

mkdir -p "${PROJECT_DIR}/dist" "${MACOS_DIR}"

if (( ${#BUILT_BINARIES[@]} == 1 )); then
    install -m 755 "${BUILT_BINARIES[1]}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
else
    universal_binary="${PROJECT_DIR}/.build/${EXECUTABLE_NAME}-universal"
    lipo -create "${BUILT_BINARIES[@]}" -output "${universal_binary}"
    install -m 755 "${universal_binary}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
fi

install -m 644 "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
plutil -replace CFBundleShortVersionString -string "${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"
plutil -replace CFBundleVersion -string "${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"

plutil -lint "${CONTENTS_DIR}/Info.plist"

codesign_arguments=(--force --deep --sign "${CODE_SIGN_IDENTITY}")
if [[ "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    codesign_arguments+=(--options runtime --timestamp)
fi
codesign "${codesign_arguments[@]}" "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "Built ${APP_BUNDLE} (${APP_VERSION}, architectures: $(lipo -archs "${MACOS_DIR}/${EXECUTABLE_NAME}"))"
