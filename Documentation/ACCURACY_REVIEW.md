# Personal accuracy review

The MVP is not accuracy-signed-off until at least ten real Health routes have been reviewed. Use a DEBUG build on the owner’s iPhone:

1. Open **Coverage → Workout history**.
2. Tap **Review** at the top right, then choose a representative workout.
3. Compare the raw Health trace, matcher candidates, credited intervals, and rejected portions with the corresponding Apple Fitness map.
4. Mark credited segments that were not walked and candidate segments that were clearly walked but missed.
5. Tap **Mark review complete**, then save the local review fixture. The inspector intentionally withholds accuracy metrics and fixture saving until this explicit confirmation. Never add the fixture, route screenshots, coordinates, or Health IDs to Git.

The nearby-network review layer intentionally searches wider than the production matcher and includes segments that never became matcher candidates. This makes true no-candidate recall failures reviewable without making production matching less conservative.

If a route has a substantial unexplained failure, use **Save private diagnostic route** only for that route. Unlike the normal review fixture, this diagnostic contains the full Health route and must remain in protected, backup-excluded app storage or the ignored `LocalRouteFixtures` directory. Never share or commit it; delete it after a non-sensitive synthetic regression test reproduces the fix.

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

The current review is intentionally paused after two passing routes because the next longer Central Park route exposed a substantial recall failure. Broader private-route diagnosis found and regression-tested two matcher defects: adjacent graph pieces from one OSM way were treated as competing streets, and confidence considered only the best route prefix instead of using later observations to resolve earlier ambiguity. The post-rebuild device review improved accepted points from 1,178 to 1,415, but still showed extensive conservative rejection.

The exact private replay then identified the main remaining cause without widening matcher tolerances: 681 of 850 points reported as having no nearby eligible way were within four meters of two OSM `highway=bridleway` ways that explicitly carry `foot=yes`. Manhattan map version 3 therefore includes only explicitly foot-accessible bridleways. On the same private route and unchanged 15-meter matcher radius, local replay increased accepted points to 2,167 and unique credited distance from 1,104.3 to 2,113.2 meters. The device has completed its version-3 Health rebuild, but this result is not yet a reviewed precision/recall fixture; the route must be visually re-reviewed before it can pass.
