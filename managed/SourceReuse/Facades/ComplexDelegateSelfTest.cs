using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class ComplexDelegateSelfTest
{
 private static readonly BindingSpec SceneHandle=new("UnityEngine.CoreModule.dll","UnityEngine.SceneManagement","Scene","m_Handle",false,true,"System.Int32",[]);
 private sealed class Effects
 {
  internal bool Triple;internal int First,Second;internal UnityEngine_SceneManagement_Scene? Escaped;internal int Mode;
  internal void Hit(string? text,int value,CosmeticsLayer__CosmeticKind kind){Triple=text=="own\0λ"&&value==-77&&(int)kind==3;First+=value;}
  internal void Other(string? text,int value,CosmeticsLayer__CosmeticKind kind)=>Second+=value;
 }
 private static int Handle(UnityEngine_SceneManagement_Scene value){using var result=FacadeRuntime.ReadField(SceneHandle,value.NativeBox.Token);return FacadeRuntime.ReadValue<int>(result);}
 [UnmanagedCallersOnly(EntryPoint="ehr_complex_delegate_self_test",CallConvs=[typeof(CallConvCdecl)])]
 internal static int Run(uint* p,nuint count)
 {
  if(p==null||count!=20)return 4;for(int i=0;i<20;++i)p[i]=0;
  var roots=new List<RuntimeObject>();var tokens=new List<ulong>();var closes=new List<System.Action>();
  T Keep<T>(T value)where T:RuntimeObject{roots.Add(value);tokens.Add(value.Token);return value;}
  var effects=new Effects();
  try
  {
   ComplexDelegateRuntime.RequireMain();p[18]=1;
   var triple=Keep(new Il2CppSystem.Action<string?,int,CosmeticsLayer__CosmeticKind>(effects.Hit));closes.Add(triple.Close);
   triple.Invoke("own\0λ",-77,(CosmeticsLayer__CosmeticKind)3);p[2]=effects.Triple?1u:0u;
   p[18]=2;using var constructed=LiveReflection.Construct(FacadeRuntime.Class("mscorlib.dll","System","Object"),[]);
   var original=Keep(new Il2CppSystem.Object(constructed.Detach()));
   var func=Keep(new Il2CppSystem.Func<Il2CppSystem.Object?,bool>(value=>{if(value is null)return false;bool same=NativeLifetime.Same(original,value);value.Dispose();return same;}));closes.Add(func.Close);
   p[3]=func.Invoke(original)?1u:0u;p[4]=!func.Invoke(null)?1u:0u;
   var network=Keep(new Il2CppSystem.Func<NetworkedPlayerInfo?,bool>(static value=>value is null));closes.Add(network.Close);p[5]=network.Invoke(null)?1u:0u;
   p[18]=3;
   var scene=default(UnityEngine_SceneManagement_Scene);Keep(scene.NativeBox);int handle=42;NativeArgument argument=FacadeRuntime.Value(&handle,"System.Int32");FacadeRuntime.WriteField(SceneHandle,scene.NativeBox.Token,argument);
   var sceneAction=Keep(new UnityEngine_Events_UnityAction<UnityEngine_SceneManagement_Scene,UnityEngine_SceneManagement_LoadSceneMode>((value,mode)=>{effects.Escaped=value;effects.Mode=(int)mode;}));closes.Add(sceneAction.Close);
   sceneAction.Invoke(scene,(UnityEngine_SceneManagement_LoadSceneMode)1);
   p[6]=effects.Escaped.HasValue&&Handle(effects.Escaped.Value)==42?1u:0u;p[7]=effects.Mode==1?1u:0u;if(effects.Escaped.HasValue)Keep(effects.Escaped.Value.NativeBox);
   p[18]=4;var error=Keep(new Il2CppSystem.Func<Il2CppSystem.Object?,bool>(static _=>throw new InvalidOperationException("own Func failure")));closes.Add(error.Close);
   p[8]=!error.Invoke(null)&&ComplexDelegateRuntime.Status(error.Registration)==6?1u:0u;
   var retained=Keep(FacadeRuntime.Retain(func));func.Dispose();p[9]=ComplexDelegateRuntime.InvokeFunction<Il2CppSystem.Object?,bool>(retained.Token,original)?1u:0u;
   func.Close();p[10]=!ComplexDelegateRuntime.InvokeFunction<Il2CppSystem.Object?,bool>(retained.Token,original)?1u:0u;
   p[18]=5;
   var other=Keep(new Il2CppSystem.Action<string?,int,CosmeticsLayer__CosmeticKind>(effects.Other));closes.Add(other.Close);
   var combined=Keep((triple+other)??throw new InvalidOperationException("missing combined Action3"));
   var fresh=Keep(new Il2CppSystem.Action<string?,int,CosmeticsLayer__CosmeticKind>(effects.Hit));
   var removed=Keep((combined-fresh)??throw new InvalidOperationException("fresh Action3 remove returned null"));removed.Invoke(null,7,default);
   p[11]=effects.First==-77&&effects.Second==7&&triple.Registration==fresh.Registration?1u:0u;
   p[18]=6;var order=new List<int>();using(var scope=new NativeCallbackScope()){scope.Own(()=>order.Add(1),()=>order.Add(3));scope.Own(()=>order.Add(2),()=>order.Add(4));scope.Dispose();scope.Dispose();}
   p[12]=order.Count==4&&order[0]==2&&order[1]==1&&order[2]==4&&order[3]==3?1u:0u;
   int cleaned=0;bool failed=false;var faulty=new NativeCallbackScope();faulty.Own(()=>throw new InvalidOperationException("own unsubscribe failure"),()=>++cleaned);faulty.Own(()=>++cleaned,()=>++cleaned);try{faulty.Dispose();}catch(InvalidOperationException){failed=true;}faulty.Dispose();
   p[13]=failed&&cleaned==3?1u:0u;
   p[18]=7;foreach(var close in closes)close();foreach(var root in roots)root.Dispose();p[14]=(uint)ComplexDelegateRuntime.SourceCount;
   bool released=true;foreach(var token in tokens)released&=!FacadeRuntime.TokenIsValid(token);p[15]=released?1u:0u;
   bool pass=true;for(int i=2;i<=13;++i)pass&=p[i]==1;p[0]=pass&&p[14]==0&&p[15]==1?1u:0u;return (int)(p[1]=p[0]==1?0u:5u);
  }
  catch(NativeGameException error){try{error.Dispose();}catch{}return (int)(p[1]=6);}
  catch(RuntimeGatewayException error){p[19]=(uint)NativeMethods.LastLookupStep;return (int)(p[1]=(uint)error.Status);}
  catch{return (int)(p[1]=4);}
  finally{foreach(var close in closes)try{close();}catch{}foreach(var root in roots)try{root.Dispose();}catch{}if(effects.Escaped.HasValue)try{effects.Escaped.Value.NativeBox.Dispose();}catch{}}
 }
}
