#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"

cd "$project_root/Packages/WalkItAllCore"
swift test

cd "$project_root"
xcodegen generate
git diff --exit-code -- WalkItAll.xcodeproj

if [[ -d /Applications/Xcode.app ]]; then
  simulator_id="$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcrun simctl list devices available --json | python3 -c '
import json, sys
document = json.load(sys.stdin)
for runtime, devices in document["devices"].items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone simulator")
')"
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project WalkItAll.xcodeproj -scheme WalkItAll \
    -destination "platform=iOS Simulator,id=$simulator_id" test
else
  print "Full Xcode is not installed; iOS build and XCTest validation were skipped."
fi
