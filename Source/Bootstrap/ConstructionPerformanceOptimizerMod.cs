using HarmonyLib;
using Multiplayer.API;
using Verse;

namespace ConstructionPerformanceOptimizer.Bootstrap
{
    /// <summary>
    /// Installs the mod's Harmony patches after RimWorld finishes loading assemblies.
    /// The mod has no settings or persistent save data.
    /// </summary>
    public static class ConstructionPerformanceOptimizerMod
    {
        internal const string PackageId = "coolnether123.constructionperformanceoptimizer";
        private static bool initialized;

        internal static void Initialize()
        {
            if (initialized)
            {
                return;
            }

            initialized = true;
            if (MP.enabled)
            {
                Log.Message(
                    "[Construction Performance Optimizer] Multiplayer API detected; " +
                    "construction optimizations will run inside Multiplayer's " +
                    "deterministic map-tick context.");
            }

            // Install each feature deliberately so a changed game method cannot leave a
            // safety-dependent optimization partially active.
            PatchInstallationReport report = PatchInstaller.Install(new Harmony(PackageId));
            Log.Message($"[Construction Performance Optimizer] {report}");
        }
    }

    /// <summary>
    /// RimWorld 1.6 discovers this type during static-constructor startup.
    /// </summary>
    [StaticConstructorOnStartup]
    internal static class ConstructionPerformanceOptimizerStartup
    {
        static ConstructionPerformanceOptimizerStartup()
        {
            // Compatibility decisions should see patches installed by normal mod startup
            // constructors. Queue inspection and installation until this load event ends;
            // patches deliberately added after that point remain outside the startup snapshot.
            LongEventHandler.ExecuteWhenFinished(ConstructionPerformanceOptimizerMod.Initialize);
        }
    }
}
