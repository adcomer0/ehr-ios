using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

const string pin = "ce23f0d050f617a59507e5bb0fbfff751d4b5134";
if (args is ["--dispatcher-fixture", string fixtureSource, string fixtureOutput])
{
    if (Directory.Exists(fixtureOutput) && Directory.EnumerateFileSystemEntries(fixtureOutput).Any()) throw new IOException("Fixture output must be empty.");
    var fixtureModel = new Model(new[] { ("Fixture.cs", File.ReadAllText(fixtureSource)) }, "Mono");
    DispatcherOutput fixture = fixtureModel.GenerateStaticDispatcher("original-arithmetic-fixture", "Mono");
    Directory.CreateDirectory(fixtureOutput);
    File.WriteAllText(Path.Combine(fixtureOutput, "Fixture.cs"), fixture.Files.GetValueOrDefault("Fixture.cs") ?? File.ReadAllText(fixtureSource));
    File.WriteAllText(Path.Combine(fixtureOutput, "EHRStaticPatchCatalog.g.cs"), fixture.Code);
    File.WriteAllText(Path.Combine(fixtureOutput, "audit.json"), JsonSerializer.Serialize(fixture.Audit, Model.JsonOptions));
    File.WriteAllText(Path.Combine(fixtureOutput, "source_target_types.json"), JsonSerializer.Serialize(fixture.SourceTypes, Model.JsonOptions));
    Console.WriteLine("Generated original arithmetic fixture callback bridges.");
    return 0;
}
if (args is ["--self-test"])
{
    Model.SelfTest();
    Console.WriteLine("Registry semantic fixtures passed.");
    return 0;
}
if (args is ["--verify-assembly", string assemblyPath, string coveragePath, string reportPath])
{
    if (File.Exists(reportPath)) throw new IOException("Refusing to overwrite assembly verification report.");
    var verification = RegistryAssemblyVerifier.Verify(assemblyPath, coveragePath);
    File.WriteAllText(reportPath, JsonSerializer.Serialize(verification, Model.JsonOptions) + "\n");
    Console.WriteLine("Compiled metadata membership/typeof/newobj coverage verified without loading the EHR assembly.");
    return 0;
}
bool bootstrapMode = args.Length == 4 && args[0] == "--bootstrap";
bool dispatcherMode = args.Length >= 4 && args[0] == "--dispatcher";
bool selectorMode = args.Length >= 5 && args[0] == "--selectors";
string[] overlays = selectorMode ? args[5..] : dispatcherMode ? args[4..] : [];
string? referenceItems = selectorMode ? args[4] : null;
dispatcherMode |= selectorMode;
string[] input = bootstrapMode || dispatcherMode ? args[1..4] : args;
if (input.Length != 3 || input[1] is not ("IL2CPP" or "Mono"))
{
    Console.Error.WriteLine("Usage: RegistryGenerator PINNED_REPO IL2CPP|Mono NEW_OUTPUT_DIRECTORY; or --self-test");
    return 2;
}
string repo = Path.GetFullPath(input[0]), profile = input[1], output = Path.GetFullPath(input[2]);
if (Git(repo, "rev-parse", "HEAD") != pin) throw new InvalidOperationException("Upstream commit pin mismatch.");
if (Git(repo, "status", "--porcelain", "--untracked-files=no").Length != 0) throw new InvalidOperationException("Upstream tracked source is modified.");
if (Git(repo, "remote", "get-url", "origin").TrimEnd('/').Replace(".git", "", StringComparison.Ordinal) != "https://github.com/Gurge44/EndlessHostRoles")
    throw new InvalidOperationException("Unexpected upstream origin.");
