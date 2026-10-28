import copy
import json
from pathlib import Path
import tempfile
import unittest
from generate_facades import canonical, generate, verify_pins

def field(name, type_, static=False, readonly=False, constant=None):
    return dict(name=name,type=type_,isStatic=static,isReadOnly=readonly,constant=constant)
def method(name, return_type, parameters=(), static=False):
    return dict(name=name,returnType=return_type,parameters=list(parameters),genericArity=0,isStatic=static)
def member(name, type_, parameters=(), static=False, token=1, parent="PlayerControl"):
    return dict(metadataToken=token,assembly="Assembly-CSharp",declaringType="[Assembly-CSharp]"+parent,
                name=name,kind="method",returnOrFieldType=type_,parameterTypes=list(parameters),isStatic=static,
                genericArity=0,hasByRef=any("&" in p for p in parameters),hasPointer=False)
def fixture(rows):
    defs=[dict(name="[<local>]PlayerControl",baseType="[<local>]InnerNet.InnerNetObject",
               fields=[field("PlayerId","System.Byte"),field("ReadOnly","System.Int32",readonly=True),
                       field("AllPlayerControls","[mscorlib]System.Collections.Generic.List`1<[<local>]PlayerControl>",static=True)],
               methods=[method("get_CanMove","System.Boolean"),method("SetRole","System.Void",["[<local>]RoleNames"]) ]),
          dict(name="[<local>]InnerNet.InnerNetObject",baseType="[mscorlib]System.Object",fields=[],methods=[]),
          dict(name="[<local>]RoleNames",baseType="[mscorlib]System.Enum",fields=[field("value__","System.UInt32"),field("Crewmate","[<local>]RoleNames",True,True,0)],methods=[]),
          dict(name="[<local>]Constants",baseType="[mscorlib]System.Object",fields=[],methods=[method("GetBroadcastVersion","System.Int32",static=True)])]
    return (dict(inputSha256="a"*64,members=rows),dict(inputSha256="b"*64,typeDefinitions=defs))

