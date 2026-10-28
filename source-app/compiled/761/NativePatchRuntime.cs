// Token-only bridge between typed native entry thunks and the static source
// dispatcher. Generated definitions supply exact source CLR types and metadata.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using EHR.Generated;

namespace EHR;

internal sealed class NativePatchDefinition(ulong id,string selector,BindingSpec spec,Type? instanceType,
    Type[] argumentTypes,string[] argumentNames,bool[] byReference,bool[] outputArguments,Type? resultType,
    ulong expectedRva,EHRStaticPatchBinding binding)
{
    internal readonly ulong Id=id,ExpectedRva=expectedRva;
    internal readonly string Selector=selector;
    internal readonly BindingSpec Spec=spec;
    internal readonly Type? InstanceType=instanceType,ResultType=resultType;
    internal readonly Type[] ArgumentTypes=argumentTypes;
    internal readonly string[] ArgumentNames=argumentNames;
    internal readonly bool[] ByReference=byReference;
    internal readonly bool[] OutputArguments=outputArguments;
    internal readonly EHRStaticPatchBinding Binding=binding;
    internal ulong Method;
    internal bool[] ValueArguments=[];
    internal bool ValueResult;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativePatchDispatchProofV2
{
    internal uint AbiVersion,ByteSize,TargetFound,DispatcherEntered;
    internal uint OriginalAttempted,RuntimeEntered,PermitConsumed,HookConsumptions;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativePatchHostTable
{
    internal uint AbiVersion,ByteSize;
    internal delegate* unmanaged[Cdecl]<ulong,ulong,ulong,int> Register;
    internal delegate* unmanaged[Cdecl]<ulong,ulong,ulong*,int> Begin;
    internal delegate* unmanaged[Cdecl]<ulong,ulong,ulong,ulong,NativeArgument*,nuint,ByRefOutput*,nuint,
        ulong*,ulong*,OriginalProof*,nuint,int> Invoke;
    internal delegate* unmanaged[Cdecl]<ulong,int> End;
    internal delegate* unmanaged[Cdecl]<ulong,int*,int> ClassIsValue;
}

internal static unsafe partial class NativePatchRuntime
{
    private static NativePatchHostTable host;
    private static bool bound;
    private static Dictionary<ulong,NativePatchDefinition> definitions=new();

    // Called only by the main-thread source bootstrap after all facade tables
    // are ready. Build the complete candidate set before publishing any bridge.
    internal static void Configure(IEnumerable<NativePatchDefinition> source)
    {
        if(!bound)throw new RuntimeGatewayException(1,"native patch host not bound");
        FacadeRuntime.RequireReady();
        var prepared=new Dictionary<ulong,NativePatchDefinition>();
        foreach(var definition in source)
        {
            int count=definition.ArgumentTypes.Length;
            if(definition.Id==0||count>128||definition.ArgumentNames.Length!=count||definition.ByReference.Length!=count||
                definition.OutputArguments.Length!=count||definition.Spec.Parameters.Length!=count||!prepared.TryAdd(definition.Id,definition))
                throw new RuntimeGatewayException(4,"invalid generated patch definition");
            definition.Method=FacadeRuntime.Resolve(definition.Spec);
            FacadeRuntime.Require(host.Register(definition.Id,definition.Method,definition.ExpectedRva),"pinned original route "+definition.Selector);
            definition.ValueArguments=new bool[count];
            for(int i=0;i<count;++i)
            {
                int value=0;FacadeRuntime.Require(host.ClassIsValue(ElementCodecs.Get(definition.ArgumentTypes[i]).NativeClass(),&value),"patch parameter kind");
                if(value!=0&&value!=1)throw new RuntimeGatewayException(5,"patch parameter kind boolean");
                definition.ValueArguments[i]=value==1;
                if(definition.OutputArguments[i]&&!definition.ByReference[i])throw new RuntimeGatewayException(4,"out parameter without reference");
                if(definition.ByReference[i]&&!definition.ValueArguments[i])throw new RuntimeGatewayException(7,"reference ref/out patch parameter");
                if(definition.ByReference[i])_=FacadeRuntime.RawValueSize(ElementCodecs.Get(definition.ArgumentTypes[i]).NativeClass());
            }
            if(definition.ResultType!=null)
            {
                int value=0;FacadeRuntime.Require(host.ClassIsValue(ElementCodecs.Get(definition.ResultType).NativeClass(),&value),"patch result kind");
                if(value!=0&&value!=1)throw new RuntimeGatewayException(5,"patch result kind boolean");
                definition.ValueResult=value==1;
            }
        }
        definitions=prepared;
    }

    private static object? NativeDefault(Type type)
    {
        var codec=ElementCodecs.Get(type);ulong klass=codec.NativeClass();
        // default(T) is zero-initialization, not a parameterless constructor.
        // Only the gateway's validated reference-free value classes enter here.
        var bytes=new byte[FacadeRuntime.RawValueSize(klass)];
        return codec.Read(FacadeRuntime.BoxRawValue(klass,bytes));
    }

    private static void Original(NativePatchDefinition definition,EHRStaticPatchFrame frame,NativePatchDispatchProofV2* outcome)
    {
        if(outcome!=null)outcome->OriginalAttempted=1;
        int count=frame.Arguments.Length;
        var boxes=new RuntimeObject?[count];
        NativeArgument* args=stackalloc NativeArgument[count];
        ByRefOutput* refs=stackalloc ByRefOutput[count];
        void** allocations=stackalloc void*[count];
        for(int i=0;i<count;++i)allocations[i]=null;
        ulong invocation=0,returned=0,exception=0;
        int refCount=0;
        using var receiver=definition.InstanceType==null?new RuntimeObject(0):ElementCodecs.Get(definition.InstanceType).Box(frame.Instance);
        try
        {
            for(int i=0;i<count;++i)
            {
                var codec=ElementCodecs.Get(definition.ArgumentTypes[i]);
                boxes[i]=codec.Box(frame.Arguments[i]);
                if(!definition.ByReference[i])args[i]=new(){Kind=definition.ValueArguments[i]?3u:1u,Token=boxes[i]!.Token};
                else
                {
                    ulong klass=codec.NativeClass();int size=FacadeRuntime.RawValueSize(klass);
                    byte* memory=(byte*)NativeMemory.Alloc((nuint)size);allocations[i]=memory;
                    if(memory==null)throw new OutOfMemoryException();
                    FacadeRuntime.CopyRawValue(boxes[i]!,new Span<byte>(memory,size));
                    args[i]=new(){Kind=2,Token=klass,Bytes=memory,ByteCount=(nuint)size};
                    refs[refCount++]=new(){ArgumentIndex=(uint)i,ValueClass=klass,Bytes=memory,ByteCount=(nuint)size};
                }
            }
            FacadeRuntime.Require(host.Begin(definition.Id,definition.Method,&invocation),"patch original capability");
            OriginalProof proof=default;
            int status=host.Invoke(invocation,definition.Id,definition.Method,receiver.Token,args,(nuint)count,refs,(nuint)refCount,
                &returned,&exception,&proof,(nuint)sizeof(OriginalProof));
            // Capture BEFORE any copyback conversion or finally cleanup can
            // throw. Thunks must never infer this from the final status alone.
            if(outcome!=null)
            {
                outcome->RuntimeEntered=proof.RuntimeEntered;
                outcome->PermitConsumed=proof.PermitConsumed;
                outcome->HookConsumptions=proof.HookConsumptions;
            }
            // Native ref writes remain observable if the original later throws.
            if(proof.RuntimeEntered==1)
                for(int i=0;i<refCount;++i)
                {
                    var descriptor=refs[i];
                    using var value=FacadeRuntime.BoxRawValue(descriptor.ValueClass,new ReadOnlySpan<byte>(descriptor.Bytes,checked((int)descriptor.ByteCount)));
                    frame.Arguments[descriptor.ArgumentIndex]=ElementCodecs.Get(definition.ArgumentTypes[descriptor.ArgumentIndex]).Read(FacadeRuntime.Retain(value));
                }
            if(exception!=0)throw NativeGameException.FromBorrowed(exception,"source patch original");
            FacadeRuntime.Require(status,"source patch original");
            if(proof.AbiVersion!=1||proof.ByteSize!=sizeof(OriginalProof)||proof.RequestAccepted!=1||proof.RuntimeEntered!=1||
                proof.PermitConsumed!=1||proof.HookConsumptions!=1)throw new RuntimeGatewayException(5,"unproved source patch original");
            if(definition.ResultType!=null)frame.Result=ElementCodecs.Get(definition.ResultType).Read(FacadeRuntime.RetainToken(returned));
            else if(returned!=0)throw new RuntimeGatewayException(5,"void patch original returned an object");
        }
        finally
        {
            try {FacadeRuntime.Release(returned);FacadeRuntime.Release(exception);}
            finally
            {
                try {if(invocation!=0)FacadeRuntime.Require(host.End(invocation),"patch original capability close");}
                finally
                {
                    Exception? cleanup=null;
                    for(int i=0;i<count;++i){try{boxes[i]?.Dispose();}catch(Exception error){cleanup??=error;}finally{NativeMemory.Free(allocations[i]);}}
                    if(cleanup!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(cleanup).Throw();
                }
            }
        }
    }

    [UnmanagedCallersOnly(EntryPoint="ehr_source_bind_patch_host")]
    internal static int Bind(NativePatchHostTable* table,nuint size)
    {
        if(table==null||size!=48||sizeof(NativePatchHostTable)!=48||table->AbiVersion!=1||table->ByteSize!=size||
            table->Register==null||table->Begin==null||table->Invoke==null||table->End==null||table->ClassIsValue==null)return 4;
        host=*table;bound=true;return 0;
    }

    [UnmanagedCallersOnly(EntryPoint="ehr_source_patch_dispatch")]
    internal static int Dispatch(ulong id,ulong receiver,ulong* arguments,nuint count,ulong* result,ulong* exception,ulong* refResults,nuint refCount)
        =>DispatchCore(id,receiver,arguments,count,result,exception,refResults,refCount,null);

    [UnmanagedCallersOnly(EntryPoint="ehr_source_patch_dispatch_v2")]
    internal static int DispatchV2(ulong id,ulong receiver,ulong* arguments,nuint count,ulong* result,ulong* exception,ulong* refResults,nuint refCount,
        NativePatchDispatchProofV2* proof,nuint proofBytes)
    {
        if(count>128||refCount!=count||proof==null||proofBytes!=32||sizeof(NativePatchDispatchProofV2)!=32||!ValidSpan(proof,32,4))return 4;
        if(RangesOverlap(proof,32,result,8)||RangesOverlap(proof,32,exception,8)||RangesOverlap(proof,32,arguments,count*8)||RangesOverlap(proof,32,refResults,count*8))return 4;
        return DispatchCore(id,receiver,arguments,count,result,exception,refResults,refCount,proof);
    }

    private static int DispatchCore(ulong id,ulong receiver,ulong* arguments,nuint count,ulong* result,ulong* exception,ulong* refResults,nuint refCount,NativePatchDispatchProofV2* proof)
    {
        if(result==null||exception==null||result==exception||count>128||refCount!=count||
            (count!=0&&(arguments==null||refResults==null)))return 4;
        if(Overlap(result,8,exception,8)||Overlap(arguments,count*8,result,8)||Overlap(arguments,count*8,exception,8)||
            Overlap(refResults,count*8,result,8)||Overlap(refResults,count*8,exception,8)||Overlap(arguments,count*8,refResults,count*8))return 4;
        if(proof!=null)*proof=new(){AbiVersion=2,ByteSize=32};
        *result=0;*exception=0;for(nuint i=0;i<count;++i)refResults[i]=0;
        NativePatchDefinition? definition=null;EHRStaticPatchFrame? frame=null;Exception? failure=null;
        try
        {
            FacadeRuntime.RequireReady();
            if(!definitions.TryGetValue(id,out definition))return 3;
            if(proof!=null)proof->TargetFound=1;
            if((nuint)definition.ArgumentTypes.Length!=count||((receiver==0)!=(definition.InstanceType==null)))return 5;
            // From this point the bridge accepted a configured call and may
            // execute source work. Native failure policy cannot retry original.
            if(proof!=null)proof->DispatcherEntered=1;
            object? instance=definition.InstanceType==null?null:ElementCodecs.Get(definition.InstanceType).Read(FacadeRuntime.RetainToken(receiver));
            var values=new object?[count];
            for(int i=0;i<values.Length;++i)values[i]=definition.OutputArguments[i]?NativeDefault(definition.ArgumentTypes[i]):
                ElementCodecs.Get(definition.ArgumentTypes[i]).Read(FacadeRuntime.RetainToken(arguments[i]));
            frame=new EHRStaticPatchFrame(instance,values,definition.ArgumentNames);
            if(definition.ValueResult)frame.Result=NativeDefault(definition.ResultType!);
            definition.Binding.Execute(frame,f=>Original(definition,f,proof));
        }
        catch(Exception error){failure=error;}
        // Preserve original/prefix ref writes even when an exception survives
        // finalizers. Native callers copy these outputs before raising it.
        try
        {
            if(definition!=null&&frame!=null)
            {
                for(int i=0;i<frame.Arguments.Length;++i)if(definition.ByReference[i])
                {using var boxed=ElementCodecs.Get(definition.ArgumentTypes[i]).Box(frame.Arguments[i]);refResults[i]=boxed.Detach();}
                if(failure==null&&definition.ResultType!=null){using var boxed=ElementCodecs.Get(definition.ResultType).Box(frame.Result);*result=boxed.Detach();}
            }
            if(failure is NativeGameException native){using var owned=native.RetainNativeException();*exception=owned.Detach();}
            return failure is RuntimeGatewayException gateway?gateway.Status:failure==null?0:6;
        }
        catch
        {
            try{FacadeRuntime.Release(*result);}catch{}*result=0;
            try{FacadeRuntime.Release(*exception);}catch{}*exception=0;
            for(nuint i=0;i<count;++i){try{FacadeRuntime.Release(refResults[i]);}catch{}refResults[i]=0;}
            return 6;
        }
    }
    private static bool ValidSpan(void* pointer,nuint size,nuint alignment)
    {
        nuint value=(nuint)pointer;
        return value!=0&&value%alignment==0&&value<=nuint.MaxValue-size;
    }
    private static bool RangesOverlap(void* a,nuint sizeA,void* b,nuint sizeB)
    {
        if(sizeA==0||sizeB==0)return false;
        if(!ValidSpan(a,sizeA,1)||!ValidSpan(b,sizeB,1))return true;
        nuint first=(nuint)a,second=(nuint)b;
        return first<second+sizeB&&second<first+sizeA;
    }
    private static bool Overlap(void* a,nuint sizeA,void* b,nuint sizeB)
    {
        if(sizeA==0||sizeB==0)return false;
        nuint first=(nuint)a,second=(nuint)b;
        if(first==0||second==0||first%8!=0||second%8!=0||first>nuint.MaxValue-sizeA||second>nuint.MaxValue-sizeB)return true;
        return first<second+sizeB&&second<first+sizeA;
    }
}
