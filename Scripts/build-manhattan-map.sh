#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
builder_root="$project_root/Tools/CityPackBuilder"
data_root="$builder_root/data"
output_root="$builder_root/output"
mkdir -p "$data_root" "$output_root"

boundary_url="https://data.cityofnewyork.us/resource/gthc-hcne.geojson?%24where=boroname%3D%27Manhattan%27"
boundary_sha256="feef754118497ae619cb56be543d1e30145b00bdc5ee0f84f5ea16ac1a301ae9"
pbf_url="https://download.geofabrik.de/north-america/us/new-york-260825.osm.pbf"
pbf_md5="0034ba33daca633e783443e384ac22a1"
boundary_path="$data_root/manhattan-borough.geojson"
pbf_path="$data_root/new-york-260825.osm.pbf"

if [[ ! -f "$boundary_path" ]]; then
  curl --fail --location --retry 3 "$boundary_url" --output "$boundary_path"
fi
if [[ ! -f "$pbf_path" ]]; then
  curl --fail --location --retry 3 "$pbf_url" --output "$pbf_path"
fi

actual_md5="$(md5 -q "$pbf_path")"
if [[ "$pbf_md5" != "$actual_md5" ]]; then
  print -u2 "OpenStreetMap download checksum mismatch"
  exit 1
fi
actual_boundary_sha256="$(shasum -a 256 "$boundary_path" | awk '{print $1}')"
if [[ "$boundary_sha256" != "$actual_boundary_sha256" ]]; then
  print -u2 "Manhattan boundary checksum mismatch"
  exit 1
fi

cd "$builder_root"
uv sync --dev
uv run walkitall-build-city-pack \
  --input-pbf "$pbf_path" \
  --boundary "$boundary_path" \
  --boundary-url "$boundary_url" \
  --output "$project_root/WalkItAll/Resources/OfflineMaps/manhattan-v1.sqlite" \
  --report "$project_root/Documentation/manhattan-v1-report.json" \
  --source-url "$pbf_url"
