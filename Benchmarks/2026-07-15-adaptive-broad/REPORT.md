# Adaptive broad construction benchmark

Date: 2026-07-15

## Result

| Variant | TPS samples | Mean | Median | Sample SD | Range | Median vs. baseline |
|---|---|---:|---:|---:|---:|---:|
| Baseline, no construction optimizer | 98.87, 101.43, 119.20 | 106.50 | 101.43 | 11.07 | 98.87-119.20 | - |
| Preserved legacy broad build | 119.25, 127.71, 126.87 | 124.61 | 126.87 | 4.66 | 119.25-127.71 | +25.08% |
| Current adaptive broad build | 132.83, 132.25, 125.77 | 130.28 | 132.25 | 3.92 | 125.77-132.83 | +30.39% |

The current build measured 4.24% above the preserved legacy median. During its
three runs, the deterministic 15-tick cadence executed the expensive validation on
6.7% of opportunities and skipped 93.3%. The final completion guard remained enabled
and continued to call the real, patched `GenConstruct.CanConstruct` path.

These results support retaining broad validation when the exact hook is clean. They
do not support claiming a 30% gain for a normal colony; this fixture deliberately
creates an extreme construction queue.

## Fixture

- Save: `SGTLMathews Story Colony - SP 12000 Tilled Soil Stress 1.6.4871.rws`
- SHA-256: `6B96E02F9037204BD9E7B65B87127698F93F6922A2BEE111B1144C0CCF1CE1ED`
- Exact `Blueprint_GT_SoilTilled` count at rest: 12,000
- The fixture was derived from the frozen single-player performance save through the
  RimWorld Agent command `construction-fixture build`; it uses vanilla blueprint
  placement validation and was saved under a new name. The source save was unchanged.

## Protocol

1. Start a fresh RimWorld process for every sample.
2. Load the same paused fixture and full historical mod profile.
3. Explicitly remove Better Work Tab, Construction Queue Optimizer, and both optimizer
   variants before adding the selected arm.
4. Keep Dubs Performance Analyzer and RimWorld Agent enabled in every arm.
5. Start the construction probe, switch to ultrafast, run for 30 seconds, pause, and
   record simulated ticks and construction call counts.
6. Close the benchmark-owned process, restore the exact pre-run `ModsConfig.xml`, and
   repeat from the unchanged save.

TPS is `constructionProbe.ticks / probe.activeWallSeconds`. Median and sample standard
deviation are reported because late-game scheduling noise was visible. One earlier
baseline capture lasting only 6.695 active seconds was excluded before comparison;
its truncated window violated the 30-second protocol.

## Runtime identity

- Source base commit: `da0028eab7de87f806a3851ec2f86c4cb1236935` plus the
  documented adaptive working-tree revision.
- Benchmarked current 1.6 DLL SHA-256:
  `5EFBC9D97B649D40370C3305782E25EE1CB710206149697EA9C5BB7C04B59099`
- Final rebuilt 1.6 DLL SHA-256 after documentation metadata and dual-target
  rollback hardening (the successful fast path is unchanged):
  `9B8AC4B8FED1D662179C94FE12454BD8FEA5775CEC1E6FA4219DCF55F5FF8AFA`
- Preserved legacy DLL SHA-256:
  `E0F349CC8C607F725E3A0F136B16E23A7D4F432D2D30E391DF81B4426E03A7C6`
- Raw baseline captures: `Results/20260715-171155-baseline` run 1 and
  `Results/20260715-171604-baseline` runs 1-2.
- Raw legacy captures: `Results/20260715-172013-legacy-broad`.
- Raw adaptive captures: `Results/20260715-172605-current-adaptive`.
- Final rebuilt DLL smoke capture: `Results/20260715-174143-current-adaptive`.

## Compatibility evidence

The exact generated validation predicate had no foreign owner in the tested profile,
so the broad pair enabled. Startup diagnostics recorded downstream patches from VEF,
QualityBuilder, and Replace Stuff. Those dependencies remained in the methods called
by the wrappers, and all three adaptive runs completed with the same feature report.

No Construction Pipeline Optimizer exceptions or desync indicators appeared. Every
variant logged the same pre-existing MPCompat/QualityBuilder null reference and
InputLegacy reflection-only dependency error, so those are not attributed to this
mod. This was a one-process single-player-derived stress benchmark, not a two-client
Multiplayer desync test.

After the failure-path rollback hardening and final rebuild, a separate 10-second
runtime smoke loaded the same fixture, advanced 1,339 ticks, executed 482 of 7,224
validation opportunities (6.7%), reported all three features enabled, and produced
no optimizer/desync error indicator. It is activation evidence only and is excluded
from the three-run statistics above.

## Build verification

The deterministic policy suite passed. The build and API audit compiled all 15
targets from Alpha 4, 0.13-0.19, and 1.0-1.6 with zero compiler warnings. Static IL
was verified where real assemblies are present; 1.0-1.5 remain compile-surface only
and all non-1.6 versions remain runtime-unverified for this revision.
