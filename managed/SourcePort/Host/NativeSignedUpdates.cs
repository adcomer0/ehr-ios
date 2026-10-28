using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using EHR.Generated;
namespace EHR.SourceHost;
public static unsafe class NativeSignedUpdates
{
    [UnmanagedCallersOnly(EntryPoint="ehr_source_updates_configure",CallConvs=new[]{typeof(CallConvCdecl)})]
    public static int Configure(byte* url,nuint length)
    {
        if(!NativeSourceHost.IsMainThread)return 2;
        if(length>2048||(length!=0&&url==null))return 4;
        try
        {
            Uri? instructions=length==0?null:new Uri(new UTF8Encoding(false,true).GetString(new ReadOnlySpan<byte>(url,(int)length)),UriKind.Absolute);
            SourceSignedUpdates.Configure(instructions,instructions==null?null:uri=>UnityEngine_Application.OpenURL(uri.AbsoluteUri),()=>NativeSourceHost.IsMainThread);
            return 0;
        }
        catch(UriFormatException){return 4;}
        catch(ArgumentException){return 4;}
        catch(InvalidOperationException){return 4;}
        catch{return 6;}
    }
}
