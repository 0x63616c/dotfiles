"""Run with: /usr/bin/python3 -m unittest hammerspoon/tests/test_diagnostics.py"""

import importlib.util
import re
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/diagnostics.py"
spec = importlib.util.spec_from_file_location("diagnostics", SCRIPT)
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)


class DiagnosticsTests(unittest.TestCase):
    def test_sample_uses_counter_delta_and_archives_old_data(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as folder:
            with mock.patch.object(diagnostics, "DB", Path(folder) / "history.sqlite3"):
                with mock.patch.object(diagnostics.time, "time", return_value=400 * diagnostics.DAY):
                    with mock.patch.object(diagnostics, "disk_space", return_value=(90, 100)):
                        with mock.patch.object(diagnostics, "io_counters", side_effect=[(1000, 2000), (1600, 3200)]):
                            diagnostics.sample()
                            with mock.patch.object(diagnostics.time, "time", return_value=400 * diagnostics.DAY + 60):
                                diagnostics.sample()
                db = sqlite3.connect(diagnostics.DB)
                row = db.execute("SELECT read_bps, write_bps FROM samples ORDER BY ts DESC LIMIT 1").fetchone()
                self.assertEqual(row, (10, 20))
                db.execute("INSERT INTO samples VALUES (?, 80, 100, 2, 3, 0, 0)", (360 * diagnostics.DAY,))
                db.execute("INSERT INTO hourly VALUES (?, 70, 100, 4, 5)", (20 * diagnostics.DAY,))
                db.commit()
                diagnostics.archive(db, 400 * diagnostics.DAY)
                db.commit()
                self.assertEqual(db.execute("SELECT COUNT(*) FROM samples").fetchone()[0], 2)
                self.assertEqual(db.execute("SELECT used FROM daily").fetchone()[0], 70)
                self.assertEqual(db.execute("SELECT used FROM hourly").fetchone()[0], 80)
                db.close()

    def test_render_embeds_local_history_without_network(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as folder:
            with mock.patch.object(diagnostics, "DB", Path(folder) / "history.sqlite3"):
                with mock.patch.object(diagnostics.time, "time", return_value=500 * diagnostics.DAY):
                    with diagnostics.connect() as db:
                        db.execute("INSERT INTO samples VALUES (?, 90, 100, 10, 20, 1, 2)", (500 * diagnostics.DAY,))
                    diagnostics.render()
                html = diagnostics.DB.with_name("diagnostics.html").read_text()
                self.assertIn('"24h":[[43200000,90,100,10.0,20.0]]', html)
                self.assertNotIn("/*__DATA__*/", html)
                self.assertNotIn("/*__THEME__*/", html)
                self.assertIn("--color-popover: #09090b;", html)
                self.assertNotIn("https://", html)

    def test_theme_changes_reach_rendered_page(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as folder:
            theme = Path(folder) / "theme.lua"
            theme.write_text(diagnostics.THEME.read_text().replace("#09090b", "#123456"))
            with mock.patch.object(diagnostics, "THEME", theme):
                self.assertIn("--color-popover: #123456;", diagnostics.theme_css())
        used = set(re.findall(r"var\((--[\w-]+)", diagnostics.TEMPLATE.read_text()))
        defined = set(re.findall(r"(--[\w-]+):", diagnostics.theme_css()))
        self.assertFalse(used - defined)


if __name__ == "__main__":
    unittest.main()
