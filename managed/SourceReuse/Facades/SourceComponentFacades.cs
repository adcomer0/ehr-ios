using System;
namespace EHR.Generated;
internal sealed class SourceComponentCodec(Type type):IElementCodec
{
 public ulong NativeClass()=>SourceComponentRuntime.NativeClass(type);
 public object? Read(RuntimeObject owned)=>SourceComponentRuntime.Lookup(type,owned);
 public RuntimeObject Box(object? source)=>source is null?new(0):FacadeRuntime.Retain((RuntimeObject)source);
}
internal static partial class SourceComponentCatalog
{
 internal static void RegisterCodecs()
 {
  ElementCodecs.Register<EHR.Coroutines>(new SourceComponentCodec(typeof(EHR.Coroutines)));
  ElementCodecs.Register<EHR.NativeProbes.StaticLifecycleProbe>(new SourceComponentCodec(typeof(EHR.NativeProbes.StaticLifecycleProbe)));
#if EHR_ALL_SOURCE_COMPONENTS
  ElementCodecs.Register<EHR.ErrorText>(new SourceComponentCodec(typeof(EHR.ErrorText)));
  ElementCodecs.Register<EHR.Patches.AbstractPagingBehaviour>(new SourceComponentCodec(typeof(EHR.Patches.AbstractPagingBehaviour)));
  ElementCodecs.Register<EHR.Patches.MeetingHudPagingBehaviour>(new SourceComponentCodec(typeof(EHR.Patches.MeetingHudPagingBehaviour)));
  ElementCodecs.Register<EHR.Patches.ShapeShifterPagingBehaviour>(new SourceComponentCodec(typeof(EHR.Patches.ShapeShifterPagingBehaviour)));
  ElementCodecs.Register<EHR.Patches.VitalsPagingBehaviour>(new SourceComponentCodec(typeof(EHR.Patches.VitalsPagingBehaviour)));
  ElementCodecs.Register<EHR.ClientControlGUI>(new SourceComponentCodec(typeof(EHR.ClientControlGUI)));
#endif
 }
}
internal static unsafe class SourceComponentFacades
{
 internal static T? Get<T>(RuntimeObject receiver,bool gameObject) where T:RuntimeObject
 {
  SourceComponentRuntime.Ready();using var type=LiveCollections.TypeObject(SourceComponentRuntime.NativeClass(typeof(T)));
  NativeArgument arg=FacadeRuntime.Reference(type);
  var spec=new BindingSpec("UnityEngine.CoreModule.dll","UnityEngine",gameObject?"GameObject":"Component","GetComponent",false,false,"UnityEngine.Component",["System.Type"]);
  var result=FacadeRuntime.Invoke(spec,receiver.Token,&arg,1);
  return (T?)SourceComponentRuntime.Lookup(typeof(T),result);
 }
}
