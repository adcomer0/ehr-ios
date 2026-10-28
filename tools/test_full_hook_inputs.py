import copy
import unittest
from full_hook_inputs import LEGACY,PIN,merge_full_inputs

def fixture():
    base=dict(metadata_version=31,framework_uuid="own-fixture",preferred_image_base="0x0",input_pins={"framework":{"sha256":"a"*64},"metadata":{"sha256":"b"*64}},methods=[])
    targets=dict(schema="ehr.harmony-native-target-map.v1",upstream_commit=PIN,selectors=[],**{k:copy.deepcopy(base[k]) for k in base if k!="methods"})
    catalog=dict(schema="ehr.native-source-patch-candidates.v1",upstreamCommit=PIN,candidates=[])
    contracts=dict(schema="ehr.native-hook-contracts.v1",methods={})
    for i,signature in enumerate(LEGACY.values(),1):
        owner,name,returns,parameters,static=signature;identifier=f"{i:020x}"
        candidate=dict(declaring_type=owner,owning_image="Own.dll",name=name,return_type=returns,parameter_types=list(parameters),static=static,shared_entry=False,generic=False,abstract=False,native_rva=hex(i*16),metadata_token=hex(0x6000000+i))
        targets["selectors"].append(dict(selector_id=identifier,status="exact_metadata_native_candidate",candidate=candidate))
        catalog["candidates"].append(dict(selectorId=identifier,targetId={1:3,2:1,3:2}[i],nativeImage="Own.dll",nativeNamespace="",nativeType=owner,nativeMethod=name,nativeReturn=returns,nativeParameters=list(parameters),isStatic=static,nativeRva=hex(i*16),coroutineBody=False))
        contracts["methods"]["ehr.full."+identifier]=dict(declaring_type=owner,name=name,return_=returns,parameters=list(parameters),static=static,symbol="_ehr_full_hook_"+identifier)
        contracts["methods"]["ehr.full."+identifier]["return"]=contracts["methods"]["ehr.full."+identifier].pop("return_")
    return base,targets,catalog,contracts

class FullHookInputTests(unittest.TestCase):
    def test_exact_join_and_legacy_aliases_preserve_inputs(self):
        inputs=fixture();before=copy.deepcopy(inputs)
        merged,contracts,selected,aliases=merge_full_inputs(*inputs)
        self.assertEqual(inputs,before);self.assertEqual(len(merged["methods"]),3)
        self.assertEqual(set(aliases),set(LEGACY));self.assertEqual(set(selected),set(contracts["methods"]))
        again=merge_full_inputs(merged,*inputs[1:]);self.assertEqual(again[0],merged)
    def test_mismatched_pins_and_contracts_fail(self):
        inputs=fixture();inputs[1]["framework_uuid"]="other"
        with self.assertRaisesRegex(ValueError,"input mismatch"):merge_full_inputs(*inputs)
        inputs=fixture();next(iter(inputs[3]["methods"].values()))["symbol"]="_unrelated"
        with self.assertRaisesRegex(ValueError,"contract signature"):merge_full_inputs(*inputs)
    def test_catalog_and_ambiguous_native_entries_fail(self):
        inputs=fixture();inputs[2]["candidates"][0]["nativeReturn"]="System.Boolean"
        with self.assertRaisesRegex(ValueError,"catalog binding"):merge_full_inputs(*inputs)
        inputs=fixture();inputs[0]["methods"]=[dict(declaring_type="PlayerControl",name="MurderPlayer",return_type="System.Void",parameters=[{"type":"PlayerControl"},{"type":"MurderResultFlags"}],static=False,native_rva="0x9990",token="0x6000001")]
        with self.assertRaisesRegex(ValueError,"contradicts"):merge_full_inputs(*inputs)
    def test_no_partial_or_shared_entry_set(self):
        inputs=fixture();inputs[1]["selectors"][0]["candidate"]["shared_entry"]=True
        with self.assertRaisesRegex(ValueError,"combined/generic"):merge_full_inputs(*inputs)
        inputs=fixture();inputs[3]["methods"].pop(next(iter(inputs[3]["methods"])))
        with self.assertRaisesRegex(ValueError,"contract set differs"):merge_full_inputs(*inputs)

if __name__=="__main__":unittest.main()
