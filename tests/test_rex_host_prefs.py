import importlib.machinery
import importlib.util
import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "home/dot_local/bin/executable_rex-host-prefs"
loader = importlib.machinery.SourceFileLoader("rex_host_prefs", str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
rex = importlib.util.module_from_spec(spec)
loader.exec_module(rex)


class RexHostPrefsTests(unittest.TestCase):
    def test_add_preserves_other_hosts_and_reapply_preserves_identity(self):
        other = {"id": "other", "locators": ["ssh://other"], "unknown": {"keep": True}}
        before = {"formatVersion": 1, "records": [other], "future": True}
        after = rex.merge(before, True)
        self.assertEqual(after["records"][0], other)
        self.assertTrue(after["future"])
        self.assertEqual(len(after["records"]), 2)
        self.assertEqual(rex.merge(after, True), after)
        self.assertEqual(before["records"], [other])
        self.assertEqual(rex.merge(after, False), before)

    def test_capture_excludes_ids_and_all_other_hosts(self):
        doc = rex.merge({"formatVersion": 1, "records": [{"locators": ["ssh://private"]}]}, True)
        doc["records"][-1]["lastInstanceID"] = "private-instance"
        self.assertEqual(rex.export_settings(doc), {"settings": {rex.KEY: {rex.SETTING: True}}})
        self.assertEqual(rex.export_settings(rex.merge(doc, False)), {"settings": {rex.KEY: {rex.SETTING: False}}})

    def test_missing_and_unsupported_preferences(self):
        self.assertEqual(rex.decode({}), {"formatVersion": 1, "records": []})
        for doc in ({"formatVersion": 2, "records": []}, {"formatVersion": 1, "records": [None]}):
            with self.assertRaises(ValueError):
                rex.decode({rex.KEY: json.dumps(doc).encode()})
        with self.assertRaises(ValueError):
            rex.merge({"formatVersion": 1, "records": []}, "true")

    def test_import_patches_only_owned_preference_with_other_hosts_intact(self):
        before = {"formatVersion": 1, "records": [{"id": "other", "locators": ["ssh://other"]}]}
        prefs = {rex.KEY: json.dumps(before).encode(), "unrelated": "leave alone"}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "settings.plist"
            path.write_bytes(plistlib.dumps({"settings": {rex.KEY: {rex.SETTING: True}}}))
            with (
                patch.object(rex.sys, "argv", ["rex-host-prefs", "import", str(path)]),
                patch.object(rex.subprocess, "check_output", return_value=plistlib.dumps(prefs)),
                patch.object(rex.subprocess, "run") as run,
            ):
                rex.main()
        args, kwargs = run.call_args
        self.assertEqual(args[0], ["/usr/bin/defaults", "import", rex.DOMAIN, "-"])
        imported = plistlib.loads(kwargs["input"])
        self.assertEqual(set(imported), {rex.KEY})
        merged = rex.decode(imported)
        self.assertEqual(merged["records"][0], before["records"][0])
        self.assertEqual(rex.export_settings(merged), {"settings": {rex.KEY: {rex.SETTING: True}}})
