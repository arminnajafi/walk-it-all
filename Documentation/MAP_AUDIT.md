# Manhattan offline-map audit

The generated `manhattan-v3.sqlite` package must pass three different checks before use:

1. SQLite structural integrity
2. Deterministic filtering and source/checksum reporting
3. Walking-graph connectivity and denominator review

The machine-readable results live in `manhattan-v3-report.json`. The builder also emits an ignored `Tools/CityPackBuilder/output/manhattan-v3-review.geojson` containing up to 5,000 suspicious public-map features for local visual review. Version 3 retains version 2’s separation of completion geometry from graph-only geometry: mapped crossings can connect roads to paths while contributing zero distance to the user’s goal. It also removes exact, semantically equivalent same-level duplicate geometry so walking one physical path can never count twice; every removal remains visible in the report.

The audit now scopes exclusion counts to the Manhattan polygon rather than the full New York State extract. It reports named and unnamed goal mileage per kind, a component-size histogram, the 25 largest component bounds and composition, disconnected and singleton mileage by kind, boundary containment, invalid and duplicate geometry, and shared-node bridge/tunnel/layer topology. The SQLite package also preserves the bridge, tunnel, and layer tags used by those checks.

Version 3 contains 36,897 graph segments and 765.060 eligible miles. The net 4.182-mile increase comes from conditionally including OSM bridleways only when `foot` is explicitly `yes`, `designated`, `permissive`, or `official`; 4.267 source miles carry `highway=bridleway`, with a small offset from deduplication and graph changes. This fixes a measured Central Park false exclusion without treating every bridleway as walkable. The affected Central Park ways explicitly carry `foot=yes`, consistent with OSM’s public-foot-access definition and the Central Park Conservancy’s current running map, whose key marks the Bridle Path as closed to bicycles rather than pedestrians. [OSM `foot=yes`](https://wiki.openstreetmap.org/wiki/Tag%3Afoot%3Dyes), [Central Park running map](https://assets.centralparknyc.org/media/documents/CPCWeb_DownloadableMaps_202502_Running_UC.pdf)

The builder found and deterministically removed one exact same-level duplicate path; its kept and removed stable IDs remain in the report. Post-build checks find zero outside-boundary segments, invalid geometries, duplicate identifiers, or duplicate geometries. The 3,222 graph components remain a release risk, as do 189.424 unnamed park-path miles; neither category is removed wholesale because legitimate public park networks often share those properties.

These figures are a technical baseline, not a claim that the denominator is final. The accuracy-gate review must inspect Central Park, Riverside Park, both waterfronts, plazas, stairs, divided roads, shoreline clipping, and bridge approaches. Any evidence-backed filtering or geometry adjustment increments the map-package version and rebuilds local coverage from Apple Health.

The expanded connectivity report narrows the risk: only 0.168 street miles sit outside the largest graph component, compared with 138.269 park-path miles, 8.269 greenway miles, and 6.933 stair miles. Single-segment components account for 16.737 park-path miles and 3.381 stair miles. This points the manual audit toward pedestrian networks without justifying wholesale removal; paths and stairs often form legitimate disconnected OSM components.

The current 503.130 street miles are close to the expected scale for Manhattan, while the 210.367 park-path miles reflect the decision to include meaningful park and pedestrian paths. Unnamed or disconnected path clusters are the highest-priority denominator review before public distribution.

The reproducible report preserves the original OSM classification behind each completion kind. It shows 208.839 eligible miles sourced from `highway=footway`; 206.297 of those miles have no more specific `footway=*` value. This is not evidence that the ways are sidewalks—15,576 explicitly tagged sidewalk ways are already excluded—but it prevents the broad `parkPath` label from hiding the main denominator uncertainty. The review GeoJSON carries both source tags so the manual park, waterfront, plaza, and divided-street inspection can make evidence-based filtering decisions.

The source is a dated Geofabrik extract rather than a moving “latest” URL. Both the PBF and the committed NYC boundary are checksum-verified, and their URLs and SHA-256 values are embedded in the database and report. The database also embeds direct OpenStreetMap attribution and ODbL license URLs; the app surfaces both links in its methodology screen in addition to keeping attribution adjacent to the map.
