#!/usr/bin/env bash
# Xcode Cloud runs this after cloning. The Xcode project is not committed, so generate it here
# (Xcode Cloud expects ci_scripts/ next to TronIPTV.xcodeproj). See docs/APP_STORE.md.
set -euo pipefail

cd "${CI_PRIMARY_REPOSITORY_PATH:?not running in Xcode Cloud}"

brew install xcodegen
scripts/fetch-vlckit.sh

# Build number from Xcode Cloud, signing team from the workflow's team. Base.xcconfig includes this file last.
{
  echo "CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER:?}"
  if [[ -n "${CI_TEAM_ID:-}" ]]; then echo "DEVELOPMENT_TEAM = $CI_TEAM_ID"; fi
} > Config/Local.xcconfig

xcodegen generate
