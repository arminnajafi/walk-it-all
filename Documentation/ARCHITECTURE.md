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

The cache also records route-less workouts that have already been checked, so an interrupted import does not repeatedly query a lifetime of indoor walks. Incremental refreshes recheck the last seven days because Health route samples can finish after their workout. A manual full rebuild remains the recovery path for older delayed data.

## Versioning

The city package records an identifier, integer version, source timestamp, and checksum. Persisted workouts also record the package identifier and version. A package change atomically invalidates workout import status, checkpoints, matches, and the aggregate snapshot. The next refresh rebuilds from Health rather than attempting brittle geometry-ID migrations.

## Map rendering

The main map uses Apple MapKit. Overlay construction runs off the main actor. An immutable custom overlay spatially indexes covered and remaining polylines, and its thread-safe renderer batches only geometry intersecting the current map rectangle. Remaining paths are faint at city scale and become clearer at neighborhood scale; solid versus dashed styling means state does not depend on color alone.
