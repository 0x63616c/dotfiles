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

sys.dont_write_bytecode = True  # no __pycache__ next to the deployed script
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


class CanonicalJsonTests(unittest.TestCase):
    def test_json_strings_sorted_others_untouched(self):
        doc = {"j": '{"b": 1, "a": [{"d": 2, "c": 1}]}', "l": "[1, 2]", "s": "{not json", "e": "", "n": 3}
        out = ps.canonical_json(doc)
        self.assertEqual(out["j"], '{"a":[{"c":1,"d":2}],"b":1}')
        self.assertEqual(out["l"], "[1,2]")
        self.assertEqual((out["s"], out["e"], out["n"]), ("{not json", "", 3))
        self.assertEqual(ps.canonical_json({"j": '{"a":[{"c":1,"d":2}],"b":1}'}), {"j": out["j"]})

    def test_cli_domain_fields(self):
        d = dom(
            export_cmd=["/x", "--export-settings", "{file}"],
            import_cmd=["/x", "--import-settings", "{file}"],
            defaults_keys=["folder"],
        )
        self.assertTrue(d.cli)
        self.assertEqual(d.export_key, "settings")
        self.assertEqual(d.defaults_keys, ["folder"])
        self.assertFalse(dom().cli)


class DoctorTests(unittest.TestCase):
    def test_resolved_commit_failures_not_reported(self):
        lines = [
            "2026-10-29 09:00:00 ERROR git commit failed (left uncommitted): hook\n",
            "2026-10-29 09:30:00 ERROR com.x: settings export failed\n",
            "2026-10-30 05:00:00 INFO committed: prefs(com.x): a 1→2\n",
            "2026-10-30 05:10:00 ERROR git commit failed (left uncommitted): hook\n",
            "2026-10-27 09:00:00 ERROR too old\n",
        ]
        errs = ps.recent_errors(lines, "2026-10-29 00:00:00")
        self.assertEqual([e[:19] for e in errs], ["2026-10-29 09:30:00", "2026-10-30 05:10:00"])


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
class _RepoCase(unittest.TestCase):
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
            subprocess.run(
                ["git", "-C", self.repo, "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", *cmd],
                check=True,
                capture_output=True,
            )
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


@unittest.skipUnless(sys.platform == "darwin", "needs macOS defaults")
class CliIntegrationTests(_RepoCase):
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


# A stand-in for an app with a settings backup CLI (modelled on Vorssaint 3.4.3): the export is every schema key with
# defaults filled in, JSON-string values in random key order and a private sub-field stripped; the import refuses while
# the app "runs", replaces every schema key (missing = deleted) and writes defaults out explicitly.
FAKE_APP = r"""#!%(python)s
import json, plistlib, random, subprocess, sys, os
DOMAIN, MARKER = %(domain)r, %(marker)r
SCHEMA = {"a": 0, "b": 2, "style": "{}", "dev": 0}
def read():
    r = subprocess.run(["defaults", "export", DOMAIN, "-"], capture_output=True)
    return plistlib.loads(r.stdout) if r.returncode == 0 else {}
cmd, path = sys.argv[1], sys.argv[2]
if cmd == "export":
    live = read()
    s = {k: live.get(k, v) for k, v in SCHEMA.items()}
    st = json.loads(s["style"]); st.pop("private", None)
    items = list(st.items()); random.shuffle(items); s["style"] = json.dumps(dict(items))
    open(path, "wb").write(plistlib.dumps({"settings": s, "backupVersion": 1}))
else:
    if os.path.exists(MARKER):
        print("quit the app before importing"); sys.exit(1)
    s = plistlib.load(open(path, "rb"))["settings"]
    live = read()
    for k in SCHEMA:
        live.pop(k, None)
    live.update({k: s.get(k, v) for k, v in SCHEMA.items()})
    subprocess.run(["defaults", "import", DOMAIN, "-"], input=plistlib.dumps(live), check=True)
"""


@unittest.skipUnless(sys.platform == "darwin", "needs macOS defaults")
class AppCliIntegrationTests(_RepoCase):
    """export_cmd/import_cmd domains, against the fake app above."""

    DOMAIN = "co.prefsync.unittest.cli"

    def setUp(self):
        super().setUp()
        self.app = os.path.join(self.tmp, "fakeapp")
        self.marker = os.path.join(self.tmp, "running")
        with open(self.app, "w") as f:
            f.write(FAKE_APP % {"python": sys.executable, "domain": self.DOMAIN, "marker": self.marker})
        os.chmod(self.app, 0o755)
        with open(os.path.join(self.repo, "home", "prefs", "manifest.toml"), "w") as f:
            f.write(
                '[settings]\ncommit = true\n[[domain]]\nname = "%s"\nrestart = "none"\n'
                'export_cmd = ["%s", "export", "{file}"]\nimport_cmd = ["%s", "import", "{file}"]\n'
                'defaults_keys = ["folder"]\ndeny = ["dev*"]\n' % (self.DOMAIN, self.app, self.app)
            )

    def write(self, key, *val):
        subprocess.run(["defaults", "write", self.DOMAIN, key, *val], check=True)

    def live(self):
        r = subprocess.run(["defaults", "export", self.DOMAIN, "-"], capture_output=True, check=True)
        return plistlib.loads(r.stdout)

    def test_capture_apply_roundtrip(self):
        self.write("a", "-int", "1")
        self.write("dev", "-int", "5")
        self.write("style", "-string", '{"y": 2, "x": 1, "private": "/secret/path"}')
        self.write("folder", "-string", ps.HOME + "/f")
        self.write("runtimeJunk", "-int", "1")
        r = self.run_ps("capture")
        self.assertEqual(r.returncode, 0, r.stderr)
        # export's view (defaults filled in, JSON canonical, private field gone) + defaults_keys; dev* denied
        self.assertEqual(self.snap(), {"a": 1, "b": 2, "style": '{"x":1,"y":2}', "folder": "@HOME@/f"})
        n = len(self.commits())
        for _ in range(3):  # random JSON key order must not look like a change
            self.run_ps("capture")
        self.assertEqual(len(self.commits()), n)

        snap = self.snap()
        snap["a"], snap["folder"] = 3, "@HOME@/g"
        with open(os.path.join(self.repo, "home", "prefs", self.DOMAIN + ".plist"), "wb") as f:
            f.write(ps.dump_plist(snap))
        open(self.marker, "w").close()  # importer refuses while the app runs
        r = self.run_ps("apply")
        self.assertNotEqual(r.returncode, 0)
        with open(self.env["PREFSYNC_LOG"]) as f:
            self.assertIn("settings import failed", r.stderr + f.read())
        os.remove(self.marker)
        r = self.run_ps("apply")
        self.assertEqual(r.returncode, 0, r.stderr)
        live = self.live()
        self.assertEqual(live["a"], 3)
        self.assertEqual(live["folder"], ps.HOME + "/g")
        self.assertEqual(live["dev"], 5)  # denied key the importer would have reset survives
        self.assertIn("/secret/path", live["style"])  # field the export strips is put back
        self.assertEqual(live["runtimeJunk"], 1)  # non-schema key untouched
        self.assertNotIn("b", live)  # defaults the importer wrote out are dropped again
        self.assertIn("in sync", self.run_ps("status").stdout)


if __name__ == "__main__":
    unittest.main()
