using System;
using System.IO;
using EHR.SourceAudio;

int checks=0;void Check(bool value,string name){checks++;if(!value)throw new Exception(name);}
string[] resources=["EHR.Resources.Sounds.Teleport.wav","EHR.Resources.Sounds.Line.wav","EHR.Resources.Other.wav"];
Check(SourceAudioNames.Resolve("teleport",_=>false,resources)=="Teleport","source lowercase literal resolves uniquely");
Check(SourceAudioNames.Resolve("teleport",s=>s=="teleport",resources)=="teleport","exact requested custom first");
Check(SourceAudioNames.Resolve("Line",_=>false,resources)=="Line","exact authored name");
Check(SourceAudioNames.Resolve("lInE",_=>false,resources)=="Line","mixed case authored name");
Check(SourceAudioNames.Resolve("Unknown",_=>false,resources)=="Unknown","unknown remains absent");
bool rejected=false;try{SourceAudioNames.Resolve("abc",_=>false,["EHR.Resources.Sounds.ABC.wav","EHR.Resources.Sounds.AbC.wav"]);}catch(InvalidDataException){rejected=true;}Check(rejected,"ambiguous authored name rejected");
Check(SourceAudioNames.Resolve("ABC",_=>false,["EHR.Resources.Sounds.ABC.wav","EHR.Resources.Sounds.AbC.wav"])=="ABC","exact authored spelling wins");
Check(SourceAudioNames.Resolve("abc",_=>false,["EHR.Resources.Sounds.ABC.wav","EHR.Resources.Sounds.AbC.wav","EHR.Resources.Sounds.abc.wav"])=="abc","exact authored choice independent of inventory order");
string root=Path.Combine(Path.GetTempPath(),"ehr-sound-names-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
try
{
    string canonical=OwnedSoundFiles.Prepare(root,"Teleport");File.WriteAllBytes(canonical,[1,2,3]);
    Check(OwnedSoundFiles.ExistingExact(root,"Teleport"),"exact actual filename exists");
    Check(!OwnedSoundFiles.ExistingExact(root,"teleport"),"case-folded filesystem lookup not accepted as exact custom");
    string resolved=SourceAudioNames.Resolve("teleport",s=>OwnedSoundFiles.ExistingExact(root,s),resources);Check(resolved=="Teleport","canonical existing custom selected after lowercase missing");
    bool resourceOpened=false;bool invalidCustomRejected=false;
    try{OwnedSoundFiles.Load(root,resolved,_=>{resourceOpened=true;return new MemoryStream(new byte[44]);});}catch(FormatException){invalidCustomRejected=true;}
    Check(!resourceOpened&&invalidCustomRejected,"canonical existing custom read before extraction");
    Check(File.ReadAllBytes(canonical).AsSpan().SequenceEqual(new byte[]{1,2,3}),"canonical custom untouched");
    string outside=Path.Combine(root,"outside.wav");File.WriteAllBytes(outside,[4,5]);string link=SourceAudioPaths.SoundFile(root,"Link");File.CreateSymbolicLink(link,outside);
    rejected=false;try{OwnedSoundFiles.ExistingExact(root,"Link");}catch(IOException){rejected=true;}Check(rejected,"exact symlink custom rejected");
    Console.WriteLine($"PASS {checks} authored-name/custom-priority checks; no native/game/account/network/audio operations");
}
finally{Directory.Delete(root,true);}
