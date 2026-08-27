#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"

cd "$project_root/Packages/WalkItAllCore"
swift run WalkItAllCoreChecks

cd "$project_root/Tools/CityPackBuilder"
uv sync --dev
uv run pytest -q

cd "$project_root"
xcodegen generate
sqlite3 WalkItAll/Resources/OfflineMaps/manhattan-v1.sqlite \
  "PRAGMA integrity_check; SELECT count(*) FROM segments;"

if [[ -d /Applications/Xcode.app ]]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project WalkItAll.xcodeproj -scheme WalkItAll \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
else
  print "Full Xcode is not installed; iOS build and XCTest validation were skipped."
fi

