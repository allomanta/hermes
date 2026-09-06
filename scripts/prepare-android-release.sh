#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

"${SCRIPT_DIR}/prepare-android-signing.sh"

: "${PLAYSTORE_DEPLOY_KEY:?PLAYSTORE_DEPLOY_KEY is required}"

cd "${PROJECT_DIR}/android"
printf '%s' "${PLAYSTORE_DEPLOY_KEY}" > keys.json
bundle install
bundle update fastlane
bundle exec fastlane set_build_code_internal
