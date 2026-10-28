using System;
namespace EHR.Generated;
// Exact live Unity event API, never a fabricated SceneManager declaration.
// Method lookup uses real closed native parameter classes and validates exact
// declaring class, return class and staticness via existing reflection gateway.
internal static unsafe class SourceSceneEvents
{
 internal static void Add(global::EHR.Generated.UnityEngine_Events_UnityAction<UnityEngine_SceneManagement_Scene,UnityEngine_SceneManagement_LoadSceneMode> callback)=>Change(callback,true);
 internal static void Remove(global::EHR.Generated.UnityEngine_Events_UnityAction<UnityEngine_SceneManagement_Scene,UnityEngine_SceneManagement_LoadSceneMode> callback)=>Change(callback,false);
 private static void Change(global::EHR.Generated.UnityEngine_Events_UnityAction<UnityEngine_SceneManagement_Scene,UnityEngine_SceneManagement_LoadSceneMode> callback,bool add)
 {
  var owner=FacadeRuntime.Class("UnityEngine.CoreModule.dll","UnityEngine.SceneManagement","SceneManager");
  ulong carrier=ComplexDelegateRuntime.SceneClass<UnityEngine_SceneManagement_Scene,UnityEngine_SceneManagement_LoadSceneMode>();
  ulong method=NativeMethods.Lookup(owner,add?"add_sceneLoaded":"remove_sceneLoaded",[carrier],FacadeRuntime.Class("mscorlib.dll","System","Void"),true);
  NativeArgument arg=FacadeRuntime.Reference(callback);using var result=FacadeRuntime.InvokeResolved(method,0,&arg,1);
 }
 internal static global::EHR.Generated.UnityEngine_Events_UnityAction<UnityEngine_SceneManagement_Scene,UnityEngine_SceneManagement_LoadSceneMode> Own(RuntimeObject owner,System.Action<UnityEngine_SceneManagement_Scene,UnityEngine_SceneManagement_LoadSceneMode> source,System.Action? hidden=null)
 {
  var scope=SourceComponentRuntime.ScopeFor(owner);
  var callback=new global::EHR.Generated.UnityEngine_Events_UnityAction<UnityEngine_SceneManagement_Scene,UnityEngine_SceneManagement_LoadSceneMode>(source);
  bool subscribed=false;
  try{Add(callback);subscribed=true;scope.Own(()=>{try{Remove(callback);}finally{hidden?.Invoke();}},()=>{try{callback.Close();}finally{callback.Dispose();}});return callback;}
  catch{try{if(subscribed)Remove(callback);}finally{try{callback.Close();}finally{callback.Dispose();}}throw;}
 }
}
