# Product Direction

## Promise

Walk It All answers one question:

> Where have my recorded outdoor workouts taken me?

The primary experience is a calm lifetime route map. Manhattan is the opening camera position, while saved routes may be anywhere in the world.

## What the map means

Indigo lines are simplified GPS paths from Apple Health walking, hiking, running, and cycling workouts. Repeated routes deepen subtly. An orange, outlined line is the selected workout. The standard blue MapKit indicator shows position and heading after the user requests location access.

For intentional gap-hunting, the user may explicitly start Live Trail. A solid, outlined green line appears immediately and continues through screen lock. Pause turns location delivery off; Resume starts a new route part so the break is never bridged. Finish permanently stops tracking and keeps the slightly muted solid trail until the user clears it or starts a new one. Live Trail is independent of Apple Health and never becomes permanent workout history.

The app does not claim street, sidewalk, block, or city completion. Ordinary steps, indoor workouts, activities without GPS routes, and portions rejected by the safety filters do not appear.

## MVP constraints

Keep:

- one map-first screen;
- two-step onboarding;
- Apple Health refresh, rebuild, history, help, privacy, and limitations;
- explicit Live Trail with Pause/Resume, a 12-hour wall-clock safety limit, and one user-retained finished trail;
- local-first recovery and no recurring service cost.

Defer until user evidence justifies them:

- street or grid completion;
- route suggestions and planning;
- manual drawing or corrections;
- passive or automatic background recording;
- starting or mirroring an Apple Watch workout;
- Live Activities, workout metrics, and fitness coaching;
- sharing, social, playback, and gamification;
- additional map databases, accounts, and monetization.

## Business stance

This is a personal MVP in an established category, not yet a differentiated App Store business. Personal signoff comes before TestFlight. After signoff, 5–10 testers should establish whether the simple gap-finding map changes where people walk and whether a more formal “what remains” system solves a real unmet need.

If public distribution later becomes worthwhile, validate a narrow differentiator first and prefer a one-time purchase or lifetime unlock over a subscription.
