# RimWorld 1.6 exact-artifact construction benchmark

Date: 2026-07-15

## Release-candidate identity

- Code baseline commit: `4c0f1d5` (`Prepare adaptive 1.6 release candidate`)
- Release evidence also includes reproducible assembly metadata, documentation, and
  packaging changes carried by the final `v1.0.0` tag.
- Exact 1.6 DLL SHA-256:
  `64E3FED700B75BA4B349867D98E783ED317EF50B434D1EF2E6AB783D5834D212`
- Workshop-ready ZIP SHA-256:
  `8F21B996215C05EA9A5759CC8A3BFAE89AB9983270FEFFA4014CAFEE5CF687A1`
- Preserved legacy DLL SHA-256:
  `E0F349CC8C607F725E3A0F136B16E23A7D4F432D2D30E391DF81B4426E03A7C6`
- The runner checked the current DLL hash before every trial. All 27 manifests
  recorded the expected hash.

## Randomized 60-second result

Each arm has nine fresh-process samples, randomized as three balanced blocks. TPS is
`simulated ticks / active wall seconds`.

| Variant | Mean TPS | Median TPS | Sample SD | 95% CI for mean | Range | Mean vs. baseline | Median vs. baseline |
|---|---:|---:|---:|---:|---:|---:|---:|
| Baseline, no construction optimizer | 114.19 | 111.11 | 13.79 | 103.59-124.78 | 99.25-137.82 | - | - |
| Preserved legacy broad build | 137.48 | 139.00 | 12.16 | 128.13-146.83 | 118.95-153.89 | +20.40% | +25.10% |
| Exact adaptive release candidate | 124.18 | 115.31 | 18.46 | 109.99-138.37 | 100.22-154.44 | **+8.75%** | **+3.78%** |

The adaptive build's block-mean gains over baseline were +7.10%, +18.84%, and
+0.11%. The 95% confidence intervals for the pooled per-arm means overlap. The
Welch 95% interval for the adaptive-minus-baseline mean difference is -6.39 to
+26.37 TPS (`t = 1.30`, approximately 14.8 degrees of freedom). The result therefore
supports a positive point estimate on this fixture, but does not statistically
establish a general throughput improvement.

The preserved legacy build measured 9.67% above adaptive by mean and 17.04% by
median. That build bypasses compatibility-preserving work-giver behavior and remains
an unsafe comparison artifact, not a release option. This result does show that the
safer current path has measurable overhead relative to the old aggressive path.

The deterministic cadence executed 49,540 of 745,785 observed validation
opportunities: 6.643% executed and 93.357% skipped, matching the intended one-in-15
schedule. The paired final completion authorization remained enabled.

These percentages are observations from an extreme construction fixture, not a
promise for normal colonies or other computers.

## Block results

| Block | Baseline mean / median | Legacy mean / median | Adaptive mean / median |
|---|---:|---:|---:|
| 1 | 116.40 / 114.66 | 144.40 / 142.25 | 124.67 / 115.31 |
| 2 | 114.61 / 105.41 | 132.17 / 133.41 | 136.20 / 141.50 |
| 3 | 111.55 / 104.33 | 135.88 / 131.92 | 111.67 / 111.44 |

Throughput varied materially by block and arm. Because the arms were shuffled inside
each block, the weak third-block adaptive result remains visible rather than being
hidden by an arm-by-arm execution order.

## Fixed schedule and samples

Seed: `160715`. No trial was discarded, replaced, or rerun based on performance.

| Trial | Block | Variant | TPS |
|---:|---:|---|---:|
| 1 | 1 | Legacy | 139.00 |
| 2 | 1 | Adaptive | 113.38 |
| 3 | 1 | Baseline | 111.11 |
| 4 | 1 | Adaptive | 115.31 |
| 5 | 1 | Legacy | 151.96 |
| 6 | 1 | Adaptive | 145.32 |
| 7 | 1 | Baseline | 114.66 |
| 8 | 1 | Legacy | 142.25 |
| 9 | 1 | Baseline | 123.41 |
| 10 | 2 | Legacy | 118.95 |
| 11 | 2 | Baseline | 105.41 |
| 12 | 2 | Baseline | 100.60 |
| 13 | 2 | Legacy | 133.41 |
| 14 | 2 | Legacy | 144.13 |
| 15 | 2 | Adaptive | 112.67 |
| 16 | 2 | Adaptive | 154.44 |
| 17 | 2 | Baseline | 137.82 |
| 18 | 2 | Adaptive | 141.50 |
| 19 | 3 | Legacy | 131.92 |
| 20 | 3 | Baseline | 131.07 |
| 21 | 3 | Legacy | 121.83 |
| 22 | 3 | Adaptive | 100.22 |
| 23 | 3 | Legacy | 153.89 |
| 24 | 3 | Adaptive | 123.37 |
| 25 | 3 | Adaptive | 111.44 |
| 26 | 3 | Baseline | 99.25 |
| 27 | 3 | Baseline | 104.33 |

