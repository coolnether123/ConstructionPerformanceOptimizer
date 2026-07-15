# Architecture

## Boundary

The mod owns only the transition and validation path for zero-cost terrain construction:

```text
PlaceNoCostFrame -> validate completed frame -> FinishFrame
```

It does not patch general work selection, ordinary material-bearing frames, turret targeting, component ticks, pawn health, rendering, or Multiplayer networking.

## Safety invariants

- Continuation applies only to a `Frame` whose build target is a `TerrainDef` with no cost list.
- Continuation asks the registered `ConstructFinishFrames` work giver for the actual next job; patched or replacement work-giver logic participates normally.
- On RimWorld 0.18+, only eligible zero-cost terrain finish jobs distribute defensive validation every 15 ticks by pawn ID. Ordinary frames remain fully vanilla.
- A targeted transpiler guards the exact `CompleteConstruction` call inside the finish-job tick action. Invalid completion returns from that tick without calling `ReadyForNextToil`, so vanilla later marks the job incompletable.
- Modded and direct frame-completion paths are left unchanged.

## Compatibility boundary

Direct continuation calls `WorkGiver_ConstructFinishFrames.JobOnThing` through the active `WorkGiverDef.Worker`. A mod can reject or replace the job without being bypassed.

Compiler-generated finish-frame methods are resolved by their exact IL calls to `CanConstruct` and `CompleteConstruction`. Zero or multiple matches disable the affected feature instead of guessing. The completion guard installs before the cadence; the cadence is never installed without its safety dependency.

## Single-use helper review

`ZeroCostTerrainEligibility.IsEligibleFrame` now has two production callers:
the continuation and the cadence wrapper. It remains the shared policy seam.

`CreateContinuationToil` also has one caller. It remains separate because the
iterator that appends the toil and the closure that initializes and starts the
next job have different responsibilities. Inlining it would make the Harmony
postfix harder to audit without reducing runtime work.

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
