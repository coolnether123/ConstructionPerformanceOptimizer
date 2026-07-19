#nullable enable
using System;
using System.Reflection;

namespace ConstructionPerformanceOptimizer.Infrastructure.Transpilers
{
    /// <summary>
    /// Fluent exact-call recipes adapted from Better Work Tab's Spine.Harmony call recipes.
    /// Every recipe resolves ambiguity and validates its replacement before mutating IL.
    /// </summary>
    internal sealed class FluentCallSelection
    {
        private readonly FluentTranspiler transpiler;
        private readonly MethodInfo sourceMethod;

        internal FluentCallSelection(FluentTranspiler transpiler, MethodInfo sourceMethod)
        {
            this.transpiler = transpiler ?? throw new ArgumentNullException(nameof(transpiler));
            this.sourceMethod = sourceMethod;
        }

        internal FluentTranspiler ReplaceSingleWith(MethodInfo replacementMethod)
        {
            int callIndex = transpiler.FindUniqueCallIndex(sourceMethod);
            FluentTranspilerValidation.ValidateReplacementCallSignature(
                sourceMethod,
                replacementMethod,
                expectedReplacementReturnType: sourceMethod.ReturnType);
            transpiler.ReplaceCall(callIndex, replacementMethod);
            return transpiler;
        }

        internal FluentTranspiler ReplaceSingleVoidWithBooleanGuardAndReturn(
            MethodInfo replacementMethod)
        {
            int callIndex = transpiler.FindUniqueCallIndex(sourceMethod);
            if (sourceMethod.ReturnType != typeof(void))
            {
                throw new InvalidOperationException(
                    $"Guarded replacement requires a void source call, but " +
                    $"{FluentTranspilerValidation.FormatMethod(sourceMethod)} returns " +
                    $"{sourceMethod.ReturnType.FullName}.");
            }

            if (!(transpiler.OriginalMethod is MethodInfo originalMethod) ||
                originalMethod.ReturnType != typeof(void))
            {
                throw new InvalidOperationException(
                    "Guarded replacement may emit ret only inside a void method.");
            }

            FluentTranspilerValidation.ValidateReplacementCallSignature(
                sourceMethod,
                replacementMethod,
                expectedReplacementReturnType: typeof(bool));
            transpiler.ReplaceCall(callIndex, replacementMethod);
            transpiler.AppendBooleanGuardAndReturn(callIndex);
            return transpiler;
        }
    }
}
