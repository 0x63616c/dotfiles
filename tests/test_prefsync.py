"""Unit-ish tests for prefsync: manifest parsing, filtering, merging, three-way capture.
Run: python3 -m unittest discover -s tests -v   (macOS-only integration tests are skipped elsewhere)
"""

import importlib.machinery
import importlib.util
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "home", "dot_local", "bin", "executable_prefsync")
MANIFEST = os.path.join(ROOT, "home", "prefs", "manifest.toml")

os.environ.setdefault("PREFSYNC_STATE_DIR", tempfile.mkdtemp(prefix="prefsync-test-state-"))
os.environ.setdefault("PREFSYNC_LOG", os.path.join(os.environ["PREFSYNC_STATE_DIR"], "test.log"))
_loader = importlib.machinery.SourceFileLoader("prefsync", SCRIPT)
_spec = importlib.util.spec_from_loader("prefsync", _loader)
ps = importlib.util.module_from_spec(_spec)
_loader.exec_module(ps)


def dom(**kw):
    kw.setdefault("name", "co.test")
    return ps.Domain(kw)


class TomlTests(unittest.TestCase):
    def test_manifest_parses(self):
        with open(MANIFEST) as f:
            m = ps.mini_toml(f.read())
        names = [d["name"] for d in m["domain"]]
        self.assertIn("com.vorssaint.utils", names)
        self.assertIn("com.apple.symbolichotkeys", names)
        self.assertEqual(m["settings"]["commit"], True)
        self.assertEqual(len(names), len(set(names)))

    def test_mini_matches_tomllib(self):
        try:
            import tomllib
        except ImportError:
            self.skipTest("no tomllib on this Python")
        with open(MANIFEST) as f:
            text = f.read()
        self.assertEqual(ps.mini_toml(text), tomllib.loads(text))

    def test_subset(self):
        t = (
            '# c\n[a]\nx = 1\ny = "s # not comment" # real\nz = [\n "p", # c\n \'q\',\n]\nb = true\n'
            '[[d]]\nn = "1"\n[[d]]\nn = "2"\n'
        )
        self.assertEqual(
            ps.mini_toml(t),
            {"a": {"x": 1, "y": "s # not comment", "z": ["p", "q"], "b": True}, "d": [{"n": "1"}, {"n": "2"}]},
        )


class FilterTests(unittest.TestCase):
    def f(self, doc, **kw):
        return ps.filter_doc(doc, dom(**kw), ["calum", "calums-macbook-pro"])

    def test_deny_globs(self):
        kept, _ = self.f({"keep": 1, "NSWindow Frame x": "a", "mic1Saved": 2}, deny=["NS*", "mic*Saved*"])
        self.assertEqual(kept, {"keep": 1})

    def test_allow_list_is_exclusive(self):
        kept, _ = self.f({"KeyRepeat": 2, "Other": 1}, allow=["KeyRepeat"])
        self.assertEqual(kept, {"KeyRepeat": 2})

    def test_home_templated(self):
        kept, _ = self.f({"p": ps.HOME + "/Documents"})
        self.assertEqual(kept["p"], "@HOME@/Documents")
        self.assertEqual(ps.from_template(kept)["p"], ps.HOME + "/Documents")

    def test_private_values_denied(self):
        doc = {
            "email": "someone@example.com",
            "phone": "call 818 599 6605",
            "uuid": "1E6D9F9E-0000-0000-0B23-0104B5682C78",
            "host": "Calums-MacBook-Pro",
            "nested": {"a": ["x", "me@x.io"]},
            "user": "/mnt/calum/secret",  # not under HOME: caught by username
            "ok": "hello",
        }
        kept, denied = self.f(doc)
        self.assertEqual(set(kept), {"ok"})
        self.assertEqual(set(denied), set(doc) - {"ok"})

    def test_data_and_dates_denied_unless_allowed(self):
        import datetime

        doc = {"blob": b"abc", "when": datetime.datetime(2026, 1, 1), "cfg": b"[1]"}
        kept, denied = self.f(doc, allow_data=["cfg"])
        self.assertEqual(set(kept), {"cfg"})
        self.assertEqual(set(denied), {"blob", "when"})

    def test_allowed_data_still_scanned(self):
        kept, denied = self.f({"cfg": b'{"mail":"a@b.co"}'}, allow_data=["cfg"])
        self.assertEqual(kept, {})
        self.assertIn("cfg", denied)


class MergeTests(unittest.TestCase):
    def test_deep_merge_keeps_live_only_keys(self):
        live = {"a": {"x": 1, "y": 2}, "keep": 1}
        snap = {"a": {"y": 3, "z": 4}}
        self.assertEqual(ps.deep_merge(live["a"], snap["a"]), {"x": 1, "y": 3, "z": 4})

    def test_deep_merge_replaces_lists(self):
        self.assertEqual(ps.deep_merge({"l": [1, 2]}, {"l": [3]}), {"l": [3]})

    def test_merge3_local_change_wins_repo_change_kept(self):
        base = {"a": 1, "b": 1, "c": 1, "d": {"x": 1, "y": 1}}
        live = {"a": 2, "b": 1, "d": {"x": 1, "y": 5}, "e": 9}  # local: a changed, c removed, y changed, e added
        snap = {"a": 1, "b": 7, "c": 1, "d": {"x": 8, "y": 1}}  # repo (pulled): b changed, d.x changed
        self.assertEqual(
            ps.merge3(base, live, snap),
            {"a": 2, "b": 7, "d": {"x": 8, "y": 5}, "e": 9},
        )

    def test_merge3_no_local_change_is_identity(self):
        base = {"a": 1}
        self.assertEqual(ps.merge3(base, dict(base), {"a": 5}), {"a": 5})

    def test_dump_is_deterministic_and_sorted(self):
        a = ps.dump_plist({"b": 1, "a": {"z": 1, "y": 2}})
        b = ps.dump_plist({"a": {"y": 2, "z": 1}, "b": 1})
        self.assertEqual(a, b)
        self.assertLess(a.index(b"<key>a</key>"), a.index(b"<key>b</key>"))

    def test_diff_paths(self):
        d = ps.diff_paths({"a": {"x": 1}, "b": 1}, {"a": {"x": 2}, "c": 1})
        self.assertEqual([(op, p) for op, p, _, _ in d], [("~", "a.x"), ("-", "b"), ("+", "c")])


