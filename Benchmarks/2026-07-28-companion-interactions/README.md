# CPO companion interaction benchmark

This suite measures whether each named companion changes Construction Performance
Optimizer's activation, behavior, or marginal performance benefit. It does not
create or test the firefighting mod.

The executable, mod staging root, fixture, settings, and results are isolated under:

```text
A:\Dev\BenchmarkGames\RimWorld-ConstructionPerformanceOptimizer-1.6
```

The normal Steam executable and normal LocalLow profile are read-only sources and
are never used at runtime. `RimWorldCPOIsolated.exe` is the only initial player.
An identical `RimWorldWin64.exe` exists inside the same isolated copy because
Prepatcher may restart a renamed Unity player by its canonical name.

## Design

Each available companion uses a randomized 2x2 design:

| Arm | CPO | Companion |
|---|---:|---:|
| `00` | off | off |
| `10` | on | off |
| `01` | off | on |
| `11` | on | on |

For process CPU milliseconds per simulated tick:

```text
CPO effect without companion = arm10 - arm00
CPO effect with companion    = arm11 - arm01
interaction                  = (arm11 - arm01) - (arm10 - arm00)
```

A negative CPO effect means lower tick cost. The interaction term answers whether
the companion changes that CPO benefit; it is not inferred from the companion's
standalone speed effect.

The suite reuses the hash-pinned historical "12,000 Tilled Soil" save and CPO
probe. The XML contains 12,000 blueprint records, but the current 1.6.4871 load
materializes 11,004 spawned target blueprints across the three maps. Trials assert
that observed 11,004 count exactly and record the discrepancy rather than silently
claiming the historical nominal count.
Every trial gets a fresh isolated data directory, reloads the unchanged fixture,
uses the historical full mod profile with Better Work Tab and other CPO variants
removed, and enables the CPO benchmark agent symmetrically. Primary timing keeps
Dubs Performance Analyzer disabled to avoid profiler overhead. Dubs is reserved for
separate, explicitly labeled diagnostic runs and is never mixed into the primary
interaction estimates.

Before timing, the harness verifies the live fixture load contains every expected
companion package in `01`/`11` and none in `00`/`10`. CPO-on arms must expose all
three exact CPO patch/target pairs; CPO-off arms must expose none. The same CPO
patch assertions run again after timing. When a registry row declares a Harmony
owner, companion-on arms must expose that exact owner before and after timing and
companion-off arms must expose none. Trial manifests pin the runners, registry,
schedule, executable, fixture, base profile, benchmark agent, compatibility
profile set, and CPO DLL hashes. Those inputs are rehashed before every pending
trial, including a deterministic digest of every staged benchmark-agent file and
all CPO runtime projection inputs. Resume also locks each completed result path
and trial-manifest arm to its scheduled row, and refuses a changed or
misattributed configuration.

The primary endpoint is process CPU milliseconds per simulated tick. Wall
milliseconds per tick and TPS are secondary. Three blocks are screening evidence;
nine balanced blocks are required before treating an interaction as a final estimate.

## Run

For publication-quality measurements, close every RimWorld process before trials:

```powershell
& .\Tools\Test-CPOBenchmarkIsolation.ps1 -PerformanceRun

& .\Benchmarks\2026-07-28-companion-interactions\Invoke-CompanionInteraction.ps1 `
  -Companion achtung `
  -Blocks 3 `
  -RunsPerArmPerBlock 1 `
  -DurationSeconds 60
```

Run every row marked `available` in `CompanionMods.csv`. RocketMan's pulled source
supports only RimWorld 1.2, so it is recorded as unavailable instead of being
loaded into 1.6.

Validate all modular compatibility profiles without launching RimWorld:

```powershell
& .\Benchmarks\2026-07-28-companion-interactions\Test-CompatibilityProfiles.ps1
```

For broad screening while another isolated RimWorld benchmark is running, pass
`-AllowConcurrentRimWorld`. The harness records foreign-process observations at
every measurement checkpoint. The analyzer excludes an entire randomized block
when any of its four arms overlapped another RimWorld process; it never silently
mixes overlapped and uncontaminated arms.

## Companion-specific profiles

Optional compatibility settings live in `CompatibilityProfiles` and are named
`Set-<package-id>.ps1`. The trial runner discovers them only for package IDs active
in companion-on arms. Companion-off arms never execute or write those settings.
Companion-specific load placement, dependency-order constraints, and minimum
warmup live as data in `CompanionMods.csv`; the generic runner contains no
Performance Fish, Better Pawn Control, or MissileGirl branch.

Performance Fish 0.6.2 and Tech Advancing crash together during startup inside
Performance Fish's global `MonoCustomAttrs.GetCustomAttributes` reflection cache,
with or without CPO. `Set-bs.performance.ps1` disables only that Performance Fish
cache for Performance Fish arms. The setting is hash-recorded in each trial
manifest. It is a benchmark/runtime compatibility profile, not a CPO base-code
change.

## Intentional one-caller helpers

`Set-InteractionProfile` and `Stage-CpoBenchmarkRuntime` each currently have one
caller. They remain separate because profile mutation and runtime projection are
auditable side-effect boundaries. If another benchmark suite needs either behavior,
extract them into a shared tested module rather than copying or further splitting
them.

Each companion profile script also has one dynamic caller by design. Keep these
scripts separate: they are the modular extension boundary that prevents one mod's
workaround from changing other arms or CPO's base implementation.
