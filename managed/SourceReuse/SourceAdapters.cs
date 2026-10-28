using System;

// Compile adapters for the two linked original source files. No Harmony runtime,
// game assembly, BepInEx loader, injected class, or runtime detour is included.
namespace HarmonyLib
{
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = true)]
    internal sealed class HarmonyPatch : Attribute
    {
        public HarmonyPatch(Type type, string name) { }
    }
}

internal static class Constants
{
    public static int GetBroadcastVersion() => EHRManagedGateway.GetBroadcastVersion();
    public static bool IsVersionModded() => throw new NotSupportedException("Game facade is not bound");
}

namespace EHR
{
    internal static class GameStates
    {
        [ThreadStatic] internal static bool Online;
        [ThreadStatic] internal static bool Local;
        public static bool IsOnlineGame => Online;
        public static bool IsLocalGame => Local;
    }
    internal static class Logger
    {
        public static void Info(string message, string source) { }
    }
}
