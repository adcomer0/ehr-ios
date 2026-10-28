using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace EHR.SourcePort;

// Pure source DTO/JSON gate. Does not initialize Main, run gameplay, access an
// account or network, or write a save file. All failures stay inside the AOT ABI.
internal static class EHRPortableJsonSelfTest
{
    [UnmanagedCallersOnly(EntryPoint="ehr_source_json_self_test_v1",CallConvs=[typeof(CallConvCdecl)])]
    internal static unsafe int Export(uint* output,nuint count)
    {
        if(output==null||count!=10)return 4;
        return Run(new Span<uint>(output,10));
    }
    internal static int Run(Span<uint> output)
    {
        if(output.Length!=10)return 4;output.Clear();
        try
        {
            var a=EHRPortableJsonContext.Default;var indent=EHRPortableJsonContext.Indented;
            string colors=JsonSerializer.Serialize(new Dictionary<global::EHR.CustomRoles,string>{{global::EHR.CustomRoles.Crewmate,"#ffffff"}},indent.RoleColors);
            output[1]=colors.Contains("\n  \"Crewmate\"")&&JsonSerializer.Deserialize(colors,a.StringColors)!["Crewmate"]=="#ffffff"?1u:0;
            var options=new global::EHR.Modules.OptionSaver.SerializableOptionsData{Version=0,SingleOptions=new(){{0,2}},PresetOptions=new(){{7,[1,2]}}};
            var saved=JsonSerializer.Deserialize(JsonSerializer.Serialize(options,indent.OptionData),a.OptionData)!;
            output[2]=saved.SingleOptions[0]==2&&saved.PresetOptions[7][1]==2?1u:0;
            output[3]=JsonSerializer.Deserialize("{\"Vip\":true}",a.UserData)!.Vip&&!JsonSerializer.Deserialize("{\"vip\":true}",a.UserData)!.Vip?1u:0;
            var achievements=new HashSet<global::EHR.Modules.Achievements.Type>{global::EHR.Modules.Achievements.Type.IdeasLiveOn};
            output[4]=JsonSerializer.Serialize(achievements,a.Achievements)=="[0]"?1u:0;
            output[5]=JsonSerializer.Serialize(new AchievementUploadRequest{userId="own-json-probe",achievements=achievements},a.AchievementUpload)=="{\"userId\":\"own-json-probe\",\"achievements\":[0]}"?1u:0;
            using(var stream=new MemoryStream(Encoding.UTF8.GetBytes("{\"LanguageID\":\"0\",\"Hello\":\"world\"}")))
                output[6]=JsonSerializer.Deserialize(stream,a.Language)!["LanguageID"].GetString()=="0"?1u:0;
            var combo=new Dictionary<int,Dictionary<string,List<string>>>{{2,new(){{"Crewmate",["Bait"]}}}};
            output[7]=JsonSerializer.Deserialize(JsonSerializer.Serialize(combo,indent.Combos),a.Combos)![2]["Crewmate"][0]=="Bait"?1u:0;
            var tags=JsonSerializer.Deserialize("{\"own\":{\"tag_name\":\"T\",\"tag_color\":\"C\",\"up\":true,\"ip\":null}}",a.Tags)!;
            var draft=JsonSerializer.Deserialize("{\"draft_id\":\"d\",\"error\":null}",a.PresetDraftResponse)!;
            var download=JsonSerializer.Deserialize("{\"preset\":{\"1\":2},\"hash\":\"h\",\"error\":null}",a.PresetDownloadResponse)!;
            var list=JsonSerializer.Deserialize("{\"presets\":[{\"id\":\"i\",\"created_at\":1.5,\"downloads\":2}]}",a.PresetListResponse)!;
            var request=new global::EHR.Modules.OnlinePresetsManager.PresetDraftRequest{friend_code="own",puid="own",preset=new()};
            var news=JsonSerializer.Deserialize("[{\"Number\":1,\"Date\":\"2026-10-28\",\"Title\":\"own\",\"SubTitle\":\"s\",\"ShortTitle\":\"t\",\"Text\":\"body\"}]",a.News)!;
            output[8]=tags["own"].up&&draft.draft_id=="d"&&download.preset[1]==2&&list.presets[0].downloads==2&&news[0].Text=="body"&&JsonSerializer.Serialize(request,a.PresetDraftRequest).Contains("\"friend_code\":\"own\"")?1u:0;
            output[9]=JsonSerializer.IsReflectionEnabledByDefault?0u:1u;
            output[0]=1;for(int i=1;i<9;++i)output[0]&=output[i];return output[0]==1?0:5;
        }
        catch{return 6;}
    }
}