string[] paths = Git(repo, "ls-files", "*.cs").Split('\n').Where(p => !p.StartsWith("CTA/", StringComparison.Ordinal)).ToArray();
var texts = paths.Select(p => (p, File.ReadAllText(overlays.Select(o => Path.Combine(o, p)).FirstOrDefault(File.Exists) ?? Path.Combine(repo, p)))).ToArray();
var model = new Model(texts, profile, referenceItems);
if (dispatcherMode)
{
    DispatcherOutput dispatcher = model.GenerateStaticDispatcher(pin, profile);
    if (Directory.Exists(output) && Directory.EnumerateFileSystemEntries(output).Any()) throw new IOException("Dispatcher output must be empty.");
    Directory.CreateDirectory(output);
    File.WriteAllText(Path.Combine(output, "EHRStaticPatchCatalog.g.cs"), dispatcher.Code);
    foreach (var file in dispatcher.Files)
    {
        string destination = Path.Combine(output, "source", file.Key);
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        File.WriteAllText(destination, file.Value);
    }
    File.WriteAllText(Path.Combine(output, "static_dispatch_audit.json"), JsonSerializer.Serialize(dispatcher.Audit, Model.JsonOptions) + "\n");
    File.WriteAllText(Path.Combine(output, "native_target_selectors.json"), JsonSerializer.Serialize(dispatcher.Selectors, Model.JsonOptions) + "\n");
    File.WriteAllText(Path.Combine(output, "source_target_types.json"), JsonSerializer.Serialize(dispatcher.SourceTypes, Model.JsonOptions) + "\n");
    Console.WriteLine("Generated direct static callback bridges and catalog; native target binding remains unavailable until supplied and validated.");
    return 0;
}
if (bootstrapMode)
{
    BootstrapOutput bootstrap = model.GenerateBootstrap(pin, profile);
    if (Directory.Exists(output) && Directory.EnumerateFileSystemEntries(output).Any()) throw new IOException("Bootstrap output must be empty.");
    Directory.CreateDirectory(output);
    File.WriteAllText(Path.Combine(output, "EHRSourceBootstrap.g.cs"), bootstrap.Code);
    foreach (var file in bootstrap.Files)
    {
        string destination = Path.Combine(output, "source", file.Key);
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        File.WriteAllText(destination, file.Value);
    }
    File.WriteAllText(Path.Combine(output, "bootstrap_audit.json"), JsonSerializer.Serialize(bootstrap.Audit, Model.JsonOptions) + "\n");
    Console.WriteLine("Generated explicit source bootstrap roots, name maps, role method/RPC dispatch and bounded setting field getters.");
    return 0;
}
var groups = model.Groups();
var randomMappings = model.RandomMappings();
var auxiliaryDispatch = model.AuxiliaryDispatch(groups);
var diagnostics = model.Diagnostics();
string generated = model.Generate(groups, randomMappings, auxiliaryDispatch, pin, profile);
var report = new
{
    schema = "ehr.aot-source-registry.v1", upstreamCommit = pin, compileProfile = profile,
    scope = "Source-only Roslyn discovery and explicit constructor generation. No EHR or game assembly is loaded or executed; generated factories still require integration and actual-game verification.",
    discoveryOrder = "Tracked source file and declaration order. Preserve downstream upstream Sort/OrderBy operations; Assembly.GetTypes enumeration order is not an API guarantee. Compiled metadata validation separately checks settings-sensitive Disaster order.",
    sourceFiles = paths.Length, sourceSha256 = texts.Select(t => new { file = t.p, sha256 = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(t.Item2))).ToLowerInvariant() }).ToArray(),
    counts = new { sourceTypes = model.Types.Count, discoveredGroupMemberships = groups.Sum(g => g.Rows.Count),
        coveredMemberships = groups.Sum(g => g.Rows.Count(r => r.Status == "explicit_constructor")),
        rejectedMemberships = groups.Sum(g => g.Rows.Count(r => r.Status != "explicit_constructor")), randomIdMappings = randomMappings.Count },
    groups, randomMappings, auxiliaryDispatch, diagnostics,
    limitations = new[] {
        "The semantic compilation uses .NET framework references, not proprietary game assemblies. External base/member diagnostic errors are expected and reported; selected source hierarchy and constructor declarations are resolved independently.",
        "External constructor parameter types are source signatures. Compilation against the real facade/upstream project is a separate required check.",
        "Discovery follows actual upstream predicates, including interface predicates that do not exclude abstract types. Invalid selected types are rejected explicitly rather than silently filtered.",
        "Generated registry is not automatically wired into upstream source and makes no feature-implementation claim."
    }
};
Directory.CreateDirectory(output);
foreach (string name in new[] { "EHRAotRegistry.g.cs", "registry_coverage.json" })
    if (File.Exists(Path.Combine(output, name))) throw new IOException("Refusing to overwrite " + name);
