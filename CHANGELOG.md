# Changelog

All notable changes to Construction Pipeline Optimizer are documented here.
The project follows Semantic Versioning.

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
