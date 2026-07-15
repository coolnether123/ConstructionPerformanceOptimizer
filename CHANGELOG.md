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

- On a derived 12,000 Tilled Soil blueprint save, three fresh-process 30-second
  samples measured 132.25 median TPS for the adaptive build versus 101.43 without a
  construction optimizer (+30.39%) and 126.87 for the preserved legacy broad build.
- The adaptive cadence skipped 93.3% of repeated validation opportunities. Results
  are specific to this extreme construction workload and do not establish two-client
  Multiplayer synchronization.

### Verified

- Deterministic policy tests on .NET 8.
- RimWorld 1.6 / .NET Framework 4.7.2 release build.
- Exact generated-method resolution against the installed RimWorld 1.6 assembly.
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
