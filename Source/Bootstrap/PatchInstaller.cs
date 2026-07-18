using System;
#if RW_VALIDATION_THROTTLE
using ConstructionPipelineOptimizer.Compatibility;
using ConstructionPipelineOptimizer.Infrastructure;
#endif
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
            ValidationPatchCompatibilityReport compatibility;
            try
            {
                compatibility = ValidationPatchCompatibility.Inspect(
                    ConstructionPipelineOptimizerMod.PackageId);
            }
            catch (Exception exception)
            {
                Log.Error(
                    "[Construction Pipeline Optimizer] Disabled broad validation: " +
                    $"compatibility inspection failed.\n{exception}");
                compatibility = new ValidationPatchCompatibilityReport(
                    new[] { "inspection failed" },
                    Array.Empty<string>());
            }

            // The broad cadence and its final completion guard are a dependent pair. A foreign
            // patch on the exact validation predicate disables both. Patches on methods that
            // our wrappers still call remain composed; the transpilers themselves verify that
            // the exact vanilla call sites survived that composition.
            bool completionGuard = compatibility.AllowsBroadThrottle &&
                TryPatch(harmony, typeof(FinishFrameCompletionGuardPatch));
            bool validationThrottle = completionGuard &&
                TryPatch(harmony, typeof(FinishFrameValidationThrottlePatch));

            if (completionGuard && !validationThrottle)
            {
                // The guard exists only to make the cadence throttle safe. If the second half
                // cannot install, remove our ownership from both exact targets and leave
                // vanilla construction behavior intact rather than running a partial pair.
                harmony.Unpatch(
                    FinishFrameMethodTargets.CompletionAction(),
                    HarmonyPatchType.All,
                    harmony.Id);
                harmony.Unpatch(
                    FinishFrameMethodTargets.ValidationPredicate(),
                    HarmonyPatchType.All,
                    harmony.Id);
                completionGuard = false;
            }
#else
            string compatibility = "not available on this RimWorld version";
            bool completionGuard = false;
            bool validationThrottle = false;
#endif

            // Direct continuation is independent: it still asks the vanilla work giver for
            // the next job and can remain enabled if the validation optimization is disabled.
            bool directContinuation = TryPatch(harmony, typeof(PlaceNoCostFrameContinuationPatch));

            return new PatchInstallationReport(
                directContinuation,
                validationThrottle,
                completionGuard,
                compatibility.ToString());
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
            bool completionGuard,
            string compatibility)
        {
            DirectContinuation = directContinuation;
            ValidationThrottle = validationThrottle;
            CompletionGuard = completionGuard;
            Compatibility = compatibility;
        }

        internal bool DirectContinuation { get; }

        internal bool ValidationThrottle { get; }

        internal bool CompletionGuard { get; }

        internal string Compatibility { get; }

        public override string ToString()
        {
            return "features: " +
                $"continuation={(DirectContinuation ? "on" : "off")}, " +
                $"broad validation throttle={(ValidationThrottle ? "on" : "off")}, " +
                $"completion guard={(CompletionGuard ? "on" : "off")}, " +
                $"compatibility={Compatibility}.";
        }
    }
}
