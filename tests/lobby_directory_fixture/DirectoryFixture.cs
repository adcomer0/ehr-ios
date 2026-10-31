// Owned game/HTTP fixtures only. No game binary, SDK, account or network is used.
using System.Collections;
using System.Net;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using EHR;
using EHR.Modules;

namespace EHR.SourceHost { public static class NativeSourceHost { public static int Owner; public static bool IsMainThread => Environment.CurrentManagedThreadId == Owner; } }
namespace InnerNet {
 public class InnerNetClient { public enum GameStates { NotJoined, Joined, Started, Ended } }
 public sealed class ClientData { public int Id; public string ProductUserId = "OWN-PUID"; }
 public static class GameCode { public static string IntToGameName(int value) => value == -7 ? "ABCDEF" : "UVWXYZ"; }
}
public enum NetworkModes { LocalGame, OnlineGame, FreePlay }
public sealed class AmongUsClient : InnerNet.InnerNetClient {
 private static AmongUsClient instance = new(); public static int Reads;
 public static AmongUsClient Instance {get {++Reads;return instance;}set {instance=value;}}
 public bool AmHost = true; public int GameId = -7, ClientId = 1; public NetworkModes NetworkMode = NetworkModes.OnlineGame;
 public GameStates GameState = GameStates.Joined;
}
public sealed class PlayerControl {
 public static PlayerControl LocalPlayer = new(); public static List<PlayerControl> AllPlayerControls = [LocalPlayer];
 public byte PlayerId; public uint NetId = 12; public int OwnerId = 1; public object? Data = new(); public string FriendCode = "OWN-FRIEND";
 public InnerNet.ClientData Client = new() { Id = 1 }; public InnerNet.ClientData GetClient() => Client;
}
public sealed class EOSManager {
 public static readonly EOSManager Instance = new(); public static int Reads;
 public string UserIDToken { get { ++Reads; return "OWN-FAKE-EOS-JWT"; } }
}
namespace EHR {
 public enum TabGroup { SystemSettings }
 public class OptionItem { public int Value; public OptionItem(int value = 0) { Value = value; } public bool GetBool() => Value != 0; public int GetInt() => Value; public int GetValue() => Value; public virtual void SetValue(int value,bool doSync=true) {Value=value;} }
 public class BooleanOptionItem : OptionItem { public BooleanOptionItem(int id,string name,bool value,TabGroup tab):base(value?1:0){} }
 public static class Options {
  public enum ModLanguages { Default, English }
  public static OptionItem PostLobbyCodeToEHRWebsite = new EHRLobbyDirectoryOption(19422,"own",TabGroup.SystemSettings),ModLanguage = new(),RandomMapsMode = new(),EnableAutoGMRotation = new(),LobbyUpdateInterval = new(10);
  public static string CurrentGameMode = "OWN MODE";
 }
 public static class Translator { public static string GetUserTrueLang() => "English"; }
 public static class GameStates { public enum ServerType { Vanilla, Custom, Local } public static ServerType CurrentServerType; public static bool InGame; }
 public static class SubmergedCompatibility { public static bool Loaded; }
 public sealed class NormalOptions { public int MaxPlayers = 15, MapId; }
 public sealed class Runner {
  public readonly List<IEnumerator> Sources = [];
  public void StartCoroutine(IEnumerator source) { Sources.Add(source); }
  public void Tick() { foreach(var source in Sources.ToArray()) if(!source.MoveNext()) { Sources.Remove(source); (source as IDisposable)?.Dispose(); } }
  public void Close() { foreach(var source in Sources.ToArray()) (source as IDisposable)?.Dispose(); Sources.Clear(); }
 }
 public static class Main {
  public static readonly Runner Instance = new(); public static NormalOptions? NormalOptions = new();
  public const string ModName = "EHR", PluginVersion = "8.0.3"; public static string CurrentMap = "Skeld";
  public static readonly Dictionary<byte,string> AllPlayerNames = new() { [0] = "Own \"Host\"\nName" };
 }
 public static class Utils {
  public static readonly List<string> Messages = []; public static long TimeStamp => EHRDirectoryClock.Now / 1000;
  public static string Region = "OWN REGION"; public static string GetRegionName() => Region;
  public static PlayerControl? GetPlayerById(byte id) => PlayerControl.AllPlayerControls.FirstOrDefault(p=>p.PlayerId==id);
  public static void SendMessage(string body, byte id, string title) { Messages.Add(title); }
 }
 public static class StringExtension { public static string RemoveHtmlTags(this string value) => value; }
}
namespace EHR.Modules { public enum LobbyStatus { In_Lobby, In_Game, Ended, Closed } }

