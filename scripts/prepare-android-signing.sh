#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

: "${ANDROID_KEYSTORE_B64:?ANDROID_KEYSTORE_B64 is required}"
: "${ANDROID_KEYSTORE_PASSWORD:?ANDROID_KEYSTORE_PASSWORD is required}"
: "${ANDROID_KEY_ALIAS:?ANDROID_KEY_ALIAS is required}"
: "${ANDROID_KEY_PASSWORD:?ANDROID_KEY_PASSWORD is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KEYSTORE_PATH="${PROJECT_DIR}/android/hermes-release-keystore.jks"

if [[ "$(uname -s)" == "Darwin" ]]; then
  printf '%s' "${ANDROID_KEYSTORE_B64}" | base64 -D > "${KEYSTORE_PATH}"
else
  printf '%s' "${ANDROID_KEYSTORE_B64}" | base64 --decode > "${KEYSTORE_PATH}"
fi
chmod 600 "${KEYSTORE_PATH}"

keytool -list \
  -keystore "${KEYSTORE_PATH}" \
  -storepass "${ANDROID_KEYSTORE_PASSWORD}" \
  -alias "${ANDROID_KEY_ALIAS}" \
  >/dev/null

{
  printf 'storePassword=%s\n' "${ANDROID_KEYSTORE_PASSWORD}"
  printf 'keyPassword=%s\n' "${ANDROID_KEY_PASSWORD}"
  printf 'keyAlias=%s\n' "${ANDROID_KEY_ALIAS}"
  printf 'storeFile=../hermes-release-keystore.jks\n'
} > "${PROJECT_DIR}/android/key.properties"

echo "Android release keystore validated."
