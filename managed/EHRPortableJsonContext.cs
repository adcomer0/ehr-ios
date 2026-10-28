using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace EHR.SourcePort;

// Original property names and numeric enum values are intentional. No naming
// policy, enum-as-string converter, field inclusion, or case folding is added.
internal sealed class AchievementUploadRequest
{
    public string userId { get; init; } = null!;
    public HashSet<global::EHR.Modules.Achievements.Type> achievements { get; init; } = null!;
}

[JsonSourceGenerationOptions(GenerationMode=JsonSourceGenerationMode.Metadata)]
[JsonSerializable(typeof(Dictionary<global::EHR.CustomRoles,string>),TypeInfoPropertyName="RoleColors")]
[JsonSerializable(typeof(Dictionary<string,string>),TypeInfoPropertyName="StringColors")]
[JsonSerializable(typeof(global::EHR.Modules.OptionSaver.SerializableOptionsData),TypeInfoPropertyName="OptionData")]
[JsonSerializable(typeof(global::EHR.Options.UserData),TypeInfoPropertyName="UserData")]
[JsonSerializable(typeof(HashSet<global::EHR.Modules.Achievements.Type>),TypeInfoPropertyName="Achievements")]
[JsonSerializable(typeof(AchievementUploadRequest),TypeInfoPropertyName="AchievementUpload")]
[JsonSerializable(typeof(Dictionary<string,JsonElement>),TypeInfoPropertyName="Language")]
[JsonSerializable(typeof(Dictionary<int,Dictionary<string,List<string>>>),TypeInfoPropertyName="Combos")]
[JsonSerializable(typeof(Dictionary<string,global::EHR.DevManager.TagInfo>),TypeInfoPropertyName="Tags")]
[JsonSerializable(typeof(global::EHR.Modules.OnlinePresetsManager.PresetDraftRequest),TypeInfoPropertyName="PresetDraftRequest")]
[JsonSerializable(typeof(global::EHR.Modules.OnlinePresetsManager.PresetDraftResponse),TypeInfoPropertyName="PresetDraftResponse")]
[JsonSerializable(typeof(global::EHR.Modules.OnlinePresetsManager.PresetDownloadResponse),TypeInfoPropertyName="PresetDownloadResponse")]
[JsonSerializable(typeof(global::EHR.Modules.OnlinePresetsManager.PresetListResponse),TypeInfoPropertyName="PresetListResponse")]
[JsonSerializable(typeof(List<global::EHR.ModNews>),TypeInfoPropertyName="News")]
internal partial class EHRPortableJsonContext : JsonSerializerContext
{
    internal static readonly EHRPortableJsonContext Indented = new(new JsonSerializerOptions { WriteIndented=true });
}
