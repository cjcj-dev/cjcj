# G12 recording schema 2

R1 and R4 are recording gates, with no performance thresholds. Schema 1 history
must not be joined to schema 2: the old four pillars have no one-to-one mapping
and the old collection STW summary is not a single top-level pause.

R1 covers archived minor (`gc_tag=y`) top-level phases in ZGC
`zGeneration.cpp:538-580`. Eight phases are required; Concurrent Mark Continue is
optional and Pause Mark End may repeat. All observed retries contribute to the
sum. Shares divide phase nanoseconds by the sum of selected top-level phase
nanoseconds, not collection wall time or CPU time. Individual zero durations are
valid; the total must be positive. An absent optional phase has count 0, status
`not_observed`, and null duration/share. Coverage is archive-wide, not per cycle:
the inherited v5 phase parser exposes no generation-instance lifecycle.

Only the expected pause/conc kind can satisfy each minor phase. Major young (Y,
including both preclean and major-root starts) and old (O) are excluded; nested
subphase and critical timers do not enter the denominator. Major coverage is not
an admission requirement and is not reported as measured zero when absent.

R4 reports the sample count, median and maximum of the same minor top-level pause
records, converting ns to us once. It is not total STW: VM coordination and
untimed Verify work are outside these timers (ZGC `zStat.cpp:766-826`,
`zGeneration.cpp:1155`). New historical baselines require fresh data, not a
numerical conversion of old measurements. F1-F6 and R2/R3 are unchanged.

Tests run the actual release-gates CLI. Synthetic archives exercise classification,
missing coverage, retry aggregation and unit conversion; G12_RUNTIME_LOG supplies
an archived runtime stderr for recording-only compatibility. Its other gate
inputs are fixtures, so that test does not establish runtime or release fitness.
