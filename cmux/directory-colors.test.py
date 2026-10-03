"""Run with /usr/bin/python3 cmux/directory-colors.test.py."""

import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("directory_colors", Path(__file__).with_name("directory-colors.py"))
colors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(colors)


class DirectoryColorsTests(unittest.TestCase):
    def setUp(self):
        self.state = {}
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

    def event(self, action, color=None, workspace="a"):
        return {"name": "workspace.action", "workspace_id": workspace,
                "payload": {"result": {"action": action, "color": color}}}

    def apply(self, event):
        return colors.apply(event, self.state, self.rows, self.send)

    def test_same_full_path_only(self):
        self.apply(self.event("set_color", "#FF9E64"))
        self.assertEqual(self.state, {"/repos/dotfiles": "#FF9E64"})
        self.assertEqual([p["workspace_id"] for _, p in self.sent], ["b"])
        self.assertIsNone(self.rows[2]["custom_color"])

    def test_new_workspace_and_restart_inherit_saved_preference(self):
        self.test_same_full_path_only()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "colors.json"
            colors.save(self.state, path)
            import json
            self.state = json.loads(path.read_text())
        self.rows.append({"id": "new", "current_directory": "/repos/dotfiles", "custom_color": None})
        self.sent.clear()
        self.apply({"name": "workspace.created"})
        self.assertEqual(self.sent[0][1]["workspace_id"], "new")
        self.assertEqual(self.rows[-1]["custom_color"], "#FF9E64")

    def test_default_clears_every_match_and_remembers_reset(self):
        self.test_same_full_path_only()
        self.rows[0]["custom_color"] = None
        self.sent.clear()
        self.apply(self.event("clear_color"))
        self.assertEqual(self.state, {"/repos/dotfiles": None})
        self.assertEqual(self.sent, [("workspace.action", {"workspace_id": "b", "action": "clear_color"})])
        self.rows[1]["custom_color"] = "#FF9E64"
        self.apply({"name": "config.reloaded"})
        self.assertIsNone(self.rows[1]["custom_color"])

    def test_propagated_events_do_not_loop(self):
        self.test_same_full_path_only()
        self.sent.clear()
        self.apply(self.event("set_color", "#FF9E64", workspace="b"))
        self.assertEqual(self.sent, [])

    def test_stale_events_and_non_color_actions_are_ignored(self):
        self.assertFalse(self.apply(self.event("set_color", "#7AA2F7")))
        self.assertFalse(self.apply(self.event("pin")))
        self.assertEqual(self.state, {})
        self.assertEqual(self.sent, [])

    def test_missing_or_closed_target_does_not_change_state(self):
        self.assertFalse(self.apply(self.event("set_color", "#FF9E64", workspace="closed")))
        self.assertEqual(self.state, {})


if __name__ == "__main__":
    unittest.main()
