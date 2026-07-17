using System;
using System.Collections.Generic;
using System.Reflection;
using ConstructionPipelineOptimizer.Infrastructure;
using HarmonyLib;
using RimWorld;
using Verse;
using Verse.AI;
using FrameType = RimWorld.Frame;
using FinishFrameDriverType = RimWorld.JobDriver_ConstructFinishFrame;
using FinishFramesWorkGiverType = RimWorld.WorkGiver_ConstructFinishFrames;

namespace ConstructionPipelineOptimizer.Compatibility
{
    /// <summary>
    /// Distinguishes direct competition on the validation predicate from downstream patches
    /// that remain in the call path. Only direct competition disables the broad cadence.
    /// </summary>
    internal static class ValidationPatchCompatibility
    {
        internal static ValidationPatchCompatibilityReport Inspect(string ownHarmonyId)
        {
            MethodBase validationPredicate = FinishFrameMethodTargets.ValidationPredicate();
            if (validationPredicate == null)
            {
                throw new MissingMethodException(
                    "Could not resolve compatibility target FinishFrame validation predicate.");
            }

            string[] directConflicts = ForeignOwners(validationPredicate, ownHarmonyId);
            KeyValuePair<string, MethodBase>[] composedDependencies =
            {
                Pair("FinishFrame completion action", FinishFrameMethodTargets.CompletionAction()),
                Pair(
                    "FinishFrame MakeNewToils",
                    AccessTools.DeclaredMethod(typeof(FinishFrameDriverType), "MakeNewToils")),
                Pair("GenConstruct.CanConstruct", FinishFrameMethodTargets.CanConstruct),
                Pair("Frame.CompleteConstruction", FinishFrameMethodTargets.CompleteConstruction),
                Pair(
                    "ConstructFinishFrames.JobOnThing",
                    AccessTools.DeclaredMethod(
                        typeof(FinishFramesWorkGiverType),
                        nameof(WorkGiver_Scanner.JobOnThing),
                        new[] { typeof(Pawn), typeof(Thing), typeof(bool) }))
            };

            List<string> observedDependencies = new List<string>();
            foreach (KeyValuePair<string, MethodBase> watched in composedDependencies)
            {
                if (watched.Value == null)
                {
                    throw new MissingMethodException(
                        $"Could not resolve compatibility target {watched.Key}.");
                }

                string[] foreignOwners = ForeignOwners(watched.Value, ownHarmonyId);
                if (foreignOwners.Length > 0)
                {
                    observedDependencies.Add(
                        $"{watched.Key}=[{string.Join(",", foreignOwners)}]");
                }
            }

            return new ValidationPatchCompatibilityReport(
                directConflicts,
                observedDependencies.ToArray());
        }

        private static string[] ForeignOwners(MethodBase method, string ownHarmonyId)
        {
            HarmonyLib.Patches patchInfo = Harmony.GetPatchInfo(method);
            return PatchOwnerPolicy.ForeignOwners(patchInfo?.Owners, ownHarmonyId);
        }

        private static KeyValuePair<string, MethodBase> Pair(string name, MethodBase method)
        {
            return new KeyValuePair<string, MethodBase>(name, method);
        }
    }

    /// <summary>
    /// Immutable compatibility evidence included in the startup diagnostic.
    /// </summary>
    internal readonly struct ValidationPatchCompatibilityReport
    {
        internal ValidationPatchCompatibilityReport(
            string[] directConflicts,
            string[] observedDependencies)
        {
            DirectConflicts = directConflicts ?? Array.Empty<string>();
            ObservedDependencies = observedDependencies ?? Array.Empty<string>();
        }

        internal string[] DirectConflicts { get; }

        internal string[] ObservedDependencies { get; }

        internal bool AllowsBroadThrottle => DirectConflicts.Length == 0;

        public override string ToString()
        {
            string direct = AllowsBroadThrottle
                ? "validation target clean at install"
                : "validation target owners at install=[" + string.Join(",", DirectConflicts) + "]";
            return ObservedDependencies.Length == 0
                ? direct
                : direct + "; composed dependencies: " +
                    string.Join("; ", ObservedDependencies);
        }
    }
}
