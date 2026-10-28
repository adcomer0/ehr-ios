using System;
using System.Collections.Generic;
using System.Runtime.ExceptionServices;
namespace EHR.Generated;
// An explicit native owner lifetime, never a disposable proxy lifetime. The
// component owner must Dispose on actual OnDestroy/plugin teardown. Scene
// transition alone does not destroy DontDestroyOnLoad owners.
public sealed class NativeCallbackScope:IDisposable
{
    private readonly List<(System.Action Unsubscribe,System.Action Close)> entries=new();
    private bool disposed;
    public void Own(System.Action unsubscribe,System.Action close)
    {
        ActionRuntime.RequireMain();ArgumentNullException.ThrowIfNull(unsubscribe);ArgumentNullException.ThrowIfNull(close);
        ObjectDisposedException.ThrowIf(disposed,this);entries.Add((unsubscribe,close));
    }
    public void Dispose()
    {
        ActionRuntime.RequireMain();if(disposed)return;disposed=true;
        var cleanup=entries;Exception? first=null;
        void Capture(Exception error)
        {
            if(first is null)first=error;
            else if(error is NativeGameException native)try{native.Dispose();}catch{}
        }
        for(int i=cleanup.Count-1;i>=0;--i)try{cleanup[i].Unsubscribe();}catch(Exception error){Capture(error);}
        for(int i=cleanup.Count-1;i>=0;--i)try{cleanup[i].Close();}catch(Exception error){Capture(error);}
        cleanup.Clear();
        if(first!=null)ExceptionDispatchInfo.Capture(first).Throw();
    }
}
