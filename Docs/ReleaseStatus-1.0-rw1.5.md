# Construction Performance Optimizer 1.0 — RimWorld 1.5

## Release decision

The separate `Support/1.5` package is an independently packageable,
runtime-verified RimWorld 1.5 release candidate with verified two-client
Multiplayer support.

RimWorld 1.1-1.4 remain build/API-verified historical targets. RimWorld 1.0 is
separately runtime-verified in single-player. The
RimWorld 1.5 package must remain separate from the public RimWorld 1.6 archive.

## Runtime evidence

- RimWorld `1.5.4409 rev1120`
- Multiplayer `0.10.7`
- MultiplayerAPI `0.5`
- Normal save hosting with two separately rendered processes
- 72 active mods, including Multiplayer, Multiplayer Compatibility, Tilled Soil,
  and CPO
- Better Work Tab excluded
- Both peers reached `ClientPlaying`
- Initial synchronized pause: world/map tick `23`
- Final synchronized pause: world/map tick `14,379`
- Construction fixture: 100 remaining before, 63 frames after, 37 completed
- Host desync: false
- Client desync: false
- Harness desync detection: false
- Original mod profile restored exactly
- No test processes remaining

A 71-mod CPO-free two-client control also completed synchronized construction
without a desync. The different construction totals are not treated as performance
evidence.

## Final package

- Archive: `ConstructionPerformanceOptimizer-1.0-rw1.5.zip`
- Archive SHA-256:
  `F860CCDEF295161EA921F4BA924BFC458937C10A2561CB6328043514E087E9AF`
- CPO DLL SHA-256:
  `5173F7CB342F0C75218060B0DCE3172B6C091775AF6387D1D9029E964A0F69E7`
- MultiplayerAPI DLL SHA-256:
  `4689E799C50DB79411B00AD8855D7DF86721BF3CFE1E390B68038B6ABCD852EC`

The package passed deterministic and fluent-transpiler tests, its target build,
API-shape audit, source/staging/distribution validation, single-player construction,
and normal-hosted two-client Multiplayer construction.

## Relevant commits

- CPO 1.5 implementation/tooling:
  `006da477f79af5ba65b9c982f4673b70a57240c7`
- CPO player-facing About metadata:
  `58875d1071437e08fbe70a3a633386cec11a6787`
- CPO final package record:
  `0ba9397ffcd9270be9bd75b398e45f224a574118`
- RimWorld-Agent 1.5 tooling:
  `ed04b90b938e9d02312e3425e48824925af7b0d1`

The package has not been published. After an unlisted upload, test the downloaded
Steam copy before making the listing public.
