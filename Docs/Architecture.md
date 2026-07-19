# Architecture

## Boundary

The mod owns two narrow construction paths:

```text
PlaceNoCostFrame -> validate completed frame -> FinishFrame
active FinishFrame -> distributed defensive validation -> guarded completion
```

It does not patch general work selection, turret targeting, component ticks, pawn
health, rendering, or Multiplayer networking. Ordinary material-bearing frames are
affected only by the active-job validation cadence when its compatibility gate passes.

## Safety invariants

- Continuation applies only to a `Frame` whose build target is a `TerrainDef` with no cost list.
- Continuation asks the registered `ConstructFinishFrames` work giver for the actual next job; patched or replacement work-giver logic participates normally.
- On RimWorld 1.6, active finish jobs distribute their repeated defensive
  validation predicate every 15 ticks from `Find.TickManager.TicksGame` and pawn ID
  only when the exact generated predicate has no foreign Harmony owner. A skipped
  tick returns from the predicate before its vanilla body while leaving Harmony
  prefixes and postfixes in the normal dispatcher chain.
- Multiplayer runs the same patch set inside its deterministic map-tick context.
  CPO registers no peer-local UI sync methods and stores no gameplay state outside
  the synchronized simulation.
- A targeted transpiler guards the exact `CompleteConstruction` call inside the finish-job tick action. Invalid completion returns from that tick without calling `ReadyForNextToil`, so vanilla later marks the job incompletable.
- Both structural rewrites use a focused fluent transpiler layer adapted from Better Work
  Tab's `Spine.Harmony` implementation. The validation recipe requires the one exact
  compiler-generated predicate, its captured `build` toil field, and a boolean cadence
  hook with a validated stack signature. The completion recipe requires one exact call.
  Both clone the input stream, preserve labels and exception blocks, and lint call
  operands and branch targets before returning IL to Harmony.
- Both recipes refuse structural edits in methods with exception handlers. Each boolean
  hook, success branch, and early return is emitted as one strict recipe; any failure
  throws back to the patch installer so the cadence/guard pair is rolled back.
- The cadence and completion guard are one safety-dependent pair. If compatibility
  inspection or either exact call-site patch fails, the pair is disabled or rolled
  back and vanilla validation remains active.
- Modded and direct frame-completion paths are left unchanged.

## Compatibility boundary

Direct continuation calls `WorkGiver_ConstructFinishFrames.JobOnThing` through the active `WorkGiverDef.Worker`. A mod can reject or replace the job without being bypassed.

Continuation passes the current job's
`playerForced` value into `JobOnThing` so the work giver can make the correct approval
decision. If a job is returned, the same value is then assigned to that exact job.
These are separate requirements and both are preserved.

Compiler-generated finish-frame methods are resolved by their exact IL calls to
`CanConstruct` and `CompleteConstruction`. The validation closure must also expose
exactly one captured `Toil` field named `build`. Zero or multiple matches disable the
affected feature instead of guessing. The completion guard installs before the cadence;
the cadence is never installed without its safety dependency.

Compatibility inspection is deliberately asymmetric:

- A foreign owner directly on the exact generated validation predicate disables the
  broad pair because it competes at the replaced call site.
- Patches on `GenConstruct.CanConstruct`, `Frame.CompleteConstruction`, the finish
  driver, or `ConstructFinishFrames.JobOnThing` are observed and logged. They remain
  composed when their corresponding vanilla operation runs; the cadence deliberately
  avoids `CanConstruct` on skipped validation ticks.
- The transpilers independently require exactly one expected vanilla call. If an
  earlier transpiler removes or duplicates it, installation fails closed.

RimWorld 1.6 startup queues installation through
`LongEventHandler.ExecuteWhenFinished`. This lets normal static constructors in the
current loading event register their Harmony patches before inspection. The precise
claim is still time-bounded: a foreign owner **present when CPO installs** disables
the broad pair. A mod that deliberately patches the predicate later at runtime is
outside this startup check and requires dedicated compatibility handling.

## Single-use helper review

`FinishFrameMethodTargets.ValidationBuildField` has one production caller. It remains
separate because resolving the compiler-generated closure field is method-shape policy,
while the patch class owns cadence behavior. If another patch never needs that captured
toil, keep the resolver here rather than duplicating reflection inside the patch.

`FluentTranspiler.PrependInstanceFieldGuardOrReturnFalse` has one production recipe
caller plus direct deterministic test coverage. It remains a fluent operation because it
owns label transfer, exception-region rejection, stack-signature validation, and atomic
early-return emission as one structural IL boundary. Inlining it into the CPO patch would
couple game policy to IL mechanics; the recommended architecture is to keep it as the
tested recipe unless the fluent layer itself is retired.

`ZeroCostTerrainEligibility.IsEligibleFrame` has one production caller after the
validation cadence became adaptive and broad. It remains separate because it defines
the complete policy boundary for bypassing global work selection. If another
zero-cost transition is never added, inlining it is mechanically possible, but keeping
eligibility isolated is safer for review and future construction-policy changes.

`CreateContinuationToil` also has one caller. It remains separate because the
iterator that appends the toil and the closure that initializes and starts the
next job have different responsibilities. Inlining it would make the Harmony
postfix harder to audit without reducing runtime work.

`FluentTranspiler.ValidateOutput` has one caller, `Build`. It remains separate because it
owns whole-stream invariants after every recipe, while call recipes own local match and
stack-shape validation. If a second fluent build profile is added, keep this validator as
the shared final gate; do not duplicate its branch/call checks in individual recipes.

The benchmark fixture command's `PlaceBlueprints` helper and the benchmark runner's
variant-copy helper each currently have one caller. They are retained as explicit
mutation boundaries: one owns save mutation and one owns package projection. If
either tool stays single-purpose, do not split those helpers further; if a second
consumer appears, move the boundary into a shared tested module rather than copying it.

The PowerShell build helpers `Get-ModernAssemblyPath`, `Sync-BranchPayload`, and
`Commit-BranchPayload` each have one orchestration caller. They are intentionally
kept separate because path resolution, filesystem projection, and Git commits
are different side-effect boundaries. If the cascade remains this small, do not
split them further; if a second cascade consumer appears, move them into a
shared build module with direct Pester coverage.

## Version ownership

`Dev` owns only the RimWorld 1.6 source and references. Historical API adaptations
belong to their `Support/<version>` branches. The cascade moves reviewed changes down
that branch chain and copies only rebuilt `*/Assemblies` payloads back to `Dev`; it
never merges historical source upward. Each historical branch also receives
target-specific About/load metadata and a root assembly copied from its target build,
so checking out that branch produces a directly loadable package. The 1.5 branch alone
adds its matching MultiplayerAPI 0.5 bridge; older branches remove that bridge.

## Distribution boundary

The modern release archive contains only `About`, versioned assemblies, `LoadFolders.xml`,
the license, changelog, and user README. Source, tests, comparison research,
symbols, build tools, and intermediate output are excluded. `LoadFolders.xml`
loads the root metadata and the 1.6 runtime folder explicitly. The 1.6 runtime
folder also contains the official `0MultiplayerAPI.dll` fallback so single-player
users do not need to install Multiplayer just to satisfy CPO's optional API reference.
