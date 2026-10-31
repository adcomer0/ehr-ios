using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace EHR.Generated
{
    [StructLayout(LayoutKind.Sequential)] internal unsafe struct ProductionIteratorCallbacksV1
    {
        internal uint Version,Size;
        internal delegate* unmanaged[Cdecl]<ulong,int*,ulong*,int> Step;
        internal delegate* unmanaged[Cdecl]<ulong,int> Reset,Cancel;
    }
    [StructLayout(LayoutKind.Sequential)] internal unsafe struct ProductionIteratorHostV1
    {
        internal uint Version,Size;
        internal delegate* unmanaged[Cdecl]<ulong,ulong,ProductionIteratorCallbacksV1*,ulong*,int> Register;
        internal delegate* unmanaged[Cdecl]<ulong,ulong*,int> Acquire;
        internal delegate* unmanaged[Cdecl]<ulong,int> Close;
        internal delegate* unmanaged[Cdecl]<ulong,ulong,ulong,int> Associate;
        internal delegate* unmanaged[Cdecl]<uint,ulong,uint*,int> CloseMatching;
        internal delegate* unmanaged[Cdecl]<uint,uint*,uint*,int> Sweep;
        internal delegate* unmanaged[Cdecl]<int> IsMain;
        internal delegate* unmanaged[Cdecl]<void*,nuint,int> CopyStatus;
    }
    internal sealed class ProductionSourceEnumerator(ulong owned,ulong registration):Il2CppSystem.Collections.IEnumerator(owned)
    {
        internal ulong Registration {get;}=registration;
        // Inherited Dispose releases only this proxy root. It never cancels an
        // engine-owned source merely because a temporary proxy leaves scope.
    }
    internal static unsafe class ProductionCoroutines
    {
        private sealed class Entry(IEnumerator source,ulong id)
        {
            internal IEnumerator? Source=source;
            internal readonly ulong Id=id;
            internal ulong Registration,Parent,Child;
            internal ulong FailureSequence;
            internal bool Executing,Terminal,Disposed;
        }
        private static ProductionIteratorHostV1 host;
        private static bool bound;
        private static ulong next=0x4548524300000001;
        private static readonly Dictionary<ulong,Entry> entries=new();
        private static readonly ConditionalWeakTable<IEnumerator,Entry> identities=new();
        private static readonly BindingSpec GetEnumerator=new("mscorlib.dll","System.Collections","ArrayList","GetEnumerator",false,false,"System.Collections.IEnumerator",[]);
        internal static string? LastError {get;private set;}
        private struct FailureRecord
        {
            internal ulong Source,TypeHash,Phase,Kind,InitialStatus,ReturnedStatus,Sequence,CleanupKind,CleanupStatus;
        }
        private static FailureRecord lastFailure;
        private static ulong failureSequence;
        private static ulong ExceptionKind(Exception value)=>value switch
        {
            NativeGameException=>1,RuntimeGatewayException=>2,NullReferenceException=>3,IndexOutOfRangeException=>4,
            NotSupportedException=>5,InvalidCastException=>6,ObjectDisposedException=>7,ArgumentException=>8,
            InvalidOperationException=>9,OverflowException=>10,OutOfMemoryException=>11,_=>12
        };
        private static ulong SourceTypeHash(IEnumerator? source)
        {
            try
            {
                string? name=source?.GetType().FullName;
                if(string.IsNullOrEmpty(name)||name.Length>1024)return 0;
                ulong hash=14695981039346656037UL;
                foreach(byte value in System.Text.Encoding.UTF8.GetBytes(name))hash=unchecked((hash^value)*1099511628211UL);
                return hash;
            }
            catch{return 0;} // Diagnostic metadata must not replace the source fault.
        }
        private static void RecordFailure(Entry entry,IEnumerator? source,ulong phase,ulong kind,int initial,int returned,ulong cleanupKind,int cleanupStatus)
        {
            if(failureSequence==ulong.MaxValue)return;
            ulong sequence=++failureSequence;
            lastFailure=new(){Source=entry.Id,TypeHash=SourceTypeHash(source),Phase=phase,Kind=kind,
                InitialStatus=unchecked((uint)initial),ReturnedStatus=unchecked((uint)returned),Sequence=sequence,
                CleanupKind=cleanupKind,CleanupStatus=unchecked((uint)cleanupStatus)};
            entry.FailureSequence=sequence;
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_source_coroutine_failure_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
        internal static int CopyFailure(ulong source,ulong* words,nuint count)
        {
            if(words==null||count!=12||source==0)return 4;
            if(!bound)return 1;
            if(host.IsMain()!=1)return 2;
            if(!entries.TryGetValue(source,out Entry? entry)||lastFailure.Source!=source||entry.FailureSequence==0||entry.FailureSequence!=lastFailure.Sequence)return 3;
            var value=lastFailure;
            words[0]=1;words[1]=12;words[2]=value.Source;words[3]=value.TypeHash;words[4]=value.Phase;words[5]=value.Kind;
            words[6]=value.InitialStatus;words[7]=value.ReturnedStatus;words[8]=value.Sequence;
            words[9]=value.CleanupKind;words[10]=value.CleanupStatus;words[11]=0;
            return 0;
        }
        internal static int ActiveSources=>entries.Count;
        internal static void Ready()
        {
            if(!bound)throw new RuntimeGatewayException(1,"production source iterator table is not bound");
            if(host.IsMain()!=1)throw new RuntimeGatewayException(2,"source iterators require native main thread");
            FacadeRuntime.RequireReady();
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_source_bind_coroutines_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
        internal static int Bind(ProductionIteratorHostV1* table,nuint bytes)
        {
            if(bound||table==null||bytes!=72||table->Version!=1||table->Size!=72||table->Register==null||table->Acquire==null||table->Close==null||table->Associate==null||table->CloseMatching==null||table->Sweep==null||table->IsMain==null||table->CopyStatus==null)return 4;
            if(table->IsMain()!=1)return 2;
            try{FacadeRuntime.RequireReady();host=*table;bound=true;return 0;}
            catch(Exception exception){return Contain(exception);}
        }
        private static int Contain(Exception exception)
        {
            LastError=exception.ToString();
            if(exception is NativeGameException game){game.Dispose();return 6;}
            return exception is RuntimeGatewayException gateway?gateway.Status:exception is NotSupportedException?7:6;
        }
        internal static Il2CppSystem.Collections.IEnumerator Wrap(IEnumerator source)=>Wrap(source,0);
        private static ProductionSourceEnumerator Wrap(IEnumerator source,ulong parent)
        {
            ArgumentNullException.ThrowIfNull(source);Ready();
            ulong ancestorDepth=parent;int nesting=0;
            while(ancestorDepth!=0&&entries.TryGetValue(ancestorDepth,out Entry? ancestorEntry))
            {if(++nesting>64)throw new NotSupportedException("source iterator nesting limit");ancestorDepth=ancestorEntry.Parent;}
            if(identities.TryGetValue(source,out Entry? prior))
            {
                if(parent!=0)
                {
                    if(prior.Id==parent||prior.Parent!=0&&prior.Parent!=parent)throw new NotSupportedException("source iterator already belongs to another nested scheduler");
                    ulong ancestor=parent;int depth=0;
                    while(ancestor!=0&&entries.TryGetValue(ancestor,out Entry? owner))
                    {if(owner.Id==prior.Id||++depth>64)throw new NotSupportedException("cyclic or excessively deep source iterator");ancestor=owner.Parent;}
                    prior.Parent=parent;
                }
                ulong acquired=0;FacadeRuntime.Require(host.Acquire(prior.Registration,&acquired),"reacquire exact source iterator carrier");
                return new(acquired,prior.Registration);
            }
            if(entries.Count>=256||next==ulong.MaxValue)throw new RuntimeGatewayException(8,"active source iterator limit");
            using var list=LiveReflection.Construct(FacadeRuntime.Class("mscorlib.dll","System.Collections","ArrayList"),[]);
            using var carrier=FacadeRuntime.Invoke(GetEnumerator,list.Token,null,0);
            ulong id=next++,registration=0;
            var entry=new Entry(source,id){Parent=parent};entries.Add(id,entry);identities.Add(source,entry);
            ProductionIteratorCallbacksV1 callbacks=new(){Version=1,Size=32,Step=&Step,Reset=&Reset,Cancel=&Cancel};
            int status=host.Register(carrier.Token,id,&callbacks,&registration);
            if(status!=0||registration==0)
            {
                entries.Remove(id);identities.Remove(source);
                if(registration!=0)host.Close(registration);
                throw new RuntimeGatewayException(status==0?4:status,"register weak source iterator carrier");
            }
            entry.Registration=registration;
            return new(carrier.Detach(),registration);
        }
        internal static void Started(RuntimeObject owner,Il2CppSystem.Collections.IEnumerator? routine,RuntimeObject returned)
        {
            if(routine is not ProductionSourceEnumerator production)return;
            Ready();if(returned.Token==0)throw new RuntimeGatewayException(4,"Unity StartCoroutine returned null");
            FacadeRuntime.Require(host.Associate(production.Registration,owner.Token,returned.Token),"associate weak source coroutine owner/handle");
        }
        // These methods are called only AFTER the caught real Unity stop call
        // returned successfully. Ordinary native routines simply match nothing.
        internal static void StoppedCarrier(RuntimeObject? value)=>Stopped(1,value);
        internal static void StoppedHandle(RuntimeObject? value)=>Stopped(2,value);
        internal static void StoppedOwner(RuntimeObject value)=>Stopped(3,value);
        private static void Stopped(uint kind,RuntimeObject? value)
        {
            if(!bound||value is null||value.Token==0)return;
            Ready();uint closed=0;FacadeRuntime.Require(host.CloseMatching(kind,value.Token,&closed),"close stopped source coroutine");
        }
        internal static void StopSource(RuntimeObject owner,IEnumerator source)
        {
            ArgumentNullException.ThrowIfNull(source);Ready();
            if(!identities.TryGetValue(source,out Entry? entry))return;
            ulong carrier=0;int status=host.Acquire(entry.Registration,&carrier);
            if(status is 7 or 9)return; // known completed/collected source, no invented identity
            FacadeRuntime.Require(status,"acquire source coroutine for stop");
            using var routine=new RuntimeObject(carrier);
            NativeArgument argument=FacadeRuntime.Reference(routine);
            using var result=FacadeRuntime.Invoke(new("UnityEngine.CoreModule.dll","UnityEngine","MonoBehaviour","StopCoroutine",false,false,"System.Void",["System.Collections.IEnumerator"]),owner.Token,&argument,1);
            FacadeRuntime.Require(host.Close(entry.Registration),"close exact stopped source coroutine");
        }
        private static void CloseChild(Entry entry)
        {
            ulong child=entry.Child;entry.Child=0;
            if(child!=0)
            {
                int status=host.Close(child);
                if(status!=0&&status!=9)FacadeRuntime.Require(status,"close nested source iterator");
            }
        }
        private static void Finish(Entry entry)
        {
            if(entry.Disposed)return;
            entry.Disposed=entry.Terminal=true;
            IEnumerator? source=entry.Source;entry.Source=null;
            try{CloseChild(entry);}finally{(source as IDisposable)?.Dispose();}
        }
        [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]
        private static int Step(ulong id,int* moved,ulong* current)
        {
            if(moved==null||current==null)return 4;*moved=0;*current=0;
            if(!entries.TryGetValue(id,out Entry? entry))return 9;
            if(entry.Executing)return 4;if(entry.Terminal)return 0;
            int status=0,initialStatus=0,cleanupStatus=0;ulong phase=1,kind=0,cleanupKind=0;
            IEnumerator? source=entry.Source;entry.Executing=true;
            try
            {
                Ready();phase=2;CloseChild(entry);phase=3;
                if(!entry.Source!.MoveNext()){phase=6;Finish(entry);}
                else
                {
                    phase=4;
                    object? value=entry.Source.Current;
                    phase=5;
                    if(value is RuntimeObject reference)*current=FacadeRuntime.Retain(reference).Detach();
                    else if(value is INativeValue boxed)*current=FacadeRuntime.Retain(boxed.NativeBox).Detach();
                    else if(value is IEnumerator child)
                    {
                        using var adapter=Wrap(child,entry.Id);entry.Child=adapter.Registration;
                        *current=adapter.Detach();
                    }
                    else if(value is string text)*current=FacadeRuntime.String(text).Detach();
                    else if(value is not null&&value.GetType().IsPrimitive)*current=ElementCodecs.Get(value.GetType()).Box(value).Detach();
                    else if(value is not null)throw new NotSupportedException("source coroutine yielded a CLR value without a live native codec: "+value.GetType().FullName);
                    *moved=1;
                }
            }
            catch(Exception exception){kind=ExceptionKind(exception);status=initialStatus=Contain(exception);}
            finally{entry.Executing=false;}
            if(status!=0)
            {
                if(*current!=0){FacadeRuntime.Release(*current);*current=0;}*moved=0;
                try{Finish(entry);}catch(Exception exception){cleanupKind=ExceptionKind(exception);status=cleanupStatus=Contain(exception);}
                RecordFailure(entry,source,phase,kind,initialStatus,status,cleanupKind,cleanupStatus);
            }
            return status;
        }
        [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]
        private static int Reset(ulong id)
        {
            if(!entries.TryGetValue(id,out Entry? entry))return 9;
            if(entry.Executing)return 4;if(entry.Terminal||entry.Source is null)return 7;
            entry.Executing=true;try{Ready();entry.Source.Reset();return 0;}
            catch(Exception exception){return Contain(exception);}finally{entry.Executing=false;}
        }
        [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]
        private static int Cancel(ulong id)
        {
            if(!entries.TryGetValue(id,out Entry? entry))return 0;
            if(entry.Executing)return 4;
            entries.Remove(id);try{Ready();Finish(entry);return 0;}catch(Exception exception){return Contain(exception);}
        }
        private sealed class Probe {internal int Steps,Disposed,ChildSteps,ChildDisposed;}
        private static IEnumerator Child(Probe probe)
        {try{probe.ChildSteps++;yield return 42;probe.ChildSteps++;}finally{probe.ChildDisposed++;}}
        private static IEnumerator Parent(Probe probe)
        {try{probe.Steps++;yield return null;probe.Steps++;yield return "EHR\0🌙";probe.Steps++;yield return Child(probe);probe.Steps++;}finally{probe.Disposed++;}}
        private static IEnumerator Cancellable(Probe probe)
        {try{probe.Steps++;yield return null;probe.Steps++;yield return null;}finally{probe.Disposed++;}}
        private static bool NativeError(Action action,string expected)
        {
            try{action();return false;}
            catch(NativeGameException exception)
            {
                using(exception)using(var owned=exception.RetainNativeException())
                    return FacadeRuntime.ObjectClass(owned)==FacadeRuntime.Class("mscorlib.dll","System",expected);
            }
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_source_coroutines_self_test",CallConvs=new[]{typeof(CallConvCdecl)})]
        internal static int SelfTest(int* proof,nuint count)
        {
            if(proof==null||count!=16)return 4;for(int i=0;i<16;i++)proof[i]=0;
            try
            {
                Ready();int before=entries.Count;var probe=new Probe();IEnumerator source=Parent(probe);
                var temporary=Wrap(source,0);using var carrier=Wrap(source,0);
                proof[2]=NativeLifetime.Same(temporary,carrier)?1:0;temporary.Dispose();
                proof[3]=NativeError(()=>{using var invalid=carrier.Current;},"InvalidOperationException")?1:0;
                proof[4]=carrier.MoveNext()&&carrier.Current is null?1:0;
                proof[5]=carrier.MoveNext()?1:0;
                using(var text=carrier.Current)proof[5]&=text!=null&&FacadeRuntime.ReadString(text)=="EHR\0🌙"?1:0;
                proof[6]=carrier.MoveNext()?1:0;
                using(var current=carrier.Current)
                {
                    if(current==null)throw new InvalidOperationException("Missing actual nested native carrier");
                    using var child=new Il2CppSystem.Collections.IEnumerator(FacadeRuntime.Retain(current).Detach());
                    proof[7]=child.MoveNext()?1:0;
                    using(var boxed=child.Current)proof[7]&=boxed!=null&&FacadeRuntime.ReadValue<int>(boxed)==42?1:0;
                    proof[8]=!child.MoveNext()&&probe.ChildSteps==2&&probe.ChildDisposed==1?1:0;
                }
                proof[9]=!carrier.MoveNext()&&probe.Steps==4&&probe.Disposed==1?1:0;
                proof[10]=NativeError(carrier.Reset,"NotSupportedException")?1:0;
                proof[11]=NativeError(()=>{using var invalid=carrier.Current;},"InvalidOperationException")?1:0;
                var cancelProbe=new Probe();using var cancelled=Wrap(Cancellable(cancelProbe),0);
                if(!cancelled.MoveNext())throw new InvalidOperationException("Cancellation source did not start");
                // This is a manual-driver test; no Unity engine owns this carrier.
                // Closing it therefore satisfies the stopped-before-close rule.
                FacadeRuntime.Require(host.Close(cancelled.Registration),"close manually stopped production source");
                proof[12]=!cancelled.MoveNext()&&cancelProbe.Disposed==1?1:0;
                proof[13]=entries.Count==before?1:0;
                proof[14]=sizeof(ProductionIteratorHostV1)==72&&sizeof(ProductionIteratorCallbacksV1)==32?1:0;
                proof[15]=RuntimeFeature.IsDynamicCodeSupported||RuntimeFeature.IsDynamicCodeCompiled?1:0;
                proof[0]=1;for(int i=2;i<15;i++)proof[0]&=proof[i];if(proof[15]!=0)proof[0]=0;
                return proof[0]==1?0:7;
            }
            catch(Exception exception){proof[1]=Contain(exception);return proof[1];}
        }
    }
}
namespace BepInEx.Unity.IL2CPP.Utils.Collections
{
    public static class ProductionSourceCoroutineExtensions
    {
        public static Il2CppSystem.Collections.IEnumerator WrapToIl2Cpp(this IEnumerator source)=>EHR.Generated.ProductionCoroutines.Wrap(source);
    }
}
