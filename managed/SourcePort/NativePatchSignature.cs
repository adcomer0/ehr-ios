using System;
using System.Runtime.InteropServices;
using EHR.Generated;

namespace EHR;

[StructLayout(LayoutKind.Sequential)]
internal struct NativePatchSignatureV1
{
    internal uint AbiVersion,ByteSize,ParameterCount,Flags;
    internal ulong Method,OwnerClass,ResultClass,ExpectedRva;
}
[StructLayout(LayoutKind.Sequential)]
internal struct NativePatchParameterV1
{
    internal ulong Class;
    internal uint Flags,Reserved;
}

internal static unsafe partial class NativePatchRuntime
{
    // Opaque metadata tokens only. Does not enable a native handler. The native
    // binder separately checks its compiled signature/layout and installed
    // entry before making a source target active.
    [UnmanagedCallersOnly(EntryPoint="ehr_source_patch_signature_v1")]
    internal static int Describe(ulong id,NativePatchSignatureV1* result,nuint bytes,
        NativePatchParameterV1* parameters,nuint count)
    {
        if(result==null||bytes!=48||sizeof(NativePatchSignatureV1)!=48||sizeof(NativePatchParameterV1)!=16||
            !ValidSpan(result,48,8)||count>128||(count!=0&&!ValidSpan(parameters,count*16,8))||
            RangesOverlap(result,48,parameters,count*16))return 4;
        *result=default;for(nuint i=0;i<count;++i)parameters[i]=default;
        try
        {
            FacadeRuntime.RequireReady();
            if(!bound||!definitions.TryGetValue(id,out var definition))return 3;
            if((nuint)definition.ArgumentTypes.Length!=count)return 5;
            var prepared=new NativePatchParameterV1[count];
            for(int i=0;i<prepared.Length;++i)
                prepared[i]=new(){Class=ElementCodecs.Get(definition.ArgumentTypes[i]).NativeClass(),
                    Flags=(definition.ValueArguments[i]?1u:0u)|(definition.ByReference[i]?2u:0u)|(definition.OutputArguments[i]?4u:0u)};
            NativePatchSignatureV1 signature=new(){AbiVersion=1,ByteSize=48,ParameterCount=(uint)count,
                Flags=(definition.InstanceType!=null?1u:0u)|(definition.ResultType!=null?2u:0u)|(definition.ValueResult?4u:0u),
                Method=definition.Method,OwnerClass=FacadeRuntime.Class(definition.Spec.Image,definition.Spec.Namespace,definition.Spec.Type),
                ResultClass=definition.ResultType==null?0:ElementCodecs.Get(definition.ResultType).NativeClass(),ExpectedRva=definition.ExpectedRva};
            for(int i=0;i<prepared.Length;++i)parameters[i]=prepared[i];*result=signature;return 0;
        }
        catch(RuntimeGatewayException error){return error.Status;}catch{return 6;}
    }
}
