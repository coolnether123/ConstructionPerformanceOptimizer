using System.Collections.Generic;
using System.Reflection;
using System.Reflection.Emit;
using ConstructionPerformanceOptimizer.Infrastructure;
using ConstructionPerformanceOptimizer.Infrastructure.Transpilers;
using ConstructionPerformanceOptimizer.Scheduling;
using HarmonyLib;
using RimWorld;
using Verse;
using Verse.AI;

namespace ConstructionPerformanceOptimizer.Patches
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
            nameof(ShouldRunVanillaValidation));

        private static readonly FieldInfo ValidationBuild =
            FinishFrameMethodTargets.ValidationBuildField();

        private static MethodBase TargetMethod() => FinishFrameMethodTargets.ValidationPredicate();

        private static IEnumerable<CodeInstruction> Transpiler(
            IEnumerable<CodeInstruction> instructions,
            MethodBase original,
            ILGenerator generator)
        {
            return FluentTranspiler.Execute(instructions, original, generator, transpiler =>
                transpiler
                    .PrependInstanceFieldGuardOrReturnFalse(
                        ValidationBuild,
                        CadenceValidator));
        }

        private static bool ShouldRunVanillaValidation(Toil build)
        {
            Pawn pawn = build?.actor;
            if (pawn == null)
            {
                return true;
            }

            // Multiplayer supplies the ticking map's deterministic map tick through
            // TickManager while this toil executes. The stable pawn ID distributes the
            // cadence identically on every peer without consuming random state.
            return ValidationCadence.ShouldValidate(
                Find.TickManager.TicksGame,
                pawn.thingIDNumber,
                ValidationInterval);
        }
    }
}
