using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using ConstructionPipelineOptimizer.Infrastructure;
using HarmonyLib;
using RimWorld;
using Verse;
#if RW_ALPHA4
using FrameType = global::Frame;
#else
using FrameType = RimWorld.Frame;
#endif

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
        private static MethodBase TargetMethod() => FinishFrameMethodTargets.CompletionAction();

        private static IEnumerable<CodeInstruction> Transpiler(
            IEnumerable<CodeInstruction> instructions,
            ILGenerator generator)
        {
            List<CodeInstruction> code = instructions.ToList();
            int callIndex = code.FindIndex(instruction =>
                instruction.Calls(FinishFrameMethodTargets.CompleteConstruction));

            if (callIndex < 0 || code.Count(instruction =>
                    instruction.Calls(FinishFrameMethodTargets.CompleteConstruction)) != 1)
            {
                throw new InvalidOperationException(
                    "Expected exactly one Frame.CompleteConstruction call in FinishFrame's tick action.");
            }

            if (callIndex + 1 >= code.Count)
            {
                throw new InvalidOperationException(
                    "FinishFrame completion call did not have a continuation instruction.");
            }

            Label continueLabel = generator.DefineLabel();
            code[callIndex + 1].labels.Add(continueLabel);

            CodeInstruction guardedCall = code[callIndex];
            guardedCall.opcode = OpCodes.Call;
            guardedCall.operand = AccessTools.Method(
                typeof(FinishFrameCompletionGuardPatch),
                nameof(TryCompleteConstruction));

            code.Insert(callIndex + 1, new CodeInstruction(OpCodes.Brtrue, continueLabel));
            code.Insert(callIndex + 2, new CodeInstruction(OpCodes.Ret));
            return code;
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
