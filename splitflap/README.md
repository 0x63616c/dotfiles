# splitflap — a DIY 4×16 split-flap display

A complete, start-to-finish plan for a **modular, black, fully-enclosed
4 row × 16 column = 64 module** split-flap display, buildable on a Bambu printer,
driven by an ESP32, controlled from a small web app — culminating in
**HELLO WORLD**.

Each module shows **48 glyphs**: space, `A–Z`, `0–9`, `. , ! ? - / &`, and
currency **`$ £ € ¥`**. Flaps are **3D-printed dual-color** (black card, white
glyph) — no vinyl, no stickers.

> **New here? Read [`docs/00-build-guide.md`](docs/00-build-guide.md) top to
> bottom.** It's the master plan; everything else is reference it links into.

## The plan in one breath

Build and prove **one** module on a breadboard (~$35, one evening), then batch
the other 63. Steppers (28BYJ-48) + a shared shift-register driver PCB keep it
cheap (~$4/module) and simple. The mechanism is printed from a proven,
fully-3D-printable design; this repo's original work is the enclosure, the driver
board, the firmware, and the web app.

- **Cost of one module (at scale):** ~$4 in parts
- **Cost of the full 4×16:** ~$425 (+~$25 optional acrylic face) — ~$6.60/module
- Full numbers: [`docs/01-bom.md`](docs/01-bom.md)

## Contents

| Path | What it is |
|---|---|
| `docs/00-build-guide.md` | **The master guide** — every phase from empty printer to "HELLO WORLD" |
| `docs/01-bom.md` | Bill of materials + real 2025–26 pricing, per-one and per-64, re-checked |
| `docs/02-dimensions.md` | Every part dimension, tolerance, and Bambu print setting |
| `docs/03-electronics.md` | Wiring, the shift-register driver chain, power budget |
| `firmware/splitflap-esp32/` | ESP32 firmware — `bringup` (1 module) and `board` (full) profiles |
| `webapp/index.html` | Single-file control app (also served off the ESP32) |
| `hardware/openscad/params.scad` | All dimensions as parameters — the single source of geometry |
| `hardware/openscad/module.scad` | Parametric mechanism (drum/flap/spool) — a resizable fallback |
| `hardware/openscad/enclosure.scad` | The black, tiled, snap-together bezel/frame |
| `hardware/openscad/fit_test.scad` | Print first — dials in your printer's tolerances |
| `hardware/pcb/README.md` | Driver board schematic, netlist, JLCPCB order notes |
| `hardware/flaps/charset.json` | Canonical 48-glyph flap order (firmware + web app derive from it) |

## Quick start (module #1)

```bash
# 1. Print one module's parts (MakerWorld 1116618 + 48-flap 1296793), dual-color.
# 2. Wire ESP32 + ULN2003 + A3144 hall  (see docs/03-electronics.md).
cd firmware/splitflap-esp32
python3 tools/embed_webapp.py            # inline the web app
# edit src/main.cpp -> WIFI_SSID / WIFI_PASS
pio run -e bringup -t upload             # single-module profile
pio device monitor                       # note the IP
# 3. Open http://<esp32-ip>/  -> type a letter -> Send. It flips. 🎉
```

Then scale: build the driver board (`hardware/pcb/`), print 64 enclosure tiles
(`enclosure.scad`), batch the modules, and reflash with `pio run -e board`.

## Software / hardware split

- **Hardware:** 3D-printed mechanism (proven design) + printed enclosure (this
  repo) + 28BYJ-48 steppers + A3144 hall homing + shift-register driver PCB +
  one ESP32 + a 12 V/20 A supply.
- **Software:** ESP32 firmware (non-blocking stepper scheduler, hall homing,
  WiFi, HTTP `/api/text`, status WebSocket) + a browser control app with a live
  split-flap preview. Both read the same `charset.json`.

## Different sizes

Everything is parametric: firmware `-DROWS/-DCOLS`, `params.scad` grid vars, and
the web app's Rows/Columns fields. 1×1 desk clock → 6×20 wall, same design.

## Credit & licenses

Built on the shoulders of the open-source split-flap community — Scott Bezek's
`splitflap` (Apache-2.0), the MakerWorld modular/48-flap/customiser models, the
`jp112sdl` fork, and OpenFlap. Full references and source URLs are at the end of
[`docs/00-build-guide.md`](docs/00-build-guide.md). Respect each upstream
project's license when you reuse its printed parts.
