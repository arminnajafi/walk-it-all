# Privacy and Recovery

## Data use

Walk It All requests read-only access to walking and hiking workouts and workout routes. It never writes to Apple Health. Location access is requested only when the user asks to see their position or explicitly starts Live Trail.

There is no passive background tracking. While Live Trail is explicitly active, a When In Use Core Location session continues through screen lock with Apple’s visible location indicator. Pause or Finish invalidates background trail tracking immediately; Resume starts it again only after an explicit tap. The app never requests Always location access.

The app has no account, server, analytics, advertising, or CloudKit container. Health-derived routes are not transmitted by Walk It All. Apple Maps may use Apple’s normal MapKit network services to display its basemap.

## Local minimization

Full-resolution Health locations exist only while one workout is being processed. The durable cache contains:

- workout UUID, dates, and source name;
- simplified route parts;
- Health import cursor and processed-workout ledger; and
- the exact last successful refresh date.

The separate temporary Live Trail file contains only the current active, paused, or waiting session: session dates, filtered route parts, and last update. It never contains unfiltered location updates. It is deleted when the associated Health route imports or seven days after Finish. A non-coordinate expiry date may remain so Details can explain that a Health route was not found.

Coordinates and Health identifiers must never appear in logs. Private device evidence belongs only under the ignored `LocalRouteFixtures/` directory.

## Protection

The permanent Health-derived history directory, store, WAL/SHM sidecars, and SwiftData external-data files receive complete file protection. The temporary Live Trail file uses complete-until-first-user-authentication protection so an explicitly active trail can checkpoint while the screen is locked after the device's first unlock since boot. Both stores are explicitly excluded from backup, and the app reapplies those attributes after writes. Neither uses device backup or iCloud storage.

Live Trail recovery happens before the permanent cache is opened. If iOS relaunches the app for an explicitly active location session while the phone is locked, the temporary session can recover; lifetime history remains unavailable until unlock.

## Recovery

Apple Health is the recoverable history. After reinstalling or changing phones, the user authorizes access and Walk It All reconstructs its local route map from whatever Health history has synchronized to that device.

HealthKit intentionally does not disclose whether read access was denied. Empty-state copy therefore lists possible causes rather than asserting a permission decision.
