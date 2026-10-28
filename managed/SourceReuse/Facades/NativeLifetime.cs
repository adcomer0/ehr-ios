using System;
using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace EHR.Generated;

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct LifetimeTable
{
    internal uint AbiVersion,ByteSize;
    internal delegate* unmanaged[Cdecl]<ulong,ulong,int*,int> ObjectSame;
    internal delegate* unmanaged[Cdecl]<ulong,int*,ulong*,int> IdentityHash;
    internal delegate* unmanaged[Cdecl]<ulong,int> ReleaseDeferred;
    internal delegate* unmanaged[Cdecl]<nuint*,int> DrainDeferred;
}
internal static unsafe class NativeLifetime
{
    private static LifetimeTable table;
    private static int bound;
    // Only needed if collection/field wrappers were created before the native
    // lifetime table was attached. Queue entries own the root until handed off.
    private static readonly ConcurrentQueue<ulong> pending=new();
    internal static void Enqueue(ulong token)
    {
        if(token==0)return;
        if(Volatile.Read(ref bound)==0){pending.Enqueue(token);return;}
        // Approved native API is enqueue-only on this arbitrary/finalizer thread.
        // Failed enqueue retains ownership in our queue for later main-thread work.
        if(table.ReleaseDeferred(token)!=0)pending.Enqueue(token);
    }
    internal static bool Same(RuntimeObject left,RuntimeObject right)
    {
        if(Volatile.Read(ref bound)==0)throw new RuntimeGatewayException(1,"identity extension not bound");
        int result=0;FacadeRuntime.Require(table.ObjectSame(left.Token,right.Token,&result),"object identity");return result!=0;
    }
    internal static int Hash(RuntimeObject value)
    {
        if(Volatile.Read(ref bound)==0)throw new RuntimeGatewayException(1,"identity extension not bound");
        int hash=0;ulong exception=0;
        int status=table.IdentityHash(value.Token,&hash,&exception);
        FacadeRuntime.CheckManaged(status,exception,"object identity hash");return hash;
    }
    internal static void FlushPending()
    {
        if(Volatile.Read(ref bound)==0)return;
        int count=pending.Count;
        for(int i=0;i<count&&pending.TryDequeue(out ulong token);++i)
            if(table.ReleaseDeferred(token)!=0){pending.Enqueue(token);break;}
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_bind_lifetime")]
    internal static int Bind(LifetimeTable* source,nuint bytes)
    {
        if(source==null||bytes!=(nuint)sizeof(LifetimeTable)||source->AbiVersion!=1||source->ByteSize!=sizeof(LifetimeTable))return 4;
        if(source->ObjectSame==null||source->IdentityHash==null||source->ReleaseDeferred==null||source->DrainDeferred==null)return 4;
        table=*source;Volatile.Write(ref bound,1);FlushPending();return 0;
    }
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static WeakReference<RuntimeObject> MakeFinalizerCandidate()
    {
        RuntimeObject root=FacadeRuntime.BoxValue("mscorlib.dll","System","Int32",123);
        return new WeakReference<RuntimeObject>(root);
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_lifetime_self_test")]
    internal static int SelfTest(int* output,nuint count)
    {
        if(output==null||count!=6)return 4;
        for(int i=0;i<6;++i)output[i]=0;
        if(Volatile.Read(ref bound)==0)return output[1]=1;
        try
        {
            using var first=FacadeRuntime.BoxValue("mscorlib.dll","System","Int32",71);
            using var same=FacadeRuntime.Retain(first);
            using var different=FacadeRuntime.BoxValue("mscorlib.dll","System","Int32",71);
            output[2]=first.Equals(same)&&first.GetHashCode()==same.GetHashCode()?1:0;
            output[3]=!first.Equals(different)?1:0;
            var dispose=FacadeRuntime.BoxValue("mscorlib.dll","System","Int32",72);
            ulong old=dispose.Token;dispose.Dispose();dispose.Dispose();
            output[4]=!FacadeRuntime.TokenIsValid(old)?1:0;
            var worker=FacadeRuntime.BoxValue("mscorlib.dll","System","Int32",73);
            ulong workerToken=worker.Token;
            Task.Run(worker.Dispose).GetAwaiter().GetResult();
            var weak=MakeFinalizerCandidate();
            GC.Collect();GC.WaitForPendingFinalizers();GC.Collect();
            FlushPending();nuint drained=0;
            FacadeRuntime.Require(table.DrainDeferred(&drained),"drain deferred roots");
            output[5]=!weak.TryGetTarget(out _)&&!FacadeRuntime.TokenIsValid(workerToken)&&drained>=1?1:0;
            output[0]=output[2]==1&&output[3]==1&&output[4]==1&&output[5]==1?1:0;
            return output[1]=output[0]==1?0:5;
        }
        catch(RuntimeGatewayException exception){return output[1]=exception.Status;}
        catch{return output[1]=6;}
    }
}
