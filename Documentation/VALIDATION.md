# MVP validation record

This file records reproducible engineering evidence without workout coordinates, Health identifiers, or other personal route data.

## Automated baseline

- `WalkItAllCore`: 20 unit tests plus the executable core checks
- `CityPackBuilder`: 13 tests
- iOS app: 25 unit tests
- iOS UI: 5 end-to-end tests, including an accessibility XXXL onboarding journey
- Synthetic coverage: 1,500 workout contributions and a 2,500-point route

The complete suites must pass together before a personal-device build is signed off.

## Offline Manhattan map

Map version 2 is generated from the pinned 2026-08-25 Geofabrik New York extract and checksum-verified NYC water-excluded Manhattan boundary.

- SQLite integrity: `ok`
- Segments: 36,827
- Eligible distance: 760.877143 miles
- Outside-boundary, invalid, duplicate-ID, and duplicate-geometry counts: zero
- Exact equivalent geometry removed deterministically: one 13.6-meter park path
- Graph components: 3,230

The complete evidence and review samples are in `manhattan-v2-report.json`; the manual denominator review remains a release gate.

## Simulator UI and performance

Environment: Xcode 26.6, iOS 26.5, iPhone 17 Pro simulator.

A focused, symbolicated ETTrace 1.1.0 cold-launch-to-map capture ran for 13.174 seconds. The main thread was idle for 12.679 seconds and active for 0.495 seconds. Samples were dominated by SwiftUI setup/layout and Apple Maps rendering; route matching and aggregate coverage calculation did not appear on the main thread. Raw profiler output was temporary and contained no private Health route.

Apple's `xctrace` command-line Time Profiler failed to finalize two simulator recordings after their requested time limits under Xcode 26.6. The incomplete traces were discarded. A native Instruments capture on the real phone remains part of the final personal-device pass.

Visual and automated checks cover normal light appearance plus dark, increased-contrast, and accessibility XXXL layouts. At accessibility sizes the progress card and onboarding become scrollable, decorative imagery yields to content, controls remain reachable, and the map controls retain VoiceOver labels. The map measures the floating card and reserves that space through `MKMapView` layout margins, keeping Apple Maps attribution visible instead of relying on a device-specific fixed inset.

## Privacy and recovery

- No app networking client, CloudKit, analytics, advertising, or location permission
- Runtime cache directory has complete file protection and an explicit backup-exclusion resource value
- Simulator inspection confirms the backup-exclusion marker covers the SwiftData store, WAL, and shared-memory sidecar files
- No coordinates, routes, or Health UUIDs are logged
- The signed device bundle contains HealthKit entitlement and no profiler framework
- Coverage remains derived from per-workout contributions and can be rebuilt from authorized Apple Health history

## Personal-device evidence and remaining human gate

A real iPhone completed the version-2 Health rebuild: 229 walking/hiking workouts were considered and 211 route-bearing workouts were imported and evaluated. Automatic foreground refresh, workout selection, Manhattan recentering, and the protected on-device cache were exercised with the real history.

Two representative routes have completed visual review with no marked false credit or missed eligible segment. The next longer Central Park route exposed a substantial recall failure, so the ten-route gate is paused while that case is diagnosed. Personal-device signoff still requires fixing or explaining that route and completing the aggregate precision/recall gate described in `ACCURACY_REVIEW.md`; automated tests cannot substitute for those visual judgments.
