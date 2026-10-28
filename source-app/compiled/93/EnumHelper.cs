using System;

namespace EHR;

public static class EnumHelper
{
    public static T[] GetValues<T>() where T : struct, Enum => Enum.GetValues<T>();
    public static string[] GetNames<T>() where T : struct, Enum => Enum.GetNames<T>();
}