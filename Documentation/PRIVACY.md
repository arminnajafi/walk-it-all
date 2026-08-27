# Privacy model

Walk It All is intentionally local-first.

## Permissions

The app requests read-only access to:

- Walking and hiking workouts
- Workout route series associated with those workouts

It does not request Health write access, foreground location, background location, motion tracking, contacts, advertising identifiers, or an account.

Apple intentionally does not disclose whether Health read access was denied. The interface therefore never diagnoses denial; it explains that an empty result can mean no outdoor route, limited access, or incomplete Health synchronization.

## Local data

For each imported workout, the app retains:

- Health workout UUID and dates
- Source application/device name
- Simplified route geometry
- Matched network intervals and confidence
- Unmatched time portions

Full-resolution route locations are discarded after matching. The aggregate coverage snapshot is derived from per-workout intervals.

The SwiftData store is created with complete file protection and excluded from device backup. Logs may include public error descriptions and counts but never coordinates, route geometry, or Health UUIDs.

## Cloud recovery

There is no Walk It All cloud database. Apple Health remains the cloud-synchronized history. On a new device or after reinstalling, the app rebuilds from whatever Health data has synchronized and the user authorizes.

The app does not claim that every historical route is recoverable. Walks not recorded as route-bearing workouts, deleted from Health, or excluded by limited authorization cannot be reconstructed.

## Network behavior

The app itself has no route-upload, analytics, advertising, account, or remote map-matching service. Apple MapKit may retrieve basemap tiles under Apple’s system behavior. The bundled OpenStreetMap-derived walking network is read offline.

## Public-release checklist

Before App Store submission:

- Publish a privacy-policy URL matching the implementation
- Re-audit the privacy manifest and required-reason APIs against the release SDK
- Verify App Store privacy answers from an actual network audit
- Retain OSM attribution and ODbL notices
- Review any future crash-reporting or support export before adding it