internal sealed record Sent(string Url, string? Bearer, string Json);
internal sealed class FakeHandler : HttpMessageHandler {
 internal static readonly List<Sent> Sent = []; internal static Func<HttpResponseMessage>? Response;
 internal static TaskCompletionSource<HttpResponseMessage>? Delayed;
 protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
  string text = await request.Content!.ReadAsStringAsync(token); Sent.Add(new(request.RequestUri!.AbsoluteUri, request.Headers.Authorization?.Parameter,text));
  if(Delayed != null) return await Delayed.Task;
  return Response?.Invoke() ?? new(HttpStatusCode.OK) { Content = new StringContent("{\"token\":\"OWN-ROOM-TOKEN\"}") };
 }
}
internal sealed class BoundedStream(byte[] value) : Stream {
 private int position; internal int ReadCount;
 public override bool CanRead=>true; public override bool CanSeek=>false; public override bool CanWrite=>false; public override long Length=>throw new NotSupportedException(); public override long Position {get=>position;set=>throw new NotSupportedException();}
 public override int Read(byte[] buffer,int offset,int count) { int take=Math.Min(count,value.Length-position);Array.Copy(value,position,buffer,offset,take);position+=take;ReadCount+=take;return take; }
 public override ValueTask<int> ReadAsync(Memory<byte> buffer,CancellationToken cancellation=default) {cancellation.ThrowIfCancellationRequested();int take=Math.Min(buffer.Length,value.Length-position);value.AsSpan(position,take).CopyTo(buffer.Span);position+=take;ReadCount+=take;return ValueTask.FromResult(take);}
 public override void Flush(){} public override long Seek(long offset,SeekOrigin origin)=>throw new NotSupportedException(); public override void SetLength(long value)=>throw new NotSupportedException(); public override void Write(byte[] buffer,int offset,int count)=>throw new NotSupportedException();
}
internal static unsafe class Program {
 private static int checks,gateCalls,workerGateCalls,allow;
 private static void Check(bool value,string label) {++checks;if(!value)throw new InvalidOperationException(label);}
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])] private static int Allowed() {Interlocked.Increment(ref gateCalls);if(!EHR.SourceHost.NativeSourceHost.IsMainThread)Interlocked.Increment(ref workerGateCalls);return allow;}
 [UnmanagedCallersOnly(CallConvs=[typeof(CallConvCdecl)])] private static int Other() => 1;
 private static void Tick(int count=1) {for(int i=0;i<count;++i){EHRDirectoryClock.Now+=1000;EHR.Main.Instance.Tick();Thread.Sleep(1);}}
 private static void Until(Func<bool> done) {for(int i=0;i<80&&!done();++i)Tick();Check(done(),"bounded source fixture completed");}
 private static void Reset() {
  EHR.Main.Instance.Close(); LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.Closed); EHR.Main.Instance.Close();
  FakeHandler.Sent.Clear();FakeHandler.Response=null;FakeHandler.Delayed=null;Utils.Messages.Clear();allow=1;EHRDirectoryClock.Now+=100000;
  Options.PostLobbyCodeToEHRWebsite.Value=1;GameStates.CurrentServerType=GameStates.ServerType.Vanilla;AmongUsClient.Instance=new();
  Utils.Region="OWN REGION";
  PlayerControl.LocalPlayer=new();PlayerControl.AllPlayerControls=[PlayerControl.LocalPlayer];EOSManager.Reads=0;
  EHRDirectoryTransport.FixtureHandler=()=>new FakeHandler();
 }
 private static void Listed() {LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);Until(()=>LobbySharingAPI.LastRoomCode=="ABCDEF");}
 private static void TransportCases() {
  byte[] body=EHRDirectoryTransport.Json(("field","own\"\n\\value"));using(var json=JsonDocument.Parse(body))Check(json.RootElement.GetProperty("field").GetString()=="own\"\n\\value","JSON escaping roundtrip");
  Check(EHRDirectoryTransport.RoomToken(Encoding.UTF8.GetBytes("{\"token\":\"ok\"}"))=="ok","opaque bounded room token");
  foreach(string bad in new[]{"{}","[]","{\"token\":null}","{\"token\":\"bad key\"}","not json"})Check(EHRDirectoryTransport.RoomToken(Encoding.UTF8.GetBytes(bad))==null,"bad room token rejected");
  Reset();FakeHandler.Response=()=>new(HttpStatusCode.Redirect) {Content=new StringContent(""),Headers={Location=new("https://invalid.example/")}};
  var reply=EHRDirectoryTransport.PostAsync(DirectoryEndpoint.Create,body,"OWN-JWT",default).GetAwaiter().GetResult();Check(reply.Failure==DirectoryFailure.Redirect&&FakeHandler.Sent.Count==1,"redirect never followed");
  Reset();var stream=new BoundedStream(new byte[20000]);FakeHandler.Response=()=>new(HttpStatusCode.OK) {Content=new StreamContent(stream)};
  reply=EHRDirectoryTransport.PostAsync(DirectoryEndpoint.Create,body,"OWN-JWT",default).GetAwaiter().GetResult();Check(reply.Failure==DirectoryFailure.TooLarge&&stream.ReadCount<=8193&&reply.Body.Length==0,"stream body retained bounded without content length");
  Reset();reply=EHRDirectoryTransport.PostAsync(DirectoryEndpoint.Verify,body,"OWN-JWT",default).GetAwaiter().GetResult();Check(reply.Failure==DirectoryFailure.Malformed&&FakeHandler.Sent.Count==0,"EOS bearer prohibited on verification");
  Reset();FakeHandler.Response=()=>throw new HttpRequestException("OWN-PRIVATE-EXCEPTION");reply=EHRDirectoryTransport.PostAsync(DirectoryEndpoint.Create,body,"OWN-JWT",default).GetAwaiter().GetResult();Check(reply.Failure==DirectoryFailure.Network&&reply.Body.Length==0,"transport exception reduced to fixed category");
 }
 private static void Main() {
  checks += DirectoryLogSites.Run();
  EHR.SourceHost.NativeSourceHost.Owner=Environment.CurrentManagedThreadId;
  EHRDirectoryTransport.FixtureHandler=()=>new FakeHandler();Options.PostLobbyCodeToEHRWebsite.Value=1;
  delegate* unmanaged[Cdecl]<int> directoryTick=&EHRDirectoryGate.Tick;
  LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);int absentReads=AmongUsClient.Reads;Check(directoryTick()==0&&AmongUsClient.Reads==absentReads&&FakeHandler.Sent.Count==0&&EHR.Main.Instance.Sources.Count==0,"unbound gate defaults deny including tick without game reads");
  delegate* unmanaged[Cdecl]<delegate* unmanaged[Cdecl]<int>,int> bind=&EHRDirectoryGate.Bind;
  Check(bind(null)==4,"null callback rejected");Check(bind(&Allowed)==0&&gateCalls==0,"binding never evaluates permission or sends HTTP");Check(bind(&Allowed)==0&&bind(&Other)==4,"identical binding only");
  allow=2;LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);Check(FakeHandler.Sent.Count==0,"only exact allowed result1 permits action");
  TransportCases();Reset();Check(new EHRLobbyDirectoryOption(1,"own",TabGroup.SystemSettings).GetBool()==false,"listing defaults off");
  Options.PostLobbyCodeToEHRWebsite.Value=0;LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);Tick(2);Check(FakeHandler.Sent.Count==0,"option disabled sends nothing");
  Reset();Listed();Check(FakeHandler.Sent[0].Url=="https://app.gurge44.eu/lobby_created"&&FakeHandler.Sent[0].Bearer=="OWN-FAKE-EOS-JWT","only official create receives original EOS bearer");
  using(var json=JsonDocument.Parse(FakeHandler.Sent[0].Json))Check(json.RootElement.GetProperty("hostName").GetString()=="Own \"Host\"\nName"&&json.RootElement.GetProperty("gameId").GetString()=="-7","create contract escapes host and retains signed game ID");
  Until(()=>FakeHandler.Sent.Any(r=>r.Url.EndsWith("update_status")));Check(FakeHandler.Sent.Where(r=>r.Url.EndsWith("update_status")).All(r=>r.Bearer==null),"status never receives EOS or itch credential");
  PlayerControl peer=new(){PlayerId=2,NetId=33,OwnerId=2,Client=new(){Id=2,ProductUserId="OWN-PEER-PUID"},FriendCode="OWN-PEER-FRIEND"};PlayerControl.AllPlayerControls.Add(peer);
  LobbySharingAPI.ConfirmAuth(peer,["/confirmauth","OWN-NONCE"]);Until(()=>FakeHandler.Sent.Any(r=>r.Url.EndsWith("verify_ingame")));var verification=FakeHandler.Sent.Last(r=>r.Url.EndsWith("verify_ingame"));
  using(var json=JsonDocument.Parse(verification.Json))Check(json.RootElement.GetProperty("uuid").GetString()=="OWN-NONCE"&&json.RootElement.GetProperty("puid").GetString()=="OWN-PEER-PUID","verification uses exact explicit player's identifiers");
  Check(verification.Bearer==null&&EOSManager.Reads==1,"verify/status never read or send bearer");
  LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.Closed);Until(()=>FakeHandler.Sent.Any(r=>r.Json.Contains("Closed")));Check(LobbySharingAPI.LastRoomCode=="","close invalidates local listing state");
  Reset();FakeHandler.Delayed=new(TaskCreationOptions.RunContinuationsAsynchronously);LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);Until(()=>FakeHandler.Sent.Count==1);allow=0;Tick(2);Check(LobbySharingAPI.LastRoomCode==""&&EHR.Main.Instance.Sources.Count==0,"permission loss cancels and retires in-flight source");FakeHandler.Delayed.SetResult(new(HttpStatusCode.OK){Content=new StringContent("{\"token\":\"OWN-STALE\"}")});Thread.Sleep(10);Check(LobbySharingAPI.LastRoomCode=="","late response cannot publish a stale room");
  Reset();AmongUsClient.Instance.AmHost=false;LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);Tick(2);Check(FakeHandler.Sent.Count==0,"nonhost sends nothing");
  Reset();GameStates.CurrentServerType=GameStates.ServerType.Custom;LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);Tick(2);Check(FakeHandler.Sent.Count==0,"custom region never contacts official directory");
  Reset();Listed();FakeHandler.Delayed=new(TaskCreationOptions.RunContinuationsAsynchronously);LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Game);Until(()=>FakeHandler.Sent.Count==2);LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.Ended);FakeHandler.Delayed.SetResult(new(HttpStatusCode.OK){Content=new StringContent("{}")});FakeHandler.Delayed=null;Until(()=>FakeHandler.Sent.Any(r=>r.Json.Contains("Ended")));Check(FakeHandler.Sent.Last().Json.Contains("Ended"),"new status during in-flight update remains dirty");
  Reset();FakeHandler.Delayed=new(TaskCreationOptions.RunContinuationsAsynchronously);LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);Until(()=>FakeHandler.Sent.Count==1);var former=FakeHandler.Delayed;Utils.Region="OWN OTHER REGION";Tick(2);FakeHandler.Delayed=null;former.SetResult(new(HttpStatusCode.OK){Content=new StringContent("{\"token\":\"OWN-OLD-REGION\"}")});LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);Until(()=>LobbySharingAPI.LastRoomCode=="ABCDEF");Check(FakeHandler.Sent.Count==2&&FakeHandler.Sent[1].Json.Contains("OWN OTHER REGION"),"region change retires old generation and bearer room response");
  Reset();Listed();Tick(1);Options.PostLobbyCodeToEHRWebsite.Value=0;Tick(2);Check(LobbySharingAPI.LastRoomCode==""&&EHR.Main.Instance.Sources.Count==0,"option loss retires idle worker and room token");
  Reset();Options.PostLobbyCodeToEHRWebsite.Value=0;LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);Tick(2);Options.PostLobbyCodeToEHRWebsite.SetValue(1);Until(()=>LobbySharingAPI.LastRoomCode=="ABCDEF");Check(FakeHandler.Sent.Count==1,"enabling after joined lobby starts the gated listing without another join event");Options.PostLobbyCodeToEHRWebsite.SetValue(0);Tick(2);Check(LobbySharingAPI.LastRoomCode==""&&EHR.Main.Instance.Sources.Count==0,"disabling through option setter retires listing");
  Reset();Listed();allow=0;Tick(2);int deniedReads=AmongUsClient.Reads;Check(directoryTick()==0&&AmongUsClient.Reads==deniedReads&&EHR.Main.Instance.Sources.Count==0&&LobbySharingAPI.LastRoomCode=="","renewal gate loss retires worker and denied tick snapshots nothing");allow=1;int sentBefore=FakeHandler.Sent.Count;Check(directoryTick()==0&&directoryTick()==0&&EHR.Main.Instance.Sources.Count==1&&FakeHandler.Sent.Count==sentBefore,"recovery tick starts one source and duplicate tick coalesces");Tick(1);Check(FakeHandler.Sent.Count==sentBefore,"recovery tick preserves prior request spacing");Until(()=>LobbySharingAPI.LastRoomCode=="ABCDEF");Check(FakeHandler.Sent.Count==sentBefore+1&&FakeHandler.Sent.Last().Url.EndsWith("lobby_created")&&EOSManager.Reads==2,"renewal recovery creates a fresh listing with fresh EOS bearer read");
  Reset();PlayerControl.LocalPlayer.OwnerId=9;LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);Tick(2);Check(FakeHandler.Sent.Count==0,"foreign local owner cannot list");
  int workerBind=0,workerTick=0,readsBeforeWorker=AmongUsClient.Reads;var thread=new Thread(()=>{delegate* unmanaged[Cdecl]<delegate* unmanaged[Cdecl]<int>,int> bindWorker=&EHRDirectoryGate.Bind;delegate* unmanaged[Cdecl]<int> tickWorker=&EHRDirectoryGate.Tick;workerBind=bindWorker(&Allowed);workerTick=tickWorker();LobbySharingAPI.Tick();LobbySharingAPI.NotifyLobbyStatusChanged(LobbyStatus.In_Lobby);});thread.Start();thread.Join();Check(workerBind==2&&workerTick==2&&AmongUsClient.Reads==readsBeforeWorker,"worker cannot bind, tick or enter game snapshot path");
  Check(workerGateCalls==0,"worker transport never invokes native gate");EHR.Main.Instance.Close();
  Console.WriteLine(JsonSerializer.Serialize(new{schema="ehr.directory-owned-proof.v1",pass=true,checks,actualNetworkRequests=0,actualGameCalls=0,actualCredentialsRead=0}));
 }
}
