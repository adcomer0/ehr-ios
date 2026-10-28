using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
if(args.Length!=2)throw new Exception("usage: ComponentGenerator pinned-upstream output");
var root=Path.GetFullPath(args[0]);
string Git(params string[] command){var info=new System.Diagnostics.ProcessStartInfo("git"){RedirectStandardOutput=true,RedirectStandardError=true};info.ArgumentList.Add("-C");info.ArgumentList.Add(root);foreach(var part in command)info.ArgumentList.Add(part);using var process=System.Diagnostics.Process.Start(info)!;var value=process.StandardOutput.ReadToEnd();process.WaitForExit();if(process.ExitCode!=0)throw new Exception("Pinned upstream check failed: "+process.StandardError.ReadToEnd());return value.Trim();}
if(Git("rev-parse","HEAD")!="ce23f0d050f617a59507e5bb0fbfff751d4b5134")throw new Exception("Wrong EHR source commit");
Git("diff","--exit-code","HEAD","--","Main.cs","Modules/ErrorText.cs","Modules/ClientControlGUI.cs","Patches/Crowded.cs");
var output=Path.GetFullPath(args[1]);if(Directory.Exists(output))throw new Exception("fresh output required");
var wanted=new (uint Id,string Name,string Path)[]{(1,"EHR.Coroutines","Main.cs"),(2,"EHR.ErrorText","Modules/ErrorText.cs"),(3,"EHR.Patches.AbstractPagingBehaviour","Patches/Crowded.cs"),(4,"EHR.Patches.MeetingHudPagingBehaviour","Patches/Crowded.cs"),(5,"EHR.Patches.ShapeShifterPagingBehaviour","Patches/Crowded.cs"),(6,"EHR.Patches.VitalsPagingBehaviour","Patches/Crowded.cs"),(7,"EHR.ClientControlGUI","Modules/ClientControlGUI.cs")};
var syntax=new Dictionary<string,ClassDeclarationSyntax>();var inputs=new Dictionary<string,string>();
foreach(var path in wanted.Select(x=>x.Path).Distinct()){
 var bytes=File.ReadAllBytes(Path.Combine(root,path));inputs[path]=Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
 var tree=CSharpSyntaxTree.ParseText(Encoding.UTF8.GetString(bytes),new CSharpParseOptions(LanguageVersion.Preview,preprocessorSymbols:["IL2CPP"]));
 if(tree.GetDiagnostics().Any(x=>x.Severity==DiagnosticSeverity.Error))throw new Exception("parse failed: "+path);
 foreach(var c in tree.GetRoot().DescendantNodes().OfType<ClassDeclarationSyntax>()){
  var ns=string.Join(".",c.Ancestors().OfType<BaseNamespaceDeclarationSyntax>().Reverse().Select(x=>x.Name.ToString()));var owner=c.Ancestors().OfType<ClassDeclarationSyntax>().Reverse().Select(x=>x.Identifier.ValueText);
  syntax[string.Join(".",new[]{ns}.Concat(owner).Append(c.Identifier.ValueText))]=c;
 }
}
var messages=new Dictionary<uint,string>{{1,"Awake"},{2,"Update"},{3,"OnDestroy"},{4,"Ping"},{5,"Start"},{6,"LateUpdate"},{7,"FixedUpdate"},{8,"OnGUI"}};
ClassDeclarationSyntax? Base(ClassDeclarationSyntax c){var name=c.BaseList?.Types.FirstOrDefault()?.Type.ToString();return wanted.Where(x=>x.Name.EndsWith("."+name)).Select(x=>syntax[x.Name]).SingleOrDefault();}
MethodDeclarationSyntax? Find(ClassDeclarationSyntax c,string method){var methods=c.Members.OfType<MethodDeclarationSyntax>().Where(x=>x.Identifier.ValueText==method&&!x.Modifiers.Any(SyntaxKind.StaticKeyword)).ToArray();if(methods.Length>1)throw new Exception("overloaded lifecycle unsupported");if(methods.Length==1)return methods[0];return Base(c) is {} b?Find(b,method):null;}
var b=new StringBuilder("// Generated from pinned EHR source declarations; no runtime reflection discovery.\nusing System;\nusing System.Runtime.CompilerServices;\nnamespace EHR.Generated;\ninternal static class SourceComponentCatalog\n{\n");
b.AppendLine(" internal static bool IsSource(Type type)=>TryTypeId(type,out _);\n internal static uint TypeId(Type type)=>TryTypeId(type,out var id)?id:throw new RuntimeGatewayException(7,\"Uncompiled source component \"+type.FullName);\n internal static bool TryTypeId(Type type,out uint id)\n {\n  if(type==typeof(global::EHR.NativeProbes.StaticLifecycleProbe)){id=8;return true;}\n  if(type==typeof(global::EHR.Coroutines)){id=1;return true;}\n#if EHR_ALL_SOURCE_COMPONENTS");
foreach(var x in wanted.Skip(1))b.AppendLine($"  if(type==typeof(global::{x.Name})){{id={x.Id};return true;}}");
b.AppendLine("#endif\n  id=0;return false;\n }\n internal static void RequireSupported(uint id)\n {\n  if(id==1||id==8)return;\n#if EHR_ALL_SOURCE_COMPONENTS\n  if(id>=2&&id<=7)return;\n#endif\n  throw new RuntimeGatewayException(7,\"Uncompiled source component TypeID \"+id);\n }\n internal static RuntimeObject Create(uint id)=>id switch\n {\n  1=>new global::EHR.Coroutines(),\n  8=>new global::EHR.NativeProbes.StaticLifecycleProbe(),\n#if EHR_ALL_SOURCE_COMPONENTS");
foreach(var x in wanted.Skip(1))b.AppendLine($"  {x.Id}=>new global::{x.Name}(),");
b.AppendLine("#endif\n  _=>throw new RuntimeGatewayException(7,\"Uncompiled source factory\")\n };\n internal static void Dispatch(uint id,RuntimeObject source,uint message)\n {\n  if(id==8){((global::EHR.NativeProbes.StaticLifecycleProbe)source).Dispatch(message);return;}\n  if(id==1){if(message==3)return;throw new RuntimeGatewayException(7,\"Empty source Coroutines message\");}\n#if EHR_ALL_SOURCE_COMPONENTS\n  switch(id)\n  {");
var accessors=new List<string>();var manifest=new List<object>();
foreach(var x in wanted){var c=syntax[x.Name];if(c.Members.OfType<ConstructorDeclarationSyntax>().Any())throw new Exception("Explicit source constructor requires review: "+x.Name);
 var baseName=c.BaseList?.Types.Single().Type.ToString()??throw new Exception("missing base");
 if(baseName!=(x.Id>=4&&x.Id<=6?"AbstractPagingBehaviour":"MonoBehaviour")||c.TypeParameterList!=null||c.Modifiers.Any(SyntaxKind.AbstractKeyword))throw new Exception("Unexpected pinned component base/shape: "+x.Name);var methods=new List<object>();
 if(x.Id!=1){b.AppendLine($"   case {x.Id}:\n    switch(message)\n    {{");
 foreach(var pair in messages){var m=Find(c,pair.Value);if(m==null){if(pair.Key==3)b.AppendLine("     case 3:return;");continue;}
  if(m.ParameterList.Parameters.Count!=0||m.ReturnType.ToString()!="void"||m.TypeParameterList!=null)throw new Exception("unsupported Unity lifecycle shape");
  var privateMethod=m.Modifiers.Any(SyntaxKind.PrivateKeyword)||!m.Modifiers.Any(t=>t.IsKind(SyntaxKind.PublicKeyword)||t.IsKind(SyntaxKind.ProtectedKeyword)||t.IsKind(SyntaxKind.InternalKeyword));
  var declaring=syntax.Single(kv=>ReferenceEquals(kv.Value,m.Parent)).Key;var accessor="Call"+x.Id+pair.Value;
  var call=privateMethod?$"{accessor}((global::{declaring})source)":$"((global::{x.Name})source).{pair.Value}()";
  b.AppendLine($"     case {pair.Key}:{call};return;");
  if(privateMethod)accessors.Add($" [UnsafeAccessor(UnsafeAccessorKind.Method,Name=\"{pair.Value}\")] private static extern void {accessor}(global::{declaring} self);");
  methods.Add(new{id=pair.Key,name=pair.Value,declaring,privateAccessor=privateMethod,returns="System.Void",parameters=Array.Empty<string>(),inherited=declaring!=x.Name});
 }
 b.AppendLine("     default:throw new RuntimeGatewayException(7,\"Uncompiled Unity message\");\n    }");}
 manifest.Add(new{id=x.Id,name=x.Name,source=x.Path,baseName,sourceConstructor="implicit parameterless; field initializers unchanged",nativeInstanceFieldsAdded=0,unityMessages=methods,otherSourceMethodsNativeMetadataImplemented=false});
}
b.AppendLine("  }\n#endif\n  throw new RuntimeGatewayException(7,\"Unknown source component callback\");\n }");
b.AppendLine("#if EHR_ALL_SOURCE_COMPONENTS");foreach(var line in accessors)b.AppendLine(line);b.AppendLine("#endif\n}");
Directory.CreateDirectory(output);File.WriteAllText(Path.Combine(output,"SourceComponentCatalog.g.cs"),b.ToString());
var coroutines=syntax["EHR.Coroutines"];File.WriteAllText(Path.Combine(output,"Coroutines.source.cs"),"// Exact original empty source declaration, isolated from Main.cs startup.\nusing MonoBehaviour = EHR.Generated.UnityEngine_MonoBehaviour;\nnamespace EHR;\n"+coroutines.ToFullString().Trim()+"\n");
File.WriteAllText(Path.Combine(output,"component-plan.json"),JsonSerializer.Serialize(new{schema="ehr.pinned-source-component-plan.v1",commit="ce23f0d050f617a59507e5bb0fbfff751d4b5134",inputs,components=manifest,defaultProfileCompiledTypeIds=new[]{1,8},fullProfileRequiresDefine="EHR_ALL_SOURCE_COMPONENTS",nativeRegistryImplemented=false,actualSourceLifecycleTested=false},new JsonSerializerOptions{WriteIndented=true})+"\n");
Console.WriteLine(output);
