using HarmonyLib;
using Hazel;

namespace EHR;

// There is no efficient way to get the last element of a Queue.
// So instead we keep track of the most recent incoming network transform data manually.

[HarmonyPatch(typeof(CustomNetworkTransform))]
public static class CustomNetworkTransformHelper
{
    public static readonly Vector2[] CurrentPosition = new Vector2[256];
    
    [HarmonyPatch("Awake"), HarmonyPostfix]
    public static void Awake(CustomNetworkTransform __instance)
    {
        CurrentPosition[__instance.myPlayer.PlayerId] = __instance.transform.position;
    }

    [HarmonyPatch("Deserialize"), HarmonyPrefix]
    public static void Deserialize(CustomNetworkTransform __instance, MessageReader reader, bool initialState)
    {
        if (__instance.isPaused) return;
        
        MessageReader subReader = MessageReader.Get(reader);

        try
        {
            if (initialState)
            {
                subReader.ReadUInt16();
                CurrentPosition[__instance.myPlayer.PlayerId] = NetHelpers.ReadVector2(subReader);
            }
            else
            {
                if (__instance.AmOwner) return;
                
                ushort num1 = subReader.ReadUInt16();
                int num2 = subReader.ReadPackedInt32();

                for (int index = 0; index < num2; ++index)
                {
                    ushort newSid = (ushort)(num1 + (uint) index);
                    Vector2 pt = NetHelpers.ReadVector2(subReader);
                    
                    if (NetHelpers.SidGreaterThan(newSid, __instance.lastSequenceId))
                        CurrentPosition[__instance.myPlayer.PlayerId] = pt;
                }
            }
        }
        finally
        {
            subReader.Recycle();
        }
    }

    internal static void __EHRStaticCallback_18(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        CustomNetworkTransform __ehrp0 = __ehrFrame.GetInstance<CustomNetworkTransform>();
        try
        {
            Awake(__ehrp0);
        }
        finally
        {
        }
    }


    internal static void __EHRStaticCallback_19(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        CustomNetworkTransform __ehrp0 = __ehrFrame.GetInstance<CustomNetworkTransform>();
        MessageReader __ehrp1 = __ehrFrame.GetArgument<MessageReader>("reader");
        bool __ehrp2 = __ehrFrame.GetArgument<bool>("initialState");
        try
        {
            Deserialize(__ehrp0, __ehrp1, __ehrp2);
        }
        finally
        {
        }
    }

}