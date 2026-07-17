using System.Reflection;
using System.Reflection.Emit;
using ConstructionPipelineOptimizer.Infrastructure.Transpilers;
using HarmonyLib;

internal static class FluentTranspilerTests
{
    private static readonly MethodInfo SourcePredicate = GetStaticMethod(nameof(IsAllowed));
    private static readonly MethodInfo ReplacementPredicate = GetStaticMethod(nameof(IsAllowedOnCadence));
    private static readonly MethodInfo BadPredicate = GetStaticMethod(nameof(IsAllowedWithWrongSignature));
    private static readonly MethodInfo PredicateCaller = GetStaticMethod(nameof(CallPredicate));
    private static readonly MethodInfo CompleteCall = typeof(CompletionTarget).GetMethod(
        nameof(CompletionTarget.Complete),
        BindingFlags.Instance | BindingFlags.NonPublic)!;
    private static readonly MethodInfo GuardedComplete = GetStaticMethod(nameof(TryComplete));
    private static readonly MethodInfo AfterComplete = GetStaticMethod(nameof(AfterCompletion));
    private static readonly MethodInfo CompletionCaller = GetStaticMethod(nameof(CallCompletion));
    private static readonly MethodInfo CompletionCallerWithCatch =
        GetStaticMethod(nameof(CallCompletionInsideTryCatch));

    internal static void Run()
    {
        ReplacesOneExactCallWithoutMutatingInput();
        RejectsMissingAndAmbiguousCalls();
        RejectsUnsafeSignaturesBeforeMutation();
        RejectsMalformedBranchOperands();
        EmitsValidatedBooleanGuardControlFlow();
        RejectsStructuralEditsInsideExceptionHandlers();
        RejectsStructuralEditsAfterForeignExceptionBlockChanges();
    }

    private static void ReplacesOneExactCallWithoutMutatingInput()
    {
        DynamicMethod labels = new DynamicMethod("CpoRedirectLabels", typeof(void), Type.EmptyTypes);
        Label preservedLabel = labels.GetILGenerator().DefineLabel();
        CodeInstruction sourceCall = new CodeInstruction(OpCodes.Call, SourcePredicate);
        sourceCall.labels.Add(preservedLabel);
        sourceCall.blocks.Add(new ExceptionBlock(ExceptionBlockType.BeginExceptionBlock));
        List<CodeInstruction> input = new List<CodeInstruction>
        {
            new CodeInstruction(OpCodes.Ldc_I4_1),
            sourceCall,
            new CodeInstruction(OpCodes.Ret)
        };

        List<CodeInstruction> output = FluentTranspiler.Execute(
                input,
                PredicateCaller,
                null,
                transpiler => transpiler
                    .ForCall(SourcePredicate)
                    .ReplaceSingleWith(ReplacementPredicate))
            .ToList();

        Assert(output[1].opcode == OpCodes.Call && Equals(output[1].operand, ReplacementPredicate),
            "The exact source call should be redirected to the validated static replacement.");
        Assert(output[1].labels.Contains(preservedLabel),
            "Call replacement must preserve labels attached by earlier transpilers.");
        Assert(output[1].blocks.Count == 1 &&
            output[1].blocks[0].blockType == ExceptionBlockType.BeginExceptionBlock,
            "Index-aligned call replacement must preserve exception-block metadata.");
        Assert(input[1].opcode == OpCodes.Call && Equals(input[1].operand, SourcePredicate),
            "A fluent edit session must not mutate Harmony's input stream.");
    }

    private static void RejectsMissingAndAmbiguousCalls()
    {
        List<CodeInstruction> missing = new List<CodeInstruction>
        {
            new CodeInstruction(OpCodes.Ldc_I4_1),
            new CodeInstruction(OpCodes.Ret)
        };
        AssertThrows(
            () => FluentTranspiler.Execute(
                    missing,
                    PredicateCaller,
                    null,
                    transpiler => transpiler
                        .ForCall(SourcePredicate)
                        .ReplaceSingleWith(ReplacementPredicate))
                .ToList(),
            "A missing exact call must fail closed.");

        List<CodeInstruction> ambiguous = new List<CodeInstruction>
        {
            new CodeInstruction(OpCodes.Ldc_I4_1),
            new CodeInstruction(OpCodes.Call, SourcePredicate),
            new CodeInstruction(OpCodes.Pop),
            new CodeInstruction(OpCodes.Ldc_I4_1),
            new CodeInstruction(OpCodes.Call, SourcePredicate),
            new CodeInstruction(OpCodes.Ret)
        };
        AssertThrows(
            () => FluentTranspiler.Execute(
                    ambiguous,
                    PredicateCaller,
                    null,
                    transpiler => transpiler
                        .ForCall(SourcePredicate)
                        .ReplaceSingleWith(ReplacementPredicate))
                .ToList(),
            "Multiple exact calls must be treated as ambiguous rather than guessed.");
    }

    private static void RejectsUnsafeSignaturesBeforeMutation()
    {
        List<CodeInstruction> input = new List<CodeInstruction>
        {
            new CodeInstruction(OpCodes.Ldc_I4_1),
            new CodeInstruction(OpCodes.Call, SourcePredicate),
            new CodeInstruction(OpCodes.Ret)
        };

        AssertThrows(
            () => FluentTranspiler.Execute(
                    input,
                    PredicateCaller,
                    null,
                    transpiler => transpiler
                        .ForCall(SourcePredicate)
                        .ReplaceSingleWith(BadPredicate))
                .ToList(),
            "A stack-incompatible hook must be rejected before mutation.");
        Assert(Equals(input[1].operand, SourcePredicate),
            "Rejected recipes must leave the caller's original instruction objects unchanged.");
    }

