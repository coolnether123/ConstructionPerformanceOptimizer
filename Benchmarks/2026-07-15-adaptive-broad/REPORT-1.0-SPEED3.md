# CPO 1.0 speed-3 runtime metrics

Date: 2026-07-18

## Result

The hardened CPO 1.0 DLL was measured in nine fresh RimWorld processes for
60 seconds each on the 12,000-blueprint Tilled Soil stress save at normal player
speed 3 (`Superfast`). Better Work Tab was disabled. Each run used an isolated
game-data folder and the harness required CPO
to own the active validation patch before accepting the sample.

| Metric | Mean | Median | Sample SD | 95% CI for mean | Range |
|---|---:|---:|---:|---:|---:|
| Rendered FPS | 18.965 | 17.073 | 4.958 | 15.153-22.776 | 16.430-31.854 |
| Simulation TPS | 116.548 | 109.811 | 22.884 | 98.958-134.138 | 89.010-157.836 |
| Frame time | 54.902 ms | 58.574 ms | 9.443 ms | 47.644-62.161 ms | 31.393-60.865 ms |
| Wall time per simulation tick | 8.848 ms | 9.107 ms | 1.560 ms | 7.649-10.048 ms | 6.336-11.235 ms |
| Process CPU time per simulation tick | 10.765 ms | 10.897 ms | 2.110 ms | 9.143-12.388 ms | 7.622-14.642 ms |
| Process CPU utilization | 121.426% | 121.430% | 4.720% | 117.798-125.054% | 114.533-130.333% |

The process used about 1.21 logical CPU cores on average. Managed-memory growth
averaged 59.42 MiB and had a 69.09 MiB median over a run. Gen 0, Gen 1, and Gen 2
collections each averaged 1.56 per run. The working-set and private-byte delta
counters returned zero in every sample, so they are not used as evidence that the
process allocated no native memory.

Across the nine runs, RimWorld advanced 63,881 simulation ticks, rendered 10,395
frames, and completed 2,249 construction frames. CPO performed 45,762 real
`CanConstruct` validations out of 687,960 observed validation opportunities:
6.652% executed and 93.348% skipped.

## Comparison limits

The preserved no-CPO series used the same RimWorld executable and frozen save. It
recorded TPS but predates the FPS and process-CPU counters, and it requested
`Ultrafast` rather than `Superfast`. Its mean/median TPS were 114.187/111.109 and
its derived mean/median wall times were 8.866/9.000 ms per tick.

Against that historical series, the new CPO series is:

- +2.06% by mean TPS;
- -1.17% by median TPS;
- 0.018 ms/tick lower by mean wall time (0.20% lower); and
- 0.107 ms/tick higher by median wall time (1.19% higher).

These small mixed differences are inside the run-to-run variability and do not
establish a general TPS gain for the hardened DLL.

The user's separately observed no-CPO frame rate was about 17 FPS. Relative to that
reference, this CPO series was +1.965 FPS (+11.56%) by mean but only +0.073 FPS
(+0.43%) by median. The mean is strongly influenced by one 31.854 FPS sample; the
other eight samples averaged 17.354 FPS. Because the old baseline did not record
FPS through the same probe, neither +11.56% nor the remembered +4 FPS should be
published as a controlled A/B result.

## Release-safe claim

CPO demonstrably removes 14 of every 15 repeated active-frame validations when its
compatibility gate enables the cadence. On this extreme construction save, the
hardened release remained throughput-neutral within observed variance while doing
that work reduction. Performance varies by colony, active construction, mod list,
hardware, and whether rendering or simulation is the current bottleneck.

Raw accepted result:
`Results/20260718-133342-current-adaptive`

Exact identities are recorded in that directory's `manifest.txt`.