@unittest.skipUnless(sys.platform == "darwin", "needs macOS defaults")
class CliIntegrationTests(unittest.TestCase):
    """Real `defaults` against a throwaway domain, in a temp repo with a temp state dir."""

    DOMAIN = "co.prefsync.unittest"

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="prefsync-it-")
        self.repo = os.path.join(self.tmp, "repo")
        os.makedirs(os.path.join(self.repo, "home", "prefs"))
        with open(os.path.join(self.repo, ".chezmoiroot"), "w") as f:
            f.write("home\n")
        with open(os.path.join(self.repo, "home", "prefs", "manifest.toml"), "w") as f:
            f.write(
                '[settings]\ncommit = true\n[[domain]]\nname = "%s"\ndeny = ["secret*"]\nrestart = "none"\n'
                % self.DOMAIN
            )
        for cmd in (
            ["init", "-q", "-b", "main"],
            ["config", "user.email", "t@users.noreply.github.com"],
            ["config", "user.name", "T"],
            ["add", "-A"],
            ["commit", "-q", "-m", "init"],
        ):
            subprocess.run(["git", "-C", self.repo, *cmd], check=True, capture_output=True)
        self.env = dict(
            os.environ,
            PREFSYNC_SRC=self.repo,
            PREFSYNC_STATE_DIR=os.path.join(self.tmp, "state"),
            PREFSYNC_LOG=os.path.join(self.tmp, "log"),
        )
        self.clean_domain()

    def tearDown(self):
        self.clean_domain()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def clean_domain(self):
        subprocess.run(["defaults", "delete", self.DOMAIN], capture_output=True)

    def run_ps(self, *args):
        return subprocess.run([sys.executable, SCRIPT, *args], env=self.env, capture_output=True, text=True)

    def snap(self):
        with open(os.path.join(self.repo, "home", "prefs", self.DOMAIN + ".plist"), "rb") as f:
            return plistlib.load(f)

    def commits(self):
        return subprocess.run(
            ["git", "-C", self.repo, "log", "--format=%s"], capture_output=True, text=True
        ).stdout.splitlines()

    def test_capture_apply_roundtrip(self):
        subprocess.run(["defaults", "write", self.DOMAIN, "alpha", "-int", "1"], check=True)
        subprocess.run(["defaults", "write", self.DOMAIN, "secretKey", "-string", "x"], check=True)
        subprocess.run(["defaults", "write", self.DOMAIN, "path", "-string", ps.HOME + "/x"], check=True)
        r = self.run_ps("capture")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.snap(), {"alpha": 1, "path": "@HOME@/x"})  # secret* denied, home templated
        self.assertTrue(self.commits()[0].startswith("prefs(%s)" % self.DOMAIN))
        n = len(self.commits())

        self.assertEqual(self.run_ps("capture").returncode, 0)  # no-op when unchanged
        self.assertEqual(len(self.commits()), n)

        subprocess.run(["defaults", "write", self.DOMAIN, "alpha", "-int", "2"], check=True)
        self.run_ps("capture")
        self.assertEqual(self.snap()["alpha"], 2)
        self.assertEqual(len(self.commits()), n + 1)

        # repo-side edit is applied (merged), unrelated live-only key survives
        subprocess.run(["defaults", "write", self.DOMAIN, "liveOnly", "-int", "7"], check=True)
        self.run_ps("capture")
        snap = self.snap()
        snap["alpha"] = 3
        with open(os.path.join(self.repo, "home", "prefs", self.DOMAIN + ".plist"), "wb") as f:
            f.write(ps.dump_plist(snap))
        subprocess.run(["defaults", "write", self.DOMAIN, "extra", "-int", "5"], check=True)  # live-only, uncaptured
        r = self.run_ps("apply")
        self.assertEqual(r.returncode, 0, r.stderr)
        out = subprocess.run(["defaults", "read", self.DOMAIN], capture_output=True, text=True).stdout
        self.assertIn("alpha = 3", out)
        self.assertIn("liveOnly = 7", out)

    def test_apply_captures_local_change_first(self):
        subprocess.run(["defaults", "write", self.DOMAIN, "alpha", "-int", "1"], check=True)
        self.run_ps("capture")
        subprocess.run(
            ["defaults", "write", self.DOMAIN, "alpha", "-int", "9"], check=True
        )  # user change, not yet captured
        self.run_ps("apply")
        self.assertEqual(self.snap()["alpha"], 9)
        out = subprocess.run(["defaults", "read", self.DOMAIN, "alpha"], capture_output=True, text=True).stdout.strip()
        self.assertEqual(out, "9")

    def test_shrink_guard(self):
        for i in range(8):
            subprocess.run(["defaults", "write", self.DOMAIN, "k%d" % i, "-int", str(i)], check=True)
        self.run_ps("capture")
        for i in range(6):
            subprocess.run(["defaults", "delete", self.DOMAIN, "k%d" % i], check=True)
        self.run_ps("capture")
        self.assertEqual(len(self.snap()), 8)  # refused
        self.run_ps("capture", "--force")
        self.assertEqual(len(self.snap()), 2)


if __name__ == "__main__":
    unittest.main()
