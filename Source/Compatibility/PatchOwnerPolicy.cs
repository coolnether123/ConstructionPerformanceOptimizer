using System;
using System.Collections.Generic;
using System.Linq;

namespace ConstructionPipelineOptimizer.Compatibility
{
    /// <summary>
    /// Separates patch-owner classification from Harmony reflection so the fail-closed
    /// compatibility rule can be tested without loading RimWorld or Harmony.
    /// </summary>
    internal static class PatchOwnerPolicy
    {
        internal static string[] ForeignOwners(
            IEnumerable<string> owners,
            string ownHarmonyId)
        {
            return (owners ?? Enumerable.Empty<string>())
                .Where(owner =>
                    owner != null && owner.Trim().Length != 0 &&
                    !string.Equals(owner, ownHarmonyId, StringComparison.Ordinal))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(owner => owner, StringComparer.Ordinal)
                .ToArray();
        }
    }
}
