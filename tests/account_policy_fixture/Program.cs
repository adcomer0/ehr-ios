using System.Text.Json;
namespace EHR;
// Original source test doubles for EHR-only settings; no game API references.
public enum TabGroup { SystemSettings }
public abstract class OptionItem
{
    public int DefaultValue { get; protected set; }
    public bool IsText { get; protected set; }
    public int SingleValue;
    public int[] AllValues = new int[20];
    public virtual int GetValue()=>SingleValue;
    public bool GetBool()=>GetValue()!=0;
    public virtual void SetValue(int value,bool doSync=true)=>SingleValue=value;
    public void LoadLegacyNonVirtual(int value)=>SingleValue=value;
    public void SetAllValues(int[] values)=>AllValues=values;
    public virtual string GetString()=>GetValue().ToString();
}
public class TextOptionItem:OptionItem
{
    public TextOptionItem(int id,string name,TabGroup tab,int defaultValue=0,bool isSingleValue=false)
    {DefaultValue=defaultValue;SingleValue=defaultValue;IsText=true;}
}
public sealed class PlayerControl
{
    public byte PlayerId=7;
    public int NativeLevelWrites;
    public void RpcSetLevel(uint value)=>NativeLevelWrites++;
}
public static class Utils
{
    public static readonly List<(string Text,byte Player)> Messages=[];
    public static void SendMessage(string text,byte player)=>Messages.Add((text,player));
}
internal static class Program
{
    static int Main()
    {
        string[] excluded=["EHR.Modules.PrivacyPolicyScreenShowPatch::Prefix#15","EHR.Modules.PrivacyPolicyScreenClosePatch::Postfix#16","EHR.ChatControllerAwakePatch::Postfix#41","EHR.RunLoginPatch::Prefix#54","EHR.CheckOnlinePermissionsPatch::Prefix#60","EHR.GameStartManagerBeginPatch+GameStartManagerStartPatch::Prefix#138"];
        bool exact=EHRSourceAccountPolicy.ExcludedCallbackCount==6&&excluded.All(x=>EHRSourceAccountPolicy.TryExclude(x,out var reason)&&reason.Length>0);
        bool unknown=!EHRSourceAccountPolicy.TryExclude(null!,out var nullReason)&&nullReason==""&&!EHRSourceAccountPolicy.TryExclude(excluded[0].ToLowerInvariant(),out _)&&!EHRSourceAccountPolicy.TryExclude(excluded[0]+"suffix",out _)&&!EHRSourceAccountPolicy.TryExclude("EHR.OwnSafeCallback::Prefix#54",out _);
        string[] sameSelector=[excluded[3],"Own.SafeCallback"];bool preservesUnrelated=sameSelector.Where(x=>!EHRSourceAccountPolicy.TryExclude(x,out _)).SequenceEqual(["Own.SafeCallback"]);
        var option=new EHRProtectedLobbyDirectoryOption(19422,"PostLobbyCodeToEHRDiscordServer",TabGroup.SystemSettings);
        bool initial=option.DefaultValue==0&&option.IsText&&!option.GetBool();option.SetValue(1);option.LoadLegacyNonVirtual(1);option.SetAllValues(Enumerable.Repeat(1,20).ToArray());
        bool legacy=!option.GetBool()&&option.GetValue()==0&&option.GetString()=="Unavailable"&&EHRProtectedLobbyDirectoryOption.Label.Contains("unavailable");
        var player=new PlayerControl();OwnProtectedCommands.Exercise(player);
        bool commandResponses=player.NativeLevelWrites==0&&Utils.Messages.SequenceEqual(new (string,byte)[]{("This iOS test profile does not change player levels.",7),(EHRProtectedLobbyDirectoryOption.UnavailableMessage,7)});
        var registration=RegistrationPolicyFixture.Run(excluded);
        bool pass=exact&&unknown&&preservesUnrelated&&initial&&legacy&&commandResponses&&registration.Pass;
        Console.WriteLine(JsonSerializer.Serialize(new {pass,exactDescriptors=exact,unknownIdsAllowed=unknown,unrelatedSameSelectorPreserved=preservesUnrelated,legacyPresetCannotEnable=legacy,defaultFalseAndTextOnly=initial,protectedCommandResponses=commandResponses,registration,gameApiCalls=0,scope="actual dispatcher with own policy/command/EHR option fixtures; no account or game"}));
        return pass?0:1;
    }
}
