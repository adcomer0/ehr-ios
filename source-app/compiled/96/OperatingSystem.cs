using UnityEngine;

namespace EHR;

public static class OperatingSystem
{
    private static readonly bool Windows = Application.platform == RuntimePlatform.WindowsPlayer;
    private static readonly bool Android = Application.platform == RuntimePlatform.Android;
    private static readonly bool IOS = Application.platform == RuntimePlatform.IPhonePlayer;

    public static bool IsWindows() => Windows;
    public static bool IsAndroid() => Android;
    public static bool IsIOS() => IOS;
}