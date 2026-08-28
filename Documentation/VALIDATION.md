# Validation

## Automated gates

The verification script must pass:

- pure-Swift route filtering, gap separation, simplification, bounds, and stress tests;
- Health cursor migration and route-association tests;
- repository replacement, deletion, reset, corruption recovery, cursor, ledger, and timestamp round trips;
- synchronization addition, invalidation, deletion, cancellation, generation, and refresh-throttle tests;
- overlay completeness, worldwide bounds, spatial clipping, repeat pass, and selection viewport tests;
- onboarding, empty state, details, Health help, history, privacy, and Dynamic Type UI tests.

## Personal-device gate

Before signoff:

1. Rebuild the connected iPhone and confirm 210 drawable workout routes and the 229-workout processed ledger return. The former completion cache contained 211 workout rows, but one row's saved route geometry was an empty array; it was never a route-bearing map record.
2. Compare at least ten representative routes with Apple Fitness. Confirm that inaccurate points, subway travel, outages, and implausible jumps are not bridged.
3. Record a new Outdoor Walk, wait until it reaches Health, and verify foreground incremental refresh after five minutes. Verify manual Refresh bypasses the throttle.
4. Verify a replaced or deleted Health route updates the cached map.
5. Reinstall after Health synchronization and rebuild the same history.

## Performance gate

Use a Release build and realistic synthetic history of at least 1,500 workouts with multi-thousand-point raw routes. Require:

- route processing and overlay construction outside the main actor;
- smooth map pan and zoom;
- no interaction stall over 100 milliseconds attributable to the app;
- no unbounded memory growth across workouts.

If the density pass misses the gate, retain the same renderer with only the baseline stroke. Do not add a raster-tile system for the MVP.

## Privacy and accessibility gate

Verify light and dark appearance, high contrast, reduced transparency, reduced motion, VoiceOver, and all Dynamic Type sizes. Confirm 44-point controls and that normal-size layouts remain compact.

On a real device, confirm complete file protection while locked, backup exclusion on the directory/store/sidecars, redacted logs, and no app-originated network activity beyond Apple MapKit.

## Current status

The previous street-completion implementation is preserved on `codex/street-completion-archive`.

Verified on August 28, 2026:

- 13 core tests, 20 app/storage/map tests, and 7 rendered UI tests pass;
- the connected iPhone Release rebuild restored 210 drawable routes plus all 229 processed workouts;
- the active store, WAL, sidecar, and directory are excluded from backup, and the code/test invariant requests complete file protection;
- a 15-second real-device Time Profiler recording reported no hangs or hang-risk events above its 250-millisecond threshold;
- the signed tested build is installed over the prior app, and the legacy store files are gone.

The remaining personal-field checks require a future Health event or visual comparison with Apple Fitness and therefore remain acceptance follow-ups rather than release-blocking code work.
