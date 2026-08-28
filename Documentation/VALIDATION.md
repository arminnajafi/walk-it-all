# Validation

## Automated gates

The verification script must pass:

- pure-Swift route filtering, gap separation, simplification, bounds, and stress tests;
- Health cursor migration and route-association tests;
- repository replacement, deletion, reset, corruption recovery, cursor, ledger, and timestamp round trips;
- synchronization addition, invalidation, deletion, cancellation, generation, and refresh-throttle tests;
- overlay completeness, worldwide bounds, spatial clipping, repeat pass, and selection viewport tests;
- Live Trail filtering, discontinuities, Pause/Resume separation, final Finish, Health association, exact-file persistence, corruption, replacement, and expiry tests;
- onboarding, empty state, restrained populated map, Live Trail explanation, paused and finished states, details, Health help, history, privacy, and Dynamic Type UI tests.

## Personal-device gate

Before signoff:

1. Rebuild the connected iPhone and confirm 210 drawable workout routes and the 229-workout processed ledger return. The former completion cache contained 211 workout rows, but one row's saved route geometry was an empty array; it was never a route-bearing map record.
2. Compare at least ten representative routes with Apple Fitness. Confirm that inaccurate points, subway travel, outages, and implausible jumps are not bridged.
3. Start an Apple Watch Outdoor Walk and Live Trail, lock the phone, walk several blocks, and confirm the solid green trail is continuous after reopening. Pause and confirm background trail tracking and its system indicator stop; Resume and confirm a new trail part begins without bridging the break. Finish and confirm the stopped state is final.
4. Wait for Apple Health and confirm its indigo route replaces rather than duplicates the dashed provisional trail. Verify automatic five-minute refresh and manual bypass.
5. Exercise denied permission, interruption/relaunch, stationary time, implausible movement, 12-hour timeout, route replacement/deletion, and seven-day cleanup.
6. Reinstall after Health synchronization and rebuild the same permanent history; confirm no temporary Live Trail is restored from backup.

## Performance gate

Use a Release build and realistic synthetic history of at least 1,500 workouts with multi-thousand-point raw routes. Require:

- route processing and overlay construction outside the main actor;
- smooth map pan and zoom;
- no interaction stall over 100 milliseconds attributable to the app;
- no unbounded memory growth across workouts;
- no unbounded growth during a multi-hour Live Trail and no excessive map-overlay churn;
- acceptable battery use during at least one two-hour real walk.

If the density pass misses the gate, retain the same renderer with only the baseline stroke. Do not add a raster-tile system for the MVP.

## Privacy and accessibility gate

Verify light and dark appearance, high contrast, reduced transparency, reduced motion, VoiceOver, and all Dynamic Type sizes. Confirm 44-point controls and that normal-size layouts remain compact.

On a real device, confirm complete protection for permanent history, complete-until-first-user-authentication protection for the locked-screen Live Trail checkpoint, backup exclusion on both stores, redacted logs, and no app-originated network activity beyond Apple MapKit.

## Current status

The previous street-completion implementation is preserved on `codex/street-completion-archive`.

Verified on August 28, 2026:

- 19 core tests, 29 app/storage/map tests, and 10 rendered UI tests pass;
- the connected iPhone Release rebuild restored 210 drawable routes plus all 229 processed workouts;
- the active store, WAL, sidecar, temporary trail, and their directories are excluded from backup; code/test invariants request complete protection for permanent history and locked-screen-compatible protection for the temporary trail;
- a 15-second real-device Time Profiler recording reported no hangs or hang-risk events above its 250-millisecond threshold;
- Live Trail compaction runs away from the main actor, Pause/Resume cannot bridge a gap, temporary map revisions are rate-limited, and history overlays remain immutable;
- the signed Release build containing Live Trail and the location background mode is installed and launches on the connected iPhone.

The remaining field checks require physical movement or elapsed time: a locked-phone Live Trail walk including Pause/Resume, Health replacement after ending the Watch workout, two-hour battery profiling, and destructive reinstall/recovery checks. They remain explicit personal-device acceptance work rather than claims made from simulator evidence.
