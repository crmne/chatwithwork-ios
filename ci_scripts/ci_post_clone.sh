#!/bin/bash
# Xcode Cloud runs this after cloning. Signing.xcconfig is git-ignored (the
# repository is public), so write it from what Xcode Cloud knows: the team
# it signs with, and its own build number, which App Store Connect needs to
# grow with every upload. The product's next build number is set in App
# Store Connect (Xcode Cloud > ChatWithWork > Settings > Build Number); it
# started at 10002, above the builds uploaded by hand.
#
# Builds of main carry MARKETING_VERSION from Config/Base.xcconfig. A build
# started from a vX.Y.Z tag carries the tag's version instead.
set -euo pipefail

{
  echo "DEVELOPMENT_TEAM = $CI_TEAM_ID"
  echo "CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER"
  if [[ "${CI_TAG:-}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "MARKETING_VERSION = ${BASH_REMATCH[1]}"
  fi
} > "$CI_PRIMARY_REPOSITORY_PATH/Config/Signing.xcconfig"

xcodebuild -resolvePackageDependencies \
  -project "$CI_PRIMARY_REPOSITORY_PATH/ChatWithWork.xcodeproj" \
  -scheme ChatWithWork
