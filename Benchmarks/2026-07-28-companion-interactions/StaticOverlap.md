# Static CPO companion review

No reviewed companion directly patches CPO's three exact targets:

1. `JobDriver_PlaceNoCostFrame.MakeNewToils`;
2. the generated `FinishFrame` validation predicate;
3. the generated completion action containing `Frame.CompleteConstruction`.

That means every CPO-on arm is expected to report direct continuation, broad
validation throttle, and completion guard all enabled. The trial is rejected if
the startup diagnostic says otherwise.

| Companion | Adjacent interaction | Required control |
|---|---|---|
| Achtung! | High. Forced construction calls `WorkGiver_ConstructFinishFrames` and patches job transitions, construction toil failures, blueprint replacement, `Frame.FailConstruction`, and `GenConstruct.BlocksConstruction`. | Normal 2x2 experiment plus a separate forced-construction functional run. |
| Better Pawn Control | Low. Applying a policy changes priorities, schedules, and areas; its policy application is not a continuous construction hot path. | Apply and freeze one policy before timing. Never switch during a sample. |
| Performance Optimizer | High. Default 1.6 optimizations cache `Frame.WorkToBuild` and forbidden checks used by active construction jobs. | Default profile plus a focused rerun with those two caches disabled. |
| Yet another Optimizer | High. It changes construction resource-delivery work and can parallelize normal work-giver scans. | Default profile plus a focused rerun with parallel work-giver scanning disabled. |
| Performance Fish 1.6 | Medium. Its active `GenClosest.ClosestThingReachable` prepatch can change construction rediscovery cost. The apparent `JobGiver_Work` patch is block-commented. | Fresh prepatched processes with pinned Prepatcher and localavaster's 1.6 Fishery fork. |
| MissileGirl | Medium. Its `StatWorker.GetValue` cache affects construction speed and success-chance lookups. | Warm for at least 600 session ticks, then reload the frozen fixture before timing. |
| Turret Performance Tweaks | None mechanistically. | Background-load negative control. |
| Hard RimWorld Optimization | None mechanistically. | Background-load negative control. |
| RocketMan | Not testable. Available source and runtime support RimWorld 1.2 only. | Exclude until a hash-pinned 1.6 runtime exists. |

Achtung and Better Pawn Control also require one combined functional smoke test
after their individual causal experiments. All performance estimates remain
individual; an all-optimizer stack would destroy attribution.