## Fixture and protocol

- Save: `SGTLMathews Story Colony - SP 12000 Tilled Soil Stress 1.6.4871.rws`
- Save SHA-256:
  `6B96E02F9037204BD9E7B65B87127698F93F6922A2BEE111B1144C0CCF1CE1ED`
- Exact `Blueprint_GT_SoilTilled` count at rest: 12,000
- Result root: `Randomized-20260715-201635`
- Three blocks; three samples of each arm per block; 27 trials total
- 60-second requested measurement window; observed active windows 60.506-64.901s
- Fresh RimWorld process and unchanged save reload for every trial
- Same historical full mod profile in every arm
- Dubs Performance Analyzer and RimWorld Agent enabled in every arm
- Better Work Tab, Construction Queue Optimizer, and non-selected optimizer variants
  explicitly removed from every arm
- Original `ModsConfig.xml` restored exactly after every trial
- Restored `ModsConfig.xml` SHA-256:
  `75231E50E316F2D55FB8D81ED0E776B3E64E1C78C6D12EC60DD38C271048970C`
- One RimWorld executable hash and one save hash across all manifests

## Controlled compatibility and ordinary-material validation

A benchmark-only mod installed a decision-neutral prefix on the exact generated
validation predicate under owner `benchmark.cpo.foreignvalidationowner` before CPO's
deferred installation.

With the normal adaptive path:

- Startup: continuation on, broad cadence on, completion guard on
- 62,724 validation opportunities; 4,179 actual validations (6.7%)
- 64 ordinary building-frame completion calls
- Wooden walls: 81 blueprints before; 5 blueprints and 16 frames after;
  completed-wall count increased by 60

With the controlled foreign owner:

- Startup: continuation on, broad cadence off, completion guard off
- Owner reported exactly as `benchmark.cpo.foreignvalidationowner`
- 55,801 validation opportunities; all 55,801 actual validations
- 70 ordinary building-frame completion calls
- Wooden walls: 81 blueprints before; 4 blueprints and 10 frames after;
  completed-wall count increased by 67

Both runs used the exact final DLL hash and the same derived material fixture,
completed ordinary construction, and produced no CPO/desync error indicator. This
verifies the enabled path and the controlled fail-closed path in game. It does not
verify every possible foreign
transpiler or a mod that patches deliberately after CPO's installation snapshot.

## Source-level compatibility details

- Installation is deferred through `LongEventHandler.ExecuteWhenFinished`, so owners
  registered by normal startup constructors in the current loading event are visible.
- The exact claim is time-bounded: owners present when CPO installs disable the pair.
- Continuation passes `currentJob.playerForced` into
  `WorkGiver_Scanner.JobOnThing(...)` and assigns the same flag to the returned job.
- The returned job is preserved even when another mod supplies a different target or
  a blocking/prerequisite job.
- VEF, QualityBuilder, and Replace Stuff remained in downstream call paths and were
  listed in every adaptive startup diagnostic.

## Log and build audit

- All 27 randomized logs had the expected startup-owner count.
- No randomized log contained a CPO error/disabled failure, desync indicator, root
  exception, or benchmark-attributed error.
- The controlled enabled/disabled material runs also had no CPO/desync error.
- Deterministic policy tests passed.
- Two consecutive 1.6 builds produced the same DLL hash; assembly informational
  metadata is stable at `1.0.0` rather than embedding a moving Git revision.
- Alpha 4, 0.13-0.19, and 1.0-1.6 API builds compiled with zero CPO warnings.
- Older builds remain engineering evidence only. The public release supports 1.6.
- Multiplayer remains unverified until a real two-client synchronization test is run.
