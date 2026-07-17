#nullable enable
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Reflection.Emit;
using HarmonyLib;

namespace ConstructionPipelineOptimizer.Infrastructure.Transpilers
{
    /// <summary>
    /// Strict, fail-closed fluent editor for the small set of IL rewrites owned by this mod.
    /// Adapted from Better Work Tab's Spine.Harmony fluent transpiler lifecycle.
    /// </summary>
    internal sealed class FluentTranspiler
    {
        private readonly List<CodeInstruction> instructions;
        private readonly MethodBase originalMethod;
        private readonly ILGenerator? generator;
        private int editCount;

        private FluentTranspiler(
            IEnumerable<CodeInstruction> source,
            MethodBase originalMethod,
            ILGenerator? generator)
        {
            if (source == null)
            {
                throw new ArgumentNullException(nameof(source));
            }

            this.originalMethod = originalMethod ??
                throw new ArgumentNullException(nameof(originalMethod));
            this.generator = generator;
            instructions = new List<CodeInstruction>();
            foreach (CodeInstruction instruction in source)
            {
                if (instruction == null)
                {
                    throw new InvalidOperationException(
                        $"Fluent transpiler rejected {FluentTranspilerValidation.FormatMethod(originalMethod)}: " +
                        "the input stream contains a null instruction.");
                }

                CodeInstruction clone = new CodeInstruction(
                    instruction.opcode,
                    instruction.operand);
                clone.labels.AddRange(instruction.labels);
                clone.blocks.AddRange(instruction.blocks);
                instructions.Add(clone);
            }
        }

        /// <summary>
        /// Opens an isolated edit session, applies the requested recipe, and validates the
        /// complete result before returning it to Harmony. The input stream is never mutated.
        /// </summary>
        internal static IEnumerable<CodeInstruction> Execute(
            IEnumerable<CodeInstruction> source,
            MethodBase originalMethod,
            ILGenerator? generator,
            Action<FluentTranspiler> transform)
        {
            if (transform == null)
            {
                throw new ArgumentNullException(nameof(transform));
            }

            FluentTranspiler transpiler = new FluentTranspiler(source, originalMethod, generator);
            transform(transpiler);
            return transpiler.Build();
        }

        internal FluentCallSelection ForCall(MethodInfo sourceMethod)
        {
            return new FluentCallSelection(this, sourceMethod);
        }

        internal MethodBase OriginalMethod => originalMethod;

        internal int FindUniqueCallIndex(MethodInfo sourceMethod)
        {
            if (sourceMethod == null)
            {
                throw Failure("The source call resolved to null.");
            }

            List<int> matches = new List<int>();
            for (int index = 0; index < instructions.Count; index++)
            {
                CodeInstruction instruction = instructions[index];
                if (instruction != null && instruction.Calls(sourceMethod))
                {
                    matches.Add(index);
                }
            }

            if (matches.Count != 1)
            {
                throw Failure(
                    $"Expected exactly one call to {FluentTranspilerValidation.FormatMethod(sourceMethod)}; " +
                    $"found {matches.Count}.");
            }

            return matches[0];
        }

        internal void ReplaceCall(int index, MethodInfo replacementMethod)
        {
            CodeInstruction instruction = instructions[index];
            instruction.opcode = OpCodes.Call;
            instruction.operand = replacementMethod;
            editCount++;
        }

        internal void AppendBooleanGuardAndReturn(int callIndex)
        {
            if (generator == null)
            {
                throw Failure("A guarded call rewrite requires Harmony's ILGenerator.");
            }

            MethodBody? body = originalMethod.GetMethodBody();
            if (body != null && body.ExceptionHandlingClauses.Count > 0)
            {
                throw Failure(
                    "Refusing a structural guarded-call edit in a method with exception handlers.");
            }

            foreach (CodeInstruction instruction in instructions)
            {
                if (instruction.blocks.Count > 0)
                {
                    throw Failure(
                        "Refusing a structural guarded-call edit after another transpiler " +
                        "introduced exception-block boundaries.");
                }
            }

            int continuationIndex = callIndex + 1;
            if (continuationIndex >= instructions.Count)
            {
                throw Failure("The guarded call has no continuation instruction.");
            }

            Label continueLabel = generator.DefineLabel();
            instructions[continuationIndex].labels.Add(continueLabel);
            instructions.Insert(callIndex + 1, new CodeInstruction(OpCodes.Brtrue, continueLabel));
            instructions.Insert(callIndex + 2, new CodeInstruction(OpCodes.Ret));
            editCount++;
        }

        private IEnumerable<CodeInstruction> Build()
        {
            if (editCount == 0)
            {
                throw Failure("The transpiler completed without applying an edit.");
            }

            // This output linter is intentionally a separate boundary even though Build is its
            // only caller: it owns whole-stream invariants, while recipes own local stack shape.
            ValidateOutput();
            return instructions;
        }

        private void ValidateOutput()
        {
            HashSet<Label> definedLabels = new HashSet<Label>();
            for (int index = 0; index < instructions.Count; index++)
            {
                CodeInstruction instruction = instructions[index];
                if (instruction == null)
                {
                    throw Failure($"Instruction {index} is null.");
                }

                foreach (Label label in instruction.labels)
                {
                    if (!definedLabels.Add(label))
                    {
                        throw Failure($"Label {label.GetHashCode()} is defined more than once.");
                    }
                }

                if ((instruction.opcode == OpCodes.Call || instruction.opcode == OpCodes.Callvirt) &&
                    !(instruction.operand is MethodBase))
                {
                    throw Failure(
                        $"Instruction {index} has an invalid {instruction.opcode.Name} operand.");
                }
            }

            for (int index = 0; index < instructions.Count; index++)
            {
                CodeInstruction instruction = instructions[index];
                if (instruction.opcode.FlowControl != FlowControl.Branch &&
                    instruction.opcode.FlowControl != FlowControl.Cond_Branch)
                {
                    continue;
                }

                if (instruction.operand is Label label)
                {
                    if (!definedLabels.Contains(label))
                    {
                        throw Failure($"Branch instruction {index} targets an undefined label.");
                    }

                    continue;
                }

                if (instruction.operand is Label[] labels)
                {
                    foreach (Label target in labels)
                    {
                        if (!definedLabels.Contains(target))
                        {
                            throw Failure($"Switch instruction {index} targets an undefined label.");
                        }
                    }

                    continue;
                }

                throw Failure(
                    $"Branch instruction {index} has a non-label operand of type " +
                    $"{instruction.operand?.GetType().FullName ?? "<null>"}.");
            }
        }

        private InvalidOperationException Failure(string message)
        {
            string method = FluentTranspilerValidation.FormatMethod(originalMethod);
            return new InvalidOperationException($"Fluent transpiler rejected {method}: {message}");
        }

    }
}
