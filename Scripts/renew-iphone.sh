#!/bin/zsh
# Renew an existing personal installation using the project's signing settings.
set -euo pipefail
cd "${0:A:h:h}"
device_list=$(mktemp -t walk-it-all-devices)
trap 'unlink "$device_list"' EXIT
xcrun devicectl list devices --json-output "$device_list" >/dev/null
target=$(python3 - "$device_list" "${1:-}" <<'PY'
import json, sys

with open(sys.argv[1]) as f:
    devices = json.load(f)["result"]["devices"]
phones = []
for device in devices:
    hw = device["hardwareProperties"]
    if hw.get("reality") != "physical" or hw.get("deviceType") != "iPhone":
        continue
    if device["connectionProperties"].get("tunnelState") == "unavailable":
        continue
    name = device["deviceProperties"].get("name", "")
    if not sys.argv[2] or sys.argv[2] in (name, hw["udid"]):
        phones.append((name, hw["udid"]))
if not phones:
    sys.exit("Connect and unlock your iPhone, trust this Mac, then try again.")
if len(phones) > 1:
    sys.exit("Pass one iPhone name as an argument: " + ", ".join(p[0] for p in phones))
print(phones[0][1])
PY
)
build_dir="${TMPDIR:-/tmp}/walk-it-all-personal-build"
xcodebuild -quiet -project WalkItAll.xcodeproj -scheme WalkItAll -configuration Release \
  -destination "platform=iOS,id=$target" -derivedDataPath "$build_dir" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
app="$build_dir/Build/Products/Release-iphoneos/WalkItAll.app"
bundle_id=$(plutil -extract CFBundleIdentifier raw "$app/Info.plist")
expires=$(security cms -D -i "$app/embedded.mobileprovision" | plutil -extract ExpirationDate raw -)
xcrun devicectl device install app --device "$target" "$app"
print "Installed. Signing expires $expires."
xcrun devicectl device process launch --device "$target" "$bundle_id"