File.WriteAllText(Path.Combine(output, "EHRAotRegistry.g.cs"), generated);
File.WriteAllText(Path.Combine(output, "registry_coverage.json"), JsonSerializer.Serialize(report, Model.JsonOptions) + "\n");
Console.WriteLine(JsonSerializer.Serialize(report.counts, Model.JsonOptions));
return 0;

static string Git(string repo, params string[] arguments)
{
    var start = new ProcessStartInfo("git") { RedirectStandardOutput = true, RedirectStandardError = true };
    start.ArgumentList.Add("-C"); start.ArgumentList.Add(repo);
    foreach (string argument in arguments) start.ArgumentList.Add(argument);
    using Process process = Process.Start(start) ?? throw new IOException("Unable to start git.");
    string result = process.StandardOutput.ReadToEnd(), error = process.StandardError.ReadToEnd();
    process.WaitForExit();
    if (process.ExitCode != 0) throw new IOException("git failed: " + error);
    return result.Trim();
}

sealed partial class Model
{
    public static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    readonly CSharpCompilation compilation;
    readonly Dictionary<INamedTypeSymbol, SourceLocation> locations = new(SymbolEqualityComparer.Default);
    readonly Dictionary<INamedTypeSymbol, BaseTypeDeclarationSyntax> declarations = new(SymbolEqualityComparer.Default);
    public List<INamedTypeSymbol> Types { get; }
    static readonly SymbolDisplayFormat CSharpNames = SymbolDisplayFormat.FullyQualifiedFormat;
    public Model(IEnumerable<(string path, string text)> source, string profile, string? referenceItems = null)
    {
        var parse = new CSharpParseOptions(LanguageVersion.Preview, preprocessorSymbols: profile == "IL2CPP" ? ["IL2CPP"] : []);
        SyntaxTree[] trees = source.Select(t => CSharpSyntaxTree.ParseText(t.text, parse, t.path)).ToArray();
        string[] runtime = ((string?)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES") ?? "").Split(Path.PathSeparator);
        IEnumerable<PortableExecutableReference> references;
        if (referenceItems != null)
        {
            using var document = JsonDocument.Parse(File.ReadAllText(referenceItems));
            references = document.RootElement.GetProperty("Items").GetProperty("ReferencePath").EnumerateArray().Select(item =>
            {
                string path = item.GetProperty("Identity").GetString()!;
                string[] aliases = item.TryGetProperty("Aliases", out JsonElement value) && value.GetString() is string names && names.Length > 0 ? names.Split(',') : [];
                return MetadataReference.CreateFromFile(path, MetadataReferenceProperties.Assembly.WithAliases(aliases));
            }).ToArray();
        }
        else references = runtime.Where(File.Exists).Distinct().Select(p => MetadataReference.CreateFromFile(p));
        compilation = CSharpCompilation.Create("EHR.SourceRegistryAnalysis", trees, references,
            new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary, allowUnsafe: true));
        foreach (SyntaxTree tree in trees)
        {
            SemanticModel semantic = compilation.GetSemanticModel(tree);
            foreach (BaseTypeDeclarationSyntax node in tree.GetRoot().DescendantNodes().OfType<BaseTypeDeclarationSyntax>())
            {
                if (semantic.GetDeclaredSymbol(node) is not INamedTypeSymbol symbol) continue;
                if (!locations.ContainsKey(symbol))
                {
                    locations[symbol] = new(tree.FilePath, node.GetLocation().GetLineSpan().StartLinePosition.Line + 1);
                    declarations[symbol] = node;
                }
            }
        }
        Types = locations.Keys.OrderBy(t => locations[t].File, StringComparer.Ordinal).ThenBy(t => locations[t].Line).ToList();
    }

