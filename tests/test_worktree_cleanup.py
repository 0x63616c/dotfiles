import importlib.machinery
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "home/dot_local/bin/executable_worktree-cleanup"
loader = importlib.machinery.SourceFileLoader("worktree_cleanup", str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
cleanup = importlib.util.module_from_spec(spec)
loader.exec_module(cleanup)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name).resolve() / "repo"
        self.root = Path(self.tmp.name).resolve() / "worktrees"
        self.repo.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Test")
        self.git("commit", "--allow-empty", "-m", "initial")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.git("remote", "add", "origin", "git@github.com:0x63616c/world-wide-webb.git")
        self.path = self.root / "codex/task"
        self.git("worktree", "add", "-b", "codex/task", str(self.path))
        self.git("-C", str(self.path), "commit", "--allow-empty", "-m", "task")
        self.entry = {
            "worktree": str(self.path),
            "branch": "refs/heads/codex/task",
            "HEAD": self.git("rev-parse", "codex/task").strip(),
        }
        self.pr = {
            "state": "MERGED",
            "baseRefName": "main",
            "headRefOid": self.entry["HEAD"],
            "headRepository": {"nameWithOwner": cleanup.REMOTE},
            "url": "https://github.com/example/pr/1",
        }
        self.original_run = cleanup.run

        def run(*args, cwd=None):
            return self.original_run(*args, cwd=cwd or self.repo)

        for target, value in (("REPO", self.repo), ("ROOT", self.root), ("run", run)):
            patcher = patch.object(cleanup, target, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, text=True, stderr=subprocess.PIPE)

    def test_squash_merge_proof_and_changed_head(self):
        self.assertEqual(cleanup.merged_reason(self.entry, [self.pr]), self.pr["url"])
        self.git("-C", str(self.path), "commit", "--allow-empty", "-m", "new work")
        self.assertIsNone(cleanup.merged_reason(self.entry, [self.pr]))
        self.entry["HEAD"] = self.git("rev-parse", "codex/task").strip()
        self.assertIsNone(cleanup.merged_reason(self.entry, [self.pr]))

    def test_wrong_base_open_pr_and_missing_head_repository(self):
        self.assertIsNone(cleanup.merged_reason(self.entry, [{**self.pr, "baseRefName": "develop"}]))
        self.assertIsNone(cleanup.merged_reason(self.entry, [self.pr, {**self.pr, "state": "OPEN"}]))
        self.assertIsNone(cleanup.merged_reason(self.entry, [{**self.pr, "headRepository": None}]))

    def test_dirty_active_locked_and_ignored_data(self):
        self.assertIsNone(cleanup.local_blocker(self.entry, []))
        self.assertIn("active", cleanup.local_blocker(self.entry, [self.path / "subdir"]))
        self.assertIn("locked", cleanup.local_blocker({**self.entry, "locked": "hold"}, []))
        (self.path / "notes.txt").write_text("unfinished")
        self.assertIn("local changes", cleanup.local_blocker(self.entry, []))
        (self.path / "notes.txt").unlink()
        self.git("config", "core.excludesFile", str(Path(self.tmp.name) / "ignore"))
        (Path(self.tmp.name) / "ignore").write_text("*.sqlite\n")
        (self.path / "private.sqlite").write_text("retain")
        self.assertIn("database", cleanup.local_blocker(self.entry, []))
        (self.path / "private.sqlite").unlink()
        (self.path / ".build").mkdir()
        (self.path / ".build/build.sqlite").write_text("disposable")
        self.assertIsNone(cleanup.local_blocker(self.entry, []))

    def test_preview_and_apply_remove_only_merged_clean_worktree(self):
        real_run = cleanup.run

        def run(*args, cwd=None):
            if args[:2] == ("git", "fetch"):
                return ""
            if args[0] == "wtp":
                self.assertEqual(args[1:], ("remove", "--with-branch", "--force-branch", "codex/task"))
                self.git("worktree", "remove", str(self.path))
                self.git("branch", "-D", "codex/task")
                return ""
            return real_run(*args, cwd=cwd)

        with (
            patch.object(cleanup, "run", run),
            patch.object(cleanup, "pull_requests", return_value={"codex/task": [self.pr]}),
            patch.object(cleanup, "remote_heads", return_value={}),
            patch.object(cleanup, "active_directories", return_value=[]),
        ):
            preview = cleanup.cleanup()
            self.assertEqual(sum(r["action"] == "eligible" for r in preview), 1)
            self.assertTrue(self.path.exists())
            report = cleanup.cleanup(apply=True)
            self.assertEqual(sum(r["action"] == "removed" for r in report), 1)
            self.assertFalse(self.path.exists())
            self.assertTrue(self.repo.exists())

    def test_pushed_worktree_waits_24_hours_and_keeps_branch(self):
        observed = {}
        real_run = cleanup.run

        def run(*args, cwd=None):
            if args[:2] == ("git", "fetch"):
                return ""
            if args[0] == "wtp":
                self.assertEqual(args[1:], ("remove", "codex/task"))
                self.git("worktree", "remove", str(self.path))
                return ""
            return real_run(*args, cwd=cwd)

        with (
            patch.object(cleanup, "run", run),
            patch.object(cleanup, "pull_requests", return_value={"codex/task": [{**self.pr, "state": "OPEN"}]}),
            patch.object(cleanup, "remote_heads", return_value={"codex/task": self.entry["HEAD"]}),
            patch.object(cleanup, "active_directories", return_value=[]),
        ):
            cleanup.cleanup(observed=observed, now=0)
            report = cleanup.cleanup(apply=True, observed=observed, now=86399)
            self.assertFalse(any(r["action"] == "removed" for r in report))
            self.assertTrue(self.path.exists())
            report = cleanup.cleanup(apply=True, observed=observed, now=86400)
            removed = [r for r in report if r["action"] == "removed"]
            self.assertEqual(len(removed), 1)
            self.assertTrue(removed[0]["keep_branch"])
            self.assertFalse(self.path.exists())
            self.assertEqual(self.git("rev-parse", "codex/task").strip(), self.entry["HEAD"])
            self.assertEqual(observed, {})

    def test_changes_activity_and_remote_mismatch_reset_timer(self):
        observed = {}
        real_run = cleanup.run

        def run(*args, cwd=None):
            return "" if args[:2] == ("git", "fetch") else real_run(*args, cwd=cwd)

        with (
            patch.object(cleanup, "run", run),
            patch.object(cleanup, "pull_requests", return_value={"codex/task": []}),
            patch.object(cleanup, "remote_heads", return_value={"codex/task": self.entry["HEAD"]}) as remote,
            patch.object(cleanup, "active_directories", return_value=[]) as active,
        ):
            cleanup.cleanup(observed=observed, now=0)
            (self.path / "notes.txt").write_text("unfinished")
            cleanup.cleanup(observed=observed, now=3600)
            self.assertEqual(observed, {})
            (self.path / "notes.txt").unlink()
            cleanup.cleanup(observed=observed, now=7200)
            self.assertEqual(observed[str(self.path)]["since"], 7200)
            active.return_value = [self.path]
            cleanup.cleanup(observed=observed, now=10800)
            self.assertEqual(observed, {})
            active.return_value = []
            cleanup.cleanup(observed=observed, now=14400)
            remote.return_value = {}
            cleanup.cleanup(observed=observed, now=18000)
            self.assertEqual(observed, {})
            remote.return_value = {"codex/task": self.entry["HEAD"]}
            cleanup.cleanup(observed=observed, now=21600)
            self.git("-C", str(self.path), "commit", "--allow-empty", "-m", "new work")
            remote.return_value = {"codex/task": self.git("rev-parse", "codex/task").strip()}
            cleanup.cleanup(observed=observed, now=25200)
            self.assertEqual(observed[str(self.path)]["since"], 25200)


if __name__ == "__main__":
    unittest.main()
