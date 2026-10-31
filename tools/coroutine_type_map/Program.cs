// Metadata-only map of source IEnumerator type identities; never load an
// inspected assembly, read method bodies/resources or resolve game dependencies.
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
static string FullName(MetadataReader r,TypeDefinitionHandle h){var t=r.GetTypeDefinition(h);var p=t.GetDeclaringType();if(!p.IsNil)return FullName(r,p)+"+"+r.GetString(t.Name);string ns=r.GetString(t.Namespace);return (ns.Length==0?"":ns+".")+r.GetString(t.Name);}
static bool ClrIterator(MetadataReader r,TypeDefinition type){foreach(var h in type.GetInterfaceImplementations()){var i=r.GetInterfaceImplementation(h).Interface;if(i.Kind!=HandleKind.TypeReference)continue;var t=r.GetTypeReference((TypeReferenceHandle)i);if(r.GetString(t.Namespace)=="System.Collections"&&r.GetString(t.Name)=="IEnumerator")return true;}return false;}
static ulong Hash(string text){ulong hash=14695981039346656037UL;foreach(byte b in Encoding.UTF8.GetBytes(text))hash=unchecked((hash^b)*1099511628211UL);return hash;}
if(args.Length!=1)return 2;
try{
 using var input=File.OpenRead(args[0]);using var pe=new PEReader(input);var r=pe.GetMetadataReader();
 var entries=new List<object>();var seen=new Dictionary<ulong,string>();int generic=0;
 foreach(var h in r.TypeDefinitions){var type=r.GetTypeDefinition(h);if(!ClrIterator(r,type))continue;string name=FullName(r,h);
  if(type.GetGenericParameters().Count!=0){++generic;continue;} // Constructed generic FullName needs actual runtime arguments.
  if(name.Length>1024)continue;ulong hash=Hash(name);if(seen.TryGetValue(hash,out string? other)&&other!=name)return 4;seen[hash]=name;
  entries.Add(new{typeHash=hash.ToString(System.Globalization.CultureInfo.InvariantCulture),typeHashHex=hash.ToString("x16"),fullName=name});
 }
 using var hashInput=File.OpenRead(args[0]);Console.WriteLine(JsonSerializer.Serialize(new{schema="ehr.source-coroutine-type-map.v1",assemblySha256=Convert.ToHexString(SHA256.HashData(hashInput)).ToLowerInvariant(),hashEncoding="FNV1a64 UTF8 Type.FullName",entries,genericTypeDefinitionsOmitted=generic,assemblyExecuted=false,methodBodiesRead=false}));return 0;
}catch(Exception e){Console.Error.WriteLine("Coroutine type metadata read failed: "+e.GetType().Name);return 5;}
