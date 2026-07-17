using System.Collections.Generic;
using System.Reflection;
using ConstructionPipelineOptimizer.Infrastructure;
using ConstructionPipelineOptimizer.Infrastructure.Transpilers;
using ConstructionPipelineOptimizer.Scheduling;
using HarmonyLib;
using RimWorld;
using Verse;
using Verse.AI;

namespace ConstructionPipelineOptimizer.Patches
{
    /// <summary>
    /// Throttles the repeated CanConstruct fail condition inside vanilla FinishFrame jobs when
    /// compatibility inspection found a clean patch graph. Other failure checks, construction
    /// work, effects, skill gain, and completion stay vanilla.
    /// </summary>
    [HarmonyPatch]
    internal static class FinishFrameValidationThrottlePatch
    {
        internal const int ValidationInterval = 15;

        private static readonly MethodInfo CadenceValidator = AccessTools.DeclaredMethod(
            typeof(FinishFrameValidationThrottlePatch),
            nameof(CanConstructOnCadence));

        private static MethodBase TargetMethod() => FinishFrameMethodTargets.ValidationPredicate();

        private static IEnumerable<CodeInstruction> Transpiler(
            IEnumerable<CodeInstruction> instructions,
            MethodBase original)
        {
            return FluentTranspiler.Execute(instructions, original, null, transpiler =>
                transpiler
                    .ForCall(FinishFrameMethodTargets.CanConstruct)
                    .ReplaceSingleWith(CadenceValidator));
        }

        private static bool CanConstructOnCadence(
            Thing thing,
            Pawn pawn,
            bool checkSkills,
            bool forced,
            JobDef jobForReservation)
        {
            // Multiplayer supplies the ticking map's deterministic map tick through
            // TickManager while this toil executes. The stable pawn ID distributes the
            // cadence identically on every peer without consuming random state.
            bool shouldValidate = ValidationCadence.ShouldValidate(
                Find.TickManager.TicksGame,
                pawn.thingIDNumber,
                ValidationInterval);
            if (shouldValidate)
            {
                return GenConstruct.CanConstruct(
                    thing,
                    pawn,
                    checkSkills,
                    forced,
                    jobForReservation);
            }

            // The vanilla fail predicate negates this result; true therefore means "do not
            // fail on this skipped tick." Completion still has an unconditional guard.
            return true;
        }
    }
}
