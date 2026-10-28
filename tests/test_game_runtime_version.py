"""Regression for a preview package reporting an outdated game to Unity."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
try:
    spec = importlib.util.spec_from_file_location('game_probe_version', ROOT / 'tools/build_game_probe.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
finally:
    sys.path.pop(0)


class RuntimeGameVersion(unittest.TestCase):
    def test_runtime_uses_game_version_independently_of_port_and_build_labels(self):
        self.assertEqual(builder.game_runtime_version({'CFBundleShortVersionString':'2026.9.29',
            'CFBundleVersion':'3','EHRPortVersion':'0.0.0'}), '2026.9.29')

    def test_no_silent_preview_fallback_for_missing_or_invalid_game_version(self):
        for value in (None, '', '0.0.0', 'Preview', '2026.9.29-beta', 2026):
            with self.subTest(value=value), self.assertRaises(ValueError):
                builder.game_runtime_version({'CFBundleShortVersionString':value})