    public object Diagnostics()
    {
        Diagnostic[] errors = compilation.GetDiagnostics().Where(d => d.Severity == DiagnosticSeverity.Error).ToArray();
        return new { expectedExternalReferenceAndGeneratedSourceErrors = errors.Length,
            byId = errors.GroupBy(d => d.Id).OrderBy(g => g.Key).Select(g => new { id = g.Key, count = g.Count() }).ToArray(),
            scope = "Not a full-project compilation verdict. Full source plus generated registry must be compiled with the project's real references." };
    }

    INamedTypeSymbol Required(string name) => compilation.GetTypeByMetadataName(name) ?? throw new InvalidOperationException("Missing required source type " + name);
    static bool EqualsType(ITypeSymbol? a, ITypeSymbol? b) => SymbolEqualityComparer.Default.Equals(a, b);
    static bool Subclass(INamedTypeSymbol type, INamedTypeSymbol parent)
    {
        var seen = new HashSet<ITypeSymbol>(SymbolEqualityComparer.Default);
        for (INamedTypeSymbol? next = type.BaseType; next != null && seen.Add(next); next = next.BaseType)
            if (EqualsType(next, parent)) return true;
        return false;
    }
    static bool Implements(INamedTypeSymbol type, INamedTypeSymbol contract) => type.AllInterfaces.Any(i => EqualsType(i, contract)) || EqualsType(type, contract);
    static string MetadataName(INamedTypeSymbol type) => type.ContainingType != null
        ? MetadataName(type.ContainingType) + "+" + type.MetadataName
        : (type.ContainingNamespace.IsGlobalNamespace ? "" : type.ContainingNamespace.ToDisplayString() + ".") + type.MetadataName;
    static string CsName(ITypeSymbol type) => type.ToDisplayString(CSharpNames);

    public List<Group> Groups()
    {
        var specs = new[] {
            new Spec("RoleBase", "EHR.Roles.RoleBase", "t.IsClass && !t.IsAbstract && t.IsSubclassOf(typeof(RoleBase))", "Main.cs:1125", false),
            new Spec("IAddon", "EHR.Roles.IAddon", "typeof(IAddon).IsAssignableFrom(t) && !t.IsInterface", "Modules/OptionHolder.cs:1538", true),
            new Spec("IGhostRole", "EHR.Roles.IGhostRole", "typeof(IGhostRole).IsAssignableFrom(t) && !t.IsInterface", "Modules/OptionHolder.cs:1596", true),
            new Spec("IVanillaSettingHolder", "EHR.IVanillaSettingHolder", "typeof(IVanillaSettingHolder).IsAssignableFrom(t) && !t.IsInterface", "Modules/OptionHolder.cs:1575", true),
            new Spec("IHideAndSeekRole", "EHR.Roles.IHideAndSeekRole", "typeof(IHideAndSeekRole).IsAssignableFrom(t) && !t.IsInterface", "Gamemodes/CustomHnS.cs:132", true),
            new Spec("IRandom", "EHR.IRandom", "Concrete source implementations reviewed against explicit IRandom.RandomTypes mapping", "Modules/Random/IRandom.cs:10", true),
            new Spec("Disaster", "EHR.Gamemodes.NaturalDisasters+Disaster", "t.IsClass && !t.IsAbstract && t.IsSubclassOf(typeof(Disaster))", "Gamemodes/NaturalDisasters.cs:125", false)
        };
        var groups = new List<Group>();
        foreach (Spec spec in specs)
        {
            INamedTypeSymbol contract = Required(spec.Type);
            IEnumerable<INamedTypeSymbol> selected = spec.Interface
                ? Types.Where(t => t.TypeKind != TypeKind.Interface && Implements(t, contract))
                : Types.Where(t => t.TypeKind == TypeKind.Class && !t.IsAbstract && Subclass(t, contract));
            List<Row> rows = selected.Select(t => Describe(t, spec.Id == "Disaster")).ToList();
            groups.Add(new(spec.Id, spec.Type, spec.Filter, spec.Anchor, rows));
        }
        return groups;
    }

