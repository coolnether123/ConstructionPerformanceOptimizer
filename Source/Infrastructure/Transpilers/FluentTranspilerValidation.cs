#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace ConstructionPerformanceOptimizer.Infrastructure.Transpilers
{
    /// <summary>
    /// Pure stack-signature validation shared by all fluent call recipes.
    /// </summary>
    internal static class FluentTranspilerValidation
    {
        internal static void ValidateReplacementCallSignature(
            MethodInfo sourceMethod,
            MethodInfo replacementMethod,
            Type expectedReplacementReturnType)
        {
            if (sourceMethod == null)
            {
                throw new InvalidOperationException("The source call resolved to null.");
            }

            if (replacementMethod == null)
            {
                throw new InvalidOperationException("The replacement call resolved to null.");
            }

            if (!replacementMethod.IsStatic)
            {
                throw new InvalidOperationException(
                    $"Replacement {FormatMethod(replacementMethod)} must be static.");
            }

            List<Type> sourceStackInputs = new List<Type>();
            if (!sourceMethod.IsStatic)
            {
                Type declaringType = sourceMethod.DeclaringType ??
                    throw new InvalidOperationException(
                        $"Instance source {FormatMethod(sourceMethod)} has no declaring type.");
                sourceStackInputs.Add(declaringType);
            }

            sourceStackInputs.AddRange(
                sourceMethod.GetParameters().Select(parameter => parameter.ParameterType));
            ParameterInfo[] replacementParameters = replacementMethod.GetParameters();
            if (replacementParameters.Length != sourceStackInputs.Count)
            {
                throw new InvalidOperationException(
                    $"Replacement {FormatMethod(replacementMethod)} consumes " +
                    $"{replacementParameters.Length} stack values, but source " +
                    $"{FormatMethod(sourceMethod)} consumes {sourceStackInputs.Count}.");
            }

            for (int index = 0; index < sourceStackInputs.Count; index++)
            {
                Type providedType = sourceStackInputs[index];
                Type expectedType = replacementParameters[index].ParameterType;
                if (!IsStackAssignable(providedType, expectedType))
                {
                    throw new InvalidOperationException(
                        $"Replacement {FormatMethod(replacementMethod)} parameter {index} expects " +
                        $"{FormatType(expectedType)}, but source {FormatMethod(sourceMethod)} " +
                        $"provides {FormatType(providedType)}.");
                }
            }

            if (!IsStackAssignable(replacementMethod.ReturnType, expectedReplacementReturnType))
            {
                throw new InvalidOperationException(
                    $"Replacement {FormatMethod(replacementMethod)} returns " +
                    $"{FormatType(replacementMethod.ReturnType)}, but the recipe requires " +
                    $"{FormatType(expectedReplacementReturnType)}.");
            }
        }

        internal static void ValidateInstanceFieldBooleanGuard(
            MethodBase originalMethod,
            FieldInfo instanceField,
            MethodInfo guardMethod)
        {
            if (!(originalMethod is MethodInfo originalInfo) ||
                originalInfo.IsStatic ||
                originalInfo.ReturnType != typeof(bool))
            {
                throw new InvalidOperationException(
                    "An instance-field early-return guard requires an instance method " +
                    "that returns System.Boolean.");
            }

            Type originalType = originalInfo.DeclaringType ??
                throw new InvalidOperationException(
                    $"Original {FormatMethod(originalInfo)} has no declaring type.");
            if (instanceField == null ||
                instanceField.IsStatic ||
                instanceField.DeclaringType == null ||
                !instanceField.DeclaringType.IsAssignableFrom(originalType))
            {
                throw new InvalidOperationException(
                    "The early-return field must be an instance field readable from the " +
                    "original method's declaring type.");
            }

            if (guardMethod == null ||
                !guardMethod.IsStatic ||
                guardMethod.ReturnType != typeof(bool))
            {
                throw new InvalidOperationException(
                    "The early-return guard must be a static method returning System.Boolean.");
            }

            ParameterInfo[] parameters = guardMethod.GetParameters();
            if (parameters.Length != 1 ||
                !IsStackAssignable(instanceField.FieldType, parameters[0].ParameterType))
            {
                throw new InvalidOperationException(
                    $"Guard {FormatMethod(guardMethod)} must consume exactly the field type " +
                    $"{FormatType(instanceField.FieldType)}.");
            }
        }

        internal static string FormatMethod(MethodBase? method)
        {
            if (method == null)
            {
                return "<null method>";
            }

            return $"{method.DeclaringType?.FullName ?? "<global>"}.{method.Name}";
        }

        private static bool IsStackAssignable(Type providedType, Type expectedType)
        {
            if (providedType == null || expectedType == null)
            {
                return false;
            }

            if (providedType.IsByRef || expectedType.IsByRef)
            {
                return providedType.IsByRef &&
                    expectedType.IsByRef &&
                    providedType.GetElementType() == expectedType.GetElementType();
            }

            if (providedType == expectedType)
            {
                return true;
            }

            if (providedType == typeof(void) || expectedType == typeof(void))
            {
                return false;
            }

            if (IsInt32StackType(providedType) && IsInt32StackType(expectedType))
            {
                return true;
            }

            if (providedType.IsValueType || expectedType.IsValueType)
            {
                return false;
            }

            return expectedType.IsAssignableFrom(providedType);
        }

        private static bool IsInt32StackType(Type type)
        {
            if (type.IsEnum)
            {
                type = Enum.GetUnderlyingType(type);
            }

            return type == typeof(int) ||
                type == typeof(uint) ||
                type == typeof(short) ||
                type == typeof(ushort) ||
                type == typeof(byte) ||
                type == typeof(sbyte) ||
                type == typeof(char);
        }

        private static string FormatType(Type? type)
        {
            return type?.FullName ?? "<null>";
        }
    }
}
