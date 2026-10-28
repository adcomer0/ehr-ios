// Original arithmetic-only fixture. No game or EHR assembly is executed.
using System;
using HarmonyLib;
namespace HarmonyLib
{
    public enum MethodType { Normal, Getter, Constructor, StaticConstructor }
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = true)]
    public sealed class HarmonyPatch : Attribute
    {
        public HarmonyPatch() { }
        public HarmonyPatch(Type type) { }
        public HarmonyPatch(Type type, string name) { }
        public HarmonyPatch(string name) { }
    }
    public sealed class HarmonyPrefix : Attribute { }
    public sealed class HarmonyPostfix : Attribute { }
    public sealed class HarmonyFinalizer : Attribute { }
    public sealed class HarmonyPriority : Attribute { public HarmonyPriority(int value) { } }
    public sealed class HarmonyArgument : Attribute { public HarmonyArgument(int value) { } }
}
namespace EHR
{
    internal struct Number { internal int Value; }
    internal class Arithmetic
    {
        internal int Value;
        internal int Calculate(int input) => input + Value;
        internal int Throw(int input) => throw new InvalidOperationException();
        internal int Second(int input) => input;
        internal int Third(int input) => input;
        internal int Control(int input) => input;
        internal int Struct(Number payload) => payload.Value;
        internal int ExceptionReference(int input) => input;
    }
    [HarmonyPatch(typeof(Arithmetic), nameof(Arithmetic.Calculate))]
    [HarmonyPriority(700)]
    internal static class ArithmeticPatch
    {
        internal static int PrepareCount, PrefixCount, PostfixCount;
        static bool Prepare() { PrepareCount++; return true; }
        [HarmonyPrefix]
        static bool Prefix(ref int input, ref int __result, out int __state, ref Arithmetic __instance, ref int ___Value)
        {
            PrefixCount++; input += 3; __result = 40; __state = input;
            __instance = new Arithmetic { Value = 9 }; ___Value += 5;
            return false;
        }
        [HarmonyPostfix]
        static void Postfix(ref int __result, int __state, bool __runOriginal)
        { PostfixCount++; if (__runOriginal) throw new Exception("skipped original flag"); __result += __state; }
    }
    [HarmonyPatch(typeof(Arithmetic), nameof(Arithmetic.Calculate))]
    internal static class LaterPatch
    {
        [HarmonyPrefix]
        static void Prefix([HarmonyArgument(0)] ref int renamed, ref int __result)
        { renamed *= 2; __result++; }
    }
    [HarmonyPatch(typeof(Arithmetic), nameof(Arithmetic.Throw))]
    internal static class ThrowPatch
    {
        [HarmonyPrefix]
        static void Prefix(ref int input) { input = 77; throw new ApplicationException("fixture"); }
        [HarmonyFinalizer]
        static Exception Finalizer(Exception __exception)
        { if (__exception is not ApplicationException) throw new Exception("wrong exception"); return null!; }
    }
    [HarmonyPatch(typeof(Arithmetic))]
    [HarmonyPriority(700)]
    internal static class MultiplePatch
    {
        [HarmonyPatch(nameof(Arithmetic.Second))]
        [HarmonyPatch(nameof(Arithmetic.Third))]
        [HarmonyPriority(200)]
        [HarmonyPrefix]
        static void Prefix() { }
    }
    [HarmonyPatch(typeof(Arithmetic), nameof(Arithmetic.Control))]
    internal static class ControlPatch
    {
        [HarmonyPrefix]
        static bool Prefix(ref bool __runOriginal) { __runOriginal = true; return false; }
    }
    [HarmonyPatch(typeof(Arithmetic), nameof(Arithmetic.Struct))]
    internal static class StructPatch
    {
        [HarmonyPrefix]
        static void Prefix(ref Number payload, out int __state) { payload.Value += 4; __state = payload.Value; }
        [HarmonyPostfix]
        static void Postfix(int __state, ref int __result) { __result += __state; }
    }
    [HarmonyPatch(typeof(Arithmetic), nameof(Arithmetic.ExceptionReference))]
    internal static class ExceptionReferencePatch
    {
        [HarmonyFinalizer]
        static Exception Finalizer(ref Exception __exception) { __exception = new ApplicationException(); return null!; }
    }
}
