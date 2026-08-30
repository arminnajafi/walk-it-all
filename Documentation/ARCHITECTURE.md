# Architecture

## Boundaries

Walk It All has three intentionally small layers:

1. `WalkItAllCore` owns platform-independent route validation, gap splitting, simplification, and temporary-session processing.
2. The iOS services adapt Apple Health, Core Location, protected files, and SwiftData to core protocols.
3. SwiftUI owns product state and controls; a narrow `MKMapView` bridge owns route drawing and camera commands.

There is no city database, street graph, map matching, SQLite, backend, or third-party runtime SDK.

## Health synchronization

`HealthKitWorkoutRouteSource` follows two independently mutable streams: workouts and workout-route samples. Its opaque versioned cursor contains both Health query anchors and route-sample-to-workout associations. It also reconciles recent workouts for seven days because a workout can arrive before its route is finalized.

Cursor version 3 expands the workout scope to walking, hiking, running, and cycling. Upgrading resets only the workout anchor, retains the all-routes anchor, rebuilds route associations, and publishes the new cursor only after a complete reconciliation. The final authoritative workout-ID set removes stale supported-workout cache rows. If Health returns zero readable workouts while the local cache is nonempty, the app keeps that cache and asks the user to review access because HealthKit does not reveal read denial.

The source emits one workout at a time. Deleted workouts remove the route and processed-ledger row. An invalidated or replaced route removes only the cached route so the workout can be reconciled without losing its import history. If Health reports a route change while its parent workout is temporarily unavailable, the app conservatively removes that workout's cached geometry rather than advancing the route anchor and leaving a stale path visible.

After the user has connected Health, the app refreshes at launch, on foreground entry, and every five minutes while active, subject to the five-minute success/attempt throttle. Manual refresh bypasses the throttle. Health background delivery is not enabled.

## Live Trail

`LiveTrailController` starts location only after an explicit user action. It consumes `CLLocationUpdate.liveUpdates(.fitness)` and owns a `CLBackgroundActivitySession`, allowing an active session to continue through backgrounding and screen lock with Apple’s visible privacy indicator. The app requests When In Use authorization only and never requests Always access.

Live updates use the shared 50-meter accuracy and 60-second time-gap rules, plus activity-neutral temporary limits of 500 meters per point and 25 meters per second. Invalid updates force a new part, accepted points are simplified at periodic protected checkpoints, and map snapshots are published no more than once every two seconds. Fitness-mode stationary handling lets Core Location suspend unnecessary delivery. A 12-hour task plus an update-time check closes forgotten sessions.

Pause immediately invalidates location delivery and the background activity session while preserving the filtered temporary trail. Resume creates a new route part before restarting delivery, so time spent paused can never become an artificial connecting line. Finish is final. The 12-hour limit covers the whole wall-clock session, including paused time.

The app bootstraps the controller on every launch. Live Trail recovery runs before the permanent history cache is opened, and that cache is opened lazily only when protected data is available. This lets a locked background relaunch recover an explicit Live Trail without weakening the permanent cache's protection. A foreground retry after unlock opens the lifetime history without reloading an older trail checkpoint. Normal backgrounding and screen lock keep an active session alive, while recovery after process termination starts a new route part when the app is next launched. Force-quitting the app stops location delivery; When In Use authorization does not promise an automatic relaunch.

Finish stops delivery and invalidates the background session before changing state. It stores the terminal `finished` state before final compaction, so a crash cannot recover an explicitly finished checkpoint as active and restart location. Finished trails do not expire or reconcile with Health: the user clears the sole temporary trail or atomically replaces it with Start New.

## Route processing

`RouteProcessor` sorts locations, removes invalid coordinates and locations whose horizontal accuracy is negative or worse than 50 meters, and divides every activity at nonpositive time or gaps longer than 60 seconds. Distance and implied-speed limits vary by activity:

| Activity | Maximum point distance | Maximum speed |
| --- | ---: | ---: |
| Walking or hiking | 200 m | 6 m/s |
| Running | 300 m | 12 m/s |
| Cycling | 500 m | 25 m/s |

Every part must contain at least two points. Surviving parts use a three-meter Douglas-Peucker simplification. The full-resolution Health locations are then released.

These rules deliberately preserve the recorded shape rather than guessing a street. A missing or uncertain portion stays absent from the map.

## Persistence and recovery

`WalkHistoryRepository` stores simplified `WorkoutRouteRecord` values, the opaque Health cursor, the processed-workout ledger, and the exact successful-refresh date. Activity kind and geometry share a versioned payload in the existing external-data field; legacy geometry-only rows decode as walking without a SwiftData schema migration. The active store is:

`Application Support/WalkItAllHistory/history.store`

The directory, store, SQLite sidecars, and SwiftData external-data support tree use complete file protection and are excluded from backup. SwiftData CloudKit is disabled. Exact-store corruption recovery includes that support tree without touching unrelated files. The former street-completion store is no longer supported; absence of its exact files was verified on the personal device before its migration code was removed.

The sole active, paused, or finished Live Trail is stored separately at:

`Application Support/WalkItAllLiveTrail/session.json`

The file and directory use complete-until-first-user-authentication protection and backup exclusion. This is intentionally narrower than the permanent history cache: it permits checkpoint writes during an explicitly active locked-screen session after the device has been unlocked once since boot. It remains unavailable before that first unlock, stays local, and contains only filtered, periodically simplified points. A finished trail survives ordinary relaunches but not reinstall or device restore.

## Map rendering

`LifetimeRouteSnapshot` is built immutably away from the main actor and contains one native `MKMultiPolyline` overlay per workout. Each overlay has tight local bounds, so MapKit performs its own viewport culling and does not treat worldwide history as one enormous drawing surface. This also avoids maintaining a parallel custom spatial index and renderer.

Every workout receives a translucent indigo stroke, so a single route remains legible while repeated routes deepen naturally through normal alpha compositing. Selected workout parts use an orange stroke with a contrasting casing. Active and paused Live Trail parts use solid green with a casing; finished parts retain the same semantics at lower opacity. The standard MapKit user-location annotation remains the blue position indicator.

The map uses MapKit's native user-tracking modes. From a freely panned map, the location button first enters north-up position following; a second tap enters heading-up following, which rotates the map using MapKit's standard heading presentation; the next tap returns north-up. Starting or resuming Live Trail enters heading-up following. Normal map gestures return the camera to free mode through MapKit's tracking delegate, so the camera never fights the user. No parallel compass service or custom direction annotation is maintained.

Historical overlay construction and Health route processing run away from the main actor; the app replaces a complete history overlay after import completion, cancellation, or failure rather than rebuilding per workout. Selecting or clearing one workout changes only the selected overlay and preserves the immutable history. The temporary overlay has an independent revision and is updated at a bounded cadence, preserving the history snapshot and map interaction performance.
