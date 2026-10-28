// Source-namespace counterpart of the actual tested native Action-family bridge.
// Generated SourceSurface supplies the owning-token constructor/base/codec.
using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using EHR.Generated;
namespace UnityEngine.Events
{
    public unsafe partial class UnityAction
    {
        private ulong sourceRegistration;
        private bool sourceClosed;
        public UnityAction(System.Action source):this(ActionRuntime.Create(source,true)){}
        private UnityAction(ActionCreation created):base(created.Root){sourceRegistration=created.Registration;}
        public static implicit operator UnityAction?(System.Action? source)=>source is null?null:new(source);
        public void Invoke(){using var result=FacadeRuntime.Invoke(new("UnityEngine.CoreModule.dll","UnityEngine.Events","UnityAction","Invoke",false,false,"System.Void",[]),Token,null,0);}
        public void Close()
        {
            if(sourceClosed||sourceRegistration==0)return;
            ActionRuntime.Close(sourceRegistration);sourceClosed=true;
        }
    }
    public unsafe partial class UnityEvent
    {
        public void RemoveListener(UnityAction? callback)
        {
            NativeArgument argument=FacadeRuntime.Reference(callback);
            using var result=FacadeRuntime.Invoke(new("UnityEngine.CoreModule.dll","UnityEngine.Events","UnityEvent","RemoveListener",false,false,"System.Void",["UnityEngine.Events.UnityAction"]),Token,&argument,1);
        }
    }
}
namespace EHR
{
    internal static unsafe class SourceUnityActionSelfTest
    {
        [UnmanagedCallersOnly(EntryPoint="ehr_source_unity_action_self_test",CallConvs=[typeof(CallConvCdecl)])]
        internal static int Run(int* proof,nuint count)
        {
            if(proof==null||count!=10)return 4;for(int i=0;i<10;i++)proof[i]=0;
            UnityEngine.Events.UnityEvent? nativeEvent=null;
            UnityEngine.Events.UnityAction? first=null,equal=null;
            try
            {
                int before=ActionRuntime.SourceCount,effects=0;
                System.Action source=()=>++effects;
                nativeEvent=new();first=new(source);
                // This is the ACTUAL listener proxy added to the native event.
                nativeEvent.AddListener(first);
                first.Dispose();nativeEvent.Invoke();proof[2]=effects==1?1:0;
                nativeEvent.RemoveAllListeners();
                // Independently test the unchanged source extension/conversion.
                UnityActionDelegateFix.AddListener(nativeEvent,source);
                nativeEvent.Invoke();proof[3]=effects==2?1:0;
                equal=new(source);nativeEvent.RemoveListener(equal);nativeEvent.Invoke();proof[4]=effects==2?1:0;
                nativeEvent.AddListener(equal);
                equal.Close();nativeEvent.Invoke();proof[5]=effects==2?1:0;
                nativeEvent.RemoveAllListeners();proof[6]=ActionRuntime.SourceCount==before?1:0;
                proof[7]=ElementCodecs.Get<UnityEngine.Events.UnityAction>().NativeClass()==NativeTypeNames.Class("UnityEngine.Events.UnityAction")&&NativeTypeNames.RuntimeName("UnityEngine.Events.UnityAction")=="UnityEngine.Events.UnityAction"?1:0;
                proof[8]=sizeof(nuint)==8?1:0;proof[9]=RuntimeFeature.IsDynamicCodeCompiled||RuntimeFeature.IsDynamicCodeSupported?1:0;
                proof[0]=1;for(int i=2;i<9;i++)proof[0]&=proof[i];if(proof[9]!=0)proof[0]=0;
                return proof[0]==1?0:7;
            }
            catch(NativeGameException error){try{error.Dispose();}catch{}proof[1]=6;return 6;}
            catch(RuntimeGatewayException error){proof[1]=error.Status;return error.Status;}
            catch{proof[1]=6;return 6;}
            finally
            {
                try{nativeEvent?.RemoveAllListeners();}catch{}
                try{equal?.Close();}catch{}try{first?.Close();}catch{}
                try{equal?.Dispose();}catch{}try{first?.Dispose();}catch{}try{nativeEvent?.Dispose();}catch{}
            }
        }
    }
}
