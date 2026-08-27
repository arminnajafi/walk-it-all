#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
builder_root="$project_root/Tools/CityPackBuilder"
data_root="$builder_root/data"
output_root="$builder_root/output"
mkdir -p "$data_root" "$output_root"

boundary_url="https://data.cityofnewyork.us/resource/gthc-hcne.geojson?%24where=boroname%3D%27Manhattan%27"
pbf_url="https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf"
md5_url="$pbf_url.md5"
boundary_path="$data_root/manhattan-borough.geojson"
pbf_path="$data_root/new-york-latest.osm.pbf"

curl --fail --location --retry 3 "$boundary_url" --output "$boundary_path"
curl --fail --location --retry 3 "$pbf_url" --output "$pbf_path"
curl --fail --location --retry 3 "$md5_url" --output "$pbf_path.md5"

expected_md5="$(awk '{print $1}' "$pbf_path.md5")"
actual_md5="$(md5 -q "$pbf_path")"
if [[ "$expected_md5" != "$actual_md5" ]]; then
  print -u2 "OpenStreetMap download checksum mismatch"
  exit 1
fi

cd "$builder_root"
uv sync --dev
uv run walkitall-build-city-pack \
  --input-pbf "$pbf_path" \
  --boundary "$boundary_path" \
  --output "$project_root/WalkItAll/Resources/OfflineMaps/manhattan-v1.sqlite" \
  --report "$project_root/Documentation/manhattan-v1-report.json"
