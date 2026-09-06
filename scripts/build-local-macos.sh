#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_PATH="${PROJECT_DIR}/build/macos/Build/Products/Release/Hermes.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This local build currently supports Apple Silicon only." >&2
  exit 1
fi

cd "${PROJECT_DIR}"

VERSION="$(awk '/^version:/ { print $2; exit }' pubspec.yaml)"
BUILD_NAME="${VERSION%%+*}"
BUILD_NUMBER="${VERSION##*+}"
if [[ "${BUILD_NUMBER}" == "${VERSION}" ]]; then
  BUILD_NUMBER="${BUILD_NAME}"
fi

flutter pub get
(
  cd macos
  pod install
)
flutter build macos \
  --release \
  --config-only \
  --build-name "${BUILD_NAME}" \
  --build-number "${BUILD_NUMBER}"

xcrun xcodebuild \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -derivedDataPath build/macos \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  FLUTTER_BUILD_NAME="${BUILD_NAME}" \
  FLUTTER_BUILD_NUMBER="${BUILD_NUMBER}" \
  build \
  -quiet

echo "Built ${APP_PATH}"
