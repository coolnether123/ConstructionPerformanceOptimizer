# Optimization overlap analysis

## Conclusion

The construction-only split is justified. None of the surveyed RimWorld 1.6
optimizers patches any of Construction Pipeline Optimizer's three targets:

1. `JobDriver_PlaceNoCostFrame.MakeNewToils`
2. the `JobDriver_ConstructFinishFrame.MakeNewToils` defensive
   `CanConstruct` fail-condition lambda
3. the generated `FinishFrame` completion action containing the exact
   `Frame.CompleteConstruction` call

Yet another Optimizer touches adjacent construction work selection, but it does
not continue a zero-cost placement job into `FinishFrame`, distribute the active
finish job's validation, or add the final completion authorization used here.

The old all-in-one package's non-construction work is a mixed case: turret
throttling and general component lookup are already addressed more broadly by
other mods, while the dissolution and empty-health fast paths were not found in
the surveyed implementations. Those remaining exact fast paths are measurable,
but much smaller and less distinctive than the construction path.

## Exact target matrix

| Optimizer | Place no-cost frame continuation | Active finish validation cadence | Completion authorization | Adjacent construction work |
|---|---:|---:|---:|---|
| Construction Pipeline Optimizer | Yes | Yes | Yes | Deliberately excluded |
| Performance Optimizer 1.6 | No | No | No | No current 1.6 construction patch found |
| Yet another Optimizer | No | No | No | Removes redundant touch checks from resource-delivery work givers; optionally parallelizes work-giver scans |
| Performance Fish 1.6 port | No | No | No | No matching construction patch found |
| MissileGirl | No | No | No | No matching construction patch found |
| Turret Performance Tweaks | No | No | No | Turrets only |
| Hard RimWorld Optimization | No | No | No | Wildlife, turrets, prisoners, quests, and plants |

The repository search included type and method names as well as construction
keywords. Adjacent code was then read manually to avoid treating a name-only
search as proof of behavioral difference.

## What overlaps with the retired broad package

| Retired broad optimization | Closest existing implementation | Assessment |
|---|---|---|
| Change autonomous turret scan cadence from 15 to 30 ticks | Turret Performance Tweaks and Hard RimWorld Optimization both patch `Building_TurretGun` target acquisition. They suppress scans without danger, reuse valid targets, and use longer scan throttles. | Strong overlap. The focused mod should not include the old turret patch. Stacking the old interval change adds another throttle and complicates combat-response reasoning. |
| Skip an unnecessary `CompPowerTrader` lookup in `CompRefuelable.CompTick` | YaOpt with Prepatcher and Performance Fish 1.6 replace general `ThingWithComps.GetComp` lookup with cached type lookup. | Partial overlap. The old patch can still avoid even the cached lookup on irrelevant configurations, but the marginal benefit is much less distinctive once either general cache is installed. |
| Reuse repeated `CompBandNode.PowerTrader` lookup within one tick | YaOpt and Performance Fish make the underlying `GetComp` lookup cheap globally. | Partial overlap. Local reuse remains semantically distinct but becomes a micro-optimization on top of a general cache. |
| Reuse repeated `CompOverseerSubject.Overseer` lookup within `State` | Performance Optimizer caches `CompOverseerSubject.CanGoFeral` for 30 ticks, not `State` itself. | Partial behavioral overlap at some callers, not an exact method overlap. The old local reuse remains distinct. |
| Skip empty `Pawn_HealthTracker.HealthTick` loops | Performance Fish contains a similarly named experiment, but it is compiled out with `#if false` in both inspected upstream and 1.6-port source. | No active equivalent found in the surveyed set. |
| Reuse `CompDissolution.IsOutdoors` for its later rain check | No matching dissolution implementation was found. | No equivalent found in the surveyed set. |

## Relative value on the measured colony

The exact committed adaptive 1.6 DLL was remeasured on a derived save with exactly
12,000 Tilled Soil blueprints using nine fresh-process 60-second samples per arm in
three randomized blocks. Adaptive produced 124.18 mean / 115.31 median TPS versus
baseline 114.19 mean / 111.11 median TPS: +8.75% by mean and +3.78% by median.
The cadence skipped 93.357% of repeated validation opportunities. Adaptive block-mean
gains were +7.10%, +18.84%, and +0.11%; the pooled confidence intervals overlap, so
the positive result is not statistically established. The preserved unsafe legacy
build measured faster than adaptive in this run. A separate smaller frozen-colony
test produced a 7.1% median gain. These are workload-specific observations, not
universal claims.

The exact object-scale pass from the broad package saved about 0.113 ms per
simulated tick in total across refuelable, dissolution, and empty-health paths on
the 21,944-object fixture. The mechanitor lookup reuse patches reduced their
individual profiled methods by 4.6% and 2.4%, but did not establish a whole-run
TPS gain. Turret cadence reduced the turret category by 4.4%.

These measurements support positioning construction as the product rather than
publishing another broad optimizer: it is the largest demonstrated effect, has
the clearest workload identity, and has no exact implementation overlap in the
survey.

## Compatibility implications

- Do not load Construction Pipeline Optimizer with the legacy Construction Queue
  Optimizer; both patch the same construction methods.
- YaOpt's adjacent resource-delivery optimization does not patch the same
  methods, but its parallel work-giver mode is disabled in Multiplayer and its
  Smarter Construction compatibility code confirms that construction work-giver
  replacement is an active compatibility surface.
- Smarter Construction and any mod that replaces
  `WorkGiver_ConstructFinishFrames.JobOnThing` still need a dedicated play test. The
  direct continuation now calls the active work giver and preserves its exact returned
  job, so approval, rejection, different targets, and prerequisite jobs remain in the
  decision path.
- A foreign Harmony owner directly on the generated validation predicate disables the
  broad cadence and completion guard. Downstream patched methods remain composed and
  are listed in the startup diagnostic.
- All Multiplayer peers need the same DLL, load order, and settings. The focused
  mod uses no wall-clock time, random values, background threads, or save data.

## Recommended package architecture

Make Construction Pipeline Optimizer the only authoritative home of the three
construction patches. Do not maintain a second copy in the legacy broad package:
either retire that package or remove its construction classes and turn it into a
separate optional micro-optimization pack. This prevents source drift and avoids
two Harmony owners for one behavior.
