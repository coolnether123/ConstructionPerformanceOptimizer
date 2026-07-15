# Changelog

All notable changes to Construction Pipeline Optimizer are documented here.
The project follows Semantic Versioning.

## Unreleased

### Changed

- Replaced generated-name lambda selection with exact IL call-site resolution that fails closed on ambiguity.
- Limited validation throttling to eligible zero-cost terrain frames.
- Routed direct continuation through the active construction work giver so other mods can approve, reject, or replace the next job.
- Replaced the broad `Frame.CompleteConstruction` prefix with a targeted finish-job completion guard that cannot report false success.
- Added safety-aware patch installation, deterministic resolver tests, all-version builds, API-shape audits, and a Better Work Tab-style local support cascade.
- Added capability-based builds for Alpha 4 through RimWorld 1.6; 1.0–1.5 remain compile-surface verified until their runtime assemblies are tested.

## 1.0.0 - 2026-07-15

### Changed

- Promoted the tested construction optimization to its first stable release.
- Replaced the preview with a focused construction-queue visual.

### Verified

- Deterministic policy tests on .NET 8.
- RimWorld 1.6 / .NET Framework 4.7.2 release build.
- One-process Multiplayer host smoke inherited from the identical construction
  patch set in the legacy package. A two-client desync test remains pending.

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
