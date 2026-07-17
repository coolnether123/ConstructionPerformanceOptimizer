using System.Collections.Generic;
using System.Reflection;
using System.Reflection.Emit;
using ConstructionPipelineOptimizer.Infrastructure;
using ConstructionPipelineOptimizer.Infrastructure.Transpilers;
using HarmonyLib;
using RimWorld;
using Verse;
using FrameType = RimWorld.Frame;

namespace ConstructionPipelineOptimizer.Patches
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
            if (!GenConstruct.CanConstruct(frame, worker))
            {
                return false;
            }

            frame.CompleteConstruction(worker);
            return true;
        }
    }
}
