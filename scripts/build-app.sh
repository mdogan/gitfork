#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"
BUILD_DIRECTORY=".build/${CONFIGURATION}"
APP_DIRECTORY="${BUILD_DIRECTORY}/GitFork.app"
CONTENTS_DIRECTORY="${APP_DIRECTORY}/Contents"
MACOS_DIRECTORY="${CONTENTS_DIRECTORY}/MacOS"

CLANG_MODULE_CACHE_PATH=".build/clang-module-cache" \
SWIFTPM_CUSTOM_CACHE_PATH=".build/swiftpm-cache" \
swift build --disable-sandbox -c "${CONFIGURATION}"

rm -rf "${APP_DIRECTORY}"
mkdir -p "${MACOS_DIRECTORY}"
cp "${BUILD_DIRECTORY}/GitFork" "${MACOS_DIRECTORY}/GitFork"
cp "Resources/Info.plist" "${CONTENTS_DIRECTORY}/Info.plist"

codesign --force --deep --sign - "${APP_DIRECTORY}"

echo "Built ${APP_DIRECTORY}"
