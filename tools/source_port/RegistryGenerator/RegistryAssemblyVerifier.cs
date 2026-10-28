using System.Reflection;
using System.Reflection.Emit;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Text.Json;

// Reads the generated source's compiled result as metadata/IL only. Does not
// Assembly.Load EHR or execute any role/game constructor or static initializer.
static class RegistryAssemblyVerifier
{
    public static object Verify(string assemblyPath, string coveragePath)
    {
        using var stream = File.OpenRead(assemblyPath);
        using var pe = new PEReader(stream);
        MetadataReader metadata = pe.GetMetadataReader();
        using var document = JsonDocument.Parse(File.ReadAllText(coveragePath));
        JsonElement coverage = document.RootElement;
        var names = metadata.TypeDefinitions.ToDictionary(h => h, FullName);
        TypeDefinitionHandle registry = names.Single(p => p.Value == "EHR.EHRAotRegistry").Key;
        var methods = metadata.GetTypeDefinition(registry).GetMethods()
            .ToDictionary(h => metadata.GetString(metadata.GetMethodDefinition(h).Name));
        var results = new List<object>();
        foreach (JsonElement group in coverage.GetProperty("groups").EnumerateArray())
        {
            string id = group.GetProperty("id").GetString()!, contract = group.GetProperty("contract").GetString()!;
            string[] expected = group.GetProperty("rows").EnumerateArray().Select(r => r.GetProperty("type").GetString()!).Order().ToArray();
            string[] actual = names.Where(pair => Selected(pair.Key, id, contract)).Select(pair => pair.Value).Order().ToArray();
            Equal(expected, actual, id + " original reflection filter membership");
            JsonElement[] rows = group.GetProperty("rows").EnumerateArray().ToArray();
            string[] expectedArray = rows.Where(r => !r.GetProperty("rejections").EnumerateArray()
                .Any(s => s.GetString() is "not_accessible_from_generated_assembly_scope" or "open_generic_type"))
                .Select(r => r.GetProperty("type").GetString()!).Order().ToArray();
            string[] typeTokens = Instructions(methods[id + "Types"])
                .Where(i => i.opcode == OpCodes.Ldtoken.Value)
                .Select(i => EntityType(MetadataTokens.EntityHandle(i.token))).Order().ToArray();
            Equal(expectedArray, typeTokens, id + " generated typeof array");
            if (id == "Disaster")
            {
                string[] originalOrder = names.Where(pair => Selected(pair.Key, id, contract)).Select(pair => pair.Value).ToArray();
                string[] emittedOrder = Instructions(methods[id + "Types"]).Where(i => i.opcode == OpCodes.Ldtoken.Value)
                    .Select(i => EntityType(MetadataTokens.EntityHandle(i.token))).ToArray();
                Equal(originalOrder, emittedOrder, "Disaster settings-sensitive discovery order");
            }
            string[] expectedConstructed = rows.Where(r => r.GetProperty("status").GetString() == "explicit_constructor")
                .Select(r => r.GetProperty("type").GetString()!).Order().ToArray();
            string[] newObjects = Instructions(methods["Create" + id])
                .Where(i => i.opcode == OpCodes.Newobj.Value)
                .Select(i => ConstructorOwner(MetadataTokens.EntityHandle(i.token)))
                .Where(n => !n.StartsWith("System.", StringComparison.Ordinal)).Order().ToArray();
            Equal(expectedConstructed, newObjects, id + " generated constructor coverage");
            results.Add(new { group = id, compiledDiscoveryMembers = actual.Length,
                generatedTypeTokens = typeTokens.Length, explicitConstructors = newObjects.Length,
                rejectedMembers = actual.Length - expectedConstructed.Length, exactSetEquality = true });
        }
        string[] expectedRandom = coverage.GetProperty("randomMappings").EnumerateArray().Select(m => m.GetProperty("type").GetString()!).Order().ToArray();
        string[] randomConstructors = Instructions(methods["CreateRandomById"])
            .Where(i => i.opcode == OpCodes.Newobj.Value)
            .Select(i => ConstructorOwner(MetadataTokens.EntityHandle(i.token)))
            .Where(n => !n.StartsWith("System.", StringComparison.Ordinal)).Order().ToArray();
        Equal(expectedRandom, randomConstructors, "random ID factory constructor multiplicity");
        JsonElement[] auxiliary = coverage.GetProperty("auxiliaryDispatch").EnumerateArray().ToArray();
        string[] expectedSetup = auxiliary.Where(a => a.GetProperty("kind").GetString() == "disaster_option_setup"
            && a.GetProperty("status").GetString() == "explicit_static_call").Select(a => a.GetProperty("type").GetString()! + ".SetupOwnCustomOption").Order().ToArray();
        string[] setupCalls = Instructions(methods["SetupDisasterOptions"]).Where(i => i.opcode == OpCodes.Call.Value)
            .Select(i => MethodName(MetadataTokens.EntityHandle(i.token))).Where(n => n.EndsWith(".SetupOwnCustomOption", StringComparison.Ordinal)).Order().ToArray();
        Equal(expectedSetup, setupCalls, "explicit disaster option setup calls");
        string[] expectedCrew = auxiliary.Where(a => a.GetProperty("kind").GetString() == "crew_end_check_declaring_type"
            && a.GetProperty("status").GetString() == "explicit_declaring_type").Select(a => a.GetProperty("type").GetString()!).Order().ToArray();
        string[] crewTokens = Instructions(methods["CrewEndCheckDeclaringTypes"]).Where(i => i.opcode == OpCodes.Ldtoken.Value)
            .Select(i => EntityType(MetadataTokens.EntityHandle(i.token))).Order().ToArray();
        Equal(expectedCrew, crewTokens, "crew end-check declaring type tokens");
        return new { schema = "ehr.aot-registry-compiled-validation.v1", upstreamCommit = coverage.GetProperty("upstreamCommit").GetString(),
            compileProfile = coverage.GetProperty("compileProfile").GetString(),
            assemblySha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(assemblyPath))).ToLowerInvariant(),
            coverageSha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(coveragePath))).ToLowerInvariant(),
            scope = "Read-only PE metadata and IL: exact original filter membership compared to generated typeof arrays and newobj constructors. No assembly load, game execution or gameplay compatibility proof.",
            groups = results, randomFactoryConstructorSites = randomConstructors.Length,
            explicitDisasterOptionSetupCalls = setupCalls.Length, crewEndCheckDeclaringTypes = crewTokens.Length,
            noRoleOrGameAssemblyLoaded = true };

        string FullName(TypeDefinitionHandle handle)
        {
            TypeDefinition type = metadata.GetTypeDefinition(handle);
            string name = metadata.GetString(type.Name);
            return type.GetDeclaringType().IsNil
                ? (type.Namespace.IsNil || metadata.GetString(type.Namespace).Length == 0 ? "" : metadata.GetString(type.Namespace) + ".") + name
                : FullName(type.GetDeclaringType()) + "+" + name;
        }
        string EntityType(EntityHandle handle) => handle.Kind switch
        {
            HandleKind.TypeDefinition => FullName((TypeDefinitionHandle)handle),
            HandleKind.TypeReference => ReferenceName((TypeReferenceHandle)handle),
            _ => throw new InvalidOperationException("Unsupported type token in registry: " + handle.Kind)
        };
        string ReferenceName(TypeReferenceHandle handle)
        {
            TypeReference type = metadata.GetTypeReference(handle);
            string name = metadata.GetString(type.Name), ns = metadata.GetString(type.Namespace);
            return type.ResolutionScope.Kind == HandleKind.TypeReference
                ? ReferenceName((TypeReferenceHandle)type.ResolutionScope) + "+" + name
                : (ns.Length == 0 ? "" : ns + ".") + name;
        }
        bool IsInterface(TypeDefinitionHandle handle) => (metadata.GetTypeDefinition(handle).Attributes & TypeAttributes.Interface) != 0;
        bool IsAbstract(TypeDefinitionHandle handle) => (metadata.GetTypeDefinition(handle).Attributes & TypeAttributes.Abstract) != 0;
        bool Subclass(TypeDefinitionHandle handle, string target)
        {
            var seen = new HashSet<TypeDefinitionHandle>();
            for (EntityHandle parent = metadata.GetTypeDefinition(handle).BaseType; !parent.IsNil && parent.Kind == HandleKind.TypeDefinition;)
            {
                var local = (TypeDefinitionHandle)parent;
                if (!seen.Add(local)) throw new BadImageFormatException("Cyclic source inheritance metadata.");
                if (FullName(local) == target) return true;
                parent = metadata.GetTypeDefinition(local).BaseType;
            }
            return false;
        }
        bool Assignable(TypeDefinitionHandle handle, string target, HashSet<TypeDefinitionHandle> seen)
        {
            if (!seen.Add(handle)) return false;
            if (FullName(handle) == target) return true;
            TypeDefinition type = metadata.GetTypeDefinition(handle);
            foreach (InterfaceImplementationHandle implementation in type.GetInterfaceImplementations())
            {
                EntityHandle iface = metadata.GetInterfaceImplementation(implementation).Interface;
                if (iface.Kind == HandleKind.TypeDefinition && Assignable((TypeDefinitionHandle)iface, target, seen)) return true;
            }
            return !type.BaseType.IsNil && type.BaseType.Kind == HandleKind.TypeDefinition && Assignable((TypeDefinitionHandle)type.BaseType, target, seen);
        }
        bool Selected(TypeDefinitionHandle handle, string id, string contract) => id is "RoleBase" or "Disaster"
            ? !IsInterface(handle) && !IsAbstract(handle) && Subclass(handle, contract)
            : !IsInterface(handle) && Assignable(handle, contract, []);
        string ConstructorOwner(EntityHandle handle)
        {
            if (handle.Kind == HandleKind.MethodDefinition)
                return FullName(metadata.GetMethodDefinition((MethodDefinitionHandle)handle).GetDeclaringType());
            if (handle.Kind == HandleKind.MemberReference)
                return EntityType(metadata.GetMemberReference((MemberReferenceHandle)handle).Parent);
            throw new InvalidOperationException("Unsupported constructor token " + handle.Kind);
        }
        string MethodName(EntityHandle handle)
        {
            if (handle.Kind == HandleKind.MethodDefinition)
            {
                MethodDefinition method = metadata.GetMethodDefinition((MethodDefinitionHandle)handle);
                return FullName(method.GetDeclaringType()) + "." + metadata.GetString(method.Name);
            }
            if (handle.Kind == HandleKind.MemberReference)
            {
                MemberReference method = metadata.GetMemberReference((MemberReferenceHandle)handle);
                return EntityType(method.Parent) + "." + metadata.GetString(method.Name);
            }
            throw new InvalidOperationException("Unsupported call token " + handle.Kind);
        }
        List<(short opcode, int token)> Instructions(MethodDefinitionHandle handle)
        {
            MethodDefinition method = metadata.GetMethodDefinition(handle);
            byte[] bytes = pe.GetMethodBody(method.RelativeVirtualAddress).GetILBytes() ?? throw new BadImageFormatException("Missing method body.");
            var opcodes = typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static)
                .Where(f => f.FieldType == typeof(OpCode)).Select(f => (OpCode)f.GetValue(null)!)
                .ToDictionary(op => op.Value);
            var result = new List<(short opcode, int token)>();
            for (int at = 0; at < bytes.Length;)
            {
                short code = bytes[at++];
                if (code == 0xfe) code = unchecked((short)(0xfe00 | bytes[at++]));
                if (!opcodes.TryGetValue(code, out OpCode opcode)) throw new BadImageFormatException("Unknown IL opcode.");
                int size = opcode.OperandType switch
                {
                    OperandType.InlineNone => 0,
                    OperandType.ShortInlineBrTarget or OperandType.ShortInlineI or OperandType.ShortInlineVar => 1,
                    OperandType.InlineVar => 2,
                    OperandType.InlineI8 or OperandType.InlineR => 8,
                    OperandType.InlineSwitch => checked(4 + BitConverter.ToInt32(bytes, at) * 4),
                    _ => 4
                };
                if (at + size > bytes.Length) throw new BadImageFormatException("Truncated IL operand.");
                if (opcode == OpCodes.Ldtoken || opcode == OpCodes.Newobj || opcode == OpCodes.Call)
                    result.Add((code, BitConverter.ToInt32(bytes, at)));
                at += size;
            }
            return result;
        }
    }
    static void Equal(string[] expected, string[] actual, string context)
    {
        if (!expected.SequenceEqual(actual, StringComparer.Ordinal))
            throw new InvalidOperationException(context + ": missing [" + string.Join(", ", expected.Except(actual))
                + "]; unexpected [" + string.Join(", ", actual.Except(expected)) + "] or multiplicity mismatch.");
    }
}
