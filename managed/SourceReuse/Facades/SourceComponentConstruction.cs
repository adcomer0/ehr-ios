using System;
namespace EHR.Generated;
// Only exact generated TypeID factories open a context. Normal new derived
// MonoBehaviour outside AddComponent is rejected before native allocation.
internal static class SourceComponentConstruction
{
    [ThreadStatic] private static Scope? current;
    internal sealed class Scope:IDisposable
    {
        private readonly ulong token;
        private RuntimeObject? owner;
        private bool taken,committed,disposed;
        internal Scope(ulong ownedWeakSelf)
        {
            FacadeRuntime.RequireReady();
            if(ownedWeakSelf==0)throw new ArgumentOutOfRangeException(nameof(ownedWeakSelf));
            if(current!=null)throw new InvalidOperationException("Nested source component construction");
            token=ownedWeakSelf;current=this;
        }
        internal ulong Take()
        {
            if(disposed||taken)throw new InvalidOperationException("Component self already consumed");
            taken=true;return token;
        }
        internal void Bind(RuntimeObject value)
        {
            if(disposed||!taken||owner!=null||value.Token!=token)throw new InvalidOperationException("Component constructor identity mismatch");
            value.MarkUnitySourceProxy();owner=value;
        }
        internal void Commit(RuntimeObject value)
        {
            if(disposed||!taken||!ReferenceEquals(owner,value))throw new InvalidOperationException("Component factory did not bind its exact self");
            committed=true;
        }
        public void Dispose()
        {
            if(disposed)return;disposed=true;
            if(ReferenceEquals(current,this))current=null;
            if(!committed){if(owner!=null)owner.Dispose();else FacadeRuntime.Release(token);}
        }
    }
    internal static Scope Begin(ulong ownedWeakSelf)=>new(ownedWeakSelf);
    internal static ulong Take()=>current?.Take()??throw new RuntimeGatewayException(7,"Source components require registered AddComponent factory");
    internal static void Bind(RuntimeObject owner)=>(current??throw new InvalidOperationException("Missing component construction context")).Bind(owner);
}
