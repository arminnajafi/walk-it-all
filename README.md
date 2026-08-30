# Walk It All

**See what you’ve covered. Walk it all.**

Walk It All is a private iPhone app that turns outdoor walking, hiking, running, and cycling routes from Apple Health into one lifetime map. It opens on Manhattan and can display recorded routes anywhere in the world.

## Product scope

- Native SwiftUI app for iOS 17 and later
- Read-only walking, hiking, running, and cycling workout-route import from Apple Health
- Conservative filtering of inaccurate locations, GPS gaps, large jumps, and implausible speeds
- Smooth Apple Maps rendering with subtle deepening where routes repeat
- One optional temporary Live Trail with Start, Pause, Resume, Finish, Start New, and Clear
- Native position and compass plus a direction fan that does not rotate the map
- Incremental foreground refresh, including Health route replacements and deletions
- Protected, backup-excluded SwiftData cache rebuilt from Apple Health
- No passive tracking, account, backend, analytics, advertising, CloudKit, or route upload

The app visualizes recorded GPS workouts. Live Trail is only a temporary on-device guide and is never a second permanent route source. The app does not claim verified street or sidewalk completion, and ordinary steps or indoor workouts do not appear.

## Open and verify

The repository uses XcodeGen. Run:

```sh
./Scripts/verify.sh
```

Then open `WalkItAll.xcodeproj`, select the personal development team, and run on an iPhone. Health route access is not representative in Simulator.

The bundle identifier is provisionally `com.arminnajafi.walkitall` and the deployment target is iOS 17.

## Repository guide

- `WalkItAll/`: iOS app, HealthKit adapter, protected persistence, map renderer, and SwiftUI views
- `Packages/WalkItAllCore/`: portable route filtering, simplification, and temporary-session processing
- `Documentation/`: product, architecture, privacy, and validation decisions
- `LocalRouteFixtures/`: ignored private device evidence; never commit its contents

## Documentation

- [Product direction](Documentation/PRODUCT.md)
- [Architecture](Documentation/ARCHITECTURE.md)
- [Privacy and recovery](Documentation/PRIVACY.md)
- [Validation and release gates](Documentation/VALIDATION.md)
- [Route-history pivot decision](Documentation/DECISION-ROUTE-HISTORY.md)
