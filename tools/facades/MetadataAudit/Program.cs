using System.Collections.Immutable;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Text.Json;

if (args.Length < 2 || args.Length > 3 || (args.Length == 3 && args[2] != "--definitions"))
{
    Console.Error.WriteLine("Usage: MetadataAudit input-managed.dll output.json [--definitions]; reads metadata only, never loads assembly.");
    return 2;
}
using var stream = File.OpenRead(args[0]);
using var pe = new PEReader(stream, PEStreamOptions.LeaveOpen);
if (!pe.HasMetadata) throw new BadImageFormatException("Input is not a managed metadata image.");
MetadataReader reader = pe.GetMetadataReader();
var types = new TypeNames(reader);
bool HasAttribute(CustomAttributeHandleCollection attributes,string exactName)
{
    foreach(var handle in attributes)
    {
        var constructor=reader.GetCustomAttribute(handle).Constructor;
        EntityHandle owner=constructor.Kind==HandleKind.MemberReference
            ?reader.GetMemberReference((MemberReferenceHandle)constructor).Parent
            :constructor.Kind==HandleKind.MethodDefinition
                ?reader.GetMethodDefinition((MethodDefinitionHandle)constructor).GetDeclaringType():default;
        if(!owner.IsNil&&types.Entity(owner).EndsWith("]"+exactName,StringComparison.Ordinal))return true;
    }
    return false;
}
var assemblies = reader.AssemblyReferences.Select(h =>
{
    var a = reader.GetAssemblyReference(h);
    return new { name = reader.GetString(a.Name), version = a.Version.ToString() };
}).OrderBy(a => a.name).ToArray();
var rows = new List<MemberRow>();
foreach (MemberReferenceHandle handle in reader.MemberReferences)
{
    MemberReference member = reader.GetMemberReference(handle);
    string parent = types.Entity(member.Parent), assembly = types.Assembly(member.Parent);
    if (assembly == "<local>") continue;
    string name = reader.GetString(member.Name);
    if (member.GetKind() == MemberReferenceKind.Field)
    {
        string fieldType = member.DecodeFieldSignature(types, null);
        rows.Add(new(MetadataTokens.GetToken(handle), assembly, parent, name, "field", fieldType,
            [], null, 0, fieldType.Contains('&'), fieldType.Contains('*')));
    }
    else
    {
        MethodSignature<string> signature = member.DecodeMethodSignature(types, null);
        var parameters = signature.ParameterTypes.ToArray();
        rows.Add(new(MetadataTokens.GetToken(handle), assembly, parent, name, "method",
            signature.ReturnType, parameters, !signature.Header.IsInstance,
            signature.GenericParameterCount,
            parameters.Any(p => p.Contains('&')) || signature.ReturnType.Contains('&'),
            parameters.Any(p => p.Contains('*')) || signature.ReturnType.Contains('*')));
    }
}
var summary = rows.GroupBy(r => r.Assembly).OrderBy(g => g.Key).Select(g => new
{
    assembly = g.Key, memberReferenceCount = g.Count(),
    distinctDeclaringTypes = g.Select(r => r.DeclaringType).Distinct().Count(),
    methodReferences = g.Count(r => r.Kind == "method"), fieldReferences = g.Count(r => r.Kind == "field"),
    byRefSignatures = g.Count(r => r.HasByRef), pointerSignatures = g.Count(r => r.HasPointer),
    genericMethodReferences = g.Count(r => r.GenericArity != 0),
    genericDeclaringTypeReferences = g.Count(r => r.DeclaringType.Contains('<'))
}).ToArray();
stream.Position = 0;
var definitions = args.Length == 3 ? reader.TypeDefinitions.Select(h =>
{
    TypeDefinition definition = reader.GetTypeDefinition(h);
    return new {
        name = types.Entity(h), baseType = definition.BaseType.IsNil ? null : types.Entity(definition.BaseType),
        isInterface = (definition.Attributes & System.Reflection.TypeAttributes.Interface) != 0,
        interfaces = definition.GetInterfaceImplementations().Select(ih => types.Entity(reader.GetInterfaceImplementation(ih).Interface)).ToArray(),
        packingSize = definition.GetLayout().PackingSize, declaredSize = definition.GetLayout().Size,
        fields = definition.GetFields().Select(fh => {
            var field = reader.GetFieldDefinition(fh);
            return new { name = reader.GetString(field.Name), type = field.DecodeSignature(types, null),
                isStatic = (field.Attributes & System.Reflection.FieldAttributes.Static) != 0,
                isReadOnly = (field.Attributes & (System.Reflection.FieldAttributes.InitOnly | System.Reflection.FieldAttributes.Literal)) != 0,
                constant = field.GetDefaultValue().IsNil ? null : reader.GetBlobReader(reader.GetConstant(field.GetDefaultValue()).Value)
                    .ReadConstant(reader.GetConstant(field.GetDefaultValue()).TypeCode) };
        }).ToArray(),
        methods = definition.GetMethods().Select(mh => {
            var method = reader.GetMethodDefinition(mh);
            var signature = method.DecodeSignature(types, null);
            var parameterDefinitions = method.GetParameters().Select(ph=>reader.GetParameter(ph)).Where(p=>p.SequenceNumber>0).ToDictionary(p=>p.SequenceNumber);
            var parameterAttributes = method.GetParameters().Select(ph => reader.GetParameter(ph))
                .Where(p => p.SequenceNumber > 0).ToDictionary(p => p.SequenceNumber, p => p.Attributes);
            return new { name = reader.GetString(method.Name), returnType = signature.ReturnType,
                parameters = signature.ParameterTypes.ToArray(), genericArity = signature.GenericParameterCount,
                isExtension = HasAttribute(method.GetCustomAttributes(),"System.Runtime.CompilerServices.ExtensionAttribute"),
                parameterIsParams = signature.ParameterTypes.Select((_,i)=>parameterDefinitions.TryGetValue(i+1,out var p)&&HasAttribute(p.GetCustomAttributes(),"System.ParamArrayAttribute")).ToArray(),
                parameterNames = signature.ParameterTypes.Select((_,i)=>parameterDefinitions.TryGetValue(i+1,out var p)&&!p.Name.IsNil?reader.GetString(p.Name):"p"+i).ToArray(),
                parameterDefaults = signature.ParameterTypes.Select((_,i)=>parameterDefinitions.TryGetValue(i+1,out var p)&&!p.GetDefaultValue().IsNil?new {value=reader.GetBlobReader(reader.GetConstant(p.GetDefaultValue()).Value).ReadConstant(reader.GetConstant(p.GetDefaultValue()).TypeCode)}:null).ToArray(),
                parameterModes = signature.ParameterTypes.Select((p,i) => !p.EndsWith('&') ? "value" :
                    parameterAttributes.TryGetValue(i+1,out var flags) && (flags & System.Reflection.ParameterAttributes.Out) != 0 &&
                    (flags & System.Reflection.ParameterAttributes.In) == 0 ? "out" : "ref").ToArray(),
                isStatic = (method.Attributes & System.Reflection.MethodAttributes.Static) != 0 };
        }).ToArray()
    };
}).ToArray() : null;
var report = new
{
    formatVersion = 1,
    scope = "External metadata reference inventory only. Reference counts are not feature counts, reachability, executable coverage or gameplay parity. No assembly was loaded or executed.",
    inputFileName = Path.GetFileName(args[0]), inputSha256 = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant(),
    assemblyName = reader.IsAssembly ? reader.GetString(reader.GetAssemblyDefinition().Name) : null,
    assemblyReferences = assemblies, externalMemberReferenceCount = rows.Count, byAssembly = summary,
    typeReferences = reader.TypeReferences.Select(h => new { assembly = types.Assembly(h), name = types.Entity(h) }).ToArray(),
    typeDefinitions = definitions,
    gatewayAbi1Gaps = new[] { "byref/pointer parameters", "generic method inflation", "value-type receivers", "live collection/array operations", "delegate/event/coroutine translation", "field metadata staticness must be resolved against native runtime" },
    members = rows.OrderBy(r => r.Assembly).ThenBy(r => r.DeclaringType).ThenBy(r => r.Name).ToArray()
};
var options = new JsonSerializerOptions { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase, NumberHandling = System.Text.Json.Serialization.JsonNumberHandling.AllowNamedFloatingPointLiterals };
string output = Path.GetFullPath(args[1]);
Directory.CreateDirectory(Path.GetDirectoryName(output)!);
File.WriteAllText(output, JsonSerializer.Serialize(report, options));
Console.WriteLine(JsonSerializer.Serialize(new { externalMemberReferenceCount = rows.Count, byAssembly = summary }, options));
return 0;

