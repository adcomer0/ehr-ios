import hashlib, importlib.util, tempfile, unittest, xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('prepare_touch_identity',ROOT/'tools/prepare_touch_identity.py');tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
class IdentityOverlayTests(unittest.TestCase):
 def test_reject_changed_source_without_output(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp);(p/'IOSTouchShortcuts.cs').write_text('changed');(p/'input.csproj').write_text('<Project><ItemGroup><Compile Include="IOSTouchShortcuts.cs"/></ItemGroup></Project>')
   with self.assertRaisesRegex(ValueError,'helper changed'):tool.prepare(p/'input.csproj',p/'out')
   self.assertFalse((p/'out').exists())
 def test_rebase_unrelated_paths_and_only_one_replacement(self):
  with tempfile.TemporaryDirectory() as temp:
   p=Path(temp).resolve();source=p/'IOSTouchShortcuts.cs';source.write_text('own fixture');(p/'input.csproj').write_text('<Project><ItemGroup><Compile Include="IOSTouchShortcuts.cs"/><Compile Include="other.cs"/><EmbeddedResource Include="data.txt" LogicalName="Original.Name"/><Reference Include="Keep"><HintPath>lib/keep.dll</HintPath></Reference></ItemGroup></Project>')
   expected=tool.EXPECTED;tool.EXPECTED=hashlib.sha256(source.read_bytes()).hexdigest()
   try:project=tool.prepare(p/'input.csproj',p/'out')
   finally:tool.EXPECTED=expected
   root=ET.parse(project).getroot();items=list(root.iter('Compile'));self.assertEqual(len(items),3);self.assertEqual(items[1].get('Include'),str(p/'other.cs'))
   resource=next(root.iter('EmbeddedResource'));self.assertEqual(resource.get('Include'),str(p/'data.txt'));self.assertEqual(resource.get('LogicalName'),'Original.Name');self.assertEqual(next(root.iter('HintPath')).text,str(p/'lib/keep.dll'))
 def test_all_entry_routes_are_contained(self):
  source=(ROOT/'managed/IOSTouchShortcuts.cs').read_text()
  for name in ['RequestChat','TakeChat','SetNumberMultiplier','ExecutionTargets','ArmExecution','ConfirmExecution','Reconcile']:
   self.assertRegex(source,r'internal static [^\n]+ '+name+r'\([^\n]*\)=>Gate.Run\(')
  self.assertIn('CanShowChatControls=>Gate.Run',source);self.assertIn('CanShowSettingsSteps=>Gate.Run',source);self.assertIn('NumberMultiplier=>Gate.Run(NumberMultiplierCore,1)',source)
  self.assertIn('catch(Exception error){Gate.Fail(error);targetName="";armed=false;return false;}',source)
 def test_probe_does_not_touch_production_state(self):
  source=(ROOT/'managed/IOSTouchShortcuts.cs').read_text();probe=source.split('internal static int IdentitySelfTest',1)[1].split('private static void RecordProbeFailure',1)[0]
  for forbidden in ['state.','Gate.','Production.','Main.','AmongUsClient.','ClientControlGUI.','HudManager.','MeetingHud.']:
   self.assertNotIn(forbidden,probe)
  self.assertEqual(probe.count('Id(game)'),2);self.assertEqual(probe.count('Id(retained)'),1)
  self.assertIn('finally',probe);self.assertIn('retained?.Dispose()',probe);self.assertIn('game?.Dispose()',probe);self.assertIn('"Destroy",true,false,"System.Void",["UnityEngine.Object"]',probe)
  self.assertIn('if(proof==null||count!=8)return 4;',probe);self.assertIn('NativeSourceHost.IsMainThread',probe)
 def test_effect_sequence_and_guard_sources_are_retained(self):
  source=(ROOT/'managed/IOSTouchShortcuts.cs').read_text();effect=source.split('private static void ConfirmExecutionCore()',1)[1].split('internal static void Reconcile()',1)[0]
  parts=['CurrentMeeting(out var meeting)','state.TrySelection(Id(meeting),true','FindTarget(meeting,selected,out var player)','state.Confirm(Id(meeting),player.PlayerId,true)','Main.PlayerStates[player.PlayerId].deathReason = PlayerState.DeathReason.Execution;','player.RpcExileV2();','Main.PlayerStates[player.PlayerId].SetDead();','Utils.AfterPlayerDeathTasks(player, true);','Utils.SendMessage(','Logger.Info(','meeting.CheckForEndVoting();']
  offset=-1
  for part in parts:new=effect.index(part);self.assertGreater(new,offset);offset=new
  self.assertIn('client.AmHost&&meeting&&meeting.playerStates!=null',source);self.assertIn('player.Data!=null&&player.IsAlive()',source)
 def test_gate_latches_before_cleanup(self):
  source=(ROOT/'managed/IOSTouchControlFailureGate.cs').read_text();self.assertLess(source.index('Failed=true;'),source.index('try{clear();}'));self.assertIn('if(Failed)return fallback;',source)
if __name__=='__main__':unittest.main()
