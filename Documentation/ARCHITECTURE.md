# Architecture

## Sources of truth

Walk It All has two sources of truth:

1. Apple Health owns recorded walking and hiking workouts and route locations.
2. A versioned offline city map owns the eligible walking network and completion denominator.

Everything persisted by the app is a rebuildable local projection of those sources. Manual coverage is intentionally absent so there is no unsynchronized second history.

## Modules

### WalkItAllCore

The portable Swift package contains:

- Geographic coordinates and polyline projection/slicing
- Route accuracy filtering and gap splitting
- Immutable city graph and fixed-grid spatial lookup
- Bounded shortest-path search
- Continuity-aware Viterbi/HMM matching
- Segment-interval union and distance-weighted progress

It has no HealthKit, MapKit, SwiftData, UIKit, network, or user-interface dependency.

### iOS application

The app target adapts platform services through narrow boundaries:

- `HealthKitWorkoutRouteSource` implements `WorkoutRouteSource`.
- `SwiftDataCoverageRepository` implements `CoverageRepository`.
- `SQLiteCityPackLoader` creates an immutable `CityCoveragePack`.
- `AppModel` owns user-visible lifecycle state on the main actor.
- `CoverageMapView` is the only UIKit bridge and hosts `MKMapView`.

SwiftUI screens receive the root `AppModel` explicitly. Sheet presentation is enum-driven. Import and matching work is cancellable and runs outside the main actor.

## Data flow

```text
Apple Health workout
        │ batched route locations
        ▼
accuracy filter + gap splitter
        │ clean route chunks
        ▼
continuity-aware matcher ◄── offline Manhattan graph
        │ confident segment intervals
        ▼
per-workout protected cache
        │ union intervals
        ▼
coverage snapshot ─────────► map renderer + progress card
```

Health anchored-query checkpoints are saved only after the corresponding batch has been processed. Deleted workout UUIDs remove their per-workout contributions before aggregate coverage is recalculated.

The Health cursor is versioned inside the iOS adapter and contains independent workout and workout-route anchors plus route-sample-to-workout associations. Route additions and replacements reprocess their parent workout; route deletions remove only that route contribution unless the workout itself was also deleted. A legacy workout-only anchor is retained while a one-time full route reconciliation checks historical workouts, including records whose old route disappeared before the route anchor existed.

The cache also records route-less workouts that have already been checked, so an interrupted import does not repeatedly query a lifetime of indoor walks. Incremental refreshes recheck the last seven days because Health route samples can finish after their workout. Once the user has explicitly connected Health, the app refreshes when it becomes active if the last successful refresh is more than five minutes old. Manual refresh bypasses that throttle, and a manual full rebuild remains the recovery path for older delayed data.

Per-workout contributions are the only durable coverage projection. Intervals are normalized before persistence, unmatched diagnostics are coalesced, and the aggregate snapshot is always recalculated off the main actor—even for an empty record set. The legacy optional snapshot field remains temporarily in the SwiftData schema only for store compatibility and is cleared during preparation.

If any persisted workout projection cannot be decoded, the complete rebuildable cache, import ledger, and Health cursor are cleared together. Retaining a partial cache could let an old processed-workout entry or advanced anchor prevent the damaged workout from being reconstructed.

## Versioning

The city package records an identifier, integer version, source timestamp, and checksum. Persisted workouts also record the package identifier and version. The cache separately records a matching-projection version so matcher fixes cannot silently leave stale contributions behind. A city-package or matching-projection change atomically invalidates workout import status, checkpoints, and matches. The next refresh rebuilds from Health rather than attempting brittle geometry-ID migrations.

## Map rendering

The main map uses Apple MapKit. Overlay construction runs off the main actor. An immutable custom overlay spatially indexes covered and remaining polylines, and its thread-safe renderer clips and batches only geometry intersecting the requested map rectangle. The visible blue network always uses exact credited intervals; the 70% threshold affects only the secondary completed-segment count. Remaining paths are faint at city scale and become clearer at neighborhood scale; solid versus dashed styling means state does not depend on color alone.

Map movement is expressed as an explicit viewport command (`fit Manhattan` or `fit selected workout`). SwiftUI never reaches into `MKMapView` directly. The selected workout draws its simplified Health route in orange and its exact credited network intervals in indigo.
