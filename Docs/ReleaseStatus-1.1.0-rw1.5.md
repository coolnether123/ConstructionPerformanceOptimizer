# Construction Pipeline Optimizer 1.1.0 — RimWorld 1.5 release status

Date: 2026-07-17

## Release decision

**Approved as an independently packageable, runtime-verified RimWorld 1.5 release
candidate with verified two-client Multiplayer support.**

The local release candidate is committed, rebuilt, staged, and validated. It has
not been published. Alpha 4 through RimWorld 1.4 remain experimental,
build/API-verified targets only. The RimWorld 1.5 package remains separate from
the public RimWorld 1.6 archive.

## Final commits

- CPO 1.5 implementation and release tooling:
  `006da477f79af5ba65b9c982f4673b70a57240c7`
- CPO final acceptance/package documentation source:
  `e2ac386e153a1bb043e9a9b460c50e0f0c1d7dc5`
- CPO player-facing About metadata:
  `58875d1071437e08fbe70a3a633386cec11a6787`
- RimWorld-Agent 1.5 multiplayer/fixture tooling:
  `ed04b90b938e9d02312e3425e48824925af7b0d1`

This release-status file is a later documentation-only record under `Docs`, which
is intentionally excluded from the runtime archive.

## Final artifacts

- Archive:
  `ConstructionPipelineOptimizer-1.1.0-rw1.5.zip`
- Archive SHA-256:
  `F860CCDEF295161EA921F4BA924BFC458937C10A2561CB6328043514E087E9AF`
- CPO root/versioned DLL SHA-256:
  `5173F7CB342F0C75218060B0DCE3172B6C091775AF6387D1D9029E964A0F69E7`
- MultiplayerAPI 0.5 DLL SHA-256:
  `4689E799C50DB79411B00AD8855D7DF86721BF3CFE1E390B68038B6ABCD852EC`

The root and `1.5/Assemblies` CPO DLLs are byte-identical. The release archive
checksum matches its `.sha256` sidecar.

## Exact committed-artifact Multiplayer acceptance

- Raw report: `CPO-MultiplayerSmoke-20260717-173422.txt`
- Raw report SHA-256:
  `E6CCEB0508045F115FACA2F9EE05AAAC98C3515A6D6BB834F9C822A4908C74C2`
- RimWorld: `1.5.4409 rev1120`
- Multiplayer: `0.10.7`
- MultiplayerAPI: `0.5`
- Normal hosted save with two separately rendered processes.
- 72 active mods, including Multiplayer, Multiplayer Compatibility, Tilled Soil,
  and CPO.
- Better Work Tab and Construction Queue Optimizer were excluded.
- Both peers reached `ClientPlaying` and loaded the same map.
- Initial synchronized paused barrier: world/map tick `23`.
- Final synchronized paused barrier: world/map tick `14,379`.
- Synchronized advancement: `14,356` ticks.
- Construction fixture: 100 remaining before, 63 frames after, 37 completed.
- CPO continuation, broad validation throttle, and completion guard: enabled.
- Host desync: false.
- Client desync: false.
- Harness desync detection: false.
- Original mod profile restored byte-for-byte.
- Remaining host/client/other RimWorld processes: zero.

The raw report contains the game, Multiplayer/API versions, CPO/API hashes, and
archive name directly, closing the previous evidence-chain gap.

## Control and supporting checks

- A 71-mod CPO-free two-client control reached synchronized world/map tick
  `13,839`, completed 81 constructions, and reported no desync.
- The different construction totals are not treated as performance evidence.
- The isolated single-player fixture completed 27 constructions during a
  five-second ultrafast window.
- Deterministic policy and fluent-transpiler tests passed unchanged.
- RimWorld 1.5 CPO build passed with zero warnings and zero errors.
- RimWorld 1.5 construction API-shape audit passed.
- RimWorld-Agent 1.5 build passed.
- Source package, staged distribution, persistent publish folder, and archive
  validation passed.
- No RimWorld 1.6 save was loaded or modified.

## Remaining publication step

No engineering or local release-packaging blocker remains. Publishing is a
separate external action. After publishing unlisted, subscribe to the delivered
copy, remove the local development copy, and repeat a short launch/construction
check against the exact Steam-delivered files before making the listing public.

The large test mod list emits existing renderer/asset-bundle, translation,
reflection-only dependency, and transient Multiplayer client-loading messages.
They did not cause a desync or failed synchronization barrier and are not
attributed to CPO by these tests.
