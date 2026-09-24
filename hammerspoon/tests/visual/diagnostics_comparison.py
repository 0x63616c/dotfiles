#!/usr/bin/env python3
"""Build standalone before/after browser views without loading live Hammerspoon."""

import importlib.util
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
BASELINE = "7483b17b8cbb71116af42bb98f97cc50ca1714d1"

spec = importlib.util.spec_from_file_location("diagnostics", ROOT / "hammerspoon/scripts/diagnostics.py")
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)

now = int(time.time())
rows = [[now - 86400 + i * 60, 73_000_000_000 + i * 2_200_000, 100_000_000_000,
         2_000_000 + (i % 180) * 15_000 + (i % 13) * 80_000,
         900_000 + (i % 150) * 10_000 + (i % 17) * 40_000] for i in range(1441)]
series = {key: rows for key in ("1h", "6h", "24h", "7d", "30d", "All")}
data = "const DATA = " + json.dumps(series, separators=(",", ":")) + ";"
old = subprocess.check_output(["git", "show", f"{BASELINE}:hammerspoon/diagnostics.html"], cwd=ROOT, text=True)
new = (ROOT / "hammerspoon/diagnostics.html").read_text()
(OUT / "before-content.html").write_text(old.replace("/*__DATA__*/", data))
(OUT / "after-content.html").write_text(new.replace("/*__DATA__*/", data).replace("/*__THEME__*/", diagnostics.theme_css()))

reference = """
<div class="hyper-card">
  <div class="hyper-head"><span>HYPR</span><span>⌃ ⌥ ⇧ ⌘</span></div>
  <div class="hyper-rule"></div>
  <div class="hyper-row"><kbd>C</kbd>Copy latest screenshot</div>
  <div class="hyper-row"><kbd>D</kbd>Diagnostics</div>
  <div class="hyper-row"><kbd>H</kbd>Open Hammerspoon Console</div>
  <div class="hyper-row"><kbd>M</kbd>Open Messages</div>
  <div class="hyper-row"><kbd>S</kbd>Sonos</div>
  <div class="hyper-row"><kbd>W</kbd>Open Wispr Flow</div>
  <div class="hyper-row"><kbd>X</kbd>Screenshot library</div>
</div>"""

for name, title in (("before", "Before · original Diagnostics"), ("after", "After · themed Diagnostics")):
    browser = f"""<!doctype html><meta charset="utf-8"><title>{title} comparison</title>
<style>{diagnostics.theme_css()}
* {{box-sizing:border-box}} body {{margin:0;background:#202024;color:var(--color-foreground);font-family:-apple-system,BlinkMacSystemFont,sans-serif}}
.layout {{display:flex;gap:28px;padding:25px}} .stage {{width:1200px;flex:none}} .reference {{width:410px;flex:none}}
.label {{height:35px;color:var(--color-mutedForeground);font-size:13px;letter-spacing:.02em}}
.window {{height:900px;overflow:hidden;border:1px solid #45454b;box-shadow:0 20px 50px #0008}}
.window.before {{border-radius:10px;background:var(--color-popover)}}
.titlebar {{height:29px;background:#2e2e31;border-bottom:1px solid #4b4b4f;text-align:center;font-size:12px;line-height:29px;color:#d5d5d6}}
iframe {{width:100%;height:100%;border:0}} .before iframe {{height:871px}}
.hyper-stage {{height:900px;position:relative;background:#29292e;border:1px solid #45454b;display:flex;justify-content:center;align-items:flex-start;padding-top:180px}}
.hyper-card {{width:365px;background:var(--color-popover);border:1px solid var(--color-border);border-radius:var(--radius-card);padding:var(--space-pad);box-shadow:0 var(--shadow-dy) var(--shadow-blur) rgb(0 0 0 / var(--shadow-alpha))}}
.hyper-head {{display:flex;justify-content:space-between;color:var(--color-mutedForeground);font-size:var(--text-title);letter-spacing:1.8px}}
.hyper-rule {{height:1px;background:var(--color-border);margin:17px 0 10px}} .hyper-row {{height:var(--space-row);display:flex;align-items:center;gap:18px;font-size:var(--text-label)}}
kbd {{width:42px;height:33px;line-height:31px;text-align:center;background:var(--color-muted);border:1px solid var(--color-mutedEdge);border-radius:var(--radius-control);font-size:var(--text-key);font-weight:600}}
.note {{font-size:11px;color:var(--color-mutedForeground);margin-top:10px}}
</style><div class="layout"><div class="stage"><div class="label">{title}</div><div class="window {name}">{"<div class='titlebar'>Diagnostics</div>" if name == "before" else ""}<iframe src="{name}-content.html"></iframe></div></div><div class="reference"><div class="label">Hyper cheatsheet · token/layout reference</div><div class="hyper-stage">{reference}</div><div class="note">Standalone HTML reproduction of the canvas card, using lib/theme.lua values.</div></div></div>"""
    (OUT / f"{name}.html").write_text(browser)
