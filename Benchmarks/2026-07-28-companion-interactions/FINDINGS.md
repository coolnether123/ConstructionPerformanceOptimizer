# Construction Performance Optimizer companion findings

This report covers Construction Performance Optimizer (CPO) only. It does not
test or modify Firefighting Performance Optimizer.

## Current compatibility result

No reviewed companion owns any of CPO's three exact Harmony targets. CPO loaded
all three expected patches in every verified CPO-on arm and none in CPO-off arms.
The official companion payloads tested so far do not justify changing CPO's base
runtime behavior.

The percentages below are the direct CPO benefit inside companion-on arms:
`100 * (arm01 - arm11) / arm01`, using process CPU milliseconds per simulated
tick. Positive is faster with CPO. Every benchmarkable companion now has three
clean screening blocks; nine blocks would still be required for a final
effect-size estimate under this suite's protocol.

| Companion | Arm 01 CPU ms/tick | Arm 11 CPU ms/tick | CPO benefit | Evidence and disposition |
|---|---:|---:|---:|---|
| Achtung! 4.1.12 official | 9.936 combined mean | 8.200 combined mean | 17.47% | Three clean official blocks when the earlier strict block is combined with the two-block supplement; no evidence of harm. |
| Better Pawn Control | 8.639 | 7.885 | 8.73% | Three clean blocks; exact BPC and CPO owners coexist, and the interaction CI crosses zero. |
| Performance Optimizer | 9.202 | 8.239 | 10.47% | Three balanced clean blocks; interaction CI crosses zero, so no evidence that it harms CPO and no patch is warranted. |
| Yet Another Optimizer | 7.381 | 6.305 | 14.58% | Three clean blocks; CPO's marginal saving increased with YaOpt in this screening workload. |
| Performance Fish 0.6.2 profiled | 7.792 | 6.961 | 10.66% | Three clean blocks with the modular Tech Advancing profile; interaction is effectively zero. |
| MissileGirl | 7.831 | 7.845 | -0.17% | Three clean blocks; patches coexist, but CPO's marginal CPU-per-tick saving was neutral and the interaction CI is wide. |
| Turret Performance Tweaks | 9.210 combined mean | 7.897 combined mean | 14.25% | Three clean blocks; exact Turret and CPO owners coexist, and the interaction CI crosses zero. |
| Hard RimWorld Optimization | 9.144 | 8.363 | 8.55% | Three balanced clean blocks; the earlier one-pair slowdown did not reproduce, and no compatibility patch is warranted. |
| RocketMan | n/a | n/a | n/a | Available checkout is RimWorld 1.2 only; excluded from the 1.6 runtime test. |

## Achtung!

The first three-block Achtung result is invalid. Its source checkout caused
RimWorld to load legacy `AchtungMod` 2.3.3 and current `Achtung` 4.1.12 together,
with Harmony 1 type-load errors.

The corrected stage is the official v4.1.12 release. Its active 1.6 assembly is:

```text
Achtung, Version=4.1.12.0
SHA-256 13505F933CF4DA56F4AFE26F7F1293CBDD6EB563B5CE919BFABAAC66E8408408
```

Two new clean blocks measured CPO at 16.81% faster with Achtung. Their
difference-in-differences was -2.6425 ms/tick, but the two-block 95% screening
interval was [-29.1409, 23.8559], which is too wide to claim an interaction.
Combining their block interactions with the earlier clean official block gives a
three-block mean of -1.6370 ms/tick and an interval of approximately
[-8.3871, 5.1131].

Source tracing also rejects the suspected forced-job race:

- CPO's direct handoff calls vanilla `StartJob`, which calls
  `CleanupCurrentJob` directly.
- Achtung hooks `EndCurrentJob`, not `CleanupCurrentJob`.
- Achtung replaces its forced target from blueprint to frame before CPO starts
  the vanilla FinishFrame job, then resumes its chain when FinishFrame later ends.

Therefore no Achtung-specific suppression is installed. Disabling CPO merely
because Achtung is active would remove measured benefit without fixing a
demonstrated incompatibility.

The official Achtung trials predate the final full-input-hash and dual
before/after owner enforcement. Their selected probes are clean and still record
the expected exact CPO owner/patch/target evidence, but that historical evidence
should not be read as having every later harness guarantee.

## Performance Optimizer

The three-block confirmation completed with all 12 arms free of foreign RimWorld
overlap. CPO's direct benefit with Performance Optimizer active was 10.47%.
The difference-in-differences estimate was -1.045 ms/tick, with block estimates
of -2.732, +0.920, and -1.323 and a 95% screening interval of
[-5.6207, 3.5307]. The interval includes no interaction, while its point estimate
leans toward more—not less—CPO benefit.

The runtime verifier also found the exact `PerformanceOptimizer.Main::` Harmony
owner only in companion-on arms and found CPO's three exact owners only in CPO-on
arms, before and after measurement. No `Failed to patch` or `Error patching`
signature appeared in companion-on logs. This is coexistence evidence, not just
an active-mod-list check, and it does not justify a compatibility patch.

## Better Pawn Control

The final confirmation completed all 12 arms without foreign-process overlap.
CPO's direct benefit with Better Pawn Control active was 8.73%. The
difference-in-differences estimate was -0.358 ms/tick with a 95% screening
interval of [-3.3155, 2.5989].

The exact `VouLT.BetterPawnControl::` owner exposed 16 patched methods before
and after timing in BPC-on arms and none in off arms. CPO's three exact tuples
also remained present only in CPO-on arms. The workload completed correctly and
the interval provides no evidence of a harmful interaction.

