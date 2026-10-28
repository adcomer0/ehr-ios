using System;
using System.Collections.Generic;
namespace EHR.Generated;
internal static unsafe class NativeGenericMethods
{
    private static readonly Dictionary<string,ulong> cache=new(StringComparer.Ordinal);
    internal static int LastLookupStep { get; private set; }
    internal static void Reset()=>cache.Clear();
    private static RuntimeObject Reflection(RuntimeObject value,string owner,string name,string result)
        =>FacadeRuntime.Invoke(new("mscorlib.dll","System.Reflection",owner,name,false,false,result,[]),value.Token,null,0);
    private static RuntimeObject TypeCall(RuntimeObject value,string name,string result)
        =>FacadeRuntime.Invoke(new("mscorlib.dll","System","Type",name,false,false,result,[]),value.Token,null,0);
    private static bool Bool(RuntimeObject value,string owner,string name)
    {using var result=Reflection(value,owner,name,"System.Boolean");return FacadeRuntime.ReadValue<bool>(result);}
    private static bool Pattern(RuntimeObject type,string pattern,ReadOnlySpan<ulong> arguments,bool open)
    {
        if(pattern.EndsWith("[]",StringComparison.Ordinal))
        {
            using var array=TypeCall(type,"get_IsArray","System.Boolean");
            if(!FacadeRuntime.ReadValue<bool>(array))return false;
            using var rank=TypeCall(type,"GetArrayRank","System.Int32");
            if(FacadeRuntime.ReadValue<int>(rank)!=1)return false;
            using var element=TypeCall(type,"GetElementType","System.Type");
            if(!Pattern(element,pattern[..^2],arguments,open))return false;
            // Closed validation distinguishes an SZ vector from a bounded rank-1
            // array using real class metadata rather than a type-name rewrite.
            return open||LiveReflection.ClassFromTypeObject(type)==NativeTypeNames.VectorClass(Resolve(pattern[..^2],arguments));
        }
        if(pattern.StartsWith("!!",StringComparison.Ordinal))
        {
            if(!int.TryParse(pattern.AsSpan(2),out int index)||index<0||index>=arguments.Length)throw new RuntimeGatewayException(7,"generic type pattern");
            if(!open)return LiveReflection.ClassFromTypeObject(type)==arguments[index];
            using var generic=TypeCall(type,"get_IsGenericParameter","System.Boolean");
            if(!FacadeRuntime.ReadValue<bool>(generic))return false;
            using var position=TypeCall(type,"get_GenericParameterPosition","System.Int32");
            return FacadeRuntime.ReadValue<int>(position)==index;
        }
        return LiveReflection.ClassFromTypeObject(type)==NativeTypeNames.Class(pattern);
    }
    private static ulong Resolve(string pattern,ReadOnlySpan<ulong> arguments)
    {
        if(pattern.StartsWith("!!",StringComparison.Ordinal))return arguments[int.Parse(pattern.AsSpan(2))];
        return NativeTypeNames.Class(pattern);
    }
    private static bool Signature(RuntimeObject method,ulong owner,string resultPattern,ReadOnlySpan<string> patterns,ReadOnlySpan<ulong> arguments,bool isStatic,bool open)
    {
        using var declaring=Reflection(method,"MemberInfo","get_DeclaringType","System.Type");
        if(LiveReflection.ClassFromTypeObject(declaring)!=owner||Bool(method,"MethodBase","get_IsStatic")!=isStatic)return false;
        using var generic=Reflection(method,"MethodBase","GetGenericArguments","System.Type[]");
        if(LiveCollections.Length(generic)!=arguments.Length)return false;
        if(!open)for(int i=0;i<arguments.Length;++i)
        {using var type=LiveCollections.Get(generic,i);if(LiveReflection.ClassFromTypeObject(type)!=arguments[i])return false;}
        using var result=Reflection(method,"MethodInfo","get_ReturnType","System.Type");
        if(!Pattern(result,resultPattern,arguments,open))return false;
        using var parameters=Reflection(method,"MethodBase","GetParameters","System.Reflection.ParameterInfo[]");
        if(LiveCollections.Length(parameters)!=patterns.Length)return false;
        for(int i=0;i<patterns.Length;++i)
        {
            using var parameter=LiveCollections.Get(parameters,i);
            using var type=Reflection(parameter,"ParameterInfo","get_ParameterType","System.Type");
            if(!Pattern(type,patterns[i],arguments,open))return false;
        }
        return true;
    }
    internal static ulong Lookup(ulong owner,string name,string resultPattern,ReadOnlySpan<string> patterns,ReadOnlySpan<ulong> arguments,bool isStatic)
    {
        if(arguments.Length!=1||patterns.Length>16)throw new RuntimeGatewayException(7,"generic method adapter shape");
        string key=owner+"/"+name+"/"+resultPattern+"/"+isStatic+"/"+string.Join(",",patterns.ToArray())+"/"+string.Join(",",arguments.ToArray());
        if(cache.TryGetValue(key,out ulong cached))return cached;
        LastLookupStep=1;
        using var type=LiveCollections.TypeObject(owner);
        using var methods=TypeCall(type,"GetMethods","System.Reflection.MethodInfo[]");
        int count=checked((int)LiveCollections.Length(methods));
        if(count>8192)throw new RuntimeGatewayException(8,"public method discovery limit");
        ulong openMethod=0;
        for(int i=0;i<count;++i)
        {
            using var candidate=LiveCollections.Get(methods,i);
            using var candidateName=Reflection(candidate,"MemberInfo","get_Name","System.String");
            if(FacadeRuntime.ReadString(candidateName)!=name||!Bool(candidate,"MethodBase","get_IsGenericMethodDefinition"))continue;
            if(!Signature(candidate,owner,resultPattern,patterns,arguments,isStatic,true))continue;
            if(openMethod!=0)throw new RuntimeGatewayException(10,"ambiguous exact generic method");
            openMethod=NativeMethods.FromObject(candidate);
        }
        LastLookupStep=2;
        if(openMethod==0)throw new RuntimeGatewayException(3,"exact open generic method "+name);
        ulong closed=NativeMethods.MakeGeneric(openMethod,arguments);
        LastLookupStep=3;
        using var reflected=NativeMethods.ToObject(closed);
        if(!Signature(reflected,owner,resultPattern,patterns,arguments,isStatic,false)||Bool(reflected,"MethodBase","get_IsGenericMethodDefinition"))throw new RuntimeGatewayException(5,"closed generic method exact signature");
        LastLookupStep=4;
        if(NativeMethods.FromObject(reflected)!=closed)throw new RuntimeGatewayException(5,"closed reflected method roundtrip");
        cache.Add(key,closed);return closed;
    }
}
