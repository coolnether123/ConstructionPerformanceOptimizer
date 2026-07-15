using System;
using System.Collections.Generic;
using System.Reflection;
using ConstructionPipelineOptimizer.Eligibility;
using ConstructionPipelineOptimizer.Infrastructure;
using ConstructionPipelineOptimizer.Scheduling;
using HarmonyLib;
using RimWorld;
using Verse;
using Verse.AI;

namespace ConstructionPipelineOptimizer.Patches
{
    /// <summary>
    /// Throttles only the repeated CanConstruct fail condition inside vanilla FinishFrame jobs.
    /// Other failure checks, construction work, effects, skill gain, and completion stay vanilla.
    /// </summary>
    [HarmonyPatch]
    internal static class FinishFrameValidationThrottlePatch
    {
        internal const int ValidationInterval = 15;

        private static MethodBase TargetMethod() => FinishFrameMethodTargets.ValidationPredicate();

        private static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> instructions)
        {
            int replacements = 0;
            foreach (CodeInstruction instruction in instructions)
            {
                if (instruction.Calls(FinishFrameMethodTargets.CanConstruct))
                {
                    instruction.opcode = System.Reflection.Emit.OpCodes.Call;
                    instruction.operand = AccessTools.Method(
                        typeof(FinishFrameValidationThrottlePatch),
                        nameof(CanConstructOnCadence));
                    replacements++;
                }

                yield return instruction;
            }

            if (replacements != 1)
            {
                throw new InvalidOperationException(
                    $"Expected one CanConstruct call in FinishFrame validation; replaced {replacements}.");
            }
        }

#if RW_CANCONSTRUCT_3
        private static bool CanConstructOnCadence(
            Thing thing,
            Pawn pawn,
            bool forced)
#else
        private static bool CanConstructOnCadence(
            Thing thing,
            Pawn pawn,
            bool checkSkills,
            bool forced)
#endif
        {
            // Ordinary frames retain vanilla's every-tick validation. Only the zero-cost
            // terrain pipeline that creates the expensive queue burst is throttled.
            if (!ZeroCostTerrainEligibility.IsEligibleFrame(thing) ||
                ValidationCadence.ShouldValidate(
                    Find.TickManager.TicksGame,
                    pawn.thingIDNumber,
                    ValidationInterval))
            {
#if RW_CANCONSTRUCT_3
                return GenConstruct.CanConstruct(thing, pawn, forced);
#else
                return GenConstruct.CanConstruct(thing, pawn, checkSkills, forced);
#endif
            }

            // The vanilla fail predicate negates this result; true therefore means "do not
            // fail on this skipped tick." Completion still has an unconditional guard.
            return true;
        }
    }
}
