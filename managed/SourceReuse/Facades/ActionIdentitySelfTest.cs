using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class ActionIdentitySelfTest
{
    private sealed class Effects
    {
        internal int First,Second;
        internal void Zero()=>++First;
        internal void OtherZero()=>++Second;
        internal void Int(int value)=>First+=value;
        internal void OtherInt(int value)=>Second+=value;
    }
    // Original isolated event only. No scene subscription or gameplay changes.
    [UnmanagedCallersOnly(EntryPoint="ehr_action_identity_self_test",CallConvs=[typeof(CallConvCdecl)])]
    internal static int Run(uint* output,nuint count)
    {
        if(output==null||count!=12)return 4;for(int i=0;i<12;++i)output[i]=0;
        var roots=new List<RuntimeObject>();var tokens=new List<ulong>();var closes=new List<System.Action>();
        UnityEngine_UI_Button__ButtonClickedEvent? clicked=null;
        T Keep<T>(T value,System.Action? close=null)where T:RuntimeObject{roots.Add(value);tokens.Add(value.Token);if(close!=null)closes.Add(close);return value;}
        try
        {
            ActionRuntime.RequireMain();TypedActionRuntime.RequireMain();var zero=new Effects();
            var first=Keep(new Il2CppSystem.Action(zero.Zero));closes.Add(first.Close);
            var second=Keep(new Il2CppSystem.Action(zero.OtherZero));closes.Add(second.Close);
            var combined=Keep((first+second)??throw new InvalidOperationException("missing combined delegate"));
            var fresh=Keep(new Il2CppSystem.Action(zero.Zero));
            var removed=Keep((combined-fresh)??throw new InvalidOperationException("fresh removal returned null"));removed.Invoke();
            output[2]=zero.First==0&&zero.Second==1?1u:0u;
            output[7]=first.Registration==fresh.Registration&&first.Registration!=second.Registration?1u:0u;
            fresh.Dispose();first.Invoke();output[5]=zero.First==1?1u:0u;
            var typedEffects=new Effects();
            var typed=Keep(new Il2CppSystem.Action<int>(typedEffects.Int));closes.Add(typed.Close);
            var otherTyped=Keep(new Il2CppSystem.Action<int>(typedEffects.OtherInt));closes.Add(otherTyped.Close);
            var typedCombined=Keep((typed+otherTyped)??throw new InvalidOperationException("missing typed combined delegate"));
            var freshTyped=Keep(new Il2CppSystem.Action<int>(typedEffects.Int));
            var typedRemoved=Keep((typedCombined-freshTyped)??throw new InvalidOperationException("fresh typed removal returned null"));typedRemoved.Invoke(3);
            output[3]=typedEffects.First==0&&typedEffects.Second==3&&typed.Registration==freshTyped.Registration?1u:0u;
            var unityEffects=new Effects();
            clicked=Keep(new UnityEngine_UI_Button__ButtonClickedEvent());
            var unity=Keep(new UnityEngine_Events_UnityAction(unityEffects.Zero));closes.Add(unity.Close);
            var otherUnity=Keep(new UnityEngine_Events_UnityAction(unityEffects.OtherZero));closes.Add(otherUnity.Close);
            clicked.AddListener(unity);clicked.AddListener(otherUnity);
            var freshUnity=Keep(new UnityEngine_Events_UnityAction(unityEffects.Zero));clicked.RemoveListener(freshUnity);clicked.Invoke();
            output[4]=unityEffects.First==0&&unityEffects.Second==1?1u:0u;
            freshTyped.Close();typed.Invoke(9);output[6]=typedEffects.First==0?1u:0u;
            clicked.RemoveAllListeners();foreach(var close in closes)close();foreach(var root in roots)root.Dispose();
            output[8]=(uint)ActionRuntime.SourceCount;output[9]=(uint)TypedActionRuntime.SourceCount;
            bool released=true;foreach(var token in tokens)released&=!FacadeRuntime.TokenIsValid(token);output[10]=released?1u:0u;
            output[0]=output[2]==1&&output[3]==1&&output[4]==1&&output[5]==1&&output[6]==1&&output[7]==1&&output[8]==0&&output[9]==0&&output[10]==1?1u:0u;
            return (int)(output[1]=output[0]==1?0u:5u);
        }
        catch(NativeGameException error){try{error.Dispose();}catch{}return (int)(output[1]=6);}
        catch(RuntimeGatewayException error){output[11]=(uint)NativeMethods.LastLookupStep;return (int)(output[1]=(uint)error.Status);}
        catch{return (int)(output[1]=4);}
        finally{try{clicked?.RemoveAllListeners();}catch{}foreach(var close in closes)try{close();}catch{}foreach(var root in roots)try{root.Dispose();}catch{}}
    }
}
