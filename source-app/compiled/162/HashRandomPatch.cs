using HarmonyLib;

namespace EHR;

[HarmonyPatch(typeof(HashRandom))]
internal class HashRandomPatch
{
    [HarmonyPatch("FastNext")]
    [HarmonyPrefix]
    private static bool FastNext([HarmonyArgument(0)] int maxInt, ref int __result)
    {
        if (IRandom.Instance is HashRandomWrapper) return true;

        __result = IRandom.Instance.Next(maxInt);

        return false;
    }

    [HarmonyPatch("Next", typeof(int))]
    [HarmonyPrefix]
    private static bool MaxNext([HarmonyArgument(0)] int maxInt, ref int __result)
    {
        if (IRandom.Instance is HashRandomWrapper) return true;

        __result = IRandom.Instance.Next(maxInt);

        return false;
    }

    [HarmonyPatch("Next", typeof(int), typeof(int))]
    [HarmonyPrefix]
    private static bool MinMaxNext([HarmonyArgument(0)] int minInt, [HarmonyArgument(1)] int maxInt, ref int __result)
    {
        if (IRandom.Instance is HashRandomWrapper) return true;

        __result = IRandom.Instance.Next(minInt, maxInt);

        return false;
    }

    internal static void __EHRStaticCallback_143(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        int __ehrp0 = __ehrFrame.GetArgument<int>(0);
        int __ehrp1 = __ehrFrame.GetResult<int>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = FastNext(__ehrp0, ref __ehrp1);
        }
        finally
        {
            __ehrFrame.Result = __ehrp1;
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }


    internal static void __EHRStaticCallback_144(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        int __ehrp0 = __ehrFrame.GetArgument<int>(0);
        int __ehrp1 = __ehrFrame.GetResult<int>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = MaxNext(__ehrp0, ref __ehrp1);
        }
        finally
        {
            __ehrFrame.Result = __ehrp1;
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }


    internal static void __EHRStaticCallback_145(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        int __ehrp0 = __ehrFrame.GetArgument<int>(0);
        int __ehrp1 = __ehrFrame.GetArgument<int>(1);
        int __ehrp2 = __ehrFrame.GetResult<int>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = MinMaxNext(__ehrp0, __ehrp1, ref __ehrp2);
        }
        finally
        {
            __ehrFrame.Result = __ehrp2;
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}