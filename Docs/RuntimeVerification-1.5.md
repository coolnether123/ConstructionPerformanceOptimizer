# RimWorld 1.5 runtime verification

Verified on 2026-07-17 against RimWorld 1.5.4409 rev1120 and Multiplayer
0.10.7 / MultiplayerAPI 0.5.

## Isolation

- Dedicated save: `CPO Multiplayer Construction 1.5.4409`
- Save SHA-256:
  `F0176658FFC00C6F8252541E2A6E469159D825B4AF4DD5A7E84808868213980E`
- Fixture: one map, three colonists, 100 wood-wall blueprints, and 1,000 wood.
- Better Work Tab and Construction Queue Optimizer were excluded.
- The 1.5 save was copied into isolated host/client data folders for each run.
  No 1.6 save was loaded or modified.
- The normal ModsConfig profile was restored byte-for-byte after every run
  (SHA-256 `846CAAAAC075F55690681E02224D5BCB4B4D293D738418E0B2AC6CBB878DD966`).

## Results

| Run | Active mods | Simulation | Construction | Synchronization |
|---|---:|---|---|---|
| Single-player fixture check | 72 | 5 seconds at ultrafast | 27 completed; fixture reduced from 100 to 73 | Completed |
| CPO two-client acceptance | 72 | Tick 23 to 13,434 | 37 completed; fixture reduced from 100 to 63 | Host/client world and map clocks identical; no desync |
| CPO-free two-client control | 71 | Tick 23 to 13,839 | 81 completed; fixture reduced from 100 to 19 | Host/client world and map clocks identical; no desync |

Both Multiplayer runs used normal save hosting, two rendered RimWorld processes,
and a renamed client executable with WARP rendering isolation. The client reached
`ClientPlaying`, loaded the same map, ran construction at ultrafast speed, and
returned to a synchronized paused barrier before evidence collection.

The broad validation throttle, direct continuation, and completion guard were all
enabled in the CPO run. Runtime Harmony instrumentation was deliberately disabled
because changing patches independently after peers connect can itself desynchronize
the session.

## Build and package

- Deterministic policy and fluent-transpiler tests: passed.
- RimWorld 1.5 build: passed with zero warnings and zero errors.
- RimWorld 1.5 construction API-shape audit: passed.
- Source-package and staged-distribution validation: passed.
- CPO DLL SHA-256:
  `5173F7CB342F0C75218060B0DCE3172B6C091775AF6387D1D9029E964A0F69E7`
- Release archive SHA-256:
  `7FC74BF936A40CCC29DDE1F40DDD6AFA15865E263B4F928678004276AE4844E8`

The large mod list emits existing renderer/asset-bundle, translation, and transient
Multiplayer packet-handler messages while the client is loading. They occurred
without a desync or failed acceptance barrier and are not attributed to CPO by this
test. Compatibility still requires every peer to use the same CPO binary and mod
list.
