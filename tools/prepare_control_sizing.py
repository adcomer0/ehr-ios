#!/usr/bin/env python3
"""Narrow geometry-only overlay AFTER current UIKit/mobile/Scene adaptations."""
import argparse,hashlib,json,xml.etree.ElementTree as ET
from pathlib import Path
def sha(data):return hashlib.sha256(data.encode() if isinstance(data,str) else data).hexdigest()
def adapt(gui,touch):
    original=gui;originalTouch=touch
    def replace(old,new,count=1):
        nonlocal gui
        if gui.count(old)!=count:raise ValueError('GUI source anchor changed: '+old[:100])
        gui=gui.replace(old,new)
    if 'using GUI = EHR.Generated.TouchGUI;' not in gui:raise ValueError('current transformed UIKit source required')
    replace('// Scale helpers - everything is relative to a 1080px-wide reference screen\n    // On PC the UI is scaled down to 50% but on Android we keep it slightly larger (60%) for better readability','// Client-only logical point metrics, refreshed after the native UIKit viewport is measured.')
    start=gui.index('    private static float PlatformScale')
    end=gui.index('    /// <summary>',start)
    gui=gui[:start]+'''    private static float PlatformScale => OperatingSystem.IsAndroid() ? 0.6f : 0.5f;
    // Client controls use logical UIKit points, independent of render resolution.
    // Keep the measured horizontal/vertical densities separate for safe bounds.
    private static float TouchDensity => Mathf.Max(GUI.PixelsPerPointX, GUI.PixelsPerPoint);
    private static float Scale => TouchDensity * 0.72f;
    private static int MinimumFontSize => Math.Max(1, (int)Math.Ceiling(14f * GUI.PixelsPerPoint));
    private static int FontSize => Mathf.Max(MinimumFontSize, Mathf.RoundToInt(21f * Scale));
    private static float ButtonHeight => Mathf.Max(44f * GUI.PixelsPerPoint, 66f * Scale);
    private static float ButtonWidth => (OperatingSystem.IsAndroid() ? 360f : 340f) * Scale;
    private static float ToggleSize => Mathf.Max(44f * TouchDensity, 64f * Scale);
    private static float SliderHeight => Mathf.Max(44f * GUI.PixelsPerPoint, ButtonHeight * 0.52f);
    private static float Padding => 10f * Scale;
    private static int ChipFontSize => Mathf.Max(MinimumFontSize, FontSize - 4);
    private static float ScrollbarColumnWidth => (OperatingSystem.IsAndroid() ? 42f : 22f) * Scale;
    private static float WindowWidth => Mathf.Min(ButtonWidth + Padding * 4f + ScrollbarColumnWidth, GUI.SafeWidth);
    private static float WindowHeight => Mathf.Min(Screen.height * (OperatingSystem.IsAndroid() ? 0.82f : 0.65f), GUI.SafeHeight);

'''+gui[end:]
    replace('    private float _lastScale = -1f;','''    private float _lastScale = -1f;
    private float _lastDensityX = -1f, _lastDensityY = -1f;
    private float _lastSafeWidth = -1f, _lastSafeHeight = -1f, _lastSafeLeft = -1f, _lastSafeTop = -1f;
    private int _lastScreenWidth = -1, _lastScreenHeight = -1;''')
    replace('Mathf.RoundToInt(48f * Scale)','Mathf.RoundToInt(ToggleSize)')
    replace('Mathf.RoundToInt(ButtonWidth + Padding * 4f + ScrollbarColumnWidth)','Mathf.RoundToInt(WindowWidth)')
    replace('Mathf.RoundToInt(Screen.height * (OperatingSystem.IsAndroid() ? 0.82f : 0.65f))','Mathf.RoundToInt(WindowHeight)')
    replace('Mathf.Max(10, FontSize - 5)','Mathf.Max(MinimumFontSize, FontSize - 5)')
    replace('float w = ButtonWidth + Padding * 4f + ScrollbarColumnWidth;','float w = WindowWidth;')
    replace('float h = Screen.height * (OperatingSystem.IsAndroid() ? 0.82f : 0.65f);','float h = WindowHeight;')
    replace('''        _windowRect = new Rect(20f * Scale, (Screen.height - h) * 0.5f, w, h);''','''        float x = 20f * Scale, y = (Screen.height - h) * 0.5f;
        GUI.ClampToSafeArea(ref x, ref y, w, h);
        _windowRect = new Rect(x, y, w, h);''')
    marker='    // OnGUI is called by Unity every frame (and sometimes multiple times per frame)'
    replace(marker,'''    // Awake can run before a viewport exists; the first successful BeginFrame
    // measures density. Reflow on later viewport/density/safe-area changes.
    private void RefreshTouchLayout()
    {
        float px = GUI.PixelsPerPointX, py = GUI.PixelsPerPoint;
        if (_windowInitialized && Math.Abs(_lastScale - Scale) <= 0.01f
            && Math.Abs(_lastDensityX - px) <= 0.01f && Math.Abs(_lastDensityY - py) <= 0.01f
            && Math.Abs(_lastSafeWidth - GUI.SafeWidth) <= 0.01f && Math.Abs(_lastSafeHeight - GUI.SafeHeight) <= 0.01f
            && Math.Abs(_lastSafeLeft - GUI.SafeLeft) <= 0.01f && Math.Abs(_lastSafeTop - GUI.SafeTop) <= 0.01f
            && _lastScreenWidth == Screen.width && _lastScreenHeight == Screen.height) return;
        bool preserve = _windowInitialized && _lastDensityX > 0f && _lastDensityY > 0f;
        float x = preserve ? _windowRect.x / _lastDensityX * px : 0f;
        float y = preserve ? _windowRect.y / _lastDensityY * py : 0f;
        InitWindowRect();
        if (preserve)
        {
            GUI.ClampToSafeArea(ref x, ref y, _windowRect.width, _windowRect.height);
            _windowRect = new Rect(x, y, _windowRect.width, _windowRect.height);
        }
        RebuildStyles();
        _lastDensityX = px; _lastDensityY = py;
        _lastSafeWidth = GUI.SafeWidth; _lastSafeHeight = GUI.SafeHeight;
        _lastSafeLeft = GUI.SafeLeft; _lastSafeTop = GUI.SafeTop;
        _lastScreenWidth = Screen.width; _lastScreenHeight = Screen.height;
    }

'''+marker)
    replace('''            if (!_windowInitialized) InitWindowRect();
            if (Math.Abs(_lastScale - Scale) > 0.01f) RebuildStyles();''','''            RefreshTouchLayout();''')
    replace('float size = 64f * Scale;','float size = ToggleSize;')
    replace('GUI.HorizontalSlider(new Rect(0, sy, sw, ButtonHeight * 0.52f), value, min, max)','GUI.HorizontalSlider(new Rect(0, sy, sw, SliderHeight), value, min, max)')
    replace('sy += ButtonHeight * 0.52f + Padding * 0.7f;','sy += SliderHeight + Padding * 0.7f;')
    anchor='    public static float PixelsPerPoint {get;private set;}=1;'
    if touch.count(anchor)!=1:raise ValueError('touch density source anchor changed')
    touch=touch.replace(anchor,anchor+'''
    public static float PixelsPerPointX {get;private set;}=1;
    // Logical presentation facts from the last real native frame; no new ABI.
    public static float SafeWidth => viewport.width > 0 ? Math.Max(1, viewport.width-viewport.safeLeft-viewport.safeRight) : float.MaxValue;
    public static float SafeHeight => viewport.height > 0 ? Math.Max(1, viewport.height-viewport.safeTop-viewport.safeBottom) : float.MaxValue;
    public static float SafeLeft => viewport.safeLeft;
    public static float SafeTop => viewport.safeTop;''')
    anchor='PixelsPerPoint=frame.py;viewport=frame;'
    if touch.count(anchor)!=1:raise ValueError('touch last-frame source anchor changed')
    touch=touch.replace(anchor,'PixelsPerPoint=frame.py;PixelsPerPointX=frame.px;viewport=frame;')
    marker='    private void DrawButtons(ref float y, float w)'
    oldBody=original[original.index(marker):]
    newBody=gui[gui.index(marker):].replace('GUI.HorizontalSlider(new Rect(0, sy, sw, SliderHeight), value, min, max)','GUI.HorizontalSlider(new Rect(0, sy, sw, ButtonHeight * 0.52f), value, min, max)').replace('sy += SliderHeight + Padding * 0.7f;','sy += ButtonHeight * 0.52f + Padding * 0.7f;')
    if newBody!=oldBody:raise ValueError('action body or eligibility guards changed')
    return gui,touch,{'scope':'client-control presentation geometry only','minimumTouchPoints':44,'minimumTextPoints':14,'actionBodyAndGuardsUnchangedExceptSliderGeometry':True,'actionBodyOriginalSha256':sha(oldBody),'actionBodyNormalizedSha256':sha(newBody),'inputs':{'gui':sha(original),'touch':sha(originalTouch)},'outputs':{'gui':sha(gui),'touch':sha(touch)},'nativeABIChanged':False,'nativeStyleMinimumChanged':False,'gameInvoked':False}
