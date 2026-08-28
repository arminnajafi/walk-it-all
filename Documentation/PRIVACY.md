# Privacy and Recovery

## Data use

Walk It All requests read-only access to walking and hiking workouts and workout routes. It never writes to Apple Health and never requests live or background location.

The app has no account, server, analytics, advertising, or CloudKit container. Health-derived routes are not transmitted by Walk It All. Apple Maps may use Apple’s normal MapKit network services to display its basemap.

## Local minimization

Full-resolution Health locations exist only while one workout is being processed. The durable cache contains:

- workout UUID, dates, and source name;
- simplified route parts;
- Health import cursor and processed-workout ledger; and
- the exact last successful refresh date.

Coordinates and Health identifiers must never appear in logs. Private device evidence belongs only under the ignored `LocalRouteFixtures/` directory.

## Protection

The history directory, store, and existing WAL/SHM sidecars receive complete file protection and explicit backup exclusion. The app reapplies these attributes after writes. The cache is rebuildable and intentionally does not use device backup or iCloud storage.

## Recovery

Apple Health is the recoverable history. After reinstalling or changing phones, the user authorizes access and Walk It All reconstructs its local route map from whatever Health history has synchronized to that device.

HealthKit intentionally does not disclose whether read access was denied. Empty-state copy therefore lists possible causes rather than asserting a permission decision.
