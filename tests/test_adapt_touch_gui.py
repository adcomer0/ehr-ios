import hashlib
import importlib.util
import unittest
from pathlib import Path

tool=Path(__file__).resolve().parents[1]/"tools"/"adapt_touch_gui.py"
spec=importlib.util.spec_from_file_location("adapt_touch_gui",tool)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

FIXTURE='''using static EHR.Translator;
class ClientControlGUI {
private static float Scale   => Screen.width / 1080f * PlatformScale;
    private void OnDestroy()
    {
        unsubscribe();
    }
    private static Texture2D RoundedTexture(int width, int height, int radius, Color fill, Color edge)
    { return OriginalTexture(); }
    /// <summary>
    /// Returns 0 if outside (transparent)
    private void CornerAlpha() {}
    private void OnGUI()
    { OriginalRender(); }
    // Draws the small toggle button
    private void DrawToggle() {
        float size = 48f * Scale;
        ToggleRect = new Rect(x, y, size, size);
    }
    private void HandleDrag()
    { OriginalEventInput(); }
    // Draws the window background
    private void DrawWindow() {}
    private static string Label(string label, string shortcut = null)
    { return label+shortcut; }
    // Draws buttons based on game state
    private void DrawButtons(ref float y, float w)
    {
        if (actualHost && actualLobby) Btn("Start", () => ActualStart());
        Btn("End", () => ActualEnd());
    }
}
'''.encode()

class RenderingAdaptationTests(unittest.TestCase):
    def render(self,data=FIXTURE):
        return module.transform(data,hashlib.sha256(data).hexdigest())
    def test_actions_and_game_guards_unchanged(self):
        output,report=self.render()
        marker=b'    private void DrawButtons(ref float y, float w)'
        self.assertEqual(FIXTURE[FIXTURE.index(marker):],output[output.index(marker):])
        self.assertTrue(report['drawButtonsUnchanged'])
    def test_rejects_unreviewed_input(self):
        with self.assertRaisesRegex(ValueError,'hash'):
            module.transform(FIXTURE,'0'*64)
    def test_missing_or_duplicate_render_anchor_rejects(self):
        for data in (FIXTURE.replace(b'private void HandleDrag()',b'private void OtherDrag()'),FIXTURE.replace(b'using static EHR.Translator;',b'using static EHR.Translator;\nusing static EHR.Translator;')):
            with self.assertRaises(ValueError):self.render(data)
    def test_aborted_frame_and_hidden_hud_close_ui(self):
        output,_=self.render()
        self.assertIn(b'if (!HudManager.InstanceExists) { GUI.Hide(); return; }',output)
        self.assertIn(b'finally { GUI.EndFrame(committed); }',output)
        self.assertIn(b'private void OnDestroy()\n    {\n        GUI.Hide();',output)
    def test_rendering_types_are_local_aliases(self):
        output,_=self.render()
        self.assertIn(b'using GUI = EHR.Generated.TouchGUI;',output)
        self.assertNotIn(b'namespace UnityEngine',output)
        self.assertIn(b'sceneSubscriptionOwnership',str(self.render()[1]).encode())
    def test_does_not_mutate_input(self):
        original=bytes(FIXTURE)
        self.render()
        self.assertEqual(original,FIXTURE)
    def test_safe_area_and_physical_touch_scale(self):
        output,_=self.render()
        self.assertIn(b'PixelsPerPoint * 0.72f',output)
        self.assertIn(b'float size = 64f * Scale;',output)
        self.assertIn(b'GUI.ClampToSafeArea(ref x, ref y, size, size);',output)

if __name__=='__main__':unittest.main()
