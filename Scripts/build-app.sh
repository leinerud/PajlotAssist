#!/bin/bash
# Builds PajlotAssist.app (Dock + menu bar app with its desktop widget) into ./build
set -euo pipefail
cd "$(dirname "$0")/.."
DD="${TMPDIR:-/tmp}/pajlot-dd"
xcodebuild -project PajlotAssist.xcodeproj -scheme PajlotAssist -configuration Release \
  -derivedDataPath "$DD" -allowProvisioningUpdates build | grep -E "error|BUILD" || true
rm -rf build/PajlotAssist.app; mkdir -p build
cp -R "$DD/Build/Products/Release/PajlotAssist.app" build/
echo "Built build/PajlotAssist.app"
