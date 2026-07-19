using ConstructionPerformanceOptimizer.Scheduling;
using ConstructionPerformanceOptimizer.Infrastructure;
using ConstructionPerformanceOptimizer.Compatibility;
using System.Reflection;

static void Assert(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

const int interval = 15;

Assert(ValidationCadence.ShouldValidate(0, 0, interval), "Tick zero should validate for pawn zero.");
Assert(!ValidationCadence.ShouldValidate(1, 0, interval), "Adjacent ticks should be throttled.");
Assert(ValidationCadence.ShouldValidate(15, 0, interval), "The cadence should repeat exactly.");
Assert(ValidationCadence.ShouldValidate(14, 1, interval), "Pawn IDs should deterministically distribute checks.");
Assert(!ValidationCadence.ShouldValidate(14, 2, interval), "Different pawn phases should not collapse together.");
Assert(ValidationCadence.ShouldValidate(1234, 5678, 1), "Interval one must preserve vanilla validation.");
Assert(ValidationCadence.ShouldValidate(int.MaxValue, int.MaxValue, 2), "Large values must not overflow.");
Assert(
    ValidationCadence.ShouldValidate(900, 42, interval) ==
    ValidationCadence.ShouldValidate(900, 42, interval),
    "Identical Multiplayer inputs must produce identical decisions.");

MethodInfo calledMethod = typeof(CallTarget).GetMethod(
    nameof(CallTarget.IsAllowed),
    BindingFlags.Static | BindingFlags.NonPublic)!;
MethodInfo uniqueCaller = MethodCallInspector.FindUniqueNestedCaller(
    typeof(UniqueCallFixture),
    calledMethod,
    method => method.ReturnType == typeof(bool));
Assert(uniqueCaller.Name == nameof(UniqueCallFixture.GeneratedShape.Predicate),
    "The IL resolver should select the nested method that calls the requested target.");
Assert(MethodCallInspector.CountCalls(uniqueCaller, calledMethod) == 1,
    "The IL resolver should count the exact call once.");

bool rejectedAmbiguity = false;
try
{
    MethodCallInspector.FindUniqueNestedCaller(
        typeof(AmbiguousCallFixture),
        calledMethod,
        method => method.ReturnType == typeof(bool));
}
catch (MissingMethodException)
{
    rejectedAmbiguity = true;
}

Assert(rejectedAmbiguity, "The IL resolver must fail closed when multiple generated methods match.");

string[] foreignOwners = PatchOwnerPolicy.ForeignOwners(
    new[] { "other.mod", "coolnether123.constructionperformanceoptimizer", "other.mod" },
    "coolnether123.constructionperformanceoptimizer");
Assert(foreignOwners.Length == 1 && foreignOwners[0] == "other.mod",
    "Compatibility policy should ignore only this mod and deduplicate foreign owners.");
Assert(PatchOwnerPolicy.ForeignOwners(Array.Empty<string>(), "self").Length == 0,
    "An unpatched vanilla method should be eligible for the broad optimization.");

FluentTranspilerTests.Run();

Console.WriteLine("ConstructionPerformanceOptimizer deterministic policy tests passed.");

internal static class CallTarget
{
    internal static bool IsAllowed() => true;
}

internal static class UniqueCallFixture
{
    internal static class GeneratedShape
    {
        internal static bool Predicate() => CallTarget.IsAllowed();

        internal static bool Unrelated() => true;
    }
}

internal static class AmbiguousCallFixture
{
    internal static class GeneratedShape
    {
        internal static bool First() => CallTarget.IsAllowed();

        internal static bool Second() => CallTarget.IsAllowed();
    }
}
