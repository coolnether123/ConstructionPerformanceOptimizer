using Verse;
using RimWorld;
using FrameType = RimWorld.Frame;
using TerrainDefType = Verse.TerrainDef;

namespace ConstructionPipelineOptimizer.Eligibility
{
    /// <summary>
    /// Defines the narrow frame scope that may bypass the second global work search.
    /// Material-bearing terrain and all building frames remain on the vanilla path.
    /// </summary>
    internal static class ZeroCostTerrainEligibility
    {
        /// <summary>
        /// Returns true only for a terrain frame whose definition has no material cost.
        /// </summary>
        internal static bool IsEligibleFrame(Thing thing)
        {
            if (!(thing is FrameType frame) || !(frame.def.entityDefToBuild is TerrainDefType terrain))
            {
                return false;
            }

            return terrain.CostList == null || terrain.CostList.Count == 0;
        }
    }
}
