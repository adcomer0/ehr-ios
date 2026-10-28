// Compile-only unrelated surfaces for the original owned fixture. Every method
// throws if accidentally reached; no game declarations or behavior are copied.
using System;
internal static class Constants { internal static int GetBroadcastVersion() => throw new NotSupportedException("unavailable in original-route fixture"); }
namespace EHR.Generated
{
    internal static class GeneratedBindings { internal static readonly BindingSpec[] All = []; }
    internal static class LiveReflection { internal static void InitializeClass(ulong _) => throw new NotSupportedException(); }
    internal sealed class UnavailableCodec { internal ulong NativeClass() => throw new NotSupportedException(); }
    internal static class ElementCodecs { internal static UnavailableCodec Get<T>() => throw new NotSupportedException(); }
    internal static class NativeConstructors { internal static ulong Create(ulong _, ReadOnlySpan<ulong> __, RuntimeObject?[] ___) => throw new NotSupportedException(); }
    internal static class NativeTypeNames { internal static string RuntimeName(string _) => throw new NotSupportedException(); }
}
