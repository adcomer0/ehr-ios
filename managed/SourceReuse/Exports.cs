using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

public static unsafe class Exports {
 [UnmanagedCallersOnly(EntryPoint="ehr_managed_abi_version")]
 public static int Version() => 1;
 [UnmanagedCallersOnly(EntryPoint="ehr_managed_dynamic_code_flags")]
 public static int DynamicFlags() => (RuntimeFeature.IsDynamicCodeSupported ? 1 : 0) | (RuntimeFeature.IsDynamicCodeCompiled ? 2 : 0);
 [UnmanagedCallersOnly(EntryPoint="ehr_source_integer_option")]
 public static int IntegerOption(int min,int max,int step,int index) {
  try { return new EHR.IntegerValueRule(min,max,step).GetValueByIndex(index); }
  catch { return int.MinValue; }
 }
 [UnmanagedCallersOnly(EntryPoint="ehr_source_float_option")]
 public static float FloatOption(float min,float max,float step,int index) {
  try { return new EHR.FloatValueRule(min,max,step).GetValueByIndex(index); }
  catch { return float.NaN; }
 }
 [UnmanagedCallersOnly(EntryPoint="ehr_managed_native_roundtrip")]
 public static long NativeRoundTrip(delegate* unmanaged[Cdecl]<uint,long,long> native,long value) {
  if (native == null) return long.MinValue;
  try { return native(0xE801,value) + new EHR.IntegerValueRule(0,90,1).GetValueByIndex(99); }
  catch { return long.MinValue; }
 }
}
