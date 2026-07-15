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
- On RimWorld 0.18+, active finish jobs distribute their repeated defensive
  validation every 15 ticks by pawn ID only when the exact generated validation
  predicate has no foreign Harmony owner.
- A targeted transpiler guards the exact `CompleteConstruction` call inside the finish-job tick action. Invalid completion returns from that tick without calling `ReadyForNextToil`, so vanilla later marks the job incompletable.
- The cadence and completion guard are one safety-dependent pair. If compatibility
  inspection or either exact call-site patch fails, the pair is disabled or rolled
  back and vanilla validation remains active.
- Modded and direct frame-completion paths are left unchanged.

## Compatibility boundary

Direct continuation calls `WorkGiver_ConstructFinishFrames.JobOnThing` through the active `WorkGiverDef.Worker`. A mod can reject or replace the job without being bypassed.

On versions with the forced overload, continuation passes the current job's
`playerForced` value into `JobOnThing` so the work giver can make the correct approval
decision. If a job is returned, the same value is then assigned to that exact job.
These are separate requirements and both are preserved.

Compiler-generated finish-frame methods are resolved by their exact IL calls to `CanConstruct` and `CompleteConstruction`. Zero or multiple matches disable the affected feature instead of guessing. The completion guard installs before the cadence; the cadence is never installed without its safety dependency.

Compatibility inspection is deliberately asymmetric:

- A foreign owner directly on the exact generated validation predicate disables the
  broad pair because it competes at the replaced call site.
- Patches on `GenConstruct.CanConstruct`, `Frame.CompleteConstruction`, the finish
  driver, or `ConstructFinishFrames.JobOnThing` are observed and logged but remain
  composed because the wrappers still call those patched methods.
- The transpilers independently require exactly one expected vanilla call. If an
  earlier transpiler removes or duplicates it, installation fails closed.

For RimWorld 0.13 and newer, startup queues installation through
`LongEventHandler.ExecuteWhenFinished`. This lets normal static constructors in the
current loading event register their Harmony patches before inspection. The precise
claim is still time-bounded: a foreign owner **present when CPO installs** disables
the broad pair. A mod that deliberately patches the predicate later at runtime is
outside this startup check and requires dedicated compatibility handling.

## Single-use helper review

`ZeroCostTerrainEligibility.IsEligibleFrame` has one production caller after the
validation cadence became adaptive and broad. It remains separate because it defines
the complete policy boundary for bypassing global work selection. If another
zero-cost transition is never added, inlining it is mechanically possible, but keeping
eligibility isolated is safer for review and version-specific cost-list handling.

`CreateContinuationToil` also has one caller. It remains separate because the
iterator that appends the toil and the closure that initializes and starts the
next job have different responsibilities. Inlining it would make the Harmony
postfix harder to audit without reducing runtime work.

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

## Distribution boundary

The modern release archive contains only `About`, versioned assemblies, `LoadFolders.xml`,
the license, changelog, and user README. Source, tests, comparison research,
symbols, build tools, and intermediate output are excluded. `LoadFolders.xml`
loads the root metadata and the 1.6 runtime folder explicitly.
