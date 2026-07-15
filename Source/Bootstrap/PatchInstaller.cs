using System;
using ConstructionPipelineOptimizer.Patches;
using HarmonyLib;
using Verse;

namespace ConstructionPipelineOptimizer.Bootstrap
{
    /// <summary>
    /// Installs independent patch features in a safety-aware order.
    /// </summary>
    internal static class PatchInstaller
    {
        internal static PatchInstallationReport Install(Harmony harmony)
        {
#if RW_VALIDATION_THROTTLE
            bool completionGuard = TryPatch(harmony, typeof(FinishFrameCompletionGuardPatch));

            // Validation may only be reduced when the unconditional completion guard exists.
            bool validationThrottle = completionGuard &&
                TryPatch(harmony, typeof(FinishFrameValidationThrottlePatch));
#else
            bool completionGuard = false;
            bool validationThrottle = false;
#endif

            // Direct continuation is independent: it still asks the vanilla work giver for
            // the next job and can remain enabled if the validation optimization is disabled.
            bool directContinuation = TryPatch(harmony, typeof(PlaceNoCostFrameContinuationPatch));

            return new PatchInstallationReport(
                directContinuation,
                validationThrottle,
                completionGuard);
        }

        private static bool TryPatch(Harmony harmony, Type patchType)
        {
            try
            {
                harmony.CreateClassProcessor(patchType).Patch();
                return true;
            }
            catch (Exception exception)
            {
                Log.Error(
                    $"[Construction Pipeline Optimizer] Disabled {patchType.Name}: " +
                    $"the expected RimWorld method shape was not found.\n{exception}");
                return false;
            }
        }
    }

    /// <summary>
    /// Immutable installation status used for one concise startup diagnostic.
    /// </summary>
    internal readonly struct PatchInstallationReport
    {
        internal PatchInstallationReport(
            bool directContinuation,
            bool validationThrottle,
            bool completionGuard)
        {
            DirectContinuation = directContinuation;
            ValidationThrottle = validationThrottle;
            CompletionGuard = completionGuard;
        }

        internal bool DirectContinuation { get; }

        internal bool ValidationThrottle { get; }

        internal bool CompletionGuard { get; }

        public override string ToString()
        {
            return "features: " +
                $"continuation={(DirectContinuation ? "on" : "off")}, " +
                $"validation throttle={(ValidationThrottle ? "on" : "off")}, " +
                $"completion guard={(CompletionGuard ? "on" : "off")}.";
        }
    }
}
