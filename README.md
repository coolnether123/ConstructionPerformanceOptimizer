# Construction Performance Optimizer

A focused RimWorld performance mod that helps construction-heavy colonies stay
responsive. Large construction backlogs can make the game repeatedly check thousands
of unfinished projects. CPO reduces that unnecessary work so RimWorld can spend more
time advancing the simulation.

The benefit is most noticeable with large building plans, long construction queues,
many builders, higher game speeds, and terrain-building mods such as Tilled Soil. It
does not make pawns build faster or change construction rules.

Version: **1.0**

Dependencies: **Harmony**

## Scope

Vanilla performs two separate jobs:

1. `PlaceNoCostFrame`
2. return to global work selection
3. `FinishFrame`

This mod asks the active `ConstructFinishFrames` work giver for the next job when a
newly placed zero-cost terrain frame remains eligible. It preserves the returned job
exactly, including replacement or prerequisite jobs supplied by another mod.

Where the active RimWorld version has a repeated `CanConstruct` fail condition, the mod can
distribute the full defensive validation predicate across a deterministic 15-tick cadence
for every active `FinishFrame` job. It enables this broad optimization only when the exact
generated validation method has no foreign Harmony owner. Harmony prefixes and postfixes
remain in the normal call chain, while strict method-shape and field checks fail closed if
the game or another transpiler changes the expected structure. A paired, targeted
completion guard always runs the real construction authorization immediately before
completion. If either half of that safety pair cannot install, neither remains active.

Both IL rewrites run through a focused fluent transpiler layer adapted from Better Work
Tab's `Spine.Harmony` framework. It rejects missing or ambiguous call sites, validates
hook stack signatures before mutation, preserves labels and exception-block metadata,
and lints branch targets before Harmony receives the rewritten method.

The package deliberately excludes every non-construction optimization from the earlier all-in-one experiment.

## Performance expectations

Testing with a very large construction backlog confirmed that CPO can improve
simulation throughput and reduce the processing work required for each game tick.
It is not an FPS or pawn construction-speed mod. The actual improvement depends on
your colony, hardware, mod list, and how much unfinished construction is active, so
CPO does not promise a fixed percentage for ordinary colonies.

Raw observations, exact inputs, and the generated analysis are under
`Benchmarks/2026-07-15-adaptive-broad/Randomized-20260718-replicated-clean`.

The implementation comparison against current open-source and Workshop-only
optimizers is documented in `Comparisons/OverlapAnalysis.md`. No surveyed mod
patches the same three construction targets; turret and general component lookup
optimizations from the earlier broad package have substantial alternatives.

## Multiplayer

RimWorld 1.5 and 1.6 Multiplayer are supported. CPO uses the official Multiplayer API for
detection and makes its cadence decisions from synchronized game ticks and stable pawn
IDs. It does not send independent UI commands or maintain peer-local gameplay state.

Release validation used Multiplayer's normal save-host path with two rendered RimWorld
instances, 75 active mods, three maps, and more than 11,000 construction blueprints.
The final adaptive-build run returned both peers to identical world/map clocks after
2,506 synchronized ticks, completed 52 constructions, and reported no desync. Both
peers loaded all three CPO features alongside Vanilla Expanded Framework, QualityBuilder,
and Replace Stuff. Earlier CPO-enabled runs and a CPO-free control also passed. All
players still need the same CPO version and mod list, as with any deterministic
gameplay patch.

## Installation

1. Install Harmony.
2. For RimWorld 1.0-1.6, extract the main `ConstructionPerformanceOptimizer` folder
   into RimWorld's `Mods` folder, or subscribe through Steam Workshop after
   publication. It selects the matching DLL automatically.
3. For Alpha 4-0.19, use the matching ready-to-install folder or ZIP under
   `Legacy`; those games predate safe automatic selection between incompatible
   version assemblies.
4. Load this mod after Harmony and Tilled Soil.

The mod has no settings and writes no save data. It is normally safe to add or
remove between sessions, but that is not a universal compatibility guarantee;
always keep a normal save backup when changing a large mod list.

## Compatibility

- The public release includes every beneficial build from Alpha 4 through RimWorld
  1.6. RimWorld 1.0-1.6 share one automatically routed mod folder; Alpha 4-0.19
  have separate ready-to-install legacy packages because those games cannot safely
  select among incompatible version assemblies.
- All versions receive the zero-cost terrain continuation optimization. RimWorld
  1.1-1.6 also receive the guarded construction-validation cadence. Alpha 4-0.19
  and RimWorld 1.0 deliberately use continuation only for their older Mono runtime.
- Historical builds are produced from their matching `Support/<version>` branches.
  Their rebuilt DLL folders are collected on `Dev`, while their source-level API
  adaptations remain on the owning support branches.
- Harmony is required.
- Tilled Soil is supported but is not a required dependency.
- RimWorld 1.6 Multiplayer is supported and ships the official optional API bridge.
- RimWorld 1.5 compiles against the official MultiplayerAPI 0.5 package used by
  Multiplayer's open-source `rw-1.5` branch. The `Support/1.5` package passed
  single-player construction and normal-hosted two-client Multiplayer tests with
  Better Work Tab and the legacy optimizer excluded.
- Alpha 4 through RimWorld 1.4 are supported for single-player only. Multiplayer
  support is limited to RimWorld 1.5 and 1.6.
- RimWorld 1.0 passed a native quickstart construction stress test with 50 colonists
  and 300 steel-wall blueprints.
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
& .\Tools\Build.ps1 -Configuration Release
```

To compile and API-audit the current RimWorld 1.6 source:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\Build-AllVersions.ps1
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

The release workflow runs the deterministic tests, builds the 1.6 DLL, validates
metadata and assets, stages only runtime files, creates a Workshop-ready folder
and ZIP under `Releases`, and writes a SHA-256 sidecar.

Do not enable this mod together with `coolnether123.constructionqueueoptimizer`; that package contains the same construction patches.
