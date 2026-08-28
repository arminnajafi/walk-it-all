# Architecture

## Boundaries

Walk It All has three intentionally small layers:

1. `WalkItAllCore` owns platform-independent route validation, gap splitting, simplification, and temporary-session association.
2. The iOS services adapt Apple Health, Core Location, protected files, and SwiftData to core protocols.
3. SwiftUI owns product state and controls; a narrow `MKMapView` bridge owns route drawing and camera commands.

There is no city database, street graph, map matching, SQLite, backend, or third-party runtime SDK.

## Health synchronization

`HealthKitWorkoutRouteSource` follows two independently mutable streams: workouts and workout-route samples. Its opaque versioned cursor contains both Health query anchors and route-sample-to-workout associations. It also reconciles recent workouts for seven days because a workout can arrive before its route is finalized.

The source emits one workout at a time. Deleted workouts remove the route and processed-ledger row. An invalidated or replaced route removes only the cached route so the workout can be reconciled without losing its import history.

After the user has connected Health, the app refreshes at launch, on foreground entry, and every five minutes while active, subject to the five-minute success/attempt throttle. Manual refresh bypasses the throttle. Health background delivery is not enabled.

## Live Trail

`LiveTrailController` starts location only after an explicit user action. It consumes `CLLocationUpdate.liveUpdates(.fitness)` and owns a `CLBackgroundActivitySession`, allowing an active session to continue through backgrounding and screen lock with Apple’s visible privacy indicator. The app requests When In Use authorization only and never requests Always access.

Live updates reuse the same 50-meter accuracy and time/distance/speed gap rules as Health routes. Invalid updates force a new part, accepted points are simplified at periodic protected checkpoints, and map snapshots are published no more than once every two seconds. Fitness-mode stationary handling lets Core Location suspend unnecessary delivery. A 12-hour task plus an update-time check closes forgotten sessions.

The app delegate bootstraps the controller during a location-driven relaunch. Recovery always starts a new route part, so suspension or unavailable GPS can never create an artificial bridge.

Finish immediately invalidates location delivery and the background activity session, then stores a waiting-for-Health session. A Health record replaces it when the workout overlaps at least 80 percent of the temporary time interval; maximum overlap wins, followed by minimum excess workout duration. This associates sessions only and never compares or snaps geometry. Unmatched coordinates are deleted after seven days.

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

The sole active or pending Live Trail is stored separately at:

`Application Support/WalkItAllLiveTrail/session.json`

The file and directory receive the same complete protection and backup exclusion as history. It contains only filtered, periodically simplified points and is deleted after Health replacement or seven-day expiry.

## Map rendering

`LifetimeRouteOverlay` is an immutable snapshot with a fixed-grid spatial lookup. `LifetimeRouteRenderer` queries only polylines intersecting MapKit’s requested rectangle, clips drawing to that rectangle, and performs no mutation while concurrent tiles render.

All visible parts receive a baseline indigo stroke. A low-opacity per-route pass lets repeat walks deepen naturally. Selected workout parts use an orange stroke with a contrasting casing. Active Live Trail parts use solid green with a casing; waiting parts use dashed green with the same non-color distinction. The standard MapKit user-location annotation remains the blue position indicator.

Historical overlay construction and Health route processing run away from the main actor; the app replaces a complete history overlay after import completion, cancellation, or failure rather than rebuilding per workout. The temporary overlay has an independent revision and is updated at a bounded cadence, preserving the history snapshot and map interaction performance.
