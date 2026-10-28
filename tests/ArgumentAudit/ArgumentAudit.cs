using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.Loader;
using System.Text.Json;
// Offline compiled metadata only. No source callback or native method executed.
static class ArgumentAudit
{
 record Read(Type Type,object Key);
 static readonly Dictionary<ushort,OpCode> Opcodes=typeof(OpCodes).GetFields(BindingFlags.Public|BindingFlags.Static).Where(f=>f.FieldType==typeof(OpCode)).Select(f=>(OpCode)f.GetValue(null)!).ToDictionary(o=>unchecked((ushort)o.Value));
 static string Name(Type t)=>t.FullName??t.Name;
 static Dictionary<string,Type> Named=new();
 static Type? NamedType(Assembly assembly,string name)=>assembly.GetType(name)??(Named.TryGetValue(name,out var type)?type:null)??Type.GetType(name);
 static List<Read> Reads(MethodInfo callback)
 {
  var result=new List<Read>();byte[] il=callback.GetMethodBody()?.GetILAsByteArray()??[];int offset=0;object? literal=null;
  while(offset<il.Length)
  {
   ushort code=il[offset++];if(code==0xfe)code=(ushort)(0xfe00|il[offset++]);var op=Opcodes[code];int operand=offset;
   int size=op.OperandType switch{OperandType.InlineNone=>0,OperandType.ShortInlineBrTarget or OperandType.ShortInlineI or OperandType.ShortInlineVar=>1,OperandType.InlineVar=>2,OperandType.InlineI8 or OperandType.InlineR=>8,OperandType.InlineSwitch=>checked(4+4*BitConverter.ToInt32(il,offset)),_=>4};
   if(size<0||offset+size>il.Length)throw new InvalidDataException("Invalid IL operand");
   if(op==OpCodes.Ldstr)literal=callback.Module.ResolveString(BitConverter.ToInt32(il,operand));
   else if(op==OpCodes.Ldc_I4)literal=BitConverter.ToInt32(il,operand);
   else if(op==OpCodes.Ldc_I4_S)literal=(int)unchecked((sbyte)il[operand]);
   else if(op.Value>=OpCodes.Ldc_I4_M1.Value&&op.Value<=OpCodes.Ldc_I4_8.Value)literal=(int)op.Value-(int)OpCodes.Ldc_I4_0.Value;
   if(op.OperandType==OperandType.InlineMethod)
   {
    var target=callback.Module.ResolveMethod(BitConverter.ToInt32(il,operand),callback.DeclaringType!.GetGenericArguments(),callback.GetGenericArguments());
    if(target is MethodInfo method&&method.DeclaringType?.FullName=="EHR.EHRStaticPatchFrame"&&method.Name=="GetArgument")
    {if(!method.IsGenericMethod||method.GetGenericArguments().Length!=1||literal==null)throw new InvalidDataException("Unresolved argument getter");result.Add(new(method.GetGenericArguments()[0],literal));}
    literal=null;
   }
   offset+=size;
  }
  return result;
 }
 static Type Resolve(Assembly assembly,string input)
 {
  string name=input.Replace("global::","");var primitive=new Dictionary<string,Type>{{"bool",typeof(bool)},{"byte",typeof(byte)},{"sbyte",typeof(sbyte)},{"short",typeof(short)},{"ushort",typeof(ushort)},{"int",typeof(int)},{"uint",typeof(uint)},{"long",typeof(long)},{"ulong",typeof(ulong)},{"float",typeof(float)},{"double",typeof(double)},{"char",typeof(char)},{"string",typeof(string)},{"object",typeof(object)}};
  if(primitive.TryGetValue(name,out var p))return p;
  if(name.EndsWith("[]"))return Resolve(assembly,name[..^2]).MakeArrayType();
  int open=name.IndexOf('<');if(open<0)return NamedType(assembly,name)??throw new InvalidDataException("Unknown CLR type "+name);
  string content=name[(open+1)..^1];var args=new List<string>();int depth=0,start=0;
  for(int i=0;i<content.Length;++i){if(content[i]=='<')depth++;else if(content[i]=='>')depth--;else if(content[i]==','&&depth==0){args.Add(content[start..i]);start=i+1;}}args.Add(content[start..]);
  string definition=name[..open]+"`"+args.Count;return (NamedType(assembly,definition)??throw new InvalidDataException("Unknown generic CLR type "+definition)).MakeGenericType(args.Select(a=>Resolve(assembly,a)).ToArray());
 }
 static int Main(string[] args)
 {
  if(args.Length<4||args.Length>5)throw new ArgumentException("assembly candidates selectors output [reference-directory]");string assemblyPath=Path.GetFullPath(args[0]);
  AssemblyLoadContext.Default.Resolving+=(context,name)=>{foreach(string directory in args.Length==5?new[]{Path.GetDirectoryName(assemblyPath)!,Path.GetFullPath(args[4])}:new[]{Path.GetDirectoryName(assemblyPath)!}){string p=Path.Combine(directory,name.Name+".dll");if(File.Exists(p))return context.LoadFromAssemblyPath(p);}return null;};
  var assembly=AssemblyLoadContext.Default.LoadFromAssemblyPath(assemblyPath);Named=assembly.GetTypes().Where(t=>t.FullName!=null).ToDictionary(t=>t.FullName!.Replace('+','.'),t=>t);var callbacks=new Dictionary<int,(MethodInfo Method,List<Read> Reads)>();
  foreach(var type in assembly.GetTypes())foreach(var method in type.GetMethods(BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Static|BindingFlags.DeclaredOnly)){const string prefix="__EHRStaticCallback_";if(!method.Name.StartsWith(prefix,StringComparison.Ordinal))continue;int index=int.Parse(method.Name.AsSpan(prefix.Length));callbacks.Add(index,(method,Reads(method)));}
  using var candidates=JsonDocument.Parse(File.ReadAllText(args[1]));using var selectors=JsonDocument.Parse(File.ReadAllText(args[2]));var native=selectors.RootElement.GetProperty("selectors").EnumerateArray().ToDictionary(r=>r.GetProperty("selector_id").GetString()!,r=>r.GetProperty("selector"));var root=candidates.RootElement;var candidateArray=root.ValueKind==JsonValueKind.Array?root:root.GetProperty("candidates");
  var rows=new List<object>();var mismatches=new List<object>();var linked=new HashSet<int>();var unresolved=new List<string>();int edges=0;
  foreach(var candidate in candidateArray.EnumerateArray())
  {
   string selectorId=candidate.GetProperty("selectorId").GetString()!;var selector=native[selectorId];var parameters=candidate.GetProperty("parameterTypes").EnumerateArray().Select(t=>Resolve(assembly,t.GetString()!)).ToArray();var names=candidate.GetProperty("parameterNames").EnumerateArray().Select(t=>t.GetString()!).ToArray();
   foreach(var callbackElement in selector.GetProperty("callbackIds").EnumerateArray())
   {
    string callbackId=callbackElement.GetString()!;int index=int.Parse(callbackId.AsSpan(callbackId.LastIndexOf('#')+1));var callback=callbacks[index];linked.Add(index);
    foreach(var read in callback.Reads)
    {
     int parameter=read.Key is int number?number:Array.IndexOf(names,(string)read.Key);if(parameter<0||parameter>=parameters.Length){unresolved.Add(callbackId+":"+read.Key);continue;}edges++;
     Type actual=parameters[parameter],expected=read.Type;bool compatible=expected.IsAssignableFrom(actual);bool numericWidthMismatch=!compatible&&actual.IsPrimitive&&expected.IsPrimitive&&actual!=typeof(bool)&&expected!=typeof(bool);
     var row=new{targetId=candidate.GetProperty("targetId").GetUInt64(),selectorId,callbackId,argumentIndex=parameter,argumentName=names[parameter],nativeCodecType=Name(actual),callbackReadType=Name(expected),compatible,numericWidthMismatch};rows.Add(row);if(!compatible)mismatches.Add(row);
    }
   }
  }
  var report=new{schema="ehr.offline-compiled-argument-audit.v1",assembly=assemblyPath,compiledCallbacks=callbacks.Count,linkedCallbacks=linked.Count,argumentReadEdges=edges,unresolved,mismatchCount=mismatches.Count,mismatches,rows,sourceCallbacksInvoked=0,nativeGameCalls=0};File.WriteAllText(args[3],JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true})+"\n");Console.WriteLine(JsonSerializer.Serialize(new{callbacks=callbacks.Count,edges,mismatches=mismatches.Count,unresolved=unresolved.Count}));return unresolved.Count==0?0:2;
 }
}
