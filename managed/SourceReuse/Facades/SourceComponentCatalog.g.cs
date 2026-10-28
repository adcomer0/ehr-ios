// Generated from pinned EHR source declarations; no runtime reflection discovery.
using System;
using System.Runtime.CompilerServices;
namespace EHR.Generated;
internal static partial class SourceComponentCatalog
{
 internal static bool IsSource(Type type)=>TryTypeId(type,out _);
 internal static uint TypeId(Type type)=>TryTypeId(type,out var id)?id:throw new RuntimeGatewayException(7,"Uncompiled source component "+type.FullName);
 internal static bool TryTypeId(Type type,out uint id)
 {
  if(type==typeof(global::EHR.NativeProbes.StaticLifecycleProbe)){id=8;return true;}
  if(type==typeof(global::EHR.Coroutines)){id=1;return true;}
#if EHR_ALL_SOURCE_COMPONENTS
  if(type==typeof(global::EHR.ErrorText)){id=2;return true;}
  if(type==typeof(global::EHR.Patches.AbstractPagingBehaviour)){id=3;return true;}
  if(type==typeof(global::EHR.Patches.MeetingHudPagingBehaviour)){id=4;return true;}
  if(type==typeof(global::EHR.Patches.ShapeShifterPagingBehaviour)){id=5;return true;}
  if(type==typeof(global::EHR.Patches.VitalsPagingBehaviour)){id=6;return true;}
  if(type==typeof(global::EHR.ClientControlGUI)){id=7;return true;}
#endif
  id=0;return false;
 }
 internal static void RequireSupported(uint id)
 {
  if(id==1||id==8)return;
#if EHR_ALL_SOURCE_COMPONENTS
  if(id>=2&&id<=7)return;
#endif
  throw new RuntimeGatewayException(7,"Uncompiled source component TypeID "+id);
 }
 internal static RuntimeObject Create(uint id)=>id switch
 {
  1=>new global::EHR.Coroutines(),
  8=>new global::EHR.NativeProbes.StaticLifecycleProbe(),
#if EHR_ALL_SOURCE_COMPONENTS
  2=>new global::EHR.ErrorText(),
  3=>new global::EHR.Patches.AbstractPagingBehaviour(),
  4=>new global::EHR.Patches.MeetingHudPagingBehaviour(),
  5=>new global::EHR.Patches.ShapeShifterPagingBehaviour(),
  6=>new global::EHR.Patches.VitalsPagingBehaviour(),
  7=>new global::EHR.ClientControlGUI(),
#endif
  _=>throw new RuntimeGatewayException(7,"Uncompiled source factory")
 };
 internal static void Dispatch(uint id,RuntimeObject source,uint message)
 {
  if(id==8){((global::EHR.NativeProbes.StaticLifecycleProbe)source).Dispatch(message);return;}
  if(id==1){if(message==3)return;throw new RuntimeGatewayException(7,"Empty source Coroutines message");}
#if EHR_ALL_SOURCE_COMPONENTS
  switch(id)
  {
   case 2:
    switch(message)
    {
     case 1:Call2Awake((global::EHR.ErrorText)source);return;
     case 2:((global::EHR.ErrorText)source).Update();return;
     case 3:return;
     case 6:((global::EHR.ErrorText)source).LateUpdate();return;
     case 7:Call2FixedUpdate((global::EHR.ErrorText)source);return;
     default:throw new RuntimeGatewayException(7,"Uncompiled Unity message");
    }
   case 3:
    switch(message)
    {
     case 2:((global::EHR.Patches.AbstractPagingBehaviour)source).Update();return;
     case 3:return;
     case 5:((global::EHR.Patches.AbstractPagingBehaviour)source).Start();return;
     default:throw new RuntimeGatewayException(7,"Uncompiled Unity message");
    }
   case 4:
    switch(message)
    {
     case 2:((global::EHR.Patches.MeetingHudPagingBehaviour)source).Update();return;
     case 3:return;
     case 5:((global::EHR.Patches.MeetingHudPagingBehaviour)source).Start();return;
     default:throw new RuntimeGatewayException(7,"Uncompiled Unity message");
    }
   case 5:
    switch(message)
    {
     case 2:((global::EHR.Patches.ShapeShifterPagingBehaviour)source).Update();return;
     case 3:return;
     case 5:((global::EHR.Patches.ShapeShifterPagingBehaviour)source).Start();return;
     default:throw new RuntimeGatewayException(7,"Uncompiled Unity message");
    }
   case 6:
    switch(message)
    {
     case 2:((global::EHR.Patches.VitalsPagingBehaviour)source).Update();return;
     case 3:return;
     case 5:((global::EHR.Patches.VitalsPagingBehaviour)source).Start();return;
     default:throw new RuntimeGatewayException(7,"Uncompiled Unity message");
    }
   case 7:
    switch(message)
    {
     case 1:Call7Awake((global::EHR.ClientControlGUI)source);return;
     case 3:Call7OnDestroy((global::EHR.ClientControlGUI)source);return;
     case 8:Call7OnGUI((global::EHR.ClientControlGUI)source);return;
     default:throw new RuntimeGatewayException(7,"Uncompiled Unity message");
    }
  }
#endif
  throw new RuntimeGatewayException(7,"Unknown source component callback");
 }
#if EHR_ALL_SOURCE_COMPONENTS
 [UnsafeAccessor(UnsafeAccessorKind.Method,Name="Awake")] private static extern void Call2Awake(global::EHR.ErrorText self);
 [UnsafeAccessor(UnsafeAccessorKind.Method,Name="FixedUpdate")] private static extern void Call2FixedUpdate(global::EHR.ErrorText self);
 [UnsafeAccessor(UnsafeAccessorKind.Method,Name="Awake")] private static extern void Call7Awake(global::EHR.ClientControlGUI self);
 [UnsafeAccessor(UnsafeAccessorKind.Method,Name="OnDestroy")] private static extern void Call7OnDestroy(global::EHR.ClientControlGUI self);
 [UnsafeAccessor(UnsafeAccessorKind.Method,Name="OnGUI")] private static extern void Call7OnGUI(global::EHR.ClientControlGUI self);
#endif
}