    private static void EmitsValidatedBooleanGuardControlFlow()
    {
        List<CodeInstruction> input = CompletionInstructions();
        DynamicMethod dynamicMethod = new DynamicMethod(
            "CpoCompletionGuardLabels",
            typeof(void),
            new[] { typeof(CompletionTarget), typeof(object) });

        List<CodeInstruction> output = FluentTranspiler.Execute(
                input,
                CompletionCaller,
                dynamicMethod.GetILGenerator(),
                transpiler => transpiler
                    .ForCall(CompleteCall)
                    .ReplaceSingleVoidWithBooleanGuardAndReturn(GuardedComplete))
            .ToList();

        Assert(output.Count == input.Count + 2,
            "The completion guard should add exactly one branch and one early return.");
        Assert(output[2].opcode == OpCodes.Call && Equals(output[2].operand, GuardedComplete),
            "The instance completion call should become the validated static boolean guard.");
        Assert(output[3].opcode == OpCodes.Brtrue && output[3].operand is Label,
            "Successful guarded completion should branch to the original continuation.");
        Assert(output[4].opcode == OpCodes.Ret,
            "Failed guarded completion should return from the void completion action.");
        Assert(output[5].labels.Contains((Label)output[3].operand),
            "The generated success branch must target the original continuation instruction.");
        Assert(input[2].opcode == OpCodes.Callvirt && Equals(input[2].operand, CompleteCall),
            "Structural recipes must remain atomic and leave the input stream untouched.");
    }

    private static void RejectsMalformedBranchOperands()
    {
        List<CodeInstruction> input = new List<CodeInstruction>
        {
            new CodeInstruction(OpCodes.Ldc_I4_1),
            new CodeInstruction(OpCodes.Call, SourcePredicate),
            new CodeInstruction(OpCodes.Brtrue, 17),
            new CodeInstruction(OpCodes.Ldc_I4_0),
            new CodeInstruction(OpCodes.Ret)
        };

        AssertThrows(
            () => FluentTranspiler.Execute(
                    input,
                    PredicateCaller,
                    null,
                    transpiler => transpiler
                        .ForCall(SourcePredicate)
                        .ReplaceSingleWith(ReplacementPredicate))
                .ToList(),
            "The output linter must reject integer branch operands before Harmony emits IL.");
        Assert(Equals(input[1].operand, SourcePredicate),
            "Whole-stream lint failure must not mutate the input stream.");
    }

    private static void RejectsStructuralEditsInsideExceptionHandlers()
    {
        DynamicMethod dynamicMethod = new DynamicMethod(
            "CpoRejectedGuardLabels",
            typeof(void),
            new[] { typeof(CompletionTarget), typeof(object) });
        AssertThrows(
            () => FluentTranspiler.Execute(
                    CompletionInstructions(),
                    CompletionCallerWithCatch,
                    dynamicMethod.GetILGenerator(),
                    transpiler => transpiler
                        .ForCall(CompleteCall)
                        .ReplaceSingleVoidWithBooleanGuardAndReturn(GuardedComplete))
                .ToList(),
            "Structural edits in exception-handler methods must fail closed.");
    }

    private static void RejectsStructuralEditsAfterForeignExceptionBlockChanges()
    {
        List<CodeInstruction> input = CompletionInstructions();
        input[0].blocks.Add(new ExceptionBlock(ExceptionBlockType.BeginExceptionBlock));
        DynamicMethod dynamicMethod = new DynamicMethod(
            "CpoRejectedForeignBlockLabels",
            typeof(void),
            new[] { typeof(CompletionTarget), typeof(object) });

        AssertThrows(
            () => FluentTranspiler.Execute(
                    input,
                    CompletionCaller,
                    dynamicMethod.GetILGenerator(),
                    transpiler => transpiler
                        .ForCall(CompleteCall)
                        .ReplaceSingleVoidWithBooleanGuardAndReturn(GuardedComplete))
                .ToList(),
            "Structural edits must reject exception blocks introduced by an earlier transpiler.");
    }

    private static List<CodeInstruction> CompletionInstructions()
    {
        return new List<CodeInstruction>
        {
            new CodeInstruction(OpCodes.Ldarg_0),
            new CodeInstruction(OpCodes.Ldarg_1),
            new CodeInstruction(OpCodes.Callvirt, CompleteCall),
            new CodeInstruction(OpCodes.Call, AfterComplete),
            new CodeInstruction(OpCodes.Ret)
        };
    }

    private static void AssertThrows(Action action, string message)
    {
        try
        {
            action();
        }
        catch (InvalidOperationException)
        {
            return;
        }

        throw new InvalidOperationException(message);
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }

    private static MethodInfo GetStaticMethod(string name)
    {
        return typeof(FluentTranspilerTests).GetMethod(
            name,
            BindingFlags.Static | BindingFlags.NonPublic)!;
    }

    private static bool IsAllowed(int value) => value > 0;

    private static bool IsAllowedOnCadence(int value) => value > 0;

    private static bool IsAllowedWithWrongSignature() => true;

    private static bool CallPredicate(int value) => IsAllowed(value);

    private static bool TryComplete(CompletionTarget target, object worker)
    {
        target.Complete(worker);
        return true;
    }

    private static void AfterCompletion()
    {
    }

    private static void CallCompletion(CompletionTarget target, object worker)
    {
        target.Complete(worker);
        AfterCompletion();
    }

    private static void CallCompletionInsideTryCatch(CompletionTarget target, object worker)
    {
        try
        {
            target.Complete(worker);
        }
        catch (InvalidOperationException)
        {
        }
    }

    private sealed class CompletionTarget
    {
        internal void Complete(object worker)
        {
        }
    }
}