    Row Describe(INamedTypeSymbol type, bool disaster)
    {
        List<string> rejections = [];
        if (type.IsAbstract) rejections.Add("selected_by_upstream_filter_but_abstract");
        if (type.IsStatic) rejections.Add("static_type_is_not_constructible");
        if (type.Arity != 0 || Parents(type).Any(t => t.Arity != 0)) rejections.Add("open_generic_type");
        if (!compilation.IsSymbolAccessibleWithin(type, compilation.Assembly)) rejections.Add("not_accessible_from_generated_assembly_scope");
        IMethodSymbol[] constructors = type.InstanceConstructors.Where(c => c.DeclaredAccessibility == Accessibility.Public).ToArray();
        bool Matches(IMethodSymbol c) => disaster
            ? c.Parameters.Length == 2 && c.Parameters.All(p => p.RefKind == RefKind.None)
                && CsName(c.Parameters[0].Type).Replace("global::", "", StringComparison.Ordinal) == "UnityEngine.Vector2"
                && CsName(c.Parameters[1].Type).Replace("global::", "", StringComparison.Ordinal) == "EHR.NaturalDisaster"
            : c.Parameters.Length == 0;
        IMethodSymbol[] matches = constructors.Where(Matches).ToArray();
        if (matches.Length != 1) rejections.Add(disaster ? "no_unique_public_Vector2_NaturalDisaster_constructor" : "no_unique_public_parameterless_constructor");
        return new(MetadataName(type), CsName(type), type.Name, type.TypeKind.ToString(), type.IsAbstract,
            locations[type], constructors.Select(c => new Constructor(c.Parameters.Select(p => new Parameter(p.Name, CsName(p.Type), p.RefKind.ToString(), p.IsOptional, p.Type.TypeKind == TypeKind.Error)).ToArray(), c.IsImplicitlyDeclared)).ToArray(),
            rejections.Count == 0 ? "explicit_constructor" : "rejected", rejections.ToArray());
    }

    static IEnumerable<INamedTypeSymbol> Parents(INamedTypeSymbol type)
    {
        for (INamedTypeSymbol? parent = type.ContainingType; parent != null; parent = parent.ContainingType) yield return parent;
    }

    public List<RandomMapping> RandomMappings()
    {
        INamedTypeSymbol random = Required("EHR.IRandom");
        var declaration = declarations[random];
        VariableDeclaratorSyntax variable = declaration.DescendantNodes().OfType<VariableDeclaratorSyntax>().Single(v => v.Identifier.ValueText == "RandomTypes");
        InitializerExpressionSyntax initializer = variable.Initializer?.Value switch {
            ObjectCreationExpressionSyntax c => c.Initializer!, ImplicitObjectCreationExpressionSyntax c => c.Initializer!,
            _ => throw new InvalidOperationException("Unsupported RandomTypes initializer shape")
        };
        SemanticModel semantic = compilation.GetSemanticModel(declaration.SyntaxTree);
        var mappings = new List<RandomMapping>();
        foreach (ExpressionSyntax expression in initializer.Expressions)
        {
            if (expression is not InitializerExpressionSyntax { Expressions.Count: 2 } pair || pair.Expressions[1] is not TypeOfExpressionSyntax target)
                throw new InvalidOperationException("Unsupported RandomTypes entry; no mapping inferred.");
            Optional<object?> key = semantic.GetConstantValue(pair.Expressions[0]);
            if (!key.HasValue || key.Value is not int id || semantic.GetTypeInfo(target.Type).Type is not INamedTypeSymbol type)
                throw new InvalidOperationException("Unresolved RandomTypes entry; no mapping inferred.");
            if (!Implements(type, random)) throw new InvalidOperationException("RandomTypes entry does not implement IRandom.");
            mappings.Add(new(id, MetadataName(type), CsName(type)));
        }
        if (mappings.Select(m => m.Id).Distinct().Count() != mappings.Count) throw new InvalidOperationException("Duplicate random ID.");
        return mappings.OrderBy(m => m.Id).ToList();
    }

