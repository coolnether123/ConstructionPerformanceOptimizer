using ConstructionPipelineOptimizer.Infrastructure;
using HarmonyLib;
using Verse;

namespace CpoForeignValidationOwner
{
    /// <summary>
    /// Benchmark-only compatibility fixture. It claims the exact generated validation
    /// predicate without changing its result, allowing an in-game test of CPO's
    /// foreign-owner shutdown path.
    /// </summary>
    [StaticConstructorOnStartup]
    internal static class ForeignValidationOwner
    {
        internal const string HarmonyId = "benchmark.cpo.foreignvalidationowner";

        static ForeignValidationOwner()
        {
            Harmony harmony = new Harmony(HarmonyId);
            harmony.Patch(
                FinishFrameMethodTargets.ValidationPredicate(),
                prefix: new HarmonyMethod(
                    typeof(ForeignValidationOwner),
                    nameof(ObserveWithoutChangingDecision)));
            Log.Message("[CPO Foreign Validation Owner] Installed decision-neutral predicate prefix.");
        }

        private static void ObserveWithoutChangingDecision()
        {
            // Intentionally empty: Harmony ownership is the test stimulus.
        }
    }
}
