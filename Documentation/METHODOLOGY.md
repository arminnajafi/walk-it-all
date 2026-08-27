# Coverage methodology

## Completion area

Version 1 uses the largest polygon in NYC Open Data’s Manhattan borough boundary, corresponding to Manhattan Island. Roosevelt Island, Governors Island, Randall’s/Wards Island, and Marble Hill are excluded.

## Eligible ways

Included OpenStreetMap geometry:

- Primary through residential streets where pedestrian access is not prohibited
- Living streets, pedestrian streets, and linear walking ways through plazas
- Public footways, paths, greenways, steps, and meaningful connectors
- Service, cycle, and track geometry only when public foot access is explicit

Excluded geometry:

- Private, permit-only, customer-only, destination-only, or delivery-only access
- Motorways and unsupported vehicle-only highways
- Construction, indoor ways, areas, parking aisles, driveways, and drive-throughs
- Explicit sidewalk ways, because the street centerline is the completion proxy
- Path fragments shorter than 12 meters unless they are streets, pedestrian ways, or steps

Mapped crosswalks remain in the internal graph as non-goal connectors. They help the matcher move between street centerlines and pedestrian networks, but they are not rendered and add nothing to the completion denominator.

The filtering report is generated beside each map-package version. These rules are intentionally deterministic and reviewable; they will be tuned only through real-route evaluation, not silently at runtime.

## Matching

1. Sort Health locations by timestamp.
2. Reject invalid coordinates and horizontal accuracy worse than 50 meters.
3. Split rather than bridge gaps exceeding the configured time, distance, or walking-speed limits.
4. Search the offline spatial grid for nearby eligible ways.
5. Score candidates by absolute coordinate distance relative to reported accuracy; a lone nearby candidate is not automatically trusted.
6. Use heading and graph-path continuity in a Viterbi sequence.
7. Reject transitions that imply a path far longer than observed movement.
8. Credit only transitions whose confidence clears the conservative threshold.

Shortest-path searches use a transition-sized distance budget and are cached within each workout match. Graph-only crossings can connect eligible ways but cannot themselves become GPS candidates or earn coverage. No route or coordinate is sent to a server.

## Progress

Each accepted traversal becomes a distance interval on one or more network segments. Intervals are unioned across workouts so repeated walks do not count twice.

```text
completion = unique covered meters / total eligible meters
```

A segment is visually complete at 70% covered, while the headline percentage uses continuous covered distance. This prevents short map fragments from having the same weight as long avenues or greenways.

## Accuracy gate

Before public distribution, evaluate at least ten hand-reviewed Manhattan routes representing parallel Midtown streets, dense intersections, park paths, waterfronts, scaffolding/tall-building noise, pauses, gaps, and transit interruptions.

Target acceptance:

- At least 98% precision on credited segments
- At least 90% recall on clearly traversed eligible distance
- No unexplained parallel-street or gap-crossing errors

Precision is the priority: uncertain coverage remains unmarked.
