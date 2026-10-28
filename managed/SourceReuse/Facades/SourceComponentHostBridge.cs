using System;
using System.Runtime.InteropServices;
namespace EHR.SourceHost;
// Pass these exact callbacks into SourceHostOptions only after native class
// registration + source callback binding, all existing gateway tables, iterator
// scheduling, delegate families and the touch backend are ready. This does not
// create a plugin, invoke Main.Load, or claim that startup has completed.
public static class SourceComponentHostBridge
{
 public static object AddComponent(Type type)=>Generated.SourceComponentRuntime.Add(type);
 public static void RegisterComponent(Type type)=>Generated.SourceComponentRuntime.Register(type);
}
internal static class SourceComponentProfile
{
 [UnmanagedCallersOnly(EntryPoint="ehr_generated_source_component_profile")]
 internal static uint Profile()
 {
#if EHR_ALL_SOURCE_COMPONENTS
  return 255;
#else
  return 129;
#endif
 }
}
