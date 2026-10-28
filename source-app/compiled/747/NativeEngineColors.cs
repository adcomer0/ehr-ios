using System;
using System.Runtime.InteropServices;
namespace EHR.Generated;
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct EngineColorTable
{
    internal uint AbiVersion,ByteSize;
    internal delegate* unmanaged[Cdecl]<ulong,int*,uint*,int> ParseHtml;
}
internal static unsafe class NativeEngineColors
{
    private static EngineColorTable table;private static bool bound,engineAbsent;
    // 0=unattempted, 1=actual engine, 2=documented compatibility implementation.
    private static int implementation;
    internal static bool Parse(string? text,out uint rgba)
    {
        if(!bound)throw new RuntimeGatewayException(1,"engine Color icall bridge not bound");
        if(engineAbsent){implementation=2;return HtmlColorCompatibility.Parse(text,out rgba);}
        using var input=FacadeRuntime.String(text);
        int parsed=0;uint packed=0;int status=table.ParseHtml(input.Token,&parsed,&packed);
        if(status==3){engineAbsent=true;implementation=2;return HtmlColorCompatibility.Parse(text,out rgba);}
        FacadeRuntime.Require(status,"pinned engine Color HTML parser");implementation=1;
        if(parsed!=0&&parsed!=1)throw new RuntimeGatewayException(5,"engine parser boolean");
        rgba=packed;return parsed!=0;
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_engine_color_implementation")]
    internal static int Implementation()=>implementation;
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_bind_engine_colors")]
    internal static int Bind(EngineColorTable* source,nuint size)
    {
        if(source==null||size!=(nuint)sizeof(EngineColorTable)||source->AbiVersion!=1||source->ByteSize!=sizeof(EngineColorTable)||source->ParseHtml==null)return 4;
        table=*source;bound=true;return 0;
    }
}
