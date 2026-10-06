"""Run with /usr/bin/python3 -B cmux/directory-colors.test.py."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("directory_colors", Path(__file__).with_name("directory-colors.py"))
colors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(colors)


class DirectoryColorsTests(unittest.TestCase):
    def setUp(self):
        self.sent = []
        self.rows = [
            {"id": "a", "current_directory": "/repos/dotfiles", "custom_color": "#FF9E64"},
            {"id": "b", "current_directory": "/repos/dotfiles", "custom_color": None},
            {"id": "c", "current_directory": "/other/dotfiles", "custom_color": None},
            {"id": "d", "current_directory": "/repos/agentinc", "custom_color": None},
        ]

    def send(self, method, **params):
        self.sent.append((method, params))
        row = next(r for r in self.rows if r["id"] == params["workspace_id"])
        row["custom_color"] = params.get("color")

    def test_home_relative_paths_work_with_another_username(self):
        self.assertEqual(colors.path_key("/Users/alice/code/dotfiles", "/Users/alice"), "~/code/dotfiles")
        self.assertEqual(colors.path_key("/Users/bob/code/dotfiles", "/Users/bob"), "~/code/dotfiles")
        self.assertEqual(colors.path_key("/Users/alice2/code", "/Users/alice"), "/Users/alice2/code")
        self.assertIsNone(colors.path_key(""))
        self.assertIsNone(colors.path_key("relative/path"))

    def test_same_full_path_only(self):
        state = {}
        colors.set_override(state, self.rows, "a", "7dcfff")
        colors.reconcile(state, self.rows, self.send)
        self.assertEqual(state, {"/repos/dotfiles": "#7DCFFF"})
        self.assertEqual([p["workspace_id"] for _, p in self.sent], ["a", "b"])
        self.assertIsNone(self.rows[2]["custom_color"])

    def test_new_workspace_inherits_saved_preference(self):
        self.rows.append({"id": "new", "current_directory": "/repos/dotfiles", "custom_color": None})
        colors.reconcile({"/repos/dotfiles": "#7DCFFF"}, self.rows, self.send)
        self.assertEqual(self.rows[-1]["custom_color"], "#7DCFFF")

    def test_default_removes_entry_and_clears_stale_overrides(self):
        state = {"/repos/dotfiles": "#FF9E64"}
        self.rows[1]["custom_color"] = "#FF9E64"
        colors.set_override(state, self.rows, "a", "default")
        colors.reconcile(state, self.rows, self.send)
        self.assertEqual(state, {})
        self.assertEqual([p["workspace_id"] for _, p in self.sent], ["a", "b"])
        self.rows[1]["custom_color"] = "#FF9E64"
        colors.reconcile(state, self.rows, self.send)
        self.assertIsNone(self.rows[1]["custom_color"])

    def test_reconciliation_does_not_loop_or_learn_old_native_colors(self):
        state = {"/repos/dotfiles": "#7DCFFF"}
        colors.reconcile(state, self.rows, self.send)
        self.sent.clear()
        colors.reconcile(state, self.rows, self.send)
        self.assertEqual(self.sent, [])
        self.assertEqual(state, {"/repos/dotfiles": "#7DCFFF"})

    def test_missing_directory_is_skipped(self):
        self.rows.append({"id": "none", "custom_color": "#FF9E64"})
        colors.reconcile({}, self.rows, self.send)
        self.assertNotIn("none", [p["workspace_id"] for _, p in self.sent])

    def test_invalid_requests_do_not_change_config(self):
        for workspace, color in [("closed", "7DCFFF"), ("a", "not-a-color")]:
            state = {"/repos/dotfiles": "#FF9E64"}
            with self.assertRaises(ValueError):
                colors.set_override(state, self.rows, workspace, color)
            self.assertEqual(state, {"/repos/dotfiles": "#FF9E64"})

    def test_atomic_save_preserves_symlink_and_file_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "tracked.json"
            target.write_text("{}\n")
            target.chmod(0o644)
            link = Path(directory) / "installed.json"
            link.symlink_to(target)
            colors.save({"~/code/dotfiles": "#7DCFFF"}, link)
            self.assertTrue(link.is_symlink())
            self.assertEqual(target.stat().st_mode & 0o777, 0o644)
            self.assertEqual(colors.read_config(link), {"~/code/dotfiles": "#7DCFFF"})
            self.assertEqual(sorted(p.name for p in target.parent.iterdir()), ["installed.json", "tracked.json"])

    def test_malformed_config_is_not_silently_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "colors.json"
            for content in ["[]", '{"relative":"#7DCFFF"}', '{"~/repo":null}', '{"~/repo":"bad"}']:
                target.write_text(content)
                with self.assertRaises(ValueError):
                    colors.read_config(target)
                self.assertEqual(target.read_text(), content)

    def run_main(self, directory, args, send=None):
        config = Path(directory) / "colors.json"
        lock = Path(directory) / "runtime/colors.lock"
        with patch.object(colors, "CONFIG", config), patch.object(colors, "LOCK", lock), \
             patch.object(colors, "workspaces", return_value=self.rows), \
             patch.object(colors, "rpc", side_effect=send or self.send):
            colors.main(args)

    def test_save_happens_before_native_mutation_and_survives_selection(self):
        # Regression: a real menu request needs no workspace.action event.
        # The old saved orange must never undo the new cyan on selection.
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "colors.json"
            config.write_text('{"/repos/dotfiles":"#FF9E64"}\n')
            def send(method, **params):
                self.assertEqual(colors.read_config(config)["/repos/dotfiles"], "#7DCFFF")
                self.send(method, **params)
            self.run_main(directory, ["--workspace", "a", "--color", "7DCFFF"], send)
            self.run_main(directory, [])
            self.assertEqual(self.rows[0]["custom_color"], "#7DCFFF")
            self.assertEqual(self.rows[1]["custom_color"], "#7DCFFF")

    def test_failed_rpc_does_not_lose_saved_choice(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "colors.json"
            config.write_text("{}\n")
            def fail(*args, **kwargs):
                raise RuntimeError("cmux unavailable")
            with self.assertRaises(RuntimeError):
                self.run_main(directory, ["--workspace", "a", "--color", "7DCFFF"], fail)
            self.assertEqual(colors.read_config(config), {"/repos/dotfiles": "#7DCFFF"})
            self.run_main(directory, [])
            self.assertEqual(self.rows[1]["custom_color"], "#7DCFFF")

    def test_default_main_removes_saved_choice(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "colors.json"
            config.write_text('{"/repos/dotfiles":"#FF9E64"}\n')
            self.run_main(directory, ["--workspace", "a", "--color", "default"])
            self.assertEqual(json.loads(config.read_text()), {})
            self.assertIsNone(self.rows[0]["custom_color"])


if __name__ == "__main__":
    unittest.main()
