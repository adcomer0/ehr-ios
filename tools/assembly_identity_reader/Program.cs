// Read ECMA-335 constants only. Never load or execute the inspected assembly.
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

static string FullName(MetadataReader reader, TypeDefinitionHandle handle)
{
    var type = reader.GetTypeDefinition(handle);
    var parent = type.GetDeclaringType();
    if (!parent.IsNil) return FullName(reader, parent) + "+" + reader.GetString(type.Name);
    string space = reader.GetString(type.Namespace);
    return (space.Length == 0 ? "" : space + ".") + reader.GetString(type.Name);
}

if (args.Length != 1) return 2;
try
{
    using var input = File.OpenRead(args[0]);
    if (input.Length > 512L * 1024 * 1024) return 3;
    using var pe = new PEReader(input);
    var reader = pe.GetMetadataReader();
    var values = new Dictionary<string, string?>();
    foreach (var handle in reader.TypeDefinitions)
    {
        string type = FullName(reader, handle);
        bool main = type == "EHR.Main";
        bool git = type == "ThisAssembly+Git";
        if (!main && !git) continue;
        foreach (var fieldHandle in reader.GetTypeDefinition(handle).GetFields())
        {
            var field = reader.GetFieldDefinition(fieldHandle);
            string name = reader.GetString(field.Name);
            string? key = (main, name) switch
            {
                (true, "PluginVersion") => "pluginVersion",
                (true, "ForkId") => "forkId",
                (false, "Branch") => "gitBranch",
                (false, "Commit") => "gitCommit",
                (false, "Sha") => "gitSha",
                _ => null
            };
            if (key == null) continue;
            var constantHandle = field.GetDefaultValue();
            if (constantHandle.IsNil) continue;
            var constant = reader.GetConstant(constantHandle);
            if (constant.TypeCode != ConstantTypeCode.String || values.ContainsKey(key)) return 4;
            values[key] = Encoding.Unicode.GetString(reader.GetBlobBytes(constant.Value));
        }
    }
    using var hashInput = File.OpenRead(args[0]);
    Console.WriteLine(JsonSerializer.Serialize(new
    {
        schema = "ehr.assembly-identity.v1",
        assemblyName = reader.GetString(reader.GetAssemblyDefinition().Name),
        assemblyVersion = reader.GetAssemblyDefinition().Version.ToString(),
        assemblySha256 = Convert.ToHexString(SHA256.HashData(hashInput)).ToLowerInvariant(),
        constants = values,
        assemblyExecuted = false
    }));
    return 0;
}
catch (Exception error)
{
    Console.Error.WriteLine("Assembly identity metadata read failed: " + error.GetType().Name);
    return 5;
}