class GeneratorTests(unittest.TestCase):
    def complex_fixture(self, descriptor):
        refs,defs=fixture([member('get_Callback',descriptor)])
        defs['typeDefinitions'][0]['fields'].append(field('Callback',descriptor))
        defs['typeDefinitions'].append(dict(name='[<local>]IntEnum',baseType='[mscorlib]System.Enum',fields=[field('value__','System.Int32')],methods=[]))
        defs['typeDefinitions'].append(dict(name='[UnityEngine.CoreModule]UnityEngine.SceneManagement.Scene',image='UnityEngine.CoreModule.dll',baseType='[mscorlib]System.ValueType',fields=[],methods=[]))
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory));text=(Path(directory)/'GeneratedFacades.g.cs').read_text()
        return report,text
    def test_action3_uses_exact_complex_abi_class_and_owning_wrapper(self):
        report,text=self.complex_fixture('System.Action<System.String,System.Int32,IntEnum>')
        self.assertEqual(report['generatedSourceMemberReferences'],1)
        self.assertIn('global::Il2CppSystem.Action<string, int, IntEnum>',text)
        self.assertIn('ComplexDelegateRuntime.TripleClass<string, int, IntEnum>()',text)
        self.assertIn('static token=>new global::Il2CppSystem.Action<string, int, IntEnum>(token)',text)
    def test_func2_reference_bool_uses_existing_native_closed_function(self):
        report,text=self.complex_fixture('System.Func<PlayerControl,System.Boolean>')
        self.assertEqual(report['generatedSourceMemberReferences'],1)
        self.assertIn('ComplexDelegateRuntime.FunctionClass<PlayerControl, bool>()',text)
        self.assertIn('new global::Il2CppSystem.Func<PlayerControl, bool>(result.Detach())',text)
    def test_scene2_uses_qualified_wrapper_without_nongeneric_alias_collision(self):
        report,text=self.complex_fixture('UnityEngine.Events.UnityAction<UnityEngine.SceneManagement.Scene,IntEnum>')
        self.assertEqual(report['generatedSourceMemberReferences'],1)
        self.assertIn('global::EHR.Generated.UnityEngine_Events_UnityAction<UnityEngine_SceneManagement_Scene, IntEnum>',text)
        self.assertIn('ComplexDelegateRuntime.SceneClass<UnityEngine_SceneManagement_Scene, IntEnum>()',text)
    def test_complex_delegate_unproven_abi_families_reject(self):
        for descriptor in ['System.Action<System.String,System.Single,IntEnum>','System.Action<System.String,System.Int32,RoleNames>','System.Func<System.Int32,System.Boolean>','System.Func<PlayerControl,System.Int32>','UnityEngine.Events.UnityAction<PlayerControl,IntEnum>']:
            report,text=self.complex_fixture(descriptor)
            self.assertEqual(report['generatedSourceMemberReferences'],0,descriptor)
            self.assertNotIn('public global::Il2CppSystem.Func',text)
    def test_source_component_constructor_consumes_registered_weak_self_only_when_selected(self):
        refs,defs=fixture([member('.ctor','System.Void',parent='UnityEngine.MonoBehaviour')])
        defs['typeDefinitions'].append(dict(name='[UnityEngine.CoreModule]UnityEngine.MonoBehaviour',image='UnityEngine.CoreModule.dll',baseType='[mscorlib]System.Object',fields=[],methods=[method('.ctor','System.Void')]))
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory),source_components=True)
            text=(Path(directory)/'GeneratedFacades.g.cs').read_text()
        self.assertIn('public UnityEngine_MonoBehaviour() : base(SourceComponentConstruction.Take()) { SourceComponentConstruction.Bind(this); }',text)
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory))
            text=(Path(directory)/'GeneratedFacades.g.cs').read_text()
        self.assertNotIn('SourceComponentConstruction.Take()',text)
    def test_selector_signature_closure_keeps_guid_codec_without_method_facade(self):
        refs,defs=fixture([])
        defs['typeDefinitions'].append(dict(name='[mscorlib]System.Guid',image='mscorlib.dll',baseType='[mscorlib]System.ValueType',fields=[],methods=[]))
        profile={'typeDefinitions':[dict(name='[Il2Cppmscorlib]Il2CppSystem.Guid',baseType='[System.Runtime]System.ValueType',fields=[],methods=[])]}
        selectors={'selectors':[dict(selectorId='owned-guid',resolutionStatus='resolved_managed_reference_signature',declaringType='PlayerControl',image='Assembly-CSharp',methodName='Missing',returnType='System.Boolean',parameterTypes=['System.Guid&'],isStatic=True)]}
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory),True,selectors,profile)
            text=(Path(directory)/'SourceSurface.g.cs').read_text()
        self.assertIn('namespace Il2CppSystem {',text)
        self.assertIn('struct Guid : INativeValue',text)
        self.assertIn('ElementCodecs.Register<global::Il2CppSystem.Guid>',text)
        self.assertNotIn('@Missing(',text)
        self.assertEqual(report['unavailableSelectorSignatureTypes'],[])

    def test_selector_signature_closure_reports_absent_native_type(self):
        refs,defs=fixture([])
        selectors={'selectors':[dict(selectorId='owned-missing',resolutionStatus='resolved_managed_reference_signature',declaringType='PlayerControl',image='Assembly-CSharp',methodName='Missing',returnType='System.Void',parameterTypes=['NotProvided&'],isStatic=True)]}
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory),True,selectors)
            text=(Path(directory)/'SourceSurface.g.cs').read_text()
        self.assertEqual(report['unavailableSelectorSignatureTypes'][0]['type'],'NotProvided&')
        self.assertNotIn('class NotProvided',text)
    def run_fixture(self, rows, source=False):
        refs,defs=fixture(rows)
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory),source)
            text=(Path(directory)/("SourceSurface.g.cs" if source else "GeneratedFacades.g.cs")).read_text()
        return report,text
    def test_native_field_properties_use_barrier_gateway_not_fake_getter(self):
        report,text=self.run_fixture([member("get_PlayerId","System.Byte"),member("set_PlayerId","System.Void",["System.Byte"],token=2)])
        binding=next(b for b in report["bindings"] if b["member"]=="PlayerId")
        self.assertTrue(binding["isField"])
        self.assertEqual(report["generatedSourceMemberReferences"],2)
        self.assertEqual(report["uniqueNativeBindings"],2) # one field plus explicit getter probe
        self.assertIn("public byte @PlayerId",text)
        self.assertIn("FacadeRuntime.ReadField",text)
        self.assertIn("FacadeRuntime.WriteField",text)
        self.assertNotIn('"get_PlayerId"',text)
    def test_real_getter_remains_runtime_method(self):
        report,text=self.run_fixture([member("get_CanMove","System.Boolean")])
        self.assertFalse(next(b for b in report["bindings"] if b["member"]=="get_CanMove")["isField"])
        self.assertIn("FacadeRuntime.Invoke",text)
    def test_native_lists_remain_live_without_snapshot_fallback(self):
        report,text=self.run_fixture([member("get_AllPlayerControls","[Il2Cppmscorlib]Il2CppSystem.Collections.Generic.List`1<[Assembly-CSharp]PlayerControl>",static=True)])
        self.assertEqual(report["generatedSourceMemberReferences"],1)
        self.assertIn("global::Il2CppSystem.Collections.Generic.List<PlayerControl>",text)
        self.assertIn("(result.Detach(), true)",text)
        self.assertNotIn("new System.Collections.Generic.List",text)
    def test_ref_out_and_unknown_native_external_type_fail_closed(self):
        rows=[member("TryGet","System.Boolean",["System.Int32&"]),member("External","[UnityEngine.CoreModule]UnityEngine.Vector2")]
        report,_=self.run_fixture(rows)
        self.assertEqual(report["generatedSourceMemberReferences"],0)
        self.assertIn("native exact method signature absent or ambiguous",report["unsupportedByReason"])
        # External method is absent in exact native definitions; no fake method is emitted.
        self.assertIn("native exact method signature absent or ambiguous",report["unsupportedByReason"])
    def test_readonly_native_field_has_no_setter(self):
        report,text=self.run_fixture([member("get_ReadOnly","System.Int32"),member("set_ReadOnly","System.Void",["System.Int32"],token=2)])
        self.assertEqual(report["generatedSourceMemberReferences"],1)
        self.assertIn("readonly native field has no writable facade",report["unsupportedByReason"])
        self.assertNotIn("FacadeRuntime.WriteField",text)
    def test_enum_preserves_exact_native_value_class_and_underlying_type(self):
        report,text=self.run_fixture([member("SetRole","System.Void",["[Assembly-CSharp]RoleNames"])])
        self.assertIn("public enum RoleNames : uint",text)
        self.assertIn('FacadeRuntime.Value(&@p0, "RoleNames")',text)
        self.assertIn("@Crewmate = 0",text)
    def test_original_namespace_surface_preserves_available_native_inheritance(self):
        report,text=self.run_fixture([member("get_PlayerId","System.Byte")],True)
        self.assertTrue(report["originalNamespaces"])
        self.assertIn("partial class PlayerControl : global::InnerNet.InnerNetObject",text)
        self.assertIn("namespace InnerNet {",text)
        self.assertIn("partial class InnerNetObject : global::Il2CppSystem.Object",text)
    def test_constructed_type_arity_is_removed_but_open_type_is_preserved(self):
        self.assertEqual(canonical("[Il2Cppmscorlib]Il2CppSystem.Collections.Generic.List`1<[Assembly-CSharp]PlayerControl>"),"System.Collections.Generic.List<PlayerControl>")
        self.assertEqual(canonical("System.Collections.Generic.List`1"),"System.Collections.Generic.List`1")
        self.assertEqual(canonical("Il2CppInterop.Runtime.InteropTypes.Arrays.Il2CppStructArray`1<System.Int32>"),"System.Int32[]")
        self.assertEqual(canonical("Il2CppInterop.Runtime.InteropTypes.Arrays.Il2CppStringArray"),"System.String[]")
    def test_scalar_out_is_exact_live_call_and_assigns_only_after_success(self):
        refs,defs=fixture([member("TryGet","System.Boolean",["System.Int32&"])])
        defs["typeDefinitions"][0]["methods"].append(dict(name="TryGet",returnType="System.Boolean",parameters=["System.Int32&"],parameterModes=["out"],genericArity=0,isStatic=False))
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory))
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertEqual(report["generatedSourceMemberReferences"],1)
        self.assertIn("out int @p0",text)
        self.assertIn("LiveCollections.InvokeWithRefs",text)
        self.assertLess(text.index("LiveCollections.InvokeWithRefs"),text.index("@p0 = local0;"))
    def test_unsupported_reference_out_is_not_emitted(self):
        refs,defs=fixture([member("TryGet","System.Boolean",["[Assembly-CSharp]PlayerControl&"])])
        defs["typeDefinitions"][0]["methods"].append(method("TryGet","System.Boolean",["[<local>]PlayerControl&"]))
        with tempfile.TemporaryDirectory() as directory:report=generate(refs,defs,Path(directory))
        self.assertIn("ref managed reference exception-side-effect transport unsupported",report["unsupportedByReason"])
    def test_duplicate_selector_and_direct_property_emitted_once(self):
        refs,defs=fixture([member("get_CanMove","System.Boolean")])
        selectors={"selectors":[dict(resolutionStatus="resolved_managed_reference_signature",selectorId="x",image="Assembly-CSharp",declaringType="PlayerControl",methodName="get_CanMove",parameterTypes=[],returnType="System.Boolean",isStatic=False)]}
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory),selectors=selectors)
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertEqual(text.count("public bool @CanMove"),1)
        self.assertNotIn("public bool @get_CanMove",text)
    def test_mutable_field_ref_has_real_setter_without_double_counting(self):
        row=member("PlayerId","System.Byte");row["kind"]="field"
        report,text=self.run_fixture([row])
        self.assertEqual(report["generatedSourceMemberReferences"],1)
        self.assertIn("FacadeRuntime.WriteField",text)
    def test_boxed_struct_copy_on_write_and_kind3_arguments(self):
        refs,defs=fixture([member(".ctor","System.Void",["System.Single"],parent="UnityEngine.Vector2"),member("x","System.Single",parent="UnityEngine.Vector2"),member("Normalize","System.Void",parent="UnityEngine.Vector2"),member("Distance","System.Single",["UnityEngine.Vector2","UnityEngine.Vector2"],True,parent="UnityEngine.Vector2")])
        refs["members"][1]["kind"]="field"
        defs["typeDefinitions"].append(dict(name="UnityEngine.Vector2",baseType="System.ValueType",image="UnityEngine.CoreModule.dll",fields=[field("x","System.Single")],methods=[method(".ctor","System.Void",["System.Single"]),method("Normalize","System.Void"),method("Distance","System.Single",["UnityEngine.Vector2","UnityEngine.Vector2"],True)]))
        # The fixture's row assembly must match its actual owning module.
        for row in refs["members"]:row["assembly"]="UnityEngine.CoreModule"
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory))
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertEqual(report["generatedValueStructs"],1)
        self.assertIn("partial struct UnityEngine_Vector2 : INativeValue",text)
        self.assertIn("EnsureWritable();",text)
        self.assertIn("NativeValues.Clone(NativeBox)",text)
        self.assertIn("NativeValues.Argument(boxed0)",text)
        self.assertNotIn("Value(&p0",text)
    def test_nested_source_type_shape_and_native_selector_are_distinct(self):
        refs,defs=fixture([member("get_ColorId","System.Int32",parent="NetworkedPlayerInfo+PlayerOutfit")])
        defs["typeDefinitions"].append(dict(name="NetworkedPlayerInfo+PlayerOutfit",baseType="System.Object",fields=[field("ColorId","System.Int32")],methods=[]))
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory),source_surface=True)
            text=(Path(directory)/"SourceSurface.g.cs").read_text()
        binding=next(b for b in report["bindings"] if b["member"]=="ColorId")
        self.assertEqual(binding["namespace"],"")
        self.assertEqual(binding["type"],"NetworkedPlayerInfo+PlayerOutfit")
        self.assertIn("public partial class NetworkedPlayerInfo {",text)
        self.assertIn("partial class PlayerOutfit : global::Il2CppSystem.Object",text)
        self.assertIn("global::NetworkedPlayerInfo.PlayerOutfit",text)
    def test_native_value_proxy_class_keeps_reference_alias_semantics(self):
        refs,defs=fixture([member("set_Value","System.Void",["System.Single"],parent="BoxedValue")])
        defs["typeDefinitions"].append(dict(name="BoxedValue",baseType="System.ValueType",fields=[field("Value","System.Single")],methods=[]))
        profile={"typeDefinitions":[dict(name="BoxedValue",baseType="[Il2Cppmscorlib]Il2CppSystem.ValueType")]}
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory),source_profile=profile)
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertEqual(report["generatedBoxedValueClasses"],1)
        self.assertIn("partial class BoxedValue : global::Il2CppSystem.Object",text)
        self.assertNotIn("partial struct BoxedValue",text)
        self.assertNotIn("EnsureWritable()",text)
    def test_exact_descriptor_registry_retains_class_selector_without_separator_guess(self):
        refs,defs=fixture([member("get_ColorId","System.Int32",parent="NetworkedPlayerInfo+PlayerOutfit")])
        defs["typeDefinitions"].append(dict(name="NetworkedPlayerInfo+PlayerOutfit",baseType="System.Object",image="Assembly-CSharp.dll",fields=[field("ColorId","System.Int32")],methods=[]))
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory))
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertIn('new("NetworkedPlayerInfo+PlayerOutfit", "Assembly-CSharp.dll", "", "NetworkedPlayerInfo+PlayerOutfit")',text)
        self.assertNotIn('"NetworkedPlayerInfo.PlayerOutfit"',text)
    def test_arrays_use_source_compatible_live_wrapper_classes(self):
        refs,defs=fixture([member("Bytes","System.Byte[]"),member("Players","PlayerControl[]"),member("Strings","System.String[]")])
        defs["typeDefinitions"][0]["methods"] += [method("Bytes","System.Byte[]"),method("Players","PlayerControl[]"),method("Strings","System.String[]")]
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory))
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertIn("Il2CppStructArray<byte>",text)
        self.assertIn("Il2CppReferenceArray<PlayerControl>",text)
        self.assertIn("Il2CppStringArray?",text)
        self.assertIn("(result.Detach(), true)",text)
    def test_dictionary_field_returns_live_native_facade(self):
        row=member("get_Dictionary","System.Collections.Generic.Dictionary`2<System.Int32,PlayerControl>")
        refs,defs=fixture([row]);defs["typeDefinitions"][0]["fields"].append(field("Dictionary","System.Collections.Generic.Dictionary`2<System.Int32,PlayerControl>"))
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory))
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertEqual(report["generatedSourceMemberReferences"],1)
        self.assertIn("global::Il2CppSystem.Collections.Generic.Dictionary<int, PlayerControl>",text)
        self.assertIn("(result.Detach(), true)",text)
        self.assertNotIn("new System.Collections.Generic.Dictionary",text)
    def test_input_pins_reject_changed_reports_before_generation(self):
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"refs.json";path.write_text("{}")
            manifest={"formatVersion":1,"upstreamCommit":"ce23f0d050f617a59507e5bb0fbfff751d4b5134","inputs":{"references":{"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}}}
            verify_pins(manifest,{"references":path,"sourceProfile":None})
            path.write_text("{ }")
            with self.assertRaisesRegex(ValueError,"pin mismatch"):verify_pins(manifest,{"references":path,"sourceProfile":None})
    def test_real_singleton_base_is_preserved_without_host_instance_storage(self):
        refs,defs=fixture([member("get_PlayerId","System.Byte")]);refs["typeReferences"]=[dict(assembly="Assembly-CSharp",name="HudManager")]
        defs["typeDefinitions"] += [dict(name="HudManager",baseType="DestroyableSingleton`1<HudManager>",fields=[],methods=[]),dict(name="UnityEngine.MonoBehaviour",baseType="System.Object",fields=[],methods=[])]
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory))
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertIn("partial class HudManager : DestroyableSingleton<HudManager>",text)
        self.assertIn("Instance=>NativeSingletons.Instance<T>()",text)
        self.assertIn("InstanceExists=>NativeSingletons.Exists<T>()",text)
        self.assertNotIn("static T instance",text)
    def test_exact_reference_constructor_uses_live_constructorinfo(self):
        refs,defs=fixture([member(".ctor","System.Void",["System.Single"],parent="Wait")])
        defs["typeDefinitions"].append(dict(name="Wait",baseType="System.Object",fields=[],methods=[method(".ctor","System.Void",["System.Single"])]))
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory))
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertEqual(report["generatedSourceMemberReferences"],1)
        self.assertIn("public Wait(float @p0) : base(CreateNative",text)
        self.assertIn("ElementCodecs.Get<float>().Box(@p0)",text)
        self.assertIn("NativeConstructors.Create(",text)
        self.assertNotIn("LiveReflection.Construct(",text)
    def test_source_parameter_names_and_optional_enum_defaults_are_preserved(self):
        refs,defs=fixture([member("SetRole","System.Void",["RoleNames"])])
        profile={"typeDefinitions":[dict(name="PlayerControl",methods=[dict(method("SetRole","System.Void",["RoleNames"]),parameterNames=["event"],parameterDefaults=[{"value":0}])])]}
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory),source_profile=profile)
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertIn("SetRole(RoleNames @event = (RoleNames)0)",text)
        self.assertIn('FacadeRuntime.Value(&@event, "RoleNames")',text)
    def test_source_out_parameter_name_is_assigned_only_after_caught_call(self):
        refs,defs=fixture([member("TryGet","System.Boolean",["System.Int32&"])])
        native=dict(method("TryGet","System.Boolean",["System.Int32&"]),parameterModes=["out"])
        defs["typeDefinitions"][0]["methods"].append(native)
        profile={"typeDefinitions":[dict(name="PlayerControl",methods=[dict(native,parameterNames=["result"],parameterDefaults=[None])])]}
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory),source_profile=profile)
            text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertIn("out int @result",text)
        self.assertIn("int local0 = default;",text)
        self.assertLess(text.index("LiveCollections.InvokeWithRefs"),text.index("@result = local0;"))
    def test_deterministic_output_and_separate_probe_accounting(self):
        rows=[member("get_PlayerId","System.Byte")]
        first,text1=self.run_fixture(rows)
        second,text2=self.run_fixture(copy.deepcopy(rows))
        self.assertEqual(first,second)
        self.assertEqual(text1,text2)
        self.assertEqual(first["sourceGameMemberReferences"],1)
        self.assertEqual(first["explicitProbeReferences"],1)
        self.assertFalse(first["actualGameBindingValidationPerformed"])
        self.assertFalse(first["fullEHRPort"])
    def test_unity_generic_adapters_use_exact_reflection_and_native_arrays(self):
        rows=[dict(member("GetComponent","!!0",parent="UnityEngine.Component"),assembly="UnityEngine.CoreModule",genericArity=1),dict(member("GetComponentsInChildren","!!0[]",["System.Boolean"],parent="UnityEngine.Component",token=2),assembly="UnityEngine.CoreModule",genericArity=1)]
        refs,defs=fixture(rows)
        defs["typeDefinitions"].append(dict(name="UnityEngine.Component",image="UnityEngine.CoreModule.dll",baseType="System.Object",fields=[],methods=[method("GetComponent","!!0"),method("GetComponentsInChildren","!!0[]",["System.Boolean"])]))
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory));text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertEqual(len(report["genericMethodAdapters"]),2)
        self.assertIn("GetComponent<T>() where T:RuntimeObject",text)
        self.assertIn("NativeGenericMethods.Lookup(",text)
        self.assertIn("Il2CppReferenceArray<T>(result.Detach(),true)",text)
        self.assertNotIn("ToArray()",text)
        self.assertFalse(any("!!" in b["resultType"] for b in report["bindings"]))
    def test_source_component_generic_routes_preserve_native_fallback_and_profile_boundary(self):
        rows=[dict(member(name,'!!0',parent='UnityEngine.'+owner,token=i+1),assembly='UnityEngine.CoreModule',genericArity=1) for i,(owner,name) in enumerate([('GameObject','AddComponent'),('GameObject','GetComponent'),('Component','GetComponent')])]
        refs,defs=fixture(rows)
        for owner in ['GameObject','Component']:
            defs['typeDefinitions'].append(dict(name='UnityEngine.'+owner,image='UnityEngine.CoreModule.dll',baseType='System.Object',fields=[],methods=[method('GetComponent','!!0'),method('AddComponent','!!0')]))
        for enabled in [False,True]:
            with tempfile.TemporaryDirectory() as directory:
                generate(refs,defs,Path(directory),source_components=enabled);text=(Path(directory)/'GeneratedFacades.g.cs').read_text()
            self.assertEqual(text.count('if(SourceComponentRuntime.IsSource(typeof(T)))'),3 if enabled else 0)
            self.assertEqual(text.count('ulong method=NativeGenericMethods.Lookup('),3)
            if enabled:
                self.assertIn('SourceComponentFacades.Get<T>(this,true)',text)
                self.assertIn('SourceComponentFacades.Get<T>(this,false)',text)
    def test_nonwhitelisted_generic_method_is_not_fabricated(self):
        refs,defs=fixture([dict(member("Other","!!0"),genericArity=1)])
        with tempfile.TemporaryDirectory() as directory:report=generate(refs,defs,Path(directory))
        self.assertIn("generic method inflation unsupported",report["unsupportedByReason"])
    def test_boxed_value_out_uses_actual_reflection_object_array_without_layout(self):
        refs,defs=fixture([member("TryColor","System.Boolean",["System.String","Color&"])])
        defs["typeDefinitions"][0]["methods"].append(dict(method("TryColor","System.Boolean",["System.String","Color&"]),parameterModes=["value","out"]))
        defs["typeDefinitions"].append(dict(name="Color",baseType="System.ValueType",fields=[field("r","System.Single")],methods=[]))
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory));text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertEqual(report["generatedSourceMemberReferences"],1)
        self.assertIn("NativeReflectedCall.Invoke(",text)
        self.assertIn("ElementCodecs.Get<Color>().Read(invocation.Argument(1))",text)
        self.assertNotIn("sizeof(Color)",text)
    def test_extension_attribute_emits_forwarder_without_changing_native_class(self):
        refs,defs=fixture([member("SetRole","System.Void",["RoleNames"],static=True)])
        defs["typeDefinitions"][0]["methods"][1]["isStatic"]=True
        profile={"typeDefinitions":[dict(name="PlayerControl",methods=[dict(method("SetRole","System.Void",["RoleNames"],True),isExtension=True)])]}
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory),source_profile=profile);text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertIn("partial class PlayerControl :",text)
        self.assertIn("static unsafe class PlayerControl_SourceExtensions",text)
        self.assertIn("SetRole(this RoleNames @p0) => PlayerControl.@SetRole(@p0)",text)
    def test_absent_color_helper_uses_explicit_engine_adapter_not_fake_metadata(self):
        row=dict(member("TryParseHtmlString","System.Boolean",["System.String","UnityEngine.Color&"],True,parent="UnityEngine.ColorUtility"),assembly="UnityEngine.CoreModule")
        refs,defs=fixture([row])
        defs["typeDefinitions"] += [dict(name="UnityEngine.ColorUtility",image="UnityEngine.CoreModule.dll",baseType="System.Object",fields=[],methods=[]),dict(name="UnityEngine.Color",image="UnityEngine.CoreModule.dll",baseType="System.ValueType",fields=[],methods=[])]
        helper=dict(method("TryParseHtmlString","System.Boolean",["System.String","UnityEngine.Color&"],True),parameterModes=["value","out"])
        profile={"typeDefinitions":[dict(name="UnityEngine.ColorUtility",methods=[helper])]}
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory),source_profile=profile);text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertEqual(len(report["engineAdapters"]),1)
        self.assertFalse(any(b["member"]=="TryParseHtmlString" for b in report["bindings"]))
        self.assertIn("NativeEngineColors.Parse(",text)
        self.assertIn("/255f",text)
    def test_params_object_overload_creates_real_native_array(self):
        refs,defs=fixture([member("Format","System.String",["System.Object[]"])])
        defs["typeDefinitions"][0]["methods"].append(method("Format","System.String",["System.Object[]"]))
        profile={"typeDefinitions":[dict(name="PlayerControl",methods=[dict(method("Format","System.String",["System.Object[]"]),parameterIsParams=[True])])]}
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory),source_profile=profile);text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertIn("params object?[]? @p0",text)
        self.assertIn("using var nativeParts=NativeParams.Create(@p0)",text)
    def test_hashset_field_uses_live_set_wrapper_and_owning_constructor(self):
        refs,defs=fixture([member("get_Tags","System.Collections.Generic.HashSet`1<System.String>")])
        defs["typeDefinitions"][0]["fields"].append(field("Tags","[System.Core]System.Collections.Generic.HashSet`1<System.String>"))
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory));text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertIn("global::Il2CppSystem.Collections.Generic.HashSet<string>",text)
        self.assertIn("(result.Detach(), true)",text)
        self.assertNotIn("System.Collections.Generic.HashSet<string>()",text)
    def test_pinned_source_constants_are_not_invented_native_fields(self):
        refs,defs=fixture([member("get_PlayerId","System.Byte")])
        profile={"typeDefinitions":[dict(name="PlayerControl",fields=[field("PI","System.Single",True,True,3.1415927),field("Infinity","System.Single",True,True,"Infinity")])]}
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory),source_profile=profile);text=(Path(directory)/"GeneratedFacades.g.cs").read_text()
        self.assertIn("public const float @PI = 3.1415927f",text)
        self.assertIn("public const float @Infinity = float.PositiveInfinity",text)
        self.assertFalse(any(b['member']=='PI' for b in report['bindings']))
    def test_source_aliases_map_flat_rd_names_to_real_types(self):
        refs,defs=fixture([member('x','System.Single',parent='UnityEngine.Vector2')]);refs['members'][0]['kind']='field';refs['members'][0]['assembly']='UnityEngine.CoreModule'
        defs['typeDefinitions'].append(dict(name='UnityEngine.Vector2',image='UnityEngine.CoreModule.dll',baseType='System.ValueType',fields=[field('x','System.Single')],methods=[]))
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory),source_surface=True);aliases=(Path(directory)/'SourceAliases.g.cs').read_text()
        self.assertIn('global using UnityEngine_Vector2 = global::UnityEngine.Vector2;',aliases)
    def test_async_handle_field_keeps_real_boxed_native_value(self):
        handle='UnityEngine.ResourceManagement.AsyncOperations.AsyncOperationHandle`1<PlayerControl>'
        refs,defs=fixture([member('get_Handle',handle),member('set_Handle','System.Void',[handle],token=2)])
        defs['typeDefinitions'][0]['fields'].append(field('Handle',handle))
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory));text=(Path(directory)/'GeneratedFacades.g.cs').read_text()
        self.assertIn('ClosedBoxedReferenceCodec<global::UnityEngine.ResourceManagement.AsyncOperations.AsyncOperationHandle<PlayerControl>>',text)
        self.assertIn('NativeValues.Argument(boxed0)',text)
        self.assertIn('(result.Detach(), true)',text)
        self.assertNotIn('sizeof(AsyncOperationHandle',text)
    def test_typed_native_action_field_uses_exact_closed_class_and_owning_ctor(self):
        action='System.Action`1<PlayerControl>'
        refs,defs=fixture([member('get_OnValueChanged',action),member('set_OnValueChanged','System.Void',[action],token=2)])
        defs['typeDefinitions'][0]['fields'].append(field('OnValueChanged',action))
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory));text=(Path(directory)/'GeneratedFacades.g.cs').read_text()
        self.assertEqual(report['generatedSourceMemberReferences'],2)
        self.assertIn('TypedActionRuntime.NativeClass<PlayerControl>()',text)
        self.assertIn('new global::Il2CppSystem.Action<PlayerControl>(token)',text)
        self.assertIn('new global::Il2CppSystem.Action<PlayerControl>(result.Detach())',text)
        self.assertNotIn('Action<PlayerControl>(token,true)',text)
    def test_typed_action_unsupported_value_argument_is_not_emitted(self):
        action='System.Action`1<System.Boolean>'
        refs,defs=fixture([member('get_Callback',action)])
        defs['typeDefinitions'][0]['fields'].append(field('Callback',action))
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory))
        self.assertEqual(report['generatedSourceMemberReferences'],0)
        self.assertIn('typed native Action argument ABI unsupported',report['unsupportedByReason'])
    def test_queue_field_uses_live_boxed_generic_collection(self):
        queue='System.Collections.Generic.Queue`1<PlayerControl>'
        refs,defs=fixture([member('get_Pending',queue)])
        defs['typeDefinitions'][0]['fields'].append(field('Pending',queue))
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory));text=(Path(directory)/'GeneratedFacades.g.cs').read_text()
        self.assertIn('global::Il2CppSystem.Collections.Generic.Queue<PlayerControl>',text)
        self.assertIn('(result.Detach(), true)',text)
    def test_existing_func_bool_has_codec_without_native_callback_constructor(self):
        func='System.Func`1<System.Boolean>'
        refs,defs=fixture([member('get_Check',func)])
        defs['typeDefinitions'][0]['fields'].append(field('Check',func))
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory));text=(Path(directory)/'GeneratedFacades.g.cs').read_text()
        self.assertIn('NativeSystemTypes.FuncClass<bool>()',text)
        self.assertIn('new global::Il2CppSystem.Func<bool>(token)',text)
        self.assertNotIn('System.Func<bool>(token,true)',text)
    def test_builder_parameter_uses_native_wrapper_not_clr_system_shadow(self):
        refs,defs=fixture([member('Describe','System.Void',['System.Text.StringBuilder'])])
        defs['typeDefinitions'][0]['methods'].append(method('Describe','System.Void',['System.Text.StringBuilder']))
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory),True);text=(Path(directory)/'SourceSurface.g.cs').read_text()
        self.assertIn('global::Il2CppSystem.Text.StringBuilder?',text)
        self.assertNotIn('namespace System.Text',text)
    def test_out_reference_uses_real_reflection_array_and_initial_null(self):
        refs,defs=fixture([member('TryFind','System.Boolean',['PlayerControl&'])])
        defs['typeDefinitions'][0]['methods'].append(dict(method('TryFind','System.Boolean',['PlayerControl&']),parameterModes=['out']))
        with tempfile.TemporaryDirectory() as directory:
            generate(refs,defs,Path(directory));text=(Path(directory)/'GeneratedFacades.g.cs').read_text()
        self.assertIn('out PlayerControl?',text)
        self.assertIn('reflectedArg0=new RuntimeObject(0)',text)
        self.assertIn('NativeReflectedCall.Invoke(',text)
        self.assertIn('ElementCodecs.Get<PlayerControl>().Read(invocation.Argument(0))',text)
        self.assertNotIn('sizeof(PlayerControl)',text)
        self.assertNotIn('LiveReflection.Construct(ElementCodecs.Get<PlayerControl>',text)
    def test_ref_reference_still_rejects_unproven_exception_side_effects(self):
        refs,defs=fixture([member('Change','System.Void',['PlayerControl&'])])
        defs['typeDefinitions'][0]['methods'].append(dict(method('Change','System.Void',['PlayerControl&']),parameterModes=['ref']))
        with tempfile.TemporaryDirectory() as directory:report=generate(refs,defs,Path(directory))
        self.assertIn('ref managed reference exception-side-effect transport unsupported',report['unsupportedByReason'])
    def test_exact_game_generic_boolean_result_is_not_replaced_by_generic_type(self):
        row=dict(member('Connecting','System.Boolean',['!!0'],parent='MatchMaker'),genericArity=1)
        refs,defs=fixture([row]);defs['typeDefinitions'].append(dict(name='MatchMaker',baseType='System.Object',fields=[],methods=[method('Connecting','System.Boolean',['!!0'])]))
        with tempfile.TemporaryDirectory() as directory:
            report=generate(refs,defs,Path(directory));text=(Path(directory)/'GeneratedFacades.g.cs').read_text()
        self.assertIn('bool @Connecting<T>(T?',text)
        self.assertIn('"Connecting","System.Boolean",["!!0"]',text)
        self.assertIn('return FacadeRuntime.ReadValue<bool>(result)',text)
        self.assertEqual(len(report['genericMethodAdapters']),1)

if __name__=="__main__":unittest.main()
