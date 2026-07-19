# Construction Performance Optimizer 1.1.0 Release Status

## Executive status

Construction Performance Optimizer (CPO) 1.1.0 is release-ready for RimWorld 1.6.
The selected adaptive build passed deterministic policy tests, fluent-transpiler
tests, API-shape validation, package validation, randomized clean single-player
performance tests, fail-closed conflict testing, and a normal-hosted two-client
Multiplayer construction test.

Historical targets from Alpha 4 through RimWorld 1.5 build on their owning
`Support/<version>` branches and pass the available API-shape audits. Each historical
branch contains target-specific metadata and a root DLL matching its versioned build,
so the branch can be installed directly. RimWorld 1.5 additionally passed
single-player and normal-hosted two-client Multiplayer construction tests. Alpha 4
through RimWorld 1.4 remain build/API verified because those runtimes are not
installed on the test machine.

## Release artifacts

| Artifact | SHA-256 |
|---|---|
| `1.6/Assemblies/Construction Performance Optimizer.dll` | `CDA027C78449AF865BE00039392EC99FD97B66CBF65F4F499A9CBB476837AA16` |
| `1.6/Assemblies/0MultiplayerAPI.dll` | `72260148E72D263AB42CC3B6DCBBADAC27CB218CB3045B09FE6ADC4807C0437D` |

The main archive contains the automatically routed RimWorld 1.0-1.6 runtime
payloads, About metadata and preview, `LoadFolders.xml`, `README.md`, `CHANGELOG.md`,
`LICENSE`, and the optional 1.5/1.6 Multiplayer API bridges. Ready-to-install
Alpha 4-0.19 single-version folders and ZIPs are under the release's `Legacy`
directory. Source, tests, tools, and benchmark workspaces are excluded.

Current release-preparation commits:

- Dev player metadata/build alignment:
  `84f56356b11b74dd975bc04aa5e4eef161dd5a96`
- Dev refreshed historical payload set:
  `ecfd913bbffac553232a2a98329957a97f190b05`
- RimWorld 1.5 final package record:
  `0ba9397ffcd9270be9bd75b398e45f224a574118`
- RimWorld-Agent 1.5 Multiplayer tooling:
  `ed04b90b938e9d02312e3425e48824925af7b0d1`

The RimWorld 1.5 decision and evidence are recorded separately in
[`ReleaseStatus-1.1.0-rw1.5.md`](ReleaseStatus-1.1.0-rw1.5.md).

## Exact RimWorld 1.6 Multiplayer acceptance

Final evidence:

`C:\Users\PrecisionX\AppData\Local\Temp\CPO-MultiplayerSmoke-20260718-165809.txt`

| Check | Result |
|---|---|
| CPO DLL | Selected adaptive 1.1.0 build `CDA027...AA16` |
| Game instances | Two rendered RimWorld processes |
| Hosting path | Normal save hosting; replay path excluded |
| Active mods | 75 |
| Better Work Tab | Disabled |
| Legacy construction optimizer | Disabled |
| Maps | 3 |
| Initial synchronized world tick | 9,332,890 |
| Final synchronized world tick | 9,335,396 |
| Synchronized ticks completed | 2,506 |
| Construction before/after | 11,004 / 10,952 |
| Constructions completed | 52 |
| Host desync state | `False` |
| Client desync state | `False` |
| Final host/client map clocks | Identical on maps 0, 4, and 7 |
| Profile restoration | Exact original SHA-256 restored |
| Processes remaining | None |

The startup diagnostics confirmed that continuation, broad validation throttling,
and the completion guard were all enabled. Both clients loaded Multiplayer 0.11.5
and MultiplayerAPI 0.6.

Earlier supporting runs:

- CPO-free normal-host control: approximately 7,000 synchronized ticks with no desync.
- CPO run: 2,686 synchronized ticks and 57 constructions completed with no desync.
- CPO run: 2,731 synchronized ticks and 62 constructions completed with no desync.
- Single-player with Multiplayer installed: construction progressed successfully.
- Single-player with Multiplayer and Multiplayer Compatibility excluded: construction
  progressed successfully using the bundled API fallback.

## Multiplayer harness controls

`Tools/Invoke-MultiplayerSmoke.ps1` now:

- launches isolated host and client instances with separate Agent identities;
- supports copied and renamed RimWorld executables;
- starts instances sequentially and restores the exact original mod profile;
- uses WARP for the second renderer to avoid a shared NVIDIA D3D11 deadlock;
- validates real Multiplayer world/map desired speed and simulation clocks;
- requires matching host/client map sets and final clocks;
- detects and preserves desync artifacts;
- confirms actual construction progress from synchronized fixture counts;
- excludes Better Work Tab and the legacy construction optimizer;
- supports Multiplayer, single-player, and Multiplayer-excluded test modes; and
- prohibits the dynamic construction Harmony probe during two-client acceptance,
  because runtime repatching was proven capable of creating its own diagnostic desync.

