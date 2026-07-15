#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;

namespace ConstructionPipelineOptimizer.Infrastructure
{
    /// <summary>
    /// Resolves compiler-generated patch targets by the method they call, not by an unstable
    /// generated name. The resolver rejects zero or multiple matches instead of guessing.
    /// </summary>
    internal static class MethodCallInspector
    {
        private static readonly OpCode[] SingleByteOpCodes = new OpCode[0x100];
        private static readonly OpCode[] MultiByteOpCodes = new OpCode[0x100];

        static MethodCallInspector()
        {
            foreach (FieldInfo field in typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static))
            {
                if (!(field.GetValue(null) is OpCode opcode))
                {
                    continue;
                }

                ushort value = unchecked((ushort)opcode.Value);
                if (value < 0x100)
                {
                    SingleByteOpCodes[value] = opcode;
                }
                else if ((value & 0xff00) == 0xfe00)
                {
                    MultiByteOpCodes[value & 0xff] = opcode;
                }
            }
        }

        internal static MethodInfo FindUniqueNestedCaller(
            Type declaringType,
            MethodInfo calledMethod,
            Func<MethodInfo, bool> candidateFilter)
        {
            List<MethodInfo> matches = GetNestedTypesRecursively(declaringType)
                .SelectMany(type => type.GetMethods(
                    BindingFlags.Instance | BindingFlags.Static |
                    BindingFlags.Public | BindingFlags.NonPublic))
                .Where(candidateFilter)
                .Where(candidate => CountCalls(candidate, calledMethod) == 1)
                .ToList();

            if (matches.Count != 1)
            {
                string names = matches.Count == 0
                    ? "none"
                    : string.Join(", ", matches.Select(method => method.DeclaringType?.FullName + "." + method.Name));
                throw new MissingMethodException(
                    $"Expected exactly one nested method in {declaringType.FullName} to call " +
                    $"{calledMethod.DeclaringType?.FullName}.{calledMethod.Name}; found {matches.Count}: {names}.");
            }

            return matches[0];
        }

        internal static int CountCalls(MethodBase candidate, MethodInfo calledMethod)
        {
            MethodBody? body = candidate.GetMethodBody();
            byte[]? il = body?.GetILAsByteArray();
            if (il == null)
            {
                return 0;
            }

            int callCount = 0;
            int offset = 0;
            while (offset < il.Length)
            {
                OpCode opcode = ReadOpcode(il, ref offset);
                if (opcode.OperandType == OperandType.InlineMethod)
                {
                    int token = ReadInt32(il, ref offset);
                    MethodBase? resolved = ResolveMethod(candidate, token);
                    if (MethodsMatch(resolved, calledMethod))
                    {
                        callCount++;
                    }

                    continue;
                }

                SkipOperand(il, ref offset, opcode.OperandType);
            }

            return callCount;
        }

        private static IEnumerable<Type> GetNestedTypesRecursively(Type parent)
        {
            foreach (Type nested in parent.GetNestedTypes(BindingFlags.Public | BindingFlags.NonPublic))
            {
                yield return nested;
                foreach (Type descendant in GetNestedTypesRecursively(nested))
                {
                    yield return descendant;
                }
            }
        }

        private static MethodBase? ResolveMethod(MethodBase context, int metadataToken)
        {
            try
            {
                Type[]? typeArguments = context.DeclaringType?.GetGenericArguments();
                Type[]? methodArguments = context.IsGenericMethod ? context.GetGenericArguments() : null;
                return context.Module.ResolveMethod(metadataToken, typeArguments, methodArguments);
            }
            catch (ArgumentException)
            {
                return null;
            }
        }

        private static bool MethodsMatch(MethodBase? left, MethodBase right)
        {
            return left != null &&
                left.Module == right.Module &&
                left.MetadataToken == right.MetadataToken;
        }

        private static OpCode ReadOpcode(byte[] il, ref int offset)
        {
            byte first = il[offset++];
            return first == 0xfe ? MultiByteOpCodes[il[offset++]] : SingleByteOpCodes[first];
        }

        private static int ReadInt32(byte[] il, ref int offset)
        {
            int value = BitConverter.ToInt32(il, offset);
            offset += sizeof(int);
            return value;
        }

        private static void SkipOperand(byte[] il, ref int offset, OperandType operandType)
        {
            switch (operandType)
            {
                case OperandType.InlineNone:
                    return;
                case OperandType.ShortInlineBrTarget:
                case OperandType.ShortInlineI:
                case OperandType.ShortInlineVar:
                    offset += 1;
                    return;
                case OperandType.InlineVar:
                    offset += 2;
                    return;
                case OperandType.InlineI8:
                case OperandType.InlineR:
                    offset += 8;
                    return;
                case OperandType.InlineSwitch:
                    int count = ReadInt32(il, ref offset);
                    offset += count * sizeof(int);
                    return;
                default:
                    offset += 4;
                    return;
            }
        }
    }
}
