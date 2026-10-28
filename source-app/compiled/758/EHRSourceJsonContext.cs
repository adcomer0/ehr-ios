using System.Text.Json.Serialization;
namespace EHR.SourcePort;
[JsonSourceGenerationOptions(IncludeFields=true,PropertyNameCaseInsensitive=false)]
[JsonSerializable(typeof(global::EHR.Roles.Bard.Joke),TypeInfoPropertyName="BardJoke")]
internal partial class EHRSourceJsonContext:JsonSerializerContext { }