## Fluent transpiler hardening

The two construction IL rewrites use a focused fluent layer adapted from Better Work
Tab's `Spine.Harmony` design. The implementation:

- selects exactly one expected call site;
- rejects missing or ambiguous targets;
- validates complete replacement stack signatures before mutation;
- clones the input instruction stream for atomic failure behavior;
- preserves labels and exception-block metadata;
- refuses structural guarded-return edits in exception-handler methods;
- validates call operands and branch targets across the final stream; and
- lets the patch installer roll back the cadence/guard pair if either patch fails.

Off-game tests cover successful redirects, missing and duplicate calls, invalid hook
signatures, input atomicity, malformed branches, generated guard control flow, and
exception-handler rejection.

## Cross-version build and API results

| RimWorld | Continuation | Validation cadence | Completion guard/build |
|---|---|---|---|
| Alpha 4 | Verified | Not present in vanilla | Build/API audit passed |
| 0.13-0.17 | Verified | Not present in vanilla | Build/API audit passed |
| 0.18 | Verified | Not included on legacy Mono | Build/API audit passed |
| 0.19 | Verified | Not included on legacy Mono | Build/API audit passed |
| 1.0 | Verified | Disabled for old Mono compatibility | Native single-player construction stress passed |
| 1.1-1.4 | Verified | Compile surface verified | Build/API audit passed |
| 1.5 | Verified | Compile surface verified | Build/API audit passed |
| 1.6 | Verified | Verified | Build/API and runtime tests passed |

All 15 targets report assembly version 1.1.0.0 and reference their corresponding
RimWorld `Assembly-CSharp` version. The support cascade builds each target on its
own branch and copies only rebuilt versioned assembly folders back to `Dev`.

## RimWorld 1.5 Multiplayer status

The 1.5 branch builds CPO against `Assembly-CSharp` 1.5 and
`RimWorld.MultiplayerAPI` 0.5.0. Multiplayer's open-source `rw-1.5` branch uses the
same API package. The resulting CPO DLL references MultiplayerAPI 0.5.0, and its
branch package carries the corresponding `0MultiplayerAPI.dll`.

The installed RimWorld 1.5.4409 runtime passed a normal-hosted two-client session
with Multiplayer 0.10.7 and MultiplayerAPI 0.5. Both peers reached the same final
paused tick, completed active construction, and reported no desync. A separate
CPO-free control also passed.

## RimWorld Agent verification

The Agent extensions used by the harness include persistent frame-deduplicated
runtime pumping, real Multiplayer status and synchronized speed commands,
construction fixture/probe tools, exact colony inspection, and isolated
multi-instance bridge paths.

Verification:

- RimWorld Agent 1.6 build: passed with zero errors.
- RimWorld Agent 1.5 build and two-instance connection tooling: passed.
- Known build warning: the existing cross-version status writer uses Unity's obsolete
  `Application.loadedLevelName` property.
- Colony inspection argument tests: passed.
- The Agent powered the exact two-client acceptance run described above.

## Known unrelated runtime log noise

The accepted 75-mod run contained existing non-CPO diagnostics:

- Multiplayer Compatibility failed while inspecting QualityBuilder.
- A translation report contained one error.
- Reflection-only inspection could not preload `UnityEngine.InputLegacyModule`.
- The WARP client reported that dedicated video decoding fell back to software.

Neither peer desynchronized, CPO installed all three features, construction advanced,
and these messages are not attributed to CPO.

## Reproduction commands

```powershell
# Deterministic and fluent-transpiler tests plus 1.6 build/package validation
.\Tools\Build.ps1 -Version 1.6

# All historical API-shape checks after the support cascade
.\Tools\Test-ApiSurface.ps1

# Full support-branch build cascade (does not push unless -Push is supplied)
.\Tools\Invoke-SupportCascade.ps1 -ReleaseLabel v1.1.0

# Exact normal-host two-client construction test
.\Tools\Invoke-MultiplayerSmoke.ps1 -TwoClient -RunSeconds 15 -Port 30531

# Regenerate the public archive
.\Tools\Release.ps1 -Force
```

## Release decision

- RimWorld 1.6 single-player: **release-ready**
- RimWorld 1.6 Multiplayer: **release-ready**
- RimWorld 1.5 single-player: **runtime-verified release candidate**
- RimWorld 1.5 Multiplayer: **runtime-verified release candidate**
- RimWorld 1.0 single-player: **runtime-verified historical candidate**
- Alpha 4-0.19 and 1.1-1.4 branch builds: **build/API verified and directly packageable**
