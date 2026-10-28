using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
namespace EHR.Generated;
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct TypeNamesTable
{
    internal uint AbiVersion,ByteSize;
    internal delegate* unmanaged[Cdecl]<ulong,byte*,nuint,nuint*,int> ClassTypeName;
    internal delegate* unmanaged[Cdecl]<ulong,ulong*,int> VectorClass;
}
internal readonly record struct NativeTypeDescriptor(string Canonical,string Image,string Namespace,string Type);
internal static unsafe class NativeTypeNames
{
    private static TypeNamesTable table;
    private static bool bound;
    private static readonly Dictionary<string,ulong> classes=new(StringComparer.Ordinal);
    private static readonly Dictionary<string,string> names=new(StringComparer.Ordinal);
    private static readonly Dictionary<string,NativeTypeDescriptor> descriptors=BuildDescriptors();
    private static Dictionary<string,NativeTypeDescriptor> BuildDescriptors()
    {
        var result=new Dictionary<string,NativeTypeDescriptor>(StringComparer.Ordinal);
        foreach(var descriptor in GeneratedNativeTypes.All)result.Add(descriptor.Canonical,descriptor);
        foreach(string type in new[]{"Void","Object","String","Type","Array","Exception","Boolean","Byte","SByte","Char","Int16","UInt16","Int32","UInt32","Int64","UInt64","Single","Double","IDisposable","Action","Delegate","DateTime","Version"})
            result.TryAdd("System."+type,new("System."+type,"mscorlib.dll","System",type));
        foreach(string type in new[]{"IEnumerable","IEnumerator","ICollection","IList","IDictionary","IDictionaryEnumerator"})
            result.TryAdd("System.Collections."+type,new("System.Collections."+type,"mscorlib.dll","System.Collections",type));
        foreach(string type in new[]{"MemberInfo","MethodBase","MethodInfo","ParameterInfo","ConstructorInfo","TargetInvocationException"})result.TryAdd("System.Reflection."+type,new("System.Reflection."+type,"mscorlib.dll","System.Reflection",type));
        foreach((string type,int arity) in new[]{("List",1),("Dictionary",2)})
            result.TryAdd("System.Collections.Generic."+type+"`"+arity,new("System.Collections.Generic."+type+"`"+arity,"mscorlib.dll","System.Collections.Generic",type+"`"+arity));
        result.TryAdd("System.Collections.Generic.Queue`1",new("System.Collections.Generic.Queue`1","mscorlib.dll","System.Collections.Generic","Queue`1"));
        result.TryAdd("System.Func`1",new("System.Func`1","mscorlib.dll","System","Func`1"));
        result.TryAdd("System.Action`1",new("System.Action`1","mscorlib.dll","System","Action`1"));
        result.TryAdd("System.Action`3",new("System.Action`3","mscorlib.dll","System","Action`3"));
        result.TryAdd("System.Func`2",new("System.Func`2","mscorlib.dll","System","Func`2"));
        result.TryAdd("System.Text.StringBuilder",new("System.Text.StringBuilder","mscorlib.dll","System.Text","StringBuilder"));
        result.TryAdd("System.Collections.Generic.HashSet`1",new("System.Collections.Generic.HashSet`1","System.Core.dll","System.Collections.Generic","HashSet`1"));
        return result;
    }
    internal static string RuntimeName(string canonical)
    {
        if(!bound)throw new RuntimeGatewayException(1,"runtime type names not bound");
        if(names.TryGetValue(canonical,out string? cached))return cached;
        // Scalar ref/out spellings are pinned by the actual13 TryGet tests.
        string result=canonical.EndsWith('&')?RuntimeName(canonical[..^1])+"&":ReadName(Class(canonical));
        names.Add(canonical,result);return result;
    }
    internal static ulong VectorClass(ulong element)
    {
        if(!bound)throw new RuntimeGatewayException(1,"runtime type names not bound");
        ulong result=0;FacadeRuntime.Require(table.VectorClass(element,&result),"SZ array metadata class");return result;
    }
    internal static ulong Class(string canonical)
    {
        if(!bound)throw new RuntimeGatewayException(1,"runtime type names not bound");
        if(classes.TryGetValue(canonical,out ulong cached))return cached;
        ulong result;
        if(canonical.EndsWith("[]",StringComparison.Ordinal))
        {
            ulong element=Class(canonical[..^2]);result=0;
            FacadeRuntime.Require(table.VectorClass(element,&result),"SZ array class "+canonical);
        }
        else if(canonical.Contains('<'))
        {
            int start=canonical.IndexOf('<');
            if(start<1||canonical[^1]!='>')throw new RuntimeGatewayException(4,"malformed constructed type descriptor");
            string root=canonical[..start];var arguments=SplitArguments(canonical[(start+1)..^1]);
            ulong[] argumentClasses=new ulong[arguments.Length];
            for(int i=0;i<arguments.Length;++i)argumentClasses[i]=Class(arguments[i]);
            // Open metadata classes retain their actual `arity names. Closed
            // names always come from class_type_name after real inflation.
            result=LiveReflection.MakeGenericClass(Class(root+"`"+arguments.Length),argumentClasses);
        }
        else
        {
            if(!descriptors.TryGetValue(canonical,out var descriptor))throw new RuntimeGatewayException(7,"no exact native type descriptor: "+canonical);
            result=FacadeRuntime.Class(descriptor.Image,descriptor.Namespace,descriptor.Type);
        }
        if(result==0)throw new RuntimeGatewayException(9,"null metadata type token");
        classes.Add(canonical,result);return result;
    }
    private static string[] SplitArguments(string text)
    {
        var result=new List<string>();int depth=0,start=0;
        for(int i=0;i<text.Length;++i)
        {
            if(text[i]=='<')++depth;
            else if(text[i]=='>'){if(--depth<0)throw new RuntimeGatewayException(4,"unbalanced generic descriptor");}
            else if(text[i]==','&&depth==0){result.Add(text[start..i].Trim());start=i+1;}
        }
        if(depth!=0)throw new RuntimeGatewayException(4,"unbalanced generic descriptor");
        result.Add(text[start..].Trim());
        if(result.Count>32||result.Exists(x=>x.Length==0))throw new RuntimeGatewayException(4,"invalid generic descriptor arity");
        return result.ToArray();
    }
    private static string ReadName(ulong klass)
    {
        nuint count=0;int status=table.ClassTypeName(klass,null,0,&count);
        if(status!=0&&status!=8)FacadeRuntime.Require(status,"query native type name length");
        if(count<1||count>8192)throw new RuntimeGatewayException(8,"native type name limit");
        nuint capacity=count;byte* buffer=(byte*)NativeMemory.Alloc(capacity);
        try
        {
            FacadeRuntime.Require(table.ClassTypeName(klass,buffer,capacity,&count),"copy native type name");
            if(count<1||count>capacity||buffer[count-1]!=0)throw new RuntimeGatewayException(5,"native type name terminator");
            var bytes=new ReadOnlySpan<byte>(buffer,checked((int)count-1));
            if(bytes.IndexOf((byte)0)>=0)throw new RuntimeGatewayException(5,"embedded NUL in native type name");
            return new UTF8Encoding(false,true).GetString(bytes);
        }
        finally{NativeMemory.Free(buffer);}
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_bind_type_names")]
    internal static int Bind(TypeNamesTable* source,nuint size)
    {
        if(source==null||size!=(nuint)sizeof(TypeNamesTable)||source->AbiVersion!=1||source->ByteSize!=sizeof(TypeNamesTable)||source->ClassTypeName==null||source->VectorClass==null)return 4;
        table=*source;classes.Clear();names.Clear();bound=true;return 0;
    }
}