    public List<Auxiliary> AuxiliaryDispatch(List<Group> groups)
    {
        var result = new List<Auxiliary>();
        foreach (Row row in groups.Single(g => g.Id == "Disaster").Rows)
        {
            INamedTypeSymbol type = Types.Single(t => MetadataName(t) == row.Type);
            IMethodSymbol[] members = type.GetMembers("SetupOwnCustomOption").OfType<IMethodSymbol>().ToArray();
            string status = members.Length == 0 ? "absent_upstream_noop" : members.Length == 1 && members[0].IsStatic
                && members[0].DeclaredAccessibility == Accessibility.Public && members[0].Parameters.Length == 0
                && members[0].ReturnsVoid ? "explicit_static_call" : "rejected_signature";
            if (row.Rejections.Any(r => r is "open_generic_type" or "not_accessible_from_generated_assembly_scope")) status = "rejected_type_reference";
            result.Add(new(row.Type, row.CSharpType, "disaster_option_setup", status, "Gamemodes/NaturalDisasters.cs:121"));
        }
        foreach (Row row in groups.Single(g => g.Id == "RoleBase").Rows)
        {
            INamedTypeSymbol type = Types.Single(t => MetadataName(t) == row.Type);
            IMethodSymbol[] members = type.GetMembers("ManipulateGameEndCheckCrew").OfType<IMethodSymbol>()
                .Where(m => m.DeclaredAccessibility == Accessibility.Public).ToArray();
            if (members.Length == 0) continue;
            string status = members.Length == 1 && !members[0].IsStatic ? "explicit_declaring_type" : "rejected_signature";
            if (row.Rejections.Any(r => r is "open_generic_type" or "not_accessible_from_generated_assembly_scope")) status = "rejected_type_reference";
            result.Add(new(row.Type, row.CSharpType, "crew_end_check_declaring_type", status, "Modules/OptionHolder.cs:3272"));
        }
        return result;
    }

