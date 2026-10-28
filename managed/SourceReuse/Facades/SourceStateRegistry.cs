using System;
using System.Collections.Generic;
namespace EHR.Generated;
// Native owns each registration's lifetime; no CLR GCHandle/pointer crosses
// the boundary. IDs are monotonic, never recycled. All operations are main.
internal sealed class SourceStateRegistry
{
    internal sealed class Entry(uint type,RuntimeObject source,System.Action<uint> dispatch,IDisposable cleanup)
    {
        internal readonly uint Type=type;
        internal readonly RuntimeObject Source=source;
        internal readonly System.Action<uint> Dispatch=dispatch;
        internal readonly IDisposable Cleanup=cleanup;
        internal bool Destroying;
    }
    private readonly Dictionary<ulong,Entry> entries=new();
    private ulong next=1;
    internal int Count=>entries.Count;
    internal ulong Add(uint type,RuntimeObject source,System.Action<uint> dispatch,IDisposable cleanup)
    {
        FacadeRuntime.RequireReady();if(entries.Count>=4096||next==ulong.MaxValue)throw new RuntimeGatewayException(8,"source component state limit");
        ulong id=next++;entries.Add(id,new(type,source,dispatch,cleanup));return id;
    }
    internal Entry Find(ulong id)
    {
        FacadeRuntime.RequireReady();return entries.TryGetValue(id,out var entry)&&!entry.Destroying?entry:throw new RuntimeGatewayException(9,"source component state unavailable");
    }
    internal IDisposable CleanupFor(RuntimeObject source)
    {
        FacadeRuntime.RequireReady();foreach(var value in entries.Values)if(!value.Destroying&&ReferenceEquals(value.Source,source))return value.Cleanup;
        throw new RuntimeGatewayException(9,"source owner has no active lifecycle scope");
    }
    internal void Event(ulong id,uint message)
    {
        var entry=Find(id);if(message==3){Destroy(id,true);return;}entry.Dispatch(message);
    }
    internal void Destroy(ulong id,bool actualUnityDestroy)
    {
        FacadeRuntime.RequireReady();if(!entries.Remove(id,out var entry))return;
        entry.Destroying=true;Exception? first=null;
        // Remove before calling source, so reentrant native callbacks cannot
        // reenter a dying state. Even a throwing source OnDestroy releases all.
        try{if(actualUnityDestroy)entry.Dispatch(3);}catch(Exception error){first=error;}
        try{entry.Cleanup.Dispose();}catch(Exception error){if(first==null)first=error;else if(error is NativeGameException native)native.Dispose();}
        try{entry.Source.Dispose();}catch(Exception error){if(first==null)first=error;else if(error is NativeGameException native)native.Dispose();}
        if(first!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(first).Throw();
    }
    internal void CloseAll()
    {
        FacadeRuntime.RequireReady();Exception? first=null;
        foreach(var id in new List<ulong>(entries.Keys))try{Destroy(id,false);}catch(Exception error){if(first==null)first=error;else if(error is NativeGameException native)native.Dispose();}
        if(first!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(first).Throw();
    }
}
