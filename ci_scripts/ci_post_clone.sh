#!/bin/bash
# Xcode Cloud runs this after cloning. Signing.xcconfig is git-ignored (the
# repository is public), so write it from what Xcode Cloud knows: the team
# it signs with, and its own build number, which App Store Connect needs to
# grow with every upload.
set -euo pipefail

cat > "$CI_PRIMARY_REPOSITORY_PATH/Config/Signing.xcconfig" <<XCCONFIG
DEVELOPMENT_TEAM = $CI_TEAM_ID
CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER
XCCONFIG

xcodebuild -resolvePackageDependencies \
  -project "$CI_PRIMARY_REPOSITORY_PATH/ChatWithWork.xcodeproj" \
  -scheme ChatWithWork