    public string Generate(List<Group> groups, List<RandomMapping> random, List<Auxiliary> auxiliary, string pin, string profile)
    {
        var b = new StringBuilder();
        b.AppendLine("// <auto-generated />");
        b.AppendLine("// Pinned EHR source: " + pin + "; profile " + profile + ". No native game compatibility is implied.");
        b.AppendLine("// Compile into the EHR assembly so internal source types remain accessible.");
        b.AppendLine("#nullable enable\nnamespace EHR;\ninternal static class EHRAotRegistry\n{");
        foreach (Group group in groups)
        {
            Row[] covered = group.Rows.Where(r => r.Status == "explicit_constructor").ToArray();
            b.AppendLine("    // Upstream predicate: " + group.UpstreamFilter);
            b.AppendLine("    internal static global::System.Type[] " + group.Id + "Types() => new global::System.Type[]\n    {");
            foreach (Row row in group.Rows)
            {
                // Arrays include rejected selections when accessible: their constructor
                // factory fails explicitly, preserving discovery rather than hiding them.
                if (!row.Rejections.Contains("not_accessible_from_generated_assembly_scope") && !row.Rejections.Contains("open_generic_type"))
                    b.AppendLine("        typeof(" + row.CSharpType + "),");
                else b.AppendLine("        // REJECTED " + row.Type + ": " + string.Join(", ", row.Rejections));
            }
            b.AppendLine("    };\n");
            string parameters = group.Id == "Disaster" ? ", global::UnityEngine.Vector2 position, global::EHR.NaturalDisaster naturalDisaster" : "";
            string arguments = group.Id == "Disaster" ? "position, naturalDisaster" : "";
            b.AppendLine("    internal static global::" + group.Contract.Replace('+', '.') + " Create" + group.Id + "(global::System.Type type" + parameters + ")\n    {");
            b.AppendLine("        if (type is null) throw new global::System.ArgumentNullException(nameof(type));");
            b.AppendLine("        try\n        {");
            foreach (Row row in covered)
                b.AppendLine("            if (type == typeof(" + row.CSharpType + ")) return new " + row.CSharpType + "(" + arguments + ");");
            b.AppendLine("        }\n        catch (global::System.Exception error) { throw new global::System.Reflection.TargetInvocationException(error); }");
            b.AppendLine("        throw new global::System.NotSupportedException(\"Unregistered or unsupported " + group.Id + " type: \" + type.FullName);\n    }\n");
        }
        var randomGroup = groups.Single(g => g.Id == "IRandom");
        b.AppendLine("    internal static global::EHR.IRandom CreateRandomById(int id) => id switch\n    {");
        foreach (RandomMapping entry in random)
        {
            Row row = randomGroup.Rows.Single(r => r.Type == entry.Type);
            if (row.Status == "explicit_constructor") b.AppendLine("        " + entry.Id + " => new " + entry.CSharpType + "(),");
            else b.AppendLine("        " + entry.Id + " => throw new global::System.NotSupportedException(\"Unsupported upstream random constructor\"),");
        }
        b.AppendLine("        _ => throw new global::System.ArgumentOutOfRangeException(nameof(id))\n    };\n");
        b.AppendLine("    internal static void SetupDisasterOptions(global::System.Type type)\n    {");
        foreach (Auxiliary row in auxiliary.Where(a => a.Kind == "disaster_option_setup"))
        {
            if (row.Status == "rejected_type_reference") { b.AppendLine("        // REJECTED auxiliary dispatch for " + row.Type); continue; }
            b.Append("        if (type == typeof(" + row.CSharpType + ")) { ");
            if (row.Status == "explicit_static_call") b.Append("try { " + row.CSharpType + ".SetupOwnCustomOption(); } catch (global::System.Exception error) { throw new global::System.Reflection.TargetInvocationException(error); } ");
            else if (row.Status == "rejected_signature") b.Append("throw new global::System.NotSupportedException(\"Unsupported disaster option setup signature\"); ");
            b.AppendLine(row.Status == "rejected_signature" ? "}" : "return; }");
        }
        b.AppendLine("        throw new global::System.NotSupportedException(\"Unregistered disaster type\");\n    }\n");
        b.AppendLine("    internal static global::System.Type[] CrewEndCheckDeclaringTypes() => new global::System.Type[]\n    {");
        foreach (Auxiliary row in auxiliary.Where(a => a.Kind == "crew_end_check_declaring_type" && a.Status == "explicit_declaring_type"))
            b.AppendLine("        typeof(" + row.CSharpType + "),");
        b.AppendLine("    };\n");
        b.AppendLine("    internal static bool DeclaresCrewEndCheck(global::System.Type type)\n    {");
        foreach (Auxiliary row in auxiliary.Where(a => a.Kind == "crew_end_check_declaring_type"))
        {
            if (row.Status == "rejected_type_reference") { b.AppendLine("        // REJECTED auxiliary dispatch for " + row.Type); continue; }
            b.AppendLine("        if (type == typeof(" + row.CSharpType + ")) " + (row.Status == "explicit_declaring_type" ? "return true;" : "throw new global::System.NotSupportedException(\"Unsupported crew end-check overloads\");"));
        }
        b.AppendLine("        return false;\n    }\n}");
        return b.ToString();
    }

