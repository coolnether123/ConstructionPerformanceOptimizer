# Construction Performance Optimizer

A focused RimWorld construction performance mod that reduces repeated active-frame
validation and avoids one global work search in the zero-cost terrain pipeline.

Version: **1.1.0**

Dependencies: **Harmony**

## Scope

Vanilla performs two separate jobs:

1. `PlaceNoCostFrame`
2. return to global work selection
3. `FinishFrame`

This mod asks the active `ConstructFinishFrames` work giver for the next job when a
newly placed zero-cost terrain frame remains eligible. It preserves the returned job
exactly, including replacement or prerequisite jobs supplied by another mod.

Where RimWorld 1.6 has a repeated `CanConstruct` fail condition, the mod can
distribute that check across a deterministic 15-tick cadence for every active
`FinishFrame` job. It enables this broad optimization only when the exact generated
validation method has no foreign Harmony owner. Downstream patches remain in the
normal call chain, and exact IL call-site checks fail closed if another transpiler
changes the expected method shape. A paired, targeted completion guard always runs
the real construction authorization immediately before completion. If either half of
that safety pair cannot install, neither remains active.

Both IL rewrites run through a focused fluent transpiler layer adapted from Better Work
Tab's `Spine.Harmony` framework. It rejects missing or ambiguous call sites, validates
hook stack signatures before mutation, preserves labels and exception-block metadata,
and lints branch targets before Harmony receives the rewritten method.

The package deliberately excludes every non-construction optimization from the earlier all-in-one experiment.

## Current benchmark

The figures below belong to the tagged pre-hardening 1.0.0 DLL with SHA-256
`64E3FED700B75BA4B349867D98E783ED317EF50B434D1EF2E6AB783D5834D212`.
They remain historical performance evidence rather than a claim about the hardened
1.1.0 binary. The separately validated 1.1.0 DLL has SHA-256
`9D4FDA8F3F6EF33AE3D6F181BFDAB0E15D6B1A228C89F48A332E239471AC0EEA`.

On the derived 12,000 Tilled Soil blueprint fixture, the exact committed 1.6 DLL was
tested in nine fresh-process 60-second samples per arm, randomized across three
balanced blocks. Better Work Tab was disabled in every arm:

| Variant | Mean TPS | Median TPS | Range | Sample SD |
|---|---:|---:|---:|---:|
| No construction optimizer | 114.19 | 111.11 | 99.25-137.82 | 13.79 |
| Preserved legacy broad build | 137.48 | 139.00 | 118.95-153.89 | 12.16 |
| Exact adaptive release candidate | 124.18 | 115.31 | 100.22-154.44 | 18.46 |

The adaptive build was **8.75% above baseline by mean and 3.78% by median**.
Its block-mean gains were +7.10%, +18.84%, and +0.11%. It skipped 93.357% of
repeated active-job validation opportunities. The 95% confidence intervals overlap,
so this run shows a positive but not statistically established stress-fixture gain,
not a guarantee for ordinary colonies. The unsafe preserved legacy build measured
faster in this run; it is a comparison artifact, not the release. The complete
protocol, all 27 samples, hashes, uncertainty, controlled foreign-owner test, and
ordinary-material validation are in
`Benchmarks/2026-07-15-adaptive-broad/REPORT.md`.

The implementation comparison against current open-source and Workshop-only
optimizers is documented in `Comparisons/OverlapAnalysis.md`. No surveyed mod
patches the same three construction targets; turret and general component lookup
optimizations from the earlier broad package have substantial alternatives.

## Multiplayer

RimWorld 1.6 Multiplayer is supported. CPO uses the official Multiplayer API for
detection and makes its cadence decisions from synchronized game ticks and stable pawn
IDs. It does not send independent UI commands or maintain peer-local gameplay state.

Release validation used Multiplayer's normal save-host path with two rendered RimWorld
instances, 75 active mods, three maps, and more than 11,000 construction blueprints.
Three CPO-enabled runs returned both peers to identical world/map clocks after active
construction and reported no desync. The final run used the exact 1.1.0 release DLL,
advanced 1,801 synchronized ticks, and completed 23 constructions. A CPO-free control
also passed. All players still need the same CPO version and mod list, as with any
deterministic gameplay patch.

## Installation

1. Install Harmony.
2. Extract the `ConstructionPerformanceOptimizer` folder into RimWorld's `Mods`
   folder, or subscribe through Steam Workshop after publication.
3. Load this mod after Harmony and Tilled Soil.
4. Do not enable `Construction Queue Optimizer` at the same time.

The mod has no settings and writes no save data. It is normally safe to add or
remove between sessions, but that is not a universal compatibility guarantee;
always keep a normal save backup when changing a large mod list.

## Compatibility

- RimWorld **1.6 is the supported public release target**.
- Historical builds are produced from their matching `Support/<version>` branches.
  Their rebuilt DLL folders may be copied back to `Dev`, but their source-level API
  adaptations are not carried in the 1.6 development tree. Each support branch also
  carries target-specific metadata and a matching root payload so it can be installed
  directly for that historical version.
- Harmony is required.
- Tilled Soil is supported but is not a required dependency.
- RimWorld 1.6 Multiplayer is supported and ships the official optional API bridge.
- RimWorld 1.5 compiles against the official MultiplayerAPI 0.5 package used by
  Multiplayer's open-source `rw-1.5` branch. The `Support/1.5` payload passed a normal
  two-client construction test with 72 active mods: both peers finished at identical
  world/map tick 14,379 with no desync after 37 completed constructions. A 71-mod
  CPO-free control also finished synchronized with no desync.
- Mods that patch `WorkGiver_ConstructFinishFrames.JobOnThing` remain in the
  continuation decision path. Full replacements still warrant a compatibility test.
- A foreign Harmony owner present on the exact generated validation predicate when
  CPO installs disables the broad cadence and its completion guard. Installation is
  deferred until the current long loading event finishes. The independent zero-cost
  continuation can remain enabled.
- Compile success is not runtime certification. See the compatibility matrix for the
  evidence attached to historical branch payloads.
- The package is explicitly incompatible with the legacy
  `coolnether123.constructionqueueoptimizer` package.

## Build

```powershell
& .\Tools\Build.ps1 -Version 1.5
```

To compile and API-audit the RimWorld 1.5 support source:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\Build-AllVersions.ps1 -Versions 1.5
```

The support cascade merges changes down through existing local `Support/*` branches,
where each branch owns its historical API source. It copies only rebuilt DLL folders
back to `Dev` and never pushes unless `-Push` is explicitly supplied:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\Invoke-SupportCascade.ps1
```

To create the publishable runtime archive:

```powershell
& .\Tools\Release.ps1
```

On `Support/1.5`, the release workflow runs the deterministic tests, builds and
audits the 1.5 DLL, validates metadata and assets, stages matching root and versioned
runtime payloads, creates a Workshop-ready folder under `Releases`, and writes a
SHA-256 sidecar beside the `-rw1.5.zip` archive.

Do not enable this mod together with `coolnether123.constructionqueueoptimizer`; that package contains the same construction patches.
