import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


launcher = module("jev_launcher", "jev-launcher.py")
installer = module("installer", "install.py")


class ComputerControlTests(unittest.TestCase):
    def test_environment_key_avoids_keychain(self):
        with patch.object(launcher.subprocess, "run") as run:
            self.assertEqual(launcher.load_key({"OPENROUTER_API_KEY": " private-test-value "}),
                             "private-test-value")
            run.assert_not_called()

    def test_keychain_output_is_captured_not_sent_to_console(self):
        result = subprocess.CompletedProcess([], 0, "private-test-value\n", "")
        with patch.object(launcher.sys, "platform", "darwin"), \
             patch.object(launcher.subprocess, "run", return_value=result) as run:
            self.assertEqual(launcher.load_key({}), "private-test-value")
            self.assertTrue(run.call_args.kwargs["capture_output"])
            self.assertNotIn("private-test-value", run.call_args.args[0])

    def test_missing_key_and_non_mac(self):
        with patch.object(launcher.sys, "platform", "darwin"), \
             patch.object(launcher.subprocess, "run", return_value=subprocess.CompletedProcess([], 44, "", "error")):
            self.assertEqual(launcher.load_key({}), "")
        with patch.object(launcher.sys, "platform", "linux"), \
             patch.object(launcher.subprocess, "run") as run:
            self.assertEqual(launcher.load_key({}), "")
            run.assert_not_called()

    def test_exec_passes_secret_only_in_environment_and_forces_openrouter(self):
        with patch.dict(launcher.os.environ, {"JEV_PROVIDER": "typesafe"}, clear=True), \
             patch.object(launcher.sys, "argv", ["launcher"]), \
             patch.object(launcher, "load_key", return_value="private-test-value"), \
             patch.object(launcher.shutil, "which", return_value="/fake/jev-mcp"), \
             patch.object(launcher.os, "execvpe") as execute:
            launcher.main()
            executable, argv, environment = execute.call_args.args
            self.assertEqual(executable, "/fake/jev-mcp")
            self.assertEqual(argv, [executable])
            self.assertEqual(environment["OPENROUTER_API_KEY"], "private-test-value")
            self.assertEqual(environment["JEV_PROVIDER"], "openrouter")
            self.assertEqual(environment["JEV_MCP_MODEL"], "typesafe/jev-1.13")

    def test_check_prints_only_availability(self):
        for key, status in (("private-test-value", 0), ("", 1)):
            output = io.StringIO()
            with patch.object(launcher.sys, "argv", ["launcher", "--check"]), \
                 patch.object(launcher, "load_key", return_value=key), \
                 contextlib.redirect_stdout(output):
                self.assertEqual(launcher.main(), status)
                self.assertNotIn("private-test-value", output.getvalue())

    def test_keychain_failure_is_sanitized(self):
        error = io.StringIO()
        with patch.object(launcher.sys, "argv", ["launcher"]), \
             patch.object(launcher, "load_key", side_effect=OSError("private-test-value")), \
             contextlib.redirect_stderr(error):
            self.assertEqual(launcher.main(), 1)
            self.assertNotIn("private-test-value", error.getvalue())

    def test_missing_key_still_exposes_catalog_but_warns(self):
        error = io.StringIO()
        with patch.object(launcher.sys, "argv", ["launcher"]), \
             patch.object(launcher, "load_key", return_value=""), \
             patch.object(launcher.shutil, "which", return_value="/fake/jev-mcp"), \
             patch.object(launcher.os, "execvpe") as execute, \
             contextlib.redirect_stderr(error):
            launcher.main()
            execute.assert_called_once()
            self.assertIn("await", error.getvalue())

    def test_global_links_backup_and_idempotence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo, config = root / "repo", root / "config/opencode"
            for relative in ("opencode/skills/computer-control-jev",
                             "opencode/plugins/subscription-usage",
                             "opencode/plugins/full-terminal-title", "themes/opencode"):
                (repo / relative).mkdir(parents=True)
            for relative in ("opencode/AGENTS.md", "opencode/jev-launcher.py",
                             "opencode/opencode.json", "opencode/cli.json"):
                (repo / relative).write_text("test fixture\n")
            config.mkdir(parents=True)
            (config / "AGENTS.md").write_text("existing guidance")
            with contextlib.redirect_stdout(io.StringIO()):
                installer.install(repo, config)
                installer.install(repo, config)
            for relative in ("AGENTS.md", "jev-launcher.py", "skills/computer-control-jev"):
                self.assertEqual((config / relative).resolve(), (repo / "opencode" / relative).resolve())
            self.assertEqual((config / "AGENTS.md.before-dotfiles").read_text(), "existing guidance")
            self.assertFalse((config / "AGENTS.md.before-dotfiles.1").exists())

    def test_config_contains_no_key_and_evaluation_prompts_parse(self):
        root = Path(__file__).parent
        config = json.loads((root / "opencode.json").read_text())
        servers = config["mcp"]["servers"]
        self.assertIn("open-computer-use", servers)
        self.assertIn("jev", servers)
        self.assertNotIn("OPENROUTER_API_KEY", json.dumps(servers["jev"]))
        evals = json.loads((root / "skills/computer-control-jev/evals/evals.json").read_text())
        self.assertEqual(len(evals["evals"]), 3)


if __name__ == "__main__":
    unittest.main()
