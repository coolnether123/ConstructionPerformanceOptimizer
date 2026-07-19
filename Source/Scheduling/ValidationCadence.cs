namespace ConstructionPerformanceOptimizer.Scheduling
{
    /// <summary>
    /// Provides a deterministic, pawn-distributed schedule for construction validation.
    /// </summary>
    public static class ValidationCadence
    {
        /// <summary>
        /// Returns true when this pawn should run the vanilla validation on this tick.
        /// Adding the stable pawn ID spreads checks across ticks without using random state,
        /// which keeps every Multiplayer peer on the same schedule.
        /// </summary>
        public static bool ShouldValidate(int gameTick, int pawnId, int interval)
        {
            if (interval <= 1)
            {
                return true;
            }

            long phase = (long)gameTick + pawnId;
            long remainder = phase % interval;
            if (remainder < 0)
            {
                remainder += interval;
            }

            return remainder == 0;
        }
    }
}
