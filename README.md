# Construction Pipeline Optimizer

A focused RimWorld construction performance mod for the zero-cost pipeline used by Tilled Soil and similar terrain.

Version: **1.0.0**

Dependencies: **Harmony**

## Scope

Vanilla performs two separate jobs:

1. `PlaceNoCostFrame`
2. return to global work selection
3. `FinishFrame`

This mod asks the active `ConstructFinishFrames` work giver to continue into its approved job when a newly placed zero-cost terrain frame remains eligible. Other mods that patch `JobOnThing` therefore remain in the decision path. Where vanilla has a repeated `CanConstruct` fail condition (0.18+), only zero-cost terrain checks use a deterministic distributed cadence. A targeted completion-call guard still validates every final construction attempt.

The package deliberately excludes every non-construction optimization from the earlier all-in-one experiment.

The implementation comparison against current open-source and Workshop-only
optimizers is documented in `Comparisons/OverlapAnalysis.md`. No surveyed mod
patches the same three construction targets; turret and general component lookup
optimizations from the earlier broad package have substantial alternatives.

## Multiplayer

The cadence uses only `TicksGame` and pawn IDs. Every peer must use the identical DLL and load order. The mod stores no save data.

The legacy package completed a one-process Multiplayer host smoke using these
same construction patches. A two-client desync run is still recommended before
marking Multiplayer support as fully verified.

## Installation

1. Install Harmony.
2. Extract the `ConstructionPipelineOptimizer` folder into RimWorld's `Mods`
   folder, or subscribe through Steam Workshop after publication.
3. Load this mod after Harmony and Tilled Soil.
4. Do not enable `Construction Queue Optimizer` at the same time.

The mod has no settings and writes no save data. It can be added to or removed
from an existing save, but always keep a normal save backup when changing a
large mod list.

## Compatibility

- RimWorld 1.0–1.6 multi-version package.
- Alpha 4–0.19 are built through dedicated support branches because those games require legacy root payload/metadata layouts.
- Harmony is required.
- Tilled Soil is supported but is not a required dependency.
- Multiplayer peers must use the same mod version, settings, and load order.
- Mods that patch `WorkGiver_ConstructFinishFrames.JobOnThing` remain in the
  continuation decision path. Full replacements still warrant a compatibility test.
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

The release workflow runs the deterministic tests, builds the DLL, validates
metadata and assets, stages only runtime files, creates a Workshop-ready folder
and ZIP under `Releases`, and writes a SHA-256 sidecar.

Do not enable this mod together with `coolnether123.constructionqueueoptimizer`; that package contains the same construction patches.
