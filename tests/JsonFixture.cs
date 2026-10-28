using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using EHR;
using EHR.Modules;
using EHR.SourcePort;
static class Program
{
 static int checks;static void Check(bool value){++checks;if(!value)throw new Exception("check "+checks);}
 static string Roundtrip<T>(T value,JsonTypeInfo<T> info){string json=JsonSerializer.Serialize(value,info);T? again=JsonSerializer.Deserialize(json,info);Check(JsonSerializer.Serialize(again,info)==json);
#if REFERENCE_PARITY
  Check(json==JsonSerializer.Serialize(value,new JsonSerializerOptions{WriteIndented=info.Options.WriteIndented}));
#endif
  return json;}
 static void Throws(Action action){bool failed=false;try{action();}catch(JsonException){failed=true;}Check(failed);}
 static void Main(){
#if !REFERENCE_PARITY
  Check(!JsonSerializer.IsReflectionEnabledByDefault);
#endif
  var a=EHRPortableJsonContext.Default;var indent=EHRPortableJsonContext.Indented;
  var roles=new Dictionary<CustomRoles,string>{{CustomRoles.Crewmate,"#ffffff"},{CustomRoles.Impostor,"<color=red>é</color>"}};
  string roleText=Roundtrip(roles,indent.RoleColors);Check(roleText.Contains("\n  \"Crewmate\""));Check(roleText.Contains("\\u003C"));
  var strings=JsonSerializer.Deserialize(roleText,a.StringColors)!;Check(strings["Crewmate"]=="#ffffff"&&strings["Impostor"]=="<color=red>é</color>");Roundtrip(strings,a.StringColors);
  var options=new OptionSaver.SerializableOptionsData{Version=0,SingleOptions=new(){{0,2},{18,-1}},PresetOptions=new(){{7,[1,2,3]}}};
  Check(Roundtrip(options,indent.OptionData).StartsWith("{\n  \"Version\": 0"));Check(JsonSerializer.Deserialize("null",a.OptionData)==null);
  var user=new Options.UserData{Vip=true,Moderator=false,Admin=true,Tag="line\n😀"};Check(Roundtrip(user,indent.UserData).Contains("\"Moderator\": false"));
  Check(!JsonSerializer.Deserialize("{\"vip\":true}",a.UserData)!.Vip);Check(JsonSerializer.Deserialize("{\"Vip\":true,\"unknown\":1}",a.UserData)!.Vip);Throws(()=>JsonSerializer.Deserialize("{\"Vip\":\"true\"}",a.UserData));
  var achievements=new HashSet<Achievements.Type>{Achievements.Type.IdeasLiveOn,Achievements.Type.HowCouldIBelieveThem};Check(Roundtrip(achievements,a.Achievements)=="[0,1]");
  var dto=new AchievementUploadRequest{userId="hashed-id",achievements=achievements};string payload=Roundtrip(dto,a.AchievementUpload);Check(payload=="{\"userId\":\"hashed-id\",\"achievements\":[0,1]}");
#if REFERENCE_PARITY
  Check(payload==JsonSerializer.Serialize(new{userId="hashed-id",achievements}));
#endif
  var combos=new Dictionary<int,Dictionary<string,List<string>>>{{2,new(){{"Jester",["Bait","Crewmate"]}}},{-1,new()}};Check(Roundtrip(combos,indent.Combos).Contains("\"-1\""));Throws(()=>JsonSerializer.Deserialize("{\"bad\":{}}",a.Combos));
  var tags=new Dictionary<string,DevManager.TagInfo>{{"friend#1234",new(){tag_name="Dev",tag_color="#ff00ff",up=true,ip=null!}}};Check(Roundtrip(tags,a.Tags).Contains("\"tag_name\":\"Dev\""));Check(JsonSerializer.Serialize(tags,a.Tags).Contains("\"ip\":null"));
  var draft=new OnlinePresetsManager.PresetDraftRequest{friend_code="f#1",puid="product",preset=new(){{12,3}}};Check(Roundtrip(draft,a.PresetDraftRequest).Contains("\"friend_code\""));
  Roundtrip(new OnlinePresetsManager.PresetDraftResponse{draft_id="d-1",error=null!},a.PresetDraftResponse);
  Roundtrip(new OnlinePresetsManager.PresetDownloadResponse{preset=new(){{12,3}},hash="abc",error=null!},a.PresetDownloadResponse);
  var meta=new OnlinePresetsManager.PresetMeta{id="id",name="N",description="D",author="A",hash="H",created_at=12.5,downloads=3};
  Roundtrip(new OnlinePresetsManager.PresetListResponse{presets=[meta]},a.PresetListResponse);
  var news=new List<ModNews>{new(){Number=1,Date="2026-10-28",Title="T",SubTitle="S",ShortTitle="ST",Text="body"}};Check(Roundtrip(news,a.News).Contains("\"SubTitle\""));
  Dictionary<string,JsonElement>? language;using(var stream=new MemoryStream(Encoding.UTF8.GetBytes("{\"LanguageID\":\"0\",\"a\":[1,true],\"b\":{\"c\":\"你好\"}}")))language=JsonSerializer.Deserialize(stream,a.Language);
  Check(language!["LanguageID"].GetString()=="0"&&language["a"][1].GetBoolean()&&language["b"].GetProperty("c").GetString()=="你好");Roundtrip(language,a.Language);
  Throws(()=>JsonSerializer.Deserialize("{bad}",a.StringColors));Span<uint> sourceProof=stackalloc uint[10];Check(EHRPortableJsonSelfTest.Run(sourceProof)==0&&sourceProof[0]==1);Check(sourceProof[9]==(JsonSerializer.IsReflectionEnabledByDefault?0u:1u));Console.WriteLine("PASS "+checks+" exact-source JSON contract checks; reflection="+JsonSerializer.IsReflectionEnabledByDefault);
 }
}
