# Decision: Route History, Not Street Completion

**Status:** Accepted on August 29, 2026

Walk It All is a private lifetime map of recorded outdoor routes, not a verified street-completion system.

The earlier design required a bundled OpenStreetMap pedestrian graph, city-specific filtering, map matching, completion denominators, manual accuracy fixtures, and licensing UI. That machinery increased maintenance and could still credit the wrong parallel street. The product had already shown personal value by simply revealing Health routes—including park paths—without claiming proof that a street was walked.

The active design therefore keeps native SwiftUI, MapKit, HealthKit, protected local persistence, and an explicit temporary Live Trail. Walking, hiking, running, and cycling routes saved to Apple Health form one indigo lifetime layer. Live Trail remains one independently controlled green path and never reconciles with Health. Apple Maps remains the basemap because replacing it has no demonstrated user benefit and would add an SDK, credentials, billing administration, attribution, and privacy surface.

Street matching, city percentages, route suggestions, passive tracking, accounts, analytics, and a backend remain out of scope unless personal use and a small tester group establish a concrete need that the simpler product cannot meet.
