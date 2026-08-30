# Validation

## Automated gates

The verification script must pass:

- pure-Swift activity-aware route filtering, gap separation, simplification, bounds, and mixed-activity stress tests;
- Health cursor v3 migration, route association, authoritative reconciliation, and conservative zero-readable-cache preservation tests;
- repository activity payload compatibility, replacement, deletion, reset, corruption recovery, locked-data deferral, external-support-tree protection, cursor, ledger, and timestamp round trips;
- synchronization addition, invalidation, deletion, cancellation, generation, and refresh-throttle tests;
- overlay completeness, worldwide bounds, native spatial culling, repeat opacity, selection viewport, explicit true-north camera reset, north-up and heading-up tracking state, and selection-without-history-rebuild tests;
- Live Trail filtering, pre-session rejection, discontinuities, Pause/Resume separation, crash-safe final Finish, Clear, exact-file persistence, structural corruption, retained finished state, and locked relaunch ordering tests;
- onboarding, empty state, restrained populated map, Live Trail explanation, paused and finished states, details, Health help, history, privacy, and Dynamic Type UI tests.

## Personal-device gate

Before signoff:

1. Record the current drawable-route and processed-workout counts, run the activity-scope reconciliation, and confirm existing walks/hikes remain while supported runs and rides appear. Counts are intentionally not fixed because they grow as new workouts sync.
2. Compare representative walk, hike, run, and ride routes with Apple Fitness. Confirm that inaccurate points, transit, outages, and implausible jumps are not bridged.
3. Start Live Trail, lock the phone, walk several blocks, and confirm the solid green trail is continuous after reopening. Pause and confirm background trail tracking and its system indicator stop; Resume and confirm a new trail part begins without bridging the break. Finish and confirm the state is final across relaunch.
4. Confirm Start New replaces a finished trail only after confirmation when it has geometry, and Clear removes it. Record a supported Watch workout separately and verify its indigo Health route imports without altering the green trail.
5. Verify outdoors that the first location-button tap follows north-up, the second enters MapKit's heading-up view with an accurate native direction presentation, the third returns north-up, and panning or rotating releases position follow.
6. Exercise denied permission, interruption/relaunch, stationary time, implausible movement, 12-hour timeout, and Health route replacement/deletion.
7. Reinstall after Health synchronization and rebuild the same permanent history; confirm the backup-excluded temporary Live Trail is not restored.

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

Verified on 2026-08-29:

- A [fresh GitHub-hosted run](https://github.com/arminnajafi/walk-it-all/actions/runs/33289411525) from commit `6b71370` passed 22 core tests, 49 app/storage/map tests, and 10 UI tests. Project regeneration also produced no committed-project diff.
- Generic iOS Simulator test builds, Debug static analysis, and a Release simulator build completed without errors.
- A signed Release build was installed and launched wirelessly on the personal iPhone with bundle identifier `com.arminnajafi.walkitall` and team `47F6V2R9AA`.
- The activity-scope reconciliation completed on that iPhone with 220 drawable route records and a 240-workout processed ledger while preserving the existing map.
- The personal device no longer contained the exact legacy `coverage.store`, WAL, or shared-memory files before the obsolete migration path was removed.
- Source inspection confirmed no app networking client, coordinate or Health-identifier logging, CloudKit container, Always-location request, street-matching runtime, or third-party runtime SDK.
- The public repository uses `main` as its sole product branch. Private route fixtures and device exports remain ignored.

Physical movement, outdoor heading accuracy, the two-hour battery pass, and destructive reinstall/recovery remain field checks rather than simulator claims.
