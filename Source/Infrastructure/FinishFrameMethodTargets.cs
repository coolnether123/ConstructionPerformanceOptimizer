using System;
using System.Reflection;
using ConstructionPipelineOptimizer.Infrastructure;
using HarmonyLib;
using RimWorld;
using Verse;
using Verse.AI;
using FrameType = RimWorld.Frame;
using FinishFrameDriverType = RimWorld.JobDriver_ConstructFinishFrame;

namespace ConstructionPipelineOptimizer.Infrastructure
{
    /// <summary>
    /// Centralizes exact vanilla method identities used by the FinishFrame transpilers.
    /// </summary>
    internal static class FinishFrameMethodTargets
    {
        internal static readonly MethodInfo CanConstruct = AccessTools.Method(
            typeof(GenConstruct),
            nameof(GenConstruct.CanConstruct),
            new[] { typeof(Thing), typeof(Pawn), typeof(bool), typeof(bool), typeof(JobDef) });

        internal static readonly MethodInfo CompleteConstruction = AccessTools.Method(
            typeof(FrameType),
            nameof(FrameType.CompleteConstruction),
            new[] { typeof(Pawn) });

        internal static MethodBase ValidationPredicate()
        {
            EnsureResolved(CanConstruct, nameof(CanConstruct));
            return MethodCallInspector.FindUniqueNestedCaller(
                typeof(FinishFrameDriverType),
                CanConstruct,
                method => method.ReturnType == typeof(bool) && method.GetParameters().Length == 0);
        }

        internal static MethodBase CompletionAction()
        {
            EnsureResolved(CompleteConstruction, nameof(CompleteConstruction));
            return MethodCallInspector.FindUniqueNestedCaller(
                typeof(FinishFrameDriverType),
                CompleteConstruction,
                method => method.ReturnType == typeof(void) && method.GetParameters().Length <= 1);
        }

        private static void EnsureResolved(MethodInfo method, string name)
        {
            if (method == null)
            {
                throw new MissingMethodException($"Could not resolve required RimWorld method {name}.");
            }
        }
    }
}
