# MVP validation record

This file records reproducible engineering evidence without workout coordinates, Health identifiers, or other personal route data.

## Automated baseline

- Complete verification run: August 28, 2026
- `WalkItAllCore`: 24 unit tests plus the executable core checks
- `CityPackBuilder`: 15 tests
- iOS app: 25 unit tests
- iOS UI: 5 end-to-end tests, including an accessibility XXXL onboarding journey
- Synthetic coverage: 1,500 workout contributions and a 2,500-point route

The complete suites must pass together before a personal-device build is signed off.

## Offline Manhattan map

Map version 3 is generated from the pinned 2026-08-25 Geofabrik New York extract and checksum-verified NYC water-excluded Manhattan boundary.

- SQLite integrity: `ok`
- Segments: 36,897
- Eligible distance: 765.059571 miles
- Outside-boundary, invalid, duplicate-ID, and duplicate-geometry counts: zero
- Exact equivalent geometry removed deterministically: one 13.6-meter park path
- Graph components: 3,222
- Explicitly foot-accessible `highway=bridleway` geometry: 4.267 miles
- Eligible source geometry tagged `highway=footway`: 208.839 miles, including 206.297 miles without a more specific `footway=*` value

The complete evidence and review samples are in `manhattan-v3-report.json`; the manual denominator review remains a release gate.

## Simulator UI and performance

Environment: Xcode 26.6, iOS 26.5, iPhone 17 Pro simulator.

A focused, symbolicated ETTrace 1.1.0 cold-launch-to-map capture ran for 13.174 seconds. The main thread was idle for 12.679 seconds and active for 0.495 seconds. Samples were dominated by SwiftUI setup/layout and Apple Maps rendering; route matching and aggregate coverage calculation did not appear on the main thread. Raw profiler output was temporary and contained no private Health route.

Apple's `xctrace` command-line Time Profiler failed to finalize two simulator recordings after their requested time limits under Xcode 26.6. The incomplete traces were discarded. A native Instruments capture on the real phone remains part of the final personal-device pass.

Visual and automated checks cover normal light appearance plus dark, increased-contrast, and accessibility XXXL layouts. At accessibility sizes the progress card and onboarding become scrollable, decorative imagery yields to content, controls remain reachable, and the map controls retain VoiceOver labels. The map measures the floating card and reserves that space through `MKMapView` layout margins, keeping Apple Maps attribution visible instead of relying on a device-specific fixed inset. The current screenshot audit also covers onboarding, the empty map, coverage details, methodology and ODbL links, Health-access instructions, privacy, and workout history.

Matching, GPS chunking, route simplification, aggregate calculation, and overlay construction are isolated from the main actor. The August 28 Release build succeeded for a generic iPhone target with an iOS 17 deployment target; the signed app is 22 MB and links only Apple system frameworks plus SQLite.

## Privacy and recovery

- No app networking client, CloudKit, analytics, advertising, or location permission
- Runtime cache directory has complete file protection and an explicit backup-exclusion resource value
- Simulator inspection confirms the backup-exclusion marker covers the SwiftData store, WAL, and shared-memory sidecar files
- No coordinates, routes, or Health UUIDs are logged
- The signed device bundle contains HealthKit entitlement and no profiler framework
- The bundled offline-map metadata contains direct OpenStreetMap attribution and ODbL license URLs, both exposed in the methodology screen
- Coverage remains derived from per-workout contributions and can be rebuilt from authorized Apple Health history
- The August 28 Debug build was installed on the connected iPhone without opening it. While the phone was locked, iOS refused both app launch and reads from the protected local-fixture directory; no route file was copied.

## Personal-device evidence and remaining human gate

A real iPhone completed both the matching-projection rebuild and the subsequent map-version-3 rebuild: 229 walking/hiking workouts were considered and 211 route-bearing workouts were imported and evaluated. The version-3 store retained the Health checkpoint and exact successful-refresh date, cleared the obsolete aggregate snapshot, and contained 211 per-workout contributions. Automatic foreground refresh, workout selection, Manhattan recentering, and the protected on-device cache were exercised with the real history.

Two representative routes have completed visual review with no marked false credit or missed eligible segment. The next longer Central Park route exposed a substantial recall failure. Local diagnosis produced regression-tested fixes for same-way graph-split ambiguity and prefix-only confidence, then found that most residual no-nearby rejections were on OSM bridleways explicitly tagged `foot=yes`. Map version 3 adds only those explicitly walkable bridleways. The corresponding device rebuild increased the route from 0.69 to 1.31 credited miles and visibly recovered the reservoir path without a parallel-path assignment.

A follow-up rejection audit found that the 12-meter emission scale made an otherwise unambiguous candidate near the 15-meter search boundary mathematically unable to pass the 55% threshold. Matching-projection version 3 aligns those floors while retaining the confidence margin between competing ways. A private replay increased this route’s unique credited distance from 2,113.2 to 2,330.7 meters and reduced rejected observed movement from 462.0 to 267.3 meters. Personal-device signoff still requires a projection-version-3 rebuild, final visual review of that route, and completion of the aggregate precision/recall gate described in `ACCURACY_REVIEW.md`; automated tests and an unreviewed replay cannot substitute for those judgments.