record MemberRow(int MetadataToken, string Assembly, string DeclaringType, string Name, string Kind,
    string ReturnOrFieldType, string[] ParameterTypes, bool? IsStatic, int GenericArity, bool HasByRef, bool HasPointer);

sealed class TypeNames(MetadataReader reader) : ISignatureTypeProvider<string, object?>
{
    public string Entity(EntityHandle handle) => handle.Kind switch
    {
        HandleKind.TypeReference => GetTypeFromReference(reader, (TypeReferenceHandle)handle, 0),
        HandleKind.TypeDefinition => GetTypeFromDefinition(reader, (TypeDefinitionHandle)handle, 0),
        HandleKind.TypeSpecification => GetTypeFromSpecification(reader, null, (TypeSpecificationHandle)handle, 0),
        HandleKind.MethodDefinition => Entity(reader.GetMethodDefinition((MethodDefinitionHandle)handle).GetDeclaringType()),
        HandleKind.ModuleReference => "[" + reader.GetString(reader.GetModuleReference((ModuleReferenceHandle)handle).Name) + "]<module>",
        _ => "<" + handle.Kind + ">"
    };
    public string Assembly(EntityHandle handle)
    {
        if (handle.Kind == HandleKind.TypeReference)
        {
            EntityHandle scope = reader.GetTypeReference((TypeReferenceHandle)handle).ResolutionScope;
            return scope.Kind == HandleKind.AssemblyReference
                ? reader.GetString(reader.GetAssemblyReference((AssemblyReferenceHandle)scope).Name)
                : scope.Kind == HandleKind.TypeReference ? Assembly(scope) : "<local>";
        }
        if (handle.Kind == HandleKind.TypeSpecification)
        {
            string text = Entity(handle);
            int begin = text.IndexOf('['), end = text.IndexOf(']');
            return begin == 0 && end > 0 ? text[1..end] : "<local>";
        }
        return "<local>";
    }
    public string GetTypeFromReference(MetadataReader r, TypeReferenceHandle handle, byte rawTypeKind)
    {
        TypeReference type = r.GetTypeReference(handle);
        string name = r.GetString(type.Name), ns = r.GetString(type.Namespace);
        if (type.ResolutionScope.Kind == HandleKind.TypeReference)
            return Entity(type.ResolutionScope) + "+" + name;
        return "[" + Assembly(handle) + "]" + (ns.Length == 0 ? "" : ns + ".") + name;
    }
    public string GetTypeFromDefinition(MetadataReader r, TypeDefinitionHandle handle, byte rawTypeKind)
    {
        TypeDefinition type = r.GetTypeDefinition(handle);
        string name = r.GetString(type.Name), ns = r.GetString(type.Namespace);
        TypeDefinitionHandle declaring = type.GetDeclaringType();
        return declaring.IsNil ? "[<local>]" + (ns.Length == 0 ? "" : ns + ".") + name : Entity(declaring) + "+" + name;
    }
    public string GetTypeFromSpecification(MetadataReader r, object? context, TypeSpecificationHandle handle, byte rawTypeKind)
        => r.GetTypeSpecification(handle).DecodeSignature(this, context);
    public string GetArrayType(string elementType, ArrayShape shape) => elementType + "[" + new string(',', Math.Max(0, shape.Rank - 1)) + "]";
    public string GetByReferenceType(string elementType) => elementType + "&";
    public string GetFunctionPointerType(MethodSignature<string> signature) => "fnptr(" + string.Join(",", signature.ParameterTypes) + ")->" + signature.ReturnType;
    public string GetGenericInstantiation(string genericType, ImmutableArray<string> typeArguments) => genericType + "<" + string.Join(",", typeArguments) + ">";
    public string GetGenericMethodParameter(object? context, int index) => "!!" + index;
    public string GetGenericTypeParameter(object? context, int index) => "!" + index;
    public string GetModifiedType(string modifier, string unmodifiedType, bool isRequired) => unmodifiedType + (isRequired ? " modreq(" : " modopt(") + modifier + ")";
    public string GetPinnedType(string elementType) => elementType + " pinned";
    public string GetPointerType(string elementType) => elementType + "*";
    public string GetSZArrayType(string elementType) => elementType + "[]";
    public string GetPrimitiveType(PrimitiveTypeCode typeCode) => "System." + typeCode;
}