## Yet Another Optimizer

The final confirmation completed all 12 arms cleanly. CPO's direct benefit with
YaOpt active was 14.58%. The interaction estimate was -0.463 ms/tick with a
three-block screening interval of [-0.7291, -0.1962], indicating increased CPO
savings in this workload rather than interference.

Runtime verification found 82 methods under the pinned runtime's
`YetAnotherOptimizer::` and `YetAnotherOptimizer.Early::` owner family before
and after timing. CPO's exact owner/patch/target tuples remained intact.

## Performance Fish and Tech Advancing

Default Performance Fish crashes during startup in its global
`MonoCustomAttrs.GetCustomAttributes` cache when Tech Advancing initializes. The
same stack and frames occur with CPO off, so this is not caused by CPO.

The modular `CompatibilityProfiles/Set-bs.performance.ps1` profile disables only
that Performance Fish reflection cache. It runs only in Performance Fish arms,
produces a hash-pinned settings file, and leaves CPO source and all other arms
unchanged. Both CPO-off and CPO-on Performance Fish trials then completed.

The final three-block confirmation supersedes the earlier direct pair. All 12
arms were clean. CPO's direct benefit with Performance Fish active was 10.66%;
the interaction was +0.026 ms/tick with a screening interval of
[-2.3200, 2.3714]. The exact `bs.performance::` owner exposed 49 Harmony-patched
methods before and after timing, while all CPO tuples remained intact.

The settings file appeared only in arms 01/11 and always matched SHA-256
`A2F1D6951BD8A3FA51FC12B83581F95357EFA41668BEA124C6491776396F18BC`;
arms 00/10 had no companion settings output.

## MissileGirl

The final confirmation completed all 12 arms cleanly with its required
10-second warmup. The exact `VR.MissileGirl::` owner family exposed at least 100
patched methods, and CPO's exact three tuples remained intact before and after
timing.

CPO's CPU-per-tick result with MissileGirl was neutral: arm 01 averaged 7.831
ms/tick and arm 11 averaged 7.845, a -0.17% point estimate. The interaction was
+0.989 ms/tick with a wide interval of [-2.5428, 4.5208], so it does not
establish harm. CPO still increased mean completed blueprints from 102.7 to
187.0 during the fixed measurement window. This is overlapping or noisy
marginal performance, not a runtime incompatibility, and does not justify
disabling or altering CPO.

## Hard RimWorld Optimization

The three-block confirmation completed all 12 arms without a foreign RimWorld
observation. CPO's direct benefit with HRO active was 8.55%. The
difference-in-differences estimate was -0.878 ms/tick; the three block estimates
were -2.139, +2.175, and -2.669, with a 95% screening interval of
[-7.4784, 5.7231]. That interval includes zero, and the earlier one-pair 7.35%
slowdown did not reproduce.

Runtime verification found six exact `myrimworldmod.hardrimworldoptimization::`
patched methods before and after timing in every HRO-on arm and none in HRO-off
arms. CPO's three exact patch/target pairs also remained present only in CPO-on
arms. Source review found HRO patches pawn ticking, plants, turret targeting, and
quest selection—not CPO's frame-placement, validation, completion, or
construction work-giver paths. HRO therefore remains a negative control; no
HRO-specific CPO module or suppression is installed.

## Turret Performance Tweaks

The clean one-block rerun and two-block strict supplement produced three balanced
blocks with no foreign-process observations. Their block interactions were
+1.065, +1.013, and -2.617 ms/tick. Combined, CPO's direct benefit with Turret
Performance Tweaks active was 14.25%; mean interaction was -0.180 ms/tick with
an approximate 95% screening interval of [-5.4236, 5.0642].

Decompilation identifies the exact owner
`jaeger972.TurretPerformanceTweaks::` and two turret-targeting patches. Runtime
verification found both only in companion-on arms before and after timing, while
CPO's three construction patches remained present only in CPO-on arms. The mods
have no exact target overlap, the initial one-block interaction did not repeat,
and no modular CPO compatibility patch is justified.

## Harness enforcement

- Trials use only the isolated CPO game copy and fresh saved-data folders.
- Descriptive result names map to a short hash-addressed trial-data root to stay
  below Unity/Mono's Windows path limit.
- Companion package IDs are asserted from the live fixture load.
- All three exact CPO patch/target pairs are asserted before and after timing.
- Registry-declared companion Harmony owners are asserted before and after
  timing and forbidden from companion-off arms.
- Companion DLL path, assembly identity, and SHA-256 are registry-pinned.
- Companion-specific load placement, order constraints, warmup, settings, and
  forbidden log patterns are data/hooks rather than branches in CPO.
- Blocks with any foreign RimWorld observation during measurement are excluded
  as a whole.
- Runner, registry, schedule, executable, fixture, base profile, full staged
  benchmark-agent tree, CPO runtime projection inputs, compatibility-profile
  set, and CPO DLL hashes are recorded and rechecked before every pending trial.
- Completed result paths and trial-manifest arms are locked back to their
  scheduled rows; changed or misattributed configurations cannot silently
  resume.

## Interpretation limits

One block is preliminary, three balanced blocks are screening evidence, and nine
balanced blocks are required for a final estimate. The clean direct pairs establish
that CPO can remain active and complete the workload with those companions; they
do not yet prove stable effect sizes. Hard RimWorld Optimization and Performance
Optimizer received longer confirmation because their static overlap or preliminary
numbers made them the highest-value follow-ups. Both have now completed those
confirmations; neither supports a CPO compatibility patch.
