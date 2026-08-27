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

## Versioning

The city package records an identifier, integer version, source timestamp, and checksum. Persisted workouts also record the package identifier and version. A package change invalidates derived matching and should trigger a rebuild rather than attempting brittle geometry-ID migrations.

## Map rendering

The main map uses Apple MapKit. An immutable custom overlay contains covered and remaining polylines. The renderer draws only geometry intersecting the current map rectangle, hides remaining paths at broad zoom, and uses solid versus dashed styling so state does not depend on color alone.

