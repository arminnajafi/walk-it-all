# Personal accuracy review

The MVP is not accuracy-signed-off until at least ten real Health routes have been reviewed. Use a DEBUG build on the owner’s iPhone:

1. Open **Coverage → Workout history**.
2. Tap the ladybug beside a representative workout.
3. Compare the raw Health trace, matcher candidates, credited intervals, and rejected portions with the corresponding Apple Fitness map.
4. Mark credited segments that were not walked and candidate segments that were clearly walked but missed.
5. Save the local review fixture. Never add the fixture, route screenshots, coordinates, or Health IDs to Git.

Choose routes that collectively cover:

- Parallel Midtown streets
- Dense intersections and tall-building noise
- An ordinary Manhattan grid walk
- Central Park paved paths and trails
- Hudson River paths
- East River paths
- Stairs or pedestrian connectors
- Pauses and repeated points
- A GPS outage
- Transit interruption or another large gap
- A longer mixed route (this may overlap one category above)

For each route, ambiguous segments stay outside the reviewed denominator. The inspector calculates:

```text
precision = correctly credited segment meters / all credited segment meters
recall = correctly credited segment meters / all clearly walked eligible segment meters
```

Aggregate the meter totals across routes before calculating the final ratios. Required acceptance:

- Precision at least 98%
- Recall at least 90%
- No unexplained parallel-street assignment
- No subway, transit, or GPS-gap bridge
- No unexplained grade-separated crossing
- Every rejected portion has a reproducible reason

Tune matcher thresholds only in response to reviewed evidence. Convert non-sensitive synthetic reproductions of fixed failures into committed regression tests; keep real route fixtures local.
