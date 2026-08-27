# Walk It All

**See what you’ve covered. Walk it all.**

Walk It All is a private, local-first iPhone app that turns Apple Health walking and hiking workout routes into a lifetime coverage map. The first offline map covers Manhattan Island.

## Current implementation

- Native SwiftUI app for iOS 17 and later
- Read-only Apple Health workout and route import
- Continuity-aware local map matching with GPS accuracy, heading, and graph transitions
- Distance-weighted coverage with a 70% per-segment completion threshold
- Apple Maps presentation with an OpenStreetMap-derived offline walking network
- Protected, backup-excluded SwiftData cache that can be rebuilt from Apple Health
- No account, backend, analytics, advertising, background location, or route upload
- Debug-only route inspector and deterministic SwiftUI previews

## Open the app

Full Xcode is required. The project is currently validated with Xcode 26.6 and the iOS 26.5 SDK while retaining an iOS 17 deployment target.

1. Run `xcodegen generate` at the repository root.
2. Open `WalkItAll.xcodeproj`.
3. Choose the personal development team under Signing & Capabilities.
4. Run on an iPhone; Health route access is not representative in Simulator.

The bundle identifier is provisionally `com.arminnajafi.walkitall`. It can be changed before the first App Store Connect/TestFlight build upload.

## Verify the platform-independent code

```sh
./Scripts/verify.sh
```

The script verifies the pure-Swift matching core, Python map builder, generated SQLite package, and Xcode project. It also runs iOS tests when full Xcode is available.

## Rebuild the Manhattan offline map

```sh
./Scripts/build-manhattan-map.sh
```

The script verifies a pinned official NYC borough boundary and the dated, checksummed August 25, 2026 Geofabrik New York OpenStreetMap extract, selects Manhattan Island’s largest polygon, and generates:

- `WalkItAll/Resources/OfflineMaps/manhattan-v1.sqlite`
- `Documentation/manhattan-v1-report.json`

The downloaded statewide extract is intentionally ignored by Git. The generated city database contains public map geometry only—never workout data.

## Repository guide

- `WalkItAll/`: iOS application, HealthKit adapter, persistence, maps, and views
- `Packages/WalkItAllCore/`: portable geometry, graph, matcher, and coverage logic
- `Tools/CityPackBuilder/`: reproducible OSM-to-SQLite pipeline
- `Documentation/`: architecture, matching methodology, privacy, and map report

Real Health routes and coordinate-bearing debug exports must never be committed. Local fixtures belong under the ignored `LocalRouteFixtures/` directory.

## Documentation

- [Architecture](Documentation/ARCHITECTURE.md)
- [Coverage methodology](Documentation/METHODOLOGY.md)
- [Manhattan map audit](Documentation/MAP_AUDIT.md)
- [Privacy model](Documentation/PRIVACY.md)
- [Product direction and release gates](Documentation/PRODUCT.md)
- [OpenStreetMap notice](NOTICE)
