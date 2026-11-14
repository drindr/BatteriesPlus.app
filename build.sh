#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

xcodebuild -project BatteriesPlus.xcodeproj -scheme BatteriesPlus \
  -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

app="build/Build/Products/Release/Batteries++.app"
codesign --force --sign - --entitlements Configuration/App.entitlements "$app/Contents/MacOS/batteryctl"
codesign --force --sign - --entitlements Configuration/Widget.entitlements "$app/Contents/PlugIns/BatteriesPlusWidget.appex"
codesign --force --sign - --entitlements Configuration/App.entitlements "$app"
codesign --verify --deep --strict "$app"
printf '\nBuilt %s/%s\n' "$PWD" "$app"
