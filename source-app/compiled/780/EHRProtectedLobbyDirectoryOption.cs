// Original protected-profile option. Existing presets cannot enable this row.
namespace EHR;
internal sealed class EHRProtectedLobbyDirectoryOption : TextOptionItem
{
    internal const string Label = "EHR website lobby directory: unavailable (account-protected iOS)";
    internal const string UnavailableMessage = "The EHR website lobby directory is unavailable in this account-protected iOS build.";
    internal EHRProtectedLobbyDirectoryOption(int id, string name, TabGroup tab)
        : base(id, name, tab, 0, true) { }
    public override int GetValue() => 0;
    public override void SetValue(int value, bool doSync = true) { }
    public override string GetString() => "Unavailable";
}