def main():
    p=argparse.ArgumentParser();p.add_argument('--gui-source',type=Path,required=True);p.add_argument('--touch-source',type=Path,required=True);p.add_argument('--project',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output.resolve()
    if out.exists():raise ValueError('fresh output required')
    gui,touch,manifest=adapt(a.gui_source.read_text(),a.touch_source.read_text());out.mkdir(parents=True)
    (out/'ClientControlGUI.cs').write_text(gui);(out/'NativeTouchGUI.cs').write_text(touch)
    manifest['inputPaths']={'gui':str(a.gui_source.resolve()),'touch':str(a.touch_source.resolve())}
    if a.project:
        tree=ET.parse(a.project);seen={'ClientControlGUI.cs':0,'NativeTouchGUI.cs':0}
        for element in tree.getroot().iter('Compile'):
            value=element.get('Include')
            if not value:continue
            if any(c in value for c in '$*?'):raise ValueError('explicit resolved source paths required')
            path=Path(value);path=(path if path.is_absolute() else a.project.parent/path).resolve()
            element.set('Include',str(path))
            if path.name in seen:
                expected=a.gui_source.resolve() if path.name=='ClientControlGUI.cs' else a.touch_source.resolve()
                if path.resolve()!=expected:raise ValueError('project selects a different current '+path.name)
                seen[path.name]+=1;element.set('Include',str(out/path.name))
        if seen!={'ClientControlGUI.cs':1,'NativeTouchGUI.cs':1}:raise ValueError('exactly one GUI and touch source required')
        for element in tree.getroot().iter('EmbeddedResource'):
            value=element.get('Include')
            if not value:continue
            if any(c in value for c in '$*?'):raise ValueError('explicit resolved resource paths required')
            path=Path(value);element.set('Include',str((path if path.is_absolute() else a.project.parent/path).resolve()))
        tree.write(out/'EHR.csproj',encoding='unicode',xml_declaration=False)
        manifest['inputProject']={'path':str(a.project.resolve()),'sha256':sha(a.project.read_bytes())}
    (out/'sizing-adaptation.json').write_text(json.dumps(manifest,indent=2)+'\n');print(out/'sizing-adaptation.json')
if __name__=='__main__':main()
