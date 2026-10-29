import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("install", Path(__file__).with_name("install.py"))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTests(unittest.TestCase):
    def test_backups_idempotence_and_capture_after_atomic_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo, config = root / "repo", root / "config/opencode"
            (repo / "opencode/plugins/subscription-usage").mkdir(parents=True)
            (repo / "opencode/plugins/full-terminal-title").mkdir(parents=True)
            (repo / "themes/opencode").mkdir(parents=True)
            for relative in ("opencode/opencode.json", "opencode/cli.json"):
                (repo / relative).write_text("{}\n")
            config.mkdir(parents=True)
            (config / "cli.json").write_text('{"theme":{"name":"old"}}')
            (config / "cli.json.before-dotfiles").write_text("existing backup")
            (config / "service.json").write_text("private runtime settings")
            installer.install(repo, config)
            self.assertFalse((config / "plugins/statusline.tsx").exists())
            self.assertFalse((config / "theme-pack").exists())
            self.assertTrue((config / "themes").is_symlink())
            self.assertEqual((config / "plugins/full-terminal-title").resolve(), (repo / "opencode/plugins/full-terminal-title").resolve())
            self.assertEqual((config / "cli.json.before-dotfiles.1").read_text(), '{"theme":{"name":"old"}}')
            installer.install(repo, config)
            self.assertFalse((config / "cli.json.before-dotfiles.2").exists())
            replacement = config / "replacement.json"
            replacement.write_text(json.dumps({
                "theme": {"name": "aura"},
                "session": {"verbosity": "low"},
                "terminal": {"title": False, "copy": "select"},
                "plugins": [str(repo / "opencode/plugins/subscription-usage"), {"package": str(config / "plugins/full-terminal-title"), "options": {"custom": True}}],
            }))
            replacement.replace(config / "cli.json")
            installer.install(repo, config, capture=True)
            self.assertTrue((config / "cli.json").is_symlink())
            captured = json.loads((repo / "opencode/cli.json").read_text())
            self.assertEqual(captured["session"]["verbosity"], "low")
            self.assertEqual(captured["plugins"], ["./plugins/subscription-usage", {"package": "./plugins/full-terminal-title", "options": {"custom": True}}])
            self.assertEqual(captured["terminal"], {"title": False, "copy": "select"})
            self.assertEqual((config / "service.json").read_text(), "private runtime settings")
            self.assertFalse((repo / "opencode/service.json").exists())

    def test_dangling_link_is_backed_up(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, destination = root / "source", root / "destination"
            source.write_text("config")
            destination.symlink_to(root / "missing")
            installer.link(source, destination)
            self.assertEqual(destination.read_text(), "config")
            self.assertTrue((root / "destination.before-dotfiles").is_symlink())


if __name__ == "__main__":
    unittest.main()
