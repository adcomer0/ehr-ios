import importlib.util,json,os,subprocess,sys,tempfile,unittest,xml.etree.ElementTree as ET
from pathlib import Path
stage=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('sizing',stage/'tools/prepare_control_sizing.py');tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
inputProject=Path(os.environ['EHR_CONTROL_SIZING_INPUT_PROJECT']).resolve() if os.environ.get('EHR_CONTROL_SIZING_INPUT_PROJECT') else None
def selected(name):
 root=ET.parse(inputProject).getroot()
 items=[Path(item.get('Include')) for item in root.iter('Compile') if Path(item.get('Include','')).name==name]
 if len(items)!=1:raise ValueError('exactly one selected '+name+' required')
 return (items[0] if items[0].is_absolute() else inputProject.parent/items[0]).resolve()
@unittest.skipUnless(inputProject is not None,'Set EHR_CONTROL_SIZING_INPUT_PROJECT to the current generated full-source project')
class Tests(unittest.TestCase):
 def setUp(self):
  self.guiPath=selected('ClientControlGUI.cs');self.touchPath=selected('NativeTouchGUI.cs')
  self.gui=self.guiPath.read_text();self.touch=self.touchPath.read_text();self.new,self.newTouch,self.manifest=tool.adapt(self.gui,self.touch)
 def test_actions_and_guards(self):self.assertTrue(self.manifest['actionBodyAndGuardsUnchangedExceptSliderGeometry']);self.assertEqual(self.manifest['actionBodyOriginalSha256'],self.manifest['actionBodyNormalizedSha256'])
 def test_visibility_phase_guards(self):
  for text in ['ReconcileIOSNoClip();','if (!HudManager.InstanceExists) { GUI.Hide(); return; }','if (!GUI.BeginFrame(Screen.width, Screen.height)) return;','bool fadeOut = !IsOpen && (GameStates.IsInGame || GameSettingMenu.Instance);','if (fadeOut) GUI.color = new Color(1f, 1f, 1f, 0.10f);']:
   self.assertIn(text,self.new)
 def test_first_frame_layout_order(self):
  onGUI=self.new[self.new.index('    private void OnGUI()'):self.new.index('    // Draws the small toggle')]
  self.assertLess(onGUI.index('GUI.BeginFrame'),onGUI.index('RefreshTouchLayout();'));self.assertLess(onGUI.index('RefreshTouchLayout();'),onGUI.index('DrawToggle();'))
 def test_style_floor_local_only(self):self.assertIn('Math.Ceiling(14f * GUI.PixelsPerPoint)',self.new);self.assertIn('Mathf.Max(MinimumFontSize, FontSize - 5)',self.new);self.assertFalse(self.manifest['nativeStyleMinimumChanged']);self.assertNotIn('MinimumFontSize',self.newTouch)
 def test_no_native_table_change(self):
  old=self.touch[self.touch.index('[StructLayout(LayoutKind.Sequential)] public unsafe struct TouchUIV1'):self.touch.index('public static unsafe class TouchGUI')]
  new=self.newTouch[self.newTouch.index('[StructLayout(LayoutKind.Sequential)] public unsafe struct TouchUIV1'):self.newTouch.index('public static unsafe class TouchGUI')]
  self.assertEqual(old,new);self.assertFalse(self.manifest['nativeABIChanged'])
 def test_reject_untransformed_or_unknown_current(self):
  with self.assertRaises(ValueError):tool.adapt(self.gui.replace('using GUI = EHR.Generated.TouchGUI;',''),self.touch)
  with self.assertRaises(ValueError):tool.adapt(self.gui,self.touch.replace('PixelsPerPoint=frame.py;viewport=frame;',''))
 def test_slider_finger_target_only(self):
  self.assertIn('Mathf.Max(44f * GUI.PixelsPerPoint, ButtonHeight * 0.52f)',self.new);self.assertIn('sy += SliderHeight + Padding * 0.7f;',self.new)
 def test_final_audio_project_join_keeps_other_inputs(self):
  def unrelated(root,base):
   result=[]
   for element in root.iter():
    if element.tag=='Compile' and Path(element.get('Include','')).name in ['ClientControlGUI.cs','NativeTouchGUI.cs']:continue
    if element.tag in ('Compile','EmbeddedResource') and element.get('Include'):
     path=Path(element.get('Include'));element.set('Include',str((path if path.is_absolute() else base/path).resolve()))
    result.append((element.tag,tuple(element.attrib.items()),(element.text or '').strip()))
   return result
  with tempfile.TemporaryDirectory() as temp:
   output=Path(temp)/'Overlay';self.runTool(inputProject,output)
   self.assertEqual(unrelated(ET.parse(inputProject).getroot(),inputProject.parent),unrelated(ET.parse(output/'EHR.csproj').getroot(),output))
 def runTool(self,project,output):
  subprocess.run([sys.executable,str(stage/'tools/prepare_control_sizing.py'),'--gui-source',str(self.guiPath),'--touch-source',str(self.touchPath),'--project',str(project),'--output',str(output)],check=True,capture_output=True,text=True)
 def test_relative_unrelated_sources_and_resources_rebase(self):
  with tempfile.TemporaryDirectory() as temp:
   base=Path(temp).resolve();project=base/'Input.csproj';output=base/'Overlay'
   (base/'Keep.cs').write_text('// own unrelated input\n');(base/'Keep.txt').write_text('own resource')
   root=ET.Element('Project');group=ET.SubElement(root,'ItemGroup')
   for path in (self.guiPath,self.touchPath,Path('Keep.cs')):ET.SubElement(group,'Compile',Include=str(path))
   ET.SubElement(group,'EmbeddedResource',Include='Keep.txt',LogicalName='Own.Keep');ET.ElementTree(root).write(project)
   self.runTool(project,output);result=ET.parse(output/'EHR.csproj').getroot()
   self.assertIn(str(base/'Keep.cs'),[e.get('Include') for e in result.iter('Compile')])
   resource=next(result.iter('EmbeddedResource'));self.assertEqual(resource.get('Include'),str(base/'Keep.txt'));self.assertEqual(resource.get('LogicalName'),'Own.Keep')
if __name__=='__main__':unittest.main()
