#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
developer_directory=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

cd "$repository_root"
DEVELOPER_DIR="$developer_directory" xcodebuild \
  -project Matari.xcodeproj \
  -scheme MATARI \
  -configuration Release \
  -derivedDataPath .build/ReleaseDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

app_path="$repository_root/.build/ReleaseDerivedData/Build/Products/Release/MATARI.app"
codesign --force --deep --sign - --options runtime "$app_path"
echo "$app_path"
