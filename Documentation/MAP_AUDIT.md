# Manhattan offline-map audit

The generated `manhattan-v1.sqlite` package must pass three different checks before use:

1. SQLite structural integrity
2. Deterministic filtering and source/checksum reporting
3. Walking-graph connectivity and denominator review

The machine-readable results live in `manhattan-v1-report.json`. Version 1 intentionally separates completion geometry from graph-only geometry: mapped crossings can connect roads to paths while contributing zero distance to the user’s goal.

The initial figures are a technical baseline, not a claim that the denominator is final. The accuracy-gate route review should specifically inspect Central Park, Riverside Park, waterfront greenways, plazas, divided roads, and short connectors. Any filtering adjustment increments the map-package version and rebuilds local coverage from Apple Health.

The current street-centerline total is close to the expected scale for Manhattan, while the larger path total reflects the decision to include meaningful park and pedestrian paths. Unnamed or disconnected path clusters are the highest-priority denominator review before public distribution.

