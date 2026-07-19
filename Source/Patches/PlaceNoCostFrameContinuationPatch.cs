using System.Collections.Generic;
using ConstructionPerformanceOptimizer.Eligibility;
using HarmonyLib;
using RimWorld;
using Verse;
using Verse.AI;
using FrameType = RimWorld.Frame;
using PlaceNoCostDriverType = RimWorld.JobDriver_PlaceNoCostFrame;

namespace ConstructionPerformanceOptimizer.Patches
{
    /// <summary>
    /// Extends vanilla's no-cost frame placement job with one final, instant continuation toil.
    /// Eligible terrain moves directly into vanilla FinishFrame instead of ending the job and
    /// asking the global work system to rediscover the frame.
    /// </summary>
    [HarmonyPatch(typeof(PlaceNoCostDriverType), "MakeNewToils")]
    internal static class PlaceNoCostFrameContinuationPatch
    {
        private static readonly WorkGiverDef FinishFramesWorkGiverDef =
            DefDatabase<WorkGiverDef>.GetNamedSilentFail("ConstructFinishFrames");

        private static readonly WorkGiver_Scanner FinishFramesWorkGiver =
            FinishFramesWorkGiverDef?.Worker as WorkGiver_Scanner;

        private static IEnumerable<Toil> Postfix(IEnumerable<Toil> __result)
        {
            // Preserve the complete vanilla toil sequence before appending our transition.
            foreach (Toil toil in __result)
            {
                yield return toil;
            }

            yield return CreateContinuationToil();
        }

        private static Toil CreateContinuationToil()
        {
            Toil continuation = new Toil();
            continuation.initAction = delegate
            {
                Pawn pawn = continuation.actor;
                Job currentJob = pawn?.jobs?.curJob;
                FrameType frame = currentJob?.GetTarget(TargetIndex.A).Thing as FrameType;

                if (!ZeroCostTerrainEligibility.IsEligibleFrame(frame))
                {
                    return;
                }

                if (FinishFramesWorkGiver == null)
                {
                    return;
                }

                // Ask the actual vanilla work giver for the job. Any other mod that patches
                // JobOnThing can approve, reject, or replace this transition normally.
                Job finishJob = FinishFramesWorkGiver.JobOnThing(
                    pawn,
                    frame,
                    currentJob.playerForced);
                if (finishJob == null)
                {
                    return;
                }

                // Preserve the work giver's exact job, including prerequisite/blocking jobs
                // and replacement targets supplied by another mod. The forced flag belongs to
                // the transition rather than to a particular vanilla FinishFrame job shape.
                finishJob.playerForced = currentJob.playerForced;

                if (finishJob.workGiverDef == null)
                {
                    finishJob.workGiverDef = FinishFramesWorkGiverDef;
                }

                pawn.jobs.StartJob(finishJob, JobCondition.Succeeded);
            };
            continuation.defaultCompleteMode = ToilCompleteMode.Instant;
            return continuation;
        }
    }
}