    public static void SelfTest()
    {
        const string fixture = """
namespace UnityEngine { public struct Vector2 {} }
namespace EHR {
 public class NaturalDisaster {}
 public interface IVanillaSettingHolder {}
 public interface IRandom { public static readonly System.Collections.Generic.Dictionary<int,System.Type> RandomTypes = new() {{ 0, typeof(RandomA) }, { 1, typeof(RandomA) }}; }
 public class RandomA : IRandom {}
}
namespace EHR.Roles {
 public abstract class RoleBase {}
 public interface IAddon {}
 public interface IGhostRole {}
 public interface IHideAndSeekRole {}
 internal class Good : RoleBase {}
 public abstract class AbstractRole : RoleBase {}
 public class GenericRole<T> : RoleBase {}
 public class BadConstructor : RoleBase { private BadConstructor() {} }
 public abstract class AbstractAddon : IAddon {}
 public class Addon : IAddon {}
 public class Outer { private class Hidden : RoleBase {} }
}
namespace EHR.Gamemodes { public class NaturalDisasters {
 public abstract class Disaster {}
 public sealed class ValidDisaster : Disaster { public ValidDisaster(UnityEngine.Vector2 p, EHR.NaturalDisaster d) {} }
 public sealed class InvalidDisaster : Disaster { public InvalidDisaster(UnityEngine.Vector2 p) {} }
} }
""";
        var model = new Model([("Fixture.cs", fixture)], "Mono");
        var groups = model.Groups();
        Row Find(string group, string name) => groups.Single(g => g.Id == group).Rows.Single(r => r.Name == name);
        void Require(bool result, string message) { if (!result) throw new InvalidOperationException("Fixture failure: " + message); }
        Require(Find("RoleBase", "Good").Status == "explicit_constructor", "implicit public constructor");
        Require(!groups.Single(g => g.Id == "RoleBase").Rows.Any(r => r.Name == "AbstractRole"), "exact abstract subclass exclusion");
        Require(Find("IAddon", "AbstractAddon").Rejections.Contains("selected_by_upstream_filter_but_abstract"), "interface filter retains abstract selection");
        Require(Find("RoleBase", "GenericRole").Rejections.Contains("open_generic_type"), "open generic rejection");
        Require(Find("RoleBase", "Hidden").Rejections.Contains("not_accessible_from_generated_assembly_scope"), "private nested rejection");
        Require(Find("RoleBase", "BadConstructor").Rejections.Contains("no_unique_public_parameterless_constructor"), "private constructor rejection");
        Require(Find("Disaster", "ValidDisaster").Status == "explicit_constructor", "exact disaster signature");
        Require(Find("Disaster", "InvalidDisaster").Status == "rejected", "wrong disaster signature");
        Require(model.RandomMappings().Count == 2 && model.RandomMappings().All(r => r.Type == "EHR.RandomA"), "duplicate random type preserves distinct IDs");
    }
}

record Spec(string Id, string Type, string Filter, string Anchor, bool Interface);
record SourceLocation(string File, int Line);
record Parameter(string Name, string Type, string RefKind, bool Optional, bool RequiresExternalFacadeDefinition);
record Constructor(Parameter[] Parameters, bool Implicit);
record Row(string Type, string CSharpType, string Name, string Kind, bool Abstract, SourceLocation Source,
    Constructor[] PublicConstructors, string Status, string[] Rejections);
record Group(string Id, string Contract, string UpstreamFilter, string SourceAnchor, List<Row> Rows);
record RandomMapping(int Id, string Type, string CSharpType);
record Auxiliary(string Type, string CSharpType, string Kind, string Status, string SourceAnchor);
