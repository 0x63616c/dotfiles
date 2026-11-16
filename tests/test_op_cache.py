"""Tests for the op shim (home/dot_local/bin/executable_op) against a fake op that counts its calls."""

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SHIM = Path(__file__).resolve().parent.parent / "home/dot_local/bin/executable_op"

FAKE_OP = """#!/bin/sh
n=$(cat "$CALLS" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$CALLS"
case "$1" in fail) echo boom >&2; exit 3 ;; esac
echo "call $n: $*"
"""


class OpShimTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.fake = self.tmp / "op"
        self.fake.write_text(FAKE_OP)
        self.fake.chmod(self.fake.stat().st_mode | stat.S_IXUSR)
        self.cache = self.tmp / "cache"
        self.env = {
            "PATH": "/usr/bin:/bin",
            "CLAUDECODE": "1",
            "OP_CACHE_REAL": str(self.fake),
            "OP_CACHE_DIR": str(self.cache),
            "CALLS": str(self.tmp / "calls"),
        }

    def op(self, *args, **env):
        e = dict(self.env, **env)
        e = {k: v for k, v in e.items() if v is not None}
        return subprocess.run(["sh", str(SHIM), *args], env=e, capture_output=True, text=True)

    def calls(self):
        return int((self.tmp / "calls").read_text())

    def test_read_is_cached(self):
        a = self.op("read", "op://v/i/f")
        b = self.op("read", "op://v/i/f")
        self.assertEqual(a.stdout, b.stdout)
        self.assertEqual(self.calls(), 1)

    def test_different_args_are_separate_entries(self):
        self.op("item", "get", "x")
        self.op("item", "get", "y")
        self.assertEqual(self.calls(), 2)

    def test_list_after_write_is_fresh(self):
        self.op("item", "list")
        self.op("item", "create", "--title", "new")
        r = self.op("item", "list")
        self.assertEqual(self.calls(), 3)
        self.assertIn("call 3", r.stdout)

    def test_read_only_commands_do_not_invalidate(self):
        self.op("read", "op://v/i/f")
        self.op("whoami")
        self.op("read", "op://v/i/f")
        self.assertEqual(self.calls(), 2)

    def test_refresh_bypasses_and_updates(self):
        self.op("read", "op://v/i/f")
        r = self.op("read", "op://v/i/f", OP_CACHE="refresh")
        self.assertIn("call 2", r.stdout)
        r = self.op("read", "op://v/i/f")
        self.assertIn("call 2", r.stdout)
        self.assertEqual(self.calls(), 2)

    def test_off_bypasses_without_storing(self):
        self.op("read", "op://v/i/f", OP_CACHE="off")
        self.op("read", "op://v/i/f")
        self.assertEqual(self.calls(), 2)

    def test_cache_clear(self):
        self.op("read", "op://v/i/f")
        self.assertEqual(self.op("cache", "clear").returncode, 0)
        self.op("read", "op://v/i/f")
        self.assertEqual(self.calls(), 2)

    def test_otp_and_out_file_not_cached(self):
        for args in (
            ("item", "get", "x", "--otp"),
            ("read", "op://v/i/one-time password?attribute=otp"),
            ("read", "op://v/i/f", "--out-file", "/dev/null"),
        ):
            self.op(*args)
            self.op(*args)
        self.assertEqual(self.calls(), 6)

    def test_failure_not_cached(self):
        r = self.op("fail")
        self.assertEqual(r.returncode, 3)
        self.assertIn("boom", r.stderr)
        self.op("read", "op://v/x/y", OP_CACHE_REAL=str(self.fake))
        self.op("read", "op://v/x/y")
        self.assertEqual(self.calls(), 2)

    def test_outside_claude_passes_through(self):
        self.op("read", "op://v/i/f", CLAUDECODE=None)
        self.op("read", "op://v/i/f", CLAUDECODE=None)
        self.assertEqual(self.calls(), 2)
        self.assertFalse(self.cache.exists())

    def test_cache_is_private(self):
        self.op("read", "op://v/i/f")
        self.assertEqual(stat.S_IMODE(self.cache.stat().st_mode), 0o700)
        for f in self.cache.iterdir():
            self.assertEqual(stat.S_IMODE(f.stat().st_mode), 0o600)

    def test_expired_entries_refetch(self):
        self.op("read", "op://v/i/f")
        for f in self.cache.glob("*.out"):
            old = f.stat().st_mtime - 31 * 60
            os.utime(f, (old, old))
        self.op("read", "op://v/i/f")
        self.assertEqual(self.calls(), 2)


if __name__ == "__main__":
    unittest.main()
