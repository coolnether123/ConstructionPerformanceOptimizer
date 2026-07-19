# Changelog

All notable changes to Construction Performance Optimizer are documented here.
The project follows Semantic Versioning.

## 1.0 - 2026-07-17

### Changed

- Made `Dev` a strict RimWorld 1.6 source tree: removed historical API
  conditionals, references, bootstrap data, and build configurations. Historical
  source remains branch-owned under `Support/<version>`, while only rebuilt DLL
  payload folders cascade back to `Dev`.
- Added the official Multiplayer API and made the validation cadence derive only
  from deterministic game ticks and pawn IDs.
- Verified RimWorld 1.6 Multiplayer through normal save hosting with two rendered
  game instances, 75 active mods, three maps, and over 11,000 construction
  blueprints. Three release-candidate runs completed synchronized construction with
  identical map clocks and no desync; a CPO-free control also passed.
- Added a multi-instance host/client harness with isolated save data, executable and
  agent identities, authoritative Multiplayer simulation-clock barriers, WARP
  isolation for the second renderer, desync detection, exact profile restoration,
  and automatic failure-artifact preservation.
- Prohibited the Agent's runtime Harmony construction probe in two-client runs after
  proving that dynamically repatching the system under test can itself desynchronize
  the session. Multiplayer acceptance uses synchronized before/after fixture counts.
- Replaced both hand-written IL mutation loops with a focused fluent transpiler layer
  adapted from Better Work Tab's `Spine.Harmony` system.
- Added exact single-call selection, pre-mutation stack-signature checks, atomic input
  cloning, label and exception-block preservation, guarded structural-edit policy, and
  whole-stream call/branch linting.
- Added off-game fluent transpiler tests for successful redirects, missing and ambiguous
  targets, unsafe hook signatures, input-stream atomicity, generated completion-guard
  control flow, and exception-handler rejection.
- Rebuilt Alpha 4 through 1.6 on their owning support branches at version 1.0.
  Historical branches now carry target-specific metadata and a matching root payload
  so they are directly installable rather than compile artifacts only.
- Added the official MultiplayerAPI 0.5 bridge to the RimWorld 1.5 branch. Its build
  matches Multiplayer's open-source `rw-1.5` dependency and passed normal-hosted
  two-client construction testing.
- Corrected the RimWorld 1.0 target to .NET 3.5 and excluded the modern fluent
  validation pair that its old Mono runtime cannot load. The independent construction
  continuation remains enabled.

### Verified

- Deterministic policy and fluent-transpiler tests.
- RimWorld 1.6 release build with zero warnings and API-shape audit.
- RimWorld 1.0 native quickstart with 50 colonists and 300 steel-wall blueprints:
  25,512 simulation ticks, 186 new completed walls, 101 active frames, 13 blueprints
  remaining, and no runtime exceptions or errors.
- Isolated 75-mod single-player construction smoke with Better Work Tab and the
  legacy optimizer excluded.
- Three repeatable normal-session Multiplayer construction passes with identical
  host/client simulation clocks and no desync. The final exact-artifact pass advanced
  1,801 synchronized ticks and completed 23 constructions.
- Exact 1.0 DLL SHA-256:
  `9D4FDA8F3F6EF33AE3D6F181BFDAB0E15D6B1A228C89F48A332E239471AC0EEA`.

## 1.0.0 - 2026-07-15

### Changed

- Replaced generated-name lambda selection with exact IL call-site resolution that fails closed on ambiguity.
- Restored broad active-`FinishFrame` validation throttling behind an adaptive
  compatibility gate: a foreign owner on the exact generated predicate disables the
  cadence and completion guard as a pair.
- Routed direct continuation through the active construction work giver so other mods can approve, reject, or replace the next job.
- Preserved the work giver's exact returned job, including a different target or a
  blocking/prerequisite job, while carrying forward `playerForced`.
- Replaced the broad `Frame.CompleteConstruction` prefix with a targeted finish-job completion guard that cannot report false success.
- Corrected the RimWorld 1.5/1.6 five-argument `CanConstruct` runtime target and
  added API-shape assertions for the three-, four-, and five-argument eras.
- Added direct Harmony-owner inspection, composed-dependency diagnostics, and
  rollback so the completion guard cannot remain without the cadence it protects.
- Added safety-aware patch installation, deterministic resolver tests, all-version builds, API-shape audits, and a Better Work Tab-style local support cascade.
- Added capability-based engineering builds for Alpha 4 through RimWorld 1.6;
  only RimWorld 1.6 is advertised as supported for the public package.

### Benchmarked

- The exact committed 1.6 DLL completed nine fresh-process 60-second samples per arm
  in three randomized blocks on the 12,000-blueprint fixture.
- Adaptive measured 124.18 mean / 115.31 median TPS versus baseline 114.19 mean /
  111.11 median TPS: +8.75% by mean and +3.78% by median.
- Adaptive block-mean gains were +7.10%, +18.84%, and +0.11%. The cadence skipped
  93.357% of validation opportunities. Overlapping confidence intervals mean the
  pooled improvement is positive but not statistically established by this run.
- The preserved unsafe legacy build measured faster than adaptive in this run. It
  remains a comparison artifact and is not the release candidate.
- A controlled foreign owner disabled cadence and completion guard together while
  continuation stayed active; ordinary wooden-wall construction completed with the
  pair both enabled and disabled.
- Results are specific to this extreme workload and do not establish two-client
  Multiplayer synchronization.

### Verified

- Deterministic policy tests on .NET 8.
- RimWorld 1.6 / .NET Framework 4.7.2 release build.
- Exact generated-method resolution against the installed RimWorld 1.6 assembly.
- Exact release-candidate DLL SHA-256:
  `64E3FED700B75BA4B349867D98E783ED317EF50B434D1EF2E6AB783D5834D212`.
- Reproducible assembly metadata: rebuilding before or after a Git commit produces
  the same release DLL hash.
- Multiplayer remains unverified until a two-client synchronization test is run.

## 0.1.0 - 2026-07-13

### Added

- Direct continuation from a completed `PlaceNoCostFrame` job into the vanilla
  `FinishFrame` job for eligible zero-cost terrain frames.
- Deterministic 15-tick distribution of the active finish job's repeated
  defensive construction validation.
- Unconditional construction authorization immediately before an active vanilla
  finish job completes its frame.
- Explicit incompatibility metadata for the legacy Construction Queue Optimizer.
- RimWorld 1.6 release metadata, visuals, package validation, and reproducible
  runtime-only archive generation.

### Verified

- Deterministic policy tests on .NET 8.
- RimWorld 1.6 / .NET Framework 4.7.2 release build.
- One-process Multiplayer host smoke inherited from the identical construction
  patch set in the legacy package. A two-client desync test remains pending.
