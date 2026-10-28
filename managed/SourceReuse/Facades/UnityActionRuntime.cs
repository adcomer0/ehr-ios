// Original live UnityAction/event adapter. The event used by the proof is a
// separately constructed real ButtonClickedEvent; no scene button is mutated.
using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
namespace EHR.Generated;

public unsafe partial class UnityEngine_Events_UnityAction
{
    private ulong sourceRegistration;
    private bool sourceClosed;
    public UnityEngine_Events_UnityAction(System.Action source):this(ActionRuntime.Create(source,true)){}
    private UnityEngine_Events_UnityAction(ActionCreation created):base(created.Root){sourceRegistration=created.Registration;}
    public void Invoke(){using var result=FacadeRuntime.Invoke(new("UnityEngine.CoreModule.dll","UnityEngine.Events","UnityAction","Invoke",false,false,"System.Void",[]),Token,null,0);}
    public void Close()
    {
        if(sourceClosed||sourceRegistration==0)return;
        ActionRuntime.Close(sourceRegistration);sourceClosed=true;
    }
}
public unsafe partial class UnityEngine_Events_UnityEvent
{
    public void RemoveListener(UnityEngine_Events_UnityAction? call)
    {
        NativeArgument argument=FacadeRuntime.Reference(call);
        using var result=FacadeRuntime.Invoke(new("UnityEngine.CoreModule.dll","UnityEngine.Events","UnityEvent","RemoveListener",false,false,"System.Void",["UnityEngine.Events.UnityAction"]),Token,&argument,1);
    }
}
[StructLayout(LayoutKind.Sequential)]
internal struct UnityActionProofV1
{
    internal uint AbiVersion,ByteSize,Pass,Status;
    internal uint FirstEffects,SecondEffects,RemoveExactListener,ProxyDisposePreservesListener;
    internal uint ClosedListenerNoop,SourceEntriesAfter,RootsReleased,Reserved;
}
internal static unsafe class UnityActionRuntime
{
    private sealed class Effects {internal uint First,Second;}
    [UnmanagedCallersOnly(EntryPoint="ehr_unity_action_self_test",CallConvs=[typeof(CallConvCdecl)])]
    internal static int SelfTest(UnityActionProofV1* proof,nuint bytes)
    {
        if(proof==null||bytes!=(nuint)sizeof(UnityActionProofV1))return 4;
        *proof=new(){AbiVersion=1,ByteSize=(uint)sizeof(UnityActionProofV1)};
        UnityEngine_Events_UnityAction? first=null,second=null,removal=null;
        UnityEngine_UI_Button__ButtonClickedEvent? clicked=null;
        try
        {
            ActionRuntime.RequireMain();var effects=new Effects();
            clicked=new();first=new(()=>++effects.First);second=new(()=>++effects.Second);
            ulong eventToken=clicked.Token,firstToken=first.Token,secondToken=second.Token;
            using(var retained=FacadeRuntime.Retain(first))removal=new(retained.Detach());
            ulong removalToken=removal.Token;
            clicked.AddListener(first);clicked.AddListener(second);clicked.Invoke();
            first.Dispose();clicked.Invoke();
            proof->ProxyDisposePreservesListener=effects.First==2&&effects.Second==2?1u:0u;
            // Remove the very same native delegate through a different owning
            // facade. Its unique target prevents removal of the other listener.
            clicked.RemoveListener(removal);clicked.Invoke();
            proof->RemoveExactListener=effects.First==2&&effects.Second==3?1u:0u;
            first.Close();second.Close();clicked.Invoke();
            proof->ClosedListenerNoop=effects.First==2&&effects.Second==3?1u:0u;
            clicked.RemoveAllListeners();
            first.Dispose();second.Dispose();removal.Dispose();clicked.Dispose();
            proof->FirstEffects=effects.First;proof->SecondEffects=effects.Second;
            proof->SourceEntriesAfter=(uint)ActionRuntime.SourceCount;
            proof->RootsReleased=!FacadeRuntime.TokenIsValid(eventToken)&&!FacadeRuntime.TokenIsValid(firstToken)&&
                !FacadeRuntime.TokenIsValid(secondToken)&&!FacadeRuntime.TokenIsValid(removalToken)?1u:0u;
            proof->Pass=proof->ProxyDisposePreservesListener==1&&proof->RemoveExactListener==1&&proof->ClosedListenerNoop==1&&
                proof->SourceEntriesAfter==0&&proof->RootsReleased==1?1u:0u;
            return proof->Pass==1?0:4;
        }
        catch(NativeGameException error){try{error.Dispose();}catch{}return (int)(proof->Status=6);}
        catch(RuntimeGatewayException error){return (int)(proof->Status=(uint)error.Status);}
        catch{return (int)(proof->Status=4);}
        finally
        {
            try{first?.Close();}catch{}try{second?.Close();}catch{}
            try{clicked?.RemoveAllListeners();}catch{}
            try{first?.Dispose();}catch{}try{second?.Dispose();}catch{}try{removal?.Dispose();}catch{}try{clicked?.Dispose();}catch{}
        }
    }
}
