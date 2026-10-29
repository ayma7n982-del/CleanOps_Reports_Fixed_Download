# Supply Chain Dashboard

Added inside the Action Decision Hub for the existing L2–L4 roles. The three
decision tabs are preserved. The new route reuses the existing scoped live
DecisionHubService; it performs no additional Firestore queries or writes.

- 7/14/30 complete local calendar days, excluding today; optional group filter.
- Line chart: recorded trips and currently completed trips by registration/start day.
- Clustered bars: completed trips in equal current/previous periods.
- Bars: known completed-trip weights in tons, with missing/estimated weight disclosure.
- Pie/donut: current container states, including unknown; explicitly not historical.
- KPI comparison: completion and relative trip-count change. A zero or unavailable
  baseline produces no invented growth percentage. History may begin at the current
  cycle or the existing 30-day fallback; unavailable previous periods are disclosed.
- Missing/cached/capped data retains the existing quality warning. Observed record
  counts must not be interpreted as proof of no field work.
- Animated CustomPainter only, no package or Cloud Function changes.
- Dedicated Arabic PDF uses selected filters; the comprehensive hub PDF includes
  the default seven-day supply analysis. Raster chart geometry at 3x resolution,
  embedded Arabic vector labels and exact-value tables; no scroll screenshots.

Tests cover equal windows, excluding today, scope, unit conversion, missing weights,
zero/incomplete baselines, narrow RTL chart layout, and generation of five PDF types.
