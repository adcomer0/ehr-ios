using System;
using System.Runtime.InteropServices;

namespace EHR.Generated;

// Explicit source adaptation for the two pinned EHR MoveNext callbacks. The
// source's desktop wrapper reflects over generated CLR properties, whereas the
// iOS receiver is a proxy for an actual IL2CPP nested iterator. These exact fields
// are read/written through public metadata APIs, never through guessed offsets.
internal sealed class NativeStateMachineView<T>
{
    private readonly RuntimeObject iterator;
    private readonly ulong stateField,ownerField;
    internal NativeStateMachineView(object instance)
    {
        if(instance is not RuntimeObject value || value.Token==0)
            throw new ArgumentException("An actual native iterator proxy is required",nameof(instance));
        ulong owner=ElementCodecs.Get<T>().NativeClass();
        string name;
        if(owner==FacadeRuntime.Class("Assembly-CSharp.dll","","AirshipExileController"))
            name="AirshipExileController+<WrapUpAndSpawn>d__11";
        else if(owner==FacadeRuntime.Class("Assembly-CSharp.dll","","IntroCutscene"))
            name="IntroCutscene+<ShowRole>d__40";
        else throw new NotSupportedException("No pinned native state-machine owner mapping for source type");
        ulong expected=FacadeRuntime.Class("Assembly-CSharp.dll","",name);
        if(FacadeRuntime.ObjectClass(value)!=expected)
            throw new RuntimeGatewayException(5,"native state-machine receiver must match exact nested class");
        iterator=value;
        stateField=FacadeRuntime.ResolveField(expected,"<>1__state","System.Int32");
        ownerField=FacadeRuntime.ResolveField(expected,"<>4__this",name[..name.IndexOf('+')]);
    }
    internal T Instance=>(T)ElementCodecs.Get<T>().Read(FacadeRuntime.ReadResolvedField(ownerField,iterator))!;
    internal int State
    {
        get{using var value=FacadeRuntime.ReadResolvedField(stateField,iterator);return FacadeRuntime.ReadValue<int>(value);}
        set
        {
            using var box=ElementCodecs.Get<int>().Box(value);
            FacadeRuntime.WriteResolvedField(stateField,iterator,NativeValues.Argument(box));
        }
    }
}

internal static unsafe class NativeStateMachineSelfTest
{
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_state_machine_self_test")]
    internal static int Run(int* proof,nuint count)
    {
        if(proof==null||count!=7)return 4;for(int i=0;i<7;++i)proof[i]=0;
        try
        {
            using var initial=ElementCodecs.Get<int>().Box(61);
            ulong airship=FacadeRuntime.Class("Assembly-CSharp.dll","","AirshipExileController+<WrapUpAndSpawn>d__11");
            ulong intro=FacadeRuntime.Class("Assembly-CSharp.dll","","IntroCutscene+<ShowRole>d__40");
            using var first=LiveReflection.Construct(airship,[initial]);
            using var second=LiveReflection.Construct(intro,[initial]);
            var a=new NativeStateMachineView<AirshipExileController>(first);
            var b=new NativeStateMachineView<IntroCutscene>(second);
            proof[2]=a.State==61&&b.State==61?1:0;
            a.State=-12;b.State=999;
            proof[3]=a.State==-12&&b.State==999?1:0;
            proof[4]=a.Instance is null&&b.Instance is null?1:0;
            try{_=new NativeStateMachineView<IntroCutscene>(first);}
            catch(RuntimeGatewayException error)when(error.Status==5){proof[5]=1;}
            try{_=new NativeStateMachineView<Il2CppSystem.Object>(first);}
            catch(NotSupportedException){proof[6]=1;}
            proof[0]=proof[2]==1&&proof[3]==1&&proof[4]==1&&proof[5]==1&&proof[6]==1?1:0;
            return proof[1]=proof[0]==1?0:5;
        }
        catch(RuntimeGatewayException error){return proof[1]=error.Status;}catch{return proof[1]=6;}
    }
}
