# Product direction and release gates

## Product promise

Walk It All answers one question calmly and accurately: which eligible parts of a city have I covered on foot, and what remains? The personal MVP is intentionally a single map rather than a dashboard, social network, streak system, or route-planning product.

## Scope now

- Manhattan Island, using walking and hiking routes already present in Apple Health
- Private and local-first, with no account, backend, analytics, advertising, subscription, or live location tracking
- Foreground historical import and refresh, explainable conservative matching, workout inspection, and local rebuilds
- Apple Maps for context and a reproducible OpenStreetMap-derived completion network

This architecture has effectively no recurring service cost. Personal Team signing is suitable for direct use; TestFlight or App Store distribution requires the Apple Developer Program.

## Quality gates for a personal-device signoff

- Build, unit tests, UI tests, privacy manifest, entitlement, backup exclusion, and store recovery pass
- Import can be interrupted, resumed, rebuilt, and reconciled with deleted workouts
- Map pan and zoom stay smooth with the full Manhattan network
- A physical iPhone confirms Health authorization, locked-device file protection, and a complete historical import
- At least ten representative routes are manually compared with their Apple Fitness maps and meet the methodology accuracy targets

The final two checks require the owner’s Health history and cannot be substituted with Simulator data.

## Public-release gate

After personal accuracy validation, invite 5–10 testers before expanding city coverage. Before App Store submission:

- Clear the product name and trademark; reserve the App Store name
- Publish a privacy policy and verify App Privacy answers with a release-build network audit
- Run accessibility checks on supported devices and sizes
- Reproduce every bundled city map from pinned sources and retain attribution
- Add a support route and clear language about incomplete, missing, or permission-limited Health history
- Decide pricing only after retention and demand are understood; prefer a one-time purchase or lifetime city unlock over a subscription

## Deliberately deferred

Additional cities, watchOS recording, manual corrections, suggested routes, sharing, badges, social features, and background processing remain outside the MVP. Each should be added only when it strengthens lifetime city completion without compromising privacy or making the core map harder to understand.
