using System;
using System.Reflection;
using ConstructionPerformanceOptimizer.Infrastructure;
using HarmonyLib;
using RimWorld;
using Verse;
using Verse.AI;
#if RW_ALPHA4
using FrameType = global::Frame;
using FinishFrameDriverType = Verse.AI.JobDriver_ConstructFinishFrame;
#else
using FrameType = RimWorld.Frame;
using FinishFrameDriverType = RimWorld.JobDriver_ConstructFinishFrame;
#endif

namespace ConstructionPerformanceOptimizer.Infrastructure
{
    /// <summary>
    /// Centralizes exact vanilla method identities used by the FinishFrame transpilers.
    /// </summary>
    internal static class FinishFrameMethodTargets
    {
#if RW_CANCONSTRUCT_2
        internal static readonly MethodInfo CanConstruct = AccessTools.Method(
            typeof(GenConstruct),
            nameof(GenConstruct.CanConstruct),
            new[] { typeof(Thing), typeof(Pawn) });
#elif RW_CANCONSTRUCT_3
        internal static readonly MethodInfo CanConstruct = AccessTools.Method(
            typeof(GenConstruct),
            nameof(GenConstruct.CanConstruct),
            new[] { typeof(Thing), typeof(Pawn), typeof(bool) });
#elif RW_CANCONSTRUCT_4
        internal static readonly MethodInfo CanConstruct = AccessTools.Method(
            typeof(GenConstruct),
            nameof(GenConstruct.CanConstruct),
            new[] { typeof(Thing), typeof(Pawn), typeof(bool), typeof(bool) });
#else
        internal static readonly MethodInfo CanConstruct = AccessTools.Method(
            typeof(GenConstruct),
            nameof(GenConstruct.CanConstruct),
            new[] { typeof(Thing), typeof(Pawn), typeof(bool), typeof(bool), typeof(JobDef) });
#endif

        internal static readonly MethodInfo CompleteConstruction = AccessTools.Method(
            typeof(FrameType),
            nameof(FrameType.CompleteConstruction),
#if RW_ALPHA4
            Type.EmptyTypes);
#else
            new[] { typeof(Pawn) });
#endif

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
