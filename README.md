# Construction Pipeline Optimizer

A focused RimWorld construction performance mod that reduces repeated active-frame
validation and avoids one global work search in the zero-cost terrain pipeline.

Version: **1.0.0**

Dependencies: **Harmony**

## Scope

Vanilla performs two separate jobs:

1. `PlaceNoCostFrame`
2. return to global work selection
3. `FinishFrame`

This mod asks the active `ConstructFinishFrames` work giver for the next job when a
newly placed zero-cost terrain frame remains eligible. It preserves the returned job
exactly, including replacement or prerequisite jobs supplied by another mod.

Where vanilla has a repeated `CanConstruct` fail condition (0.18+), the mod can
distribute that check across a deterministic 15-tick cadence for every active
`FinishFrame` job. It enables this broad optimization only when the exact generated
validation method has no foreign Harmony owner. Downstream patches remain in the
normal call chain, and exact IL call-site checks fail closed if another transpiler
changes the expected method shape. A paired, targeted completion guard always runs
the real construction authorization immediately before completion. If either half of
that safety pair cannot install, neither remains active.

The package deliberately excludes every non-construction optimization from the earlier all-in-one experiment.

## Current benchmark

On the derived 12,000 Tilled Soil blueprint fixture, three fresh-process 30-second
runs produced these median simulation rates with the same full mod profile and
Better Work Tab disabled:

| Variant | Median TPS | Range | Sample standard deviation |
|---|---:|---:|---:|
| No construction optimizer | 101.43 | 98.87-119.20 | 11.07 |
| Preserved legacy broad build | 126.87 | 119.25-127.71 | 4.66 |
| Current adaptive build | 132.25 | 125.77-132.83 | 3.92 |

The current build was **30.39% above the baseline median** and skipped 93.3% of
the repeated active-job validation opportunities. This is a workload-specific
stress result, not a guarantee for ordinary colonies. The complete protocol, raw
captures, save hash, exclusions, and known unrelated log errors are in
`Benchmarks/2026-07-15-adaptive-broad/REPORT.md`.

The implementation comparison against current open-source and Workshop-only
optimizers is documented in `Comparisons/OverlapAnalysis.md`. No surveyed mod
patches the same three construction targets; turret and general component lookup
optimizations from the earlier broad package have substantial alternatives.

## Multiplayer

The cadence uses only `TicksGame` and pawn IDs, and the mod stores no save data.
Multiplayer compatibility is expected from that deterministic design but has not
been verified in a two-client session. It is therefore **not currently claimed as
supported**. Anyone testing it must use the identical DLL and load order on every
peer and report any desync.

## Installation

1. Install Harmony.
2. Extract the `ConstructionPipelineOptimizer` folder into RimWorld's `Mods`
   folder, or subscribe through Steam Workshop after publication.
3. Load this mod after Harmony and Tilled Soil.
4. Do not enable `Construction Queue Optimizer` at the same time.

The mod has no settings and writes no save data. It is normally safe to add or
remove between sessions, but that is not a universal compatibility guarantee;
always keep a normal save backup when changing a large mod list.

## Compatibility

- RimWorld **1.6 is the supported public release target**.
- RimWorld 1.0-1.5 builds are compile-surface experiments, not public support.
- Alpha 4-0.19 static/compile fixtures remain separate legacy engineering artifacts,
  not equally certified downloads.
- Harmony is required.
- Tilled Soil is supported but is not a required dependency.
- Multiplayer is unverified; matching versions and load order are requirements for
  testing, not evidence of support.
- Mods that patch `WorkGiver_ConstructFinishFrames.JobOnThing` remain in the
  continuation decision path. Full replacements still warrant a compatibility test.
- A foreign Harmony owner present on the exact generated validation predicate when
  CPO installs disables the broad cadence and its completion guard. Installation is
  deferred until the current long loading event finishes. The independent zero-cost
  continuation can remain enabled.
- Compile success is not runtime certification. Alpha 4, 0.13-0.19, and the installed
  1.6 assembly have static IL evidence; 1.0-1.5 are compile-surface verified only.
- The package is explicitly incompatible with the legacy
  `coolnether123.constructionqueueoptimizer` package.

## Build

```powershell
& .\Tools\Build.ps1 -Configuration Release
```

To compile and API-audit every locally available RimWorld API:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\Build-AllVersions.ps1
```

The support cascade uses local `Dev` and `Support/*` branches and never pushes
unless `-Push` is explicitly supplied:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\Invoke-SupportCascade.ps1 -InitializeMissingBranches
```

To create the publishable runtime archive:

```powershell
& .\Tools\Release.ps1
```

The release workflow runs the deterministic tests, builds the 1.6 DLL, validates
metadata and assets, stages only runtime files, creates a Workshop-ready folder
and ZIP under `Releases`, and writes a SHA-256 sidecar.

Do not enable this mod together with `coolnether123.constructionqueueoptimizer`; that package contains the same construction patches.
