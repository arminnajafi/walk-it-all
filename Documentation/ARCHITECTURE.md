# Architecture

## Boundaries

Walk It All has three intentionally small layers:

1. `WalkItAllCore` owns platform-independent route validation, gap splitting, and simplification.
2. The iOS services adapt Apple Health and SwiftData to core protocols.
3. SwiftUI owns product state and controls; a narrow `MKMapView` bridge owns route drawing and camera commands.

There is no city database, street graph, map matching, SQLite, backend, or third-party runtime SDK.

## Health synchronization

`HealthKitWorkoutRouteSource` follows two independently mutable streams: workouts and workout-route samples. Its opaque versioned cursor contains both Health query anchors and route-sample-to-workout associations. It also reconciles recent workouts for seven days because a workout can arrive before its route is finalized.

The source emits one workout at a time. Deleted workouts remove the route and processed-ledger row. An invalidated or replaced route removes only the cached route so the workout can be reconciled without losing its import history.

After the user has connected Health, the app refreshes when it becomes active if the last successful refresh and automatic attempt are at least five minutes old. Manual refresh bypasses the throttle. There is no background delivery or location permission.

## Route processing

`RouteProcessor` sorts locations, removes invalid coordinates and locations whose horizontal accuracy is negative or worse than 50 meters, and divides the route at:

- nonpositive elapsed time;
- a gap longer than 60 seconds;
- a jump longer than 200 meters; or
- an implied speed above 6 meters per second.

Every part must contain at least two points. Surviving parts use a three-meter Douglas-Peucker simplification. The full-resolution Health locations are then released.

These rules deliberately preserve the recorded shape rather than guessing a street. A missing or uncertain portion stays absent from the map.

## Persistence and recovery

`WalkHistoryRepository` stores simplified `WorkoutRouteRecord` values, the opaque Health cursor, the processed-workout ledger, and the exact successful-refresh date. The active store is:

`Application Support/WalkItAllHistory/history.store`

The directory, store, and SQLite sidecars use complete file protection and are excluded from backup. SwiftData CloudKit is disabled.

The former `coverage.store` is not migrated. On the first pivot launch, a previously connected user performs a resumable full Health import into the new store. The exact legacy store, WAL, and shared-memory files are deleted only after a successful nonempty rebuild. Failure or cancellation preserves them.

## Map rendering

`LifetimeRouteOverlay` is an immutable snapshot with a fixed-grid spatial lookup. `LifetimeRouteRenderer` queries only polylines intersecting MapKit’s requested rectangle, clips drawing to that rectangle, and performs no mutation while concurrent tiles render.

All visible parts receive a baseline indigo stroke. A low-opacity per-route pass lets repeat walks deepen naturally. Selected workout parts use an orange stroke with a contrasting casing. Overlay construction and route processing run away from the main actor; the app replaces a complete overlay after import completion, cancellation, or failure rather than rebuilding per workout.
