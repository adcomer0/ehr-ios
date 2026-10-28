using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
namespace EHR.Generated;
[StructLayout(LayoutKind.Sequential)] internal unsafe struct SourceComponentNativeV1
{
 internal uint Version,Bytes;
 internal delegate* unmanaged[Cdecl]<uint,int> RegisterType;
 internal delegate* unmanaged[Cdecl]<uint,ulong*,int> TypeClass;
 internal delegate* unmanaged[Cdecl]<uint,ulong,ulong*,ulong*,ulong*,int> Add;
 internal delegate* unmanaged[Cdecl]<uint,ulong,ulong*,int> Lookup;
 internal delegate* unmanaged[Cdecl]<ulong,ulong*,int> Weak;
 internal delegate* unmanaged[Cdecl]<ulong,int*,int> WeakAlive;
}
[StructLayout(LayoutKind.Sequential)] internal unsafe struct SourceComponentCallbacksV1
{
 internal uint Version,Bytes;
 internal delegate* unmanaged[Cdecl]<uint,ulong,ulong*,int> Create;
 internal delegate* unmanaged[Cdecl]<ulong,uint,int> Dispatch;
 internal delegate* unmanaged[Cdecl]<ulong,int> Release;
 internal delegate* unmanaged[Cdecl]<uint*,int> Count;
}
internal static unsafe class SourceComponentRuntime
{
 private static SourceComponentNativeV1 host;
 private static bool bound;
 private static readonly SourceStateRegistry states=new();
 internal static string? LastError{get;private set;}
 internal static void Ready(){FacadeRuntime.RequireReady();if(!bound)throw new RuntimeGatewayException(1,"source component table not bound");}
 internal static void Register(Type type){Ready();FacadeRuntime.Require(host.RegisterType(SourceComponentCatalog.TypeId(type)),"register exact source component");}
 internal static object Add(Type type,RuntimeObject? owner=null)
 {
  Ready();uint id=SourceComponentCatalog.TypeId(type);Register(type);ulong state=0,component=0,exception=0;
  int status=host.Add(id,owner?.Token??0,&state,&component,&exception);
  using var owned=new RuntimeObject(component);
  if(status!=0||exception!=0){FacadeRuntime.CheckManaged(status,exception,"add source component");}
  var value=states.Find(state).Source;
  if(!type.IsInstanceOfType(value))throw new RuntimeGatewayException(5,"source component factory type mismatch");
  return value;
 }
 internal static object? Lookup(Type type,RuntimeObject owned)
 {
  using(owned){Ready();if(owned.Token==0)return null;ulong state=0;
   FacadeRuntime.Require(host.Lookup(SourceComponentCatalog.TypeId(type),owned.Token,&state),"source component identity lookup");
   var source=states.Find(state).Source;return type.IsInstanceOfType(source)?source:throw new RuntimeGatewayException(5,"source component CLR type mismatch");}
 }
 internal static NativeCallbackScope ScopeFor(RuntimeObject source)=>(NativeCallbackScope)states.CleanupFor(source);
 internal static ulong NativeClass(Type type){Ready();ulong klass=0;FacadeRuntime.Require(host.TypeClass(SourceComponentCatalog.TypeId(type),&klass),"source component metadata class");return klass;}
 internal static bool IsSource(Type type)=>SourceComponentCatalog.IsSource(type);
 internal static int ActiveCount=>states.Count;
 [UnmanagedCallersOnly(EntryPoint="ehr_generated_source_component_profile_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
 internal static int Profile(uint* mask)
 {
  if(mask==null)return 4;*mask=0;
  try{Ready();
#if EHR_ALL_SOURCE_COMPONENTS
   *mask=255;
#else
   *mask=129;
#endif
   return 0;}
  catch(Exception error){return Contain(error);}
 }
 private static void ReleaseOwned(ulong token){if(token!=0)new RuntimeObject(token).Dispose();}
 private static int Contain(Exception error){LastError=error.ToString();if(error is NativeGameException native)native.Dispose();return error is RuntimeGatewayException gateway?gateway.Status:6;}
 [UnmanagedCallersOnly(EntryPoint="ehr_generated_bind_source_components")]
 internal static int Bind(SourceComponentNativeV1* table,nuint bytes,SourceComponentCallbacksV1* callbacks,nuint callbackBytes)
 {
  if(table==null||callbacks==null||bytes!=(nuint)sizeof(SourceComponentNativeV1)||callbackBytes!=(nuint)sizeof(SourceComponentCallbacksV1))return 4;
  *callbacks=default;
  if(table->Version!=1||table->Bytes!=sizeof(SourceComponentNativeV1)||table->RegisterType==null||table->TypeClass==null||table->Add==null||table->Lookup==null||table->Weak==null||table->WeakAlive==null)return 4;
  try{FacadeRuntime.RequireReady();if(bound)return 4;host=*table;bound=true;SourceComponentCatalog.RegisterCodecs();
   *callbacks=new(){Version=1,Bytes=(uint)sizeof(SourceComponentCallbacksV1),Create=&Create,Dispatch=&Dispatch,Release=&Release,Count=&Count};return 0;}
  catch(Exception error){return Contain(error);}
 }
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]
 private static int Create(uint type,ulong ownedWeakSelf,ulong* state)
 {
  if(state==null){if(ownedWeakSelf!=0)try{ReleaseOwned(ownedWeakSelf);}catch{}return 4;}*state=0;
  bool contextOwned=false;
  try{Ready();SourceComponentCatalog.RequireSupported(type);using var context=SourceComponentConstruction.Begin(ownedWeakSelf);contextOwned=true;
   var source=SourceComponentCatalog.Create(type);var cleanup=new NativeCallbackScope();
   ulong created=0;
   try{created=states.Add(type,source,message=>SourceComponentCatalog.Dispatch(type,source,message),cleanup);context.Commit(source);*state=created;return 0;}
   catch{if(created!=0)states.Destroy(created,false);else cleanup.Dispose();throw;}}
  catch(Exception error){if(!contextOwned&&ownedWeakSelf!=0)try{ReleaseOwned(ownedWeakSelf);}catch{}return Contain(error);}
 }
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]
 private static int Dispatch(ulong state,uint message){try{Ready();states.Event(state,message);return 0;}catch(Exception error){return Contain(error);}}
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]
 private static int Release(ulong state){try{Ready();states.Destroy(state,false);return 0;}catch(Exception error){return Contain(error);}}
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]
 private static int Count(uint* count){if(count==null)return 4;*count=0;try{Ready();*count=(uint)states.Count;return 0;}catch(Exception error){return Contain(error);}}
}
