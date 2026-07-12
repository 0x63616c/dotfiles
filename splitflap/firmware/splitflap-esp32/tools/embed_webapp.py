#!/usr/bin/env python3
"""Inline webapp/index.html into src/index_html.h as a PROGMEM string.

Run from anywhere:  python3 tools/embed_webapp.py
Re-run whenever you edit the web app so the ESP32 serves the latest UI.
"""
import pathlib

here = pathlib.Path(__file__).resolve().parent
root = here.parent                      # firmware/splitflap-esp32
repo = root.parent.parent               # splitflap/
src_html = repo / "webapp" / "index.html"
out = root / "src" / "index_html.h"

html = src_html.read_text(encoding="utf-8")
if ')rawliteral"' in html:
    raise SystemExit("index.html contains the raw-string terminator; pick another delimiter")

header = (
    "// AUTO-GENERATED from webapp/index.html by tools/embed_webapp.py — do not edit.\n"
    "#pragma once\n"
    "#include <pgmspace.h>\n"
    'static const char INDEX_HTML[] PROGMEM = R"rawliteral(\n'
    + html
    + '\n)rawliteral";\n'
)
out.write_text(header, encoding="utf-8")
print(f"wrote {out}  ({len(html)} bytes of HTML)")
