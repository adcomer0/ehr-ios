using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Reflection.Metadata.Ecma335;
using System.Buffers.Binary;
using System.Text.Json;
// Metadata-only audit. The target assembly is never loaded or executed.
if(args.Length!=3)throw new ArgumentException("managed.dll input-manifest.json report.json");
using var stream=File.OpenRead(args[0]);using var pe=new PEReader(stream);
var reader=pe.GetMetadataReader();
var actual=reader.ManifestResources.Select(h=>reader.GetString(reader.GetManifestResource(h).Name)).Order().ToArray();
using var json=JsonDocument.Parse(File.ReadAllText(args[1]));
var expected=json.RootElement.GetProperty("resources").EnumerateArray().Select(r=>r.GetProperty("logicalName").GetString()!).Order().ToArray();
var references=reader.AssemblyReferences.Select(h=>reader.GetString(reader.GetAssemblyReference(h).Name)).Order().ToArray();
bool resourceNames=actual.SequenceEqual(expected);
bool noGameReferences=!references.Any(r=>r is "Assembly-CSharp" or "Il2CppInterop.Runtime" or "Il2Cppmscorlib" || r.StartsWith("UnityEngine.") || r.StartsWith("AmongUs.GameLibs"));
bool actionExtensionFound=false,actionExtensionSelfCalls=false;
foreach(var handle in reader.TypeDefinitions)
{
    var type=reader.GetTypeDefinition(handle);
    if(reader.GetString(type.Namespace)!="EHR"||reader.GetString(type.Name)!="UnityActionDelegateFix")continue;
    foreach(var methodHandle in type.GetMethods())
    {
        var method=reader.GetMethodDefinition(methodHandle);
        if(reader.GetString(method.Name)!="AddListener")continue;
        actionExtensionFound=true;var il=pe.GetMethodBody(method.RelativeVirtualAddress).GetILBytes()!;
        int self=MetadataTokens.GetToken(methodHandle);
        for(int i=0;i+4<il.Length;i++)
            if(il[i]==0x28&&BinaryPrimitives.ReadInt32LittleEndian(il.AsSpan(i+1,4))==self)actionExtensionSelfCalls=true;
    }
}
var proof=new{metadataOnly=true,targetAssemblyExecuted=false,resourceNamesExact=resourceNames,resourceCount=actual.Length,noGameAssemblyReferences=noGameReferences,assemblyReferences=references,sourceUnityActionExtensionFound=actionExtensionFound,sourceUnityActionExtensionCallsItself=actionExtensionSelfCalls};
File.WriteAllText(args[2],JsonSerializer.Serialize(proof,new JsonSerializerOptions{WriteIndented=true}));
Console.WriteLine(JsonSerializer.Serialize(proof));
return resourceNames&&noGameReferences&&actionExtensionFound&&!actionExtensionSelfCalls?0:1;
