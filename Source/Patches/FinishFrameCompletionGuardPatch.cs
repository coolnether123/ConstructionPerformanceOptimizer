using System.Collections.Generic;
using System.Reflection;
using System.Reflection.Emit;
using ConstructionPerformanceOptimizer.Infrastructure;
using ConstructionPerformanceOptimizer.Infrastructure.Transpilers;
using HarmonyLib;
using RimWorld;
using Verse;
#if RW_ALPHA4
using FrameType = global::Frame;
#else
using FrameType = RimWorld.Frame;
#endif

namespace ConstructionPerformanceOptimizer.Patches
{
    /// <summary>
    /// Replaces only FinishFrame's completion call with an unconditional authorization gate.
    /// An invalid, fully-worked frame remains in its active job until vanilla's fail condition
    /// ends it, instead of reporting a false success or completing illegally.
    /// </summary>
    [HarmonyPatch]
    internal static class FinishFrameCompletionGuardPatch
    {
        private static readonly MethodInfo GuardedCompletion = AccessTools.DeclaredMethod(
            typeof(FinishFrameCompletionGuardPatch),
            nameof(TryCompleteConstruction));

        private static MethodBase TargetMethod() => FinishFrameMethodTargets.CompletionAction();

        private static IEnumerable<CodeInstruction> Transpiler(
            IEnumerable<CodeInstruction> instructions,
            MethodBase original,
            ILGenerator generator)
        {
            return FluentTranspiler.Execute(instructions, original, generator, transpiler =>
                transpiler
                    .ForCall(FinishFrameMethodTargets.CompleteConstruction)
                    .ReplaceSingleVoidWithBooleanGuardAndReturn(GuardedCompletion));
        }

        private static bool TryCompleteConstruction(FrameType frame, Pawn worker)
        {
#if RW_CANCONSTRUCT_2
            if (!GenConstruct.CanConstruct(frame, worker))
#elif RW_CANCONSTRUCT_3
            if (!GenConstruct.CanConstruct(frame, worker, false))
#else
            if (!GenConstruct.CanConstruct(frame, worker))
#endif
            {
                return false;
            }

            frame.CompleteConstruction(worker);
            return true;
        }
    }
}
