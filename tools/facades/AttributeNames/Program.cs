using System.Security.Cryptography;
using System.Text.Json;
using System.Xml.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
if(args.Length!=2){Console.Error.WriteLine("Usage: AttributeNames input-explicit-compile.csproj output-directory");return 2;}
string input=Path.GetFullPath(args[0]),output=Path.GetFullPath(args[1]);
var project=XDocument.Load(input);Directory.CreateDirectory(output);var audit=new List<object>();
foreach(var item in project.Descendants("Compile"))
{
 string? include=(string?)item.Attribute("Include");if(include is null)continue;
 if(include.IndexOfAny(['*','?'])>=0)throw new InvalidDataException("Explicit compile items required.");
 string path=Path.GetFullPath(include,Path.GetDirectoryName(input)!);string source=File.ReadAllText(path);
 var root=CSharpSyntaxTree.ParseText(source,new CSharpParseOptions(LanguageVersion.Preview,preprocessorSymbols:["IL2CPP"])).GetRoot();
 var replacements=new Dictionary<InvocationExpressionSyntax,LiteralExpressionSyntax>();var names=new List<object>();
 foreach(var attribute in root.DescendantNodes().OfType<AttributeSyntax>())
 {
  string type=attribute.Name.ToString().Split('.').Last();if(type is not("HarmonyPatch" or "HarmonyPatchAttribute"))continue;
  foreach(var expression in attribute.DescendantNodes().OfType<InvocationExpressionSyntax>())
  {
   if(expression.Expression is not IdentifierNameSyntax id||id.Identifier.ValueText!="nameof"||expression.ArgumentList.Arguments.Count!=1)continue;
   var argument=expression.ArgumentList.Arguments[0].Expression;
   string name=argument switch {MemberAccessExpressionSyntax member=>member.Name.Identifier.ValueText,IdentifierNameSyntax simple=>simple.Identifier.ValueText,GenericNameSyntax generic=>generic.Identifier.ValueText,_=>throw new InvalidDataException("Unsupported nameof syntax: "+argument)};
   replacements.Add(expression,SyntaxFactory.LiteralExpression(SyntaxKind.StringLiteralExpression,SyntaxFactory.Literal(name)).WithTriviaFrom(expression));
   var location=expression.GetLocation().GetLineSpan().StartLinePosition;
   names.Add(new{line=location.Line+1,column=location.Character+1,original=expression.ToString(),literal=name});
  }
 }
 if(replacements.Count>0)
 {
  string rewritten=root.ReplaceNodes(replacements.Keys,(original,_)=>replacements[original]).ToFullString();
  string hash=Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(source))).ToLowerInvariant();
  string destination=Path.Combine(output,"source",hash[..16],Path.GetFileName(path));Directory.CreateDirectory(Path.GetDirectoryName(destination)!);File.WriteAllText(destination,rewritten);
  item.SetAttributeValue("Include",destination);
  audit.Add(new{input=path,output=destination,inputSha256=hash,outputSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(destination))).ToLowerInvariant(),replacements=names});
 }
 else item.SetAttributeValue("Include",path);
}
// Other relative input paths must keep their original meaning after moving the project.
foreach(var item in project.Descendants("EmbeddedResource"))if((string?)item.Attribute("Include") is string include&&!Path.IsPathRooted(include))item.SetAttributeValue("Include",Path.GetFullPath(include,Path.GetDirectoryName(input)!));
string destinationProject=Path.Combine(output,"EHR.csproj");project.Save(destinationProject);
File.WriteAllText(Path.Combine(output,"attribute-name-audit.json"),JsonSerializer.Serialize(new{formatVersion=1,scope="nameof to equivalent literal only inside HarmonyPatch attributes. Original 298-target selector pin remains authoritative. No proxy methods or native behaviors invented.",modifiedFiles=audit.Count,files=audit},new JsonSerializerOptions{WriteIndented=true})+"\n");
Console.WriteLine(JsonSerializer.Serialize(new{project=destinationProject,modifiedFiles=audit.Count}));return 0;
