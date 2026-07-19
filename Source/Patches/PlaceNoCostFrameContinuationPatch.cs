using System.Collections.Generic;
using ConstructionPerformanceOptimizer.Eligibility;
using HarmonyLib;
using Verse;
using Verse.AI;
#if RW_ALPHA4
using FrameType = global::Frame;
using PlaceNoCostDriverType = Verse.AI.JobDriver_PlaceNoCostFrame;
using FinishFramesWorkGiverType = Verse.AI.WorkGiver_ConstructFinishFrames;
#else
using RimWorld;
using FrameType = RimWorld.Frame;
using PlaceNoCostDriverType = RimWorld.JobDriver_PlaceNoCostFrame;
#endif

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

#if RW_ALPHA4
                WorkGiverDef alphaWorkGiverDef =
                    DefDatabase<WorkGiverDef>.GetNamed("ConstructFinishFrames");
                FinishFramesWorkGiverType workGiver =
                    new FinishFramesWorkGiverType(alphaWorkGiverDef);
                Job finishJob = workGiver.StartingJobForOn(pawn, frame);
#else
                WorkGiverDef workGiverDef =
                    DefDatabase<WorkGiverDef>.GetNamedSilentFail("ConstructFinishFrames");
                WorkGiver_Scanner workGiver = workGiverDef?.Worker as WorkGiver_Scanner;
                if (workGiver == null)
                {
                    return;
                }

                // Ask the actual vanilla work giver for the job. Any other mod that patches
                // JobOnThing can approve, reject, or replace this transition normally.
#if RW_WORKGIVER_FORCED
                Job finishJob = workGiver.JobOnThing(pawn, frame, currentJob.playerForced);
#else
                Job finishJob = workGiver.JobOnThing(pawn, frame);
#endif
#endif
                if (finishJob == null)
                {
                    return;
                }

                // Preserve the work giver's exact job, including prerequisite/blocking jobs
                // and replacement targets supplied by another mod. The forced flag belongs to
                // the transition rather than to a particular vanilla FinishFrame job shape.
                finishJob.playerForced = currentJob.playerForced;

#if RW_JOB_WORKGIVERDEF
                if (finishJob.workGiverDef == null)
                {
                    finishJob.workGiverDef = workGiverDef;
                }
#endif

#if RW_ALPHA4
                pawn.jobs.StartJob(finishJob);
#else
                pawn.jobs.StartJob(finishJob, JobCondition.Succeeded);
#endif
            };
            continuation.defaultCompleteMode = ToilCompleteMode.Instant;
            return continuation;
        }
    }
}
