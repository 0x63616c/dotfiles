# Split-Flap Display — Full Build Guide (start → "HELLO WORLD")

A modular, black, fully-enclosed **4 × 16 = 64 module** split-flap display you
can build on a Bambu printer, driven by an ESP32 and a small web app.
Each module shows **48 glyphs**: space, `A–Z`, `0–9`, `. , ! ? - / &`, and
currency `$ £ € ¥`.

This guide is honest about one thing up front: **a split-flap drum is a
tolerance-critical mechanism, and mechanisms should not be reinvented blind.**
So the plan leans on a battle-tested, fully-3D-printable module design for the
moving parts, and adds original work where it matters for *your* goal — a clean
black enclosure, a driver PCB that makes 64 modules tractable, well-documented
ESP32 firmware, and the web app. You start by building **one** module, prove the
whole stack end-to-end, then batch the other 63.

> Every price, dimension, and part in this guide is collected in
> [`01-bom.md`](01-bom.md) (bill of materials + real pricing) and
> [`02-dimensions.md`](02-dimensions.md) (every measurement & tolerance).
> Wiring and the scaling electronics are in [`03-electronics.md`](03-electronics.md).

---

## 0. The two paths (and which to take)

| | **Path A — Stepper + your PCB (recommended)** | **Path B — OpenFlap (advanced)** |
|---|---|---|
| Mechanism | Proven 3D-printed drum, 28BYJ-48 stepper | 3D-printed + PCB-structural, geared DC motor |
| Sensing | A3144 hall + 4 mm magnet (home only) | 6-bit optical encoder on the wheel |
| Per-module electronics | Cheap ULN2003 board, or shared driver PCB | Custom per-module PCB (SMD, PY32 MCU each) |
| Cost / module (at 64) | **~$5–8** | ~$12–18 |
| Soldering skill | Low (through-hole / modules) | High (SMD, 64× boards) |
| Best when | You want cheapest, simplest, hackable | You want self-addressing magnetic chaining |
| Reference | scottbez1/splitflap (Apache-2.0), MakerWorld models | hackaday.io/project/185107-openflap |

**Take Path A.** It's the cheapest per module, the least SMD soldering, and the
firmware + web app in this repo target it directly. Path B (OpenFlap) is
genuinely elegant — fully 3D printed, PCBs as structure, modules that detect
their neighbours and self-address — but every module is a small SMD PCB build,
which is a hard first project when you "have nothing but a printer." Keep it in
your back pocket for v2.

### What you print vs. what this repo adds

- **Print the mechanism** from a proven, fully-3D-printable, dual-color design:
  - MakerWorld **1116618** — *Split-Flap Display, Modular, with Web Interface*
    (28BYJ-48, hall homing, dual-color flaps printed directly — no vinyl).
  - MakerWorld **1296793** — *Extended charset, 48 flaps* (adds punctuation +
    `€ £`), the flap set this guide's character map is built around.
  - MakerWorld **1309545** — *Flap Customiser* (generate your own flap sheets /
    glyph set, e.g. to add `¥`).
  - Alternative: `scottbez1/splitflap` printable parts, or `jp112sdl/SplitFlap`
    (45-flap fork, 28BYJ-48 + ULN2003 + A3144 — same electronics as here).
- **This repo adds:**
  - [`hardware/openscad/enclosure.scad`](../hardware/openscad/enclosure.scad) —
    the black, tiled, fully-enclosed bezel/frame (dual-color, snap-together).
  - [`hardware/pcb/`](../hardware/pcb/) — a shift-register **driver board** that
    turns "64 motors" from a wiring nightmare into a chain.
  - [`firmware/splitflap-esp32/`](../firmware/splitflap-esp32/) — ESP32 firmware
    with a one-module bring-up profile and a full-board profile.
  - [`webapp/index.html`](../webapp/index.html) — the control app (also served
    straight off the ESP32).
  - [`hardware/openscad/module.scad`](../hardware/openscad/module.scad) — a
    *parametric* mechanism you can fall back to / resize (test-fit required).

---

## 1. Architecture at a glance

```
                    ┌───────────────────────────┐
   web app  ──WiFi──►   ESP32  (the brain)       │
 (browser/phone)     │   • serves web app        │
                     │   • HTTP /api/text        │
                     │   • WebSocket status      │
                     └───────┬───────────────────┘
                             │  3 wires (data/clock/latch) + GND
                             ▼
   ┌──────────┐   chain   ┌──────────┐   chain   ┌──────────┐
   │ Driver 1 ├──ribbon──►│ Driver 2 ├──ribbon──►│ Driver N │   (~11 boards)
   │ 6 modules│           │ 6 modules│           │ 6 modules│
   └────┬─────┘           └────┬─────┘           └────┬─────┘
        │ 4 coil + 1 hall per module                  │
        ▼                                             ▼
   [28BYJ-48 + hall] × 6                        [28BYJ-48 + hall] × 6
        │
        ▼  each drum = 2 spools + 48 flaps + shaft + magnet
   ┌──────────────┐
   │  one module  │  ← shows one character
   └──────────────┘

   64 modules = 4 rows × 16 cols, each in a snap-together black bezel tile.
   Motor power (5 V or 12 V) is a SEPARATE high-current rail — never off the ESP32.
```

Why shift registers and not "just GPIO" or I²C?

- An Arduino Uno directly drives **≤3** modules; you have 64.
- I²C `MCP23017` expanders work (8 per bus × 16 GPIO = 128 pins), and driving
  28BYJ-48 + ULN2003 through them is proven — but 64 modules needs 16 expanders
  across ≥2 buses, and I²C is slower and fussier than a clocked chain.
- **Shift registers (74HC595 out / 74HC165 in)** are how the reference
  `scottbez1/splitflap` "Chainlink" system scales past 100 modules from one
  controller. That's the pattern the driver board and firmware here use.

---

## 2. Before you start: tools & consumables (Phase 0)

You said you have a printer and nothing else. Here's the realistic "get to one
module" shopping list (full pricing in [`01-bom.md`](01-bom.md)):

**One-time tools**
- Soldering iron + solder (any $20 kit is fine for through-hole)
- Wire cutters / strippers, small screwdriver set
- Superglue + a set of small files (for the shaft D-flat) or a rotary tool
- Digital calipers (**buy these** — you cannot tune tolerances without them, ~$15)
- A multimeter (cheap, for the one time a wire is wrong)

**Filament (Bambu / AMS, dual color)**
- 1 kg **matte black PLA** (bezel + flap bodies + drum)
- 1 kg **white or bright PLA** (flap glyphs — the second AMS color)
- PLA is fine indoors. Use **PETG** only if the display will sit in sun/heat
  (per Bambu's material table PLA softens ~50–60 °C).

**Electronics for module #1**
- 1 × ESP32 dev board (e.g. ESP32-DevKitC / TTGO)
- 1 × 28BYJ-48 stepper **with** its ULN2003 driver board (sold as a pair)
- 1 × A3144 hall-effect sensor + 1 × 4 mm × 2 mm neodymium magnet
- 1 × 5 mm steel rod (drum shaft) + optional 608 bearing
- Dupont jumper wires, a 5 V USB supply

> **Sourcing pitfall (verified):** many different motors ship under the name
> "28BYJ-48". Buy the version with the ULN2003 board as a set, and if you scale
> up, buy all 64 from the *same* batch/seller so their torque matches.

---

## 3. Phase 1 — Build and PROVE one module

This is the most important phase. Do not print 64 of anything until one module
flips cleanly under web-app control. Target: **~1 evening.**

### 1a. Print the module parts

From the MakerWorld modular design (1116618 + the 48-flap 1296793 flaps):
- Load the project in **Bambu Studio**.
- Flaps: assign **black** to the flap body and **white** to the glyph in the
  AMS/filament mapping — this is your "dual color" and means **no vinyl, no
  stickers** (the fully-3D-printable win).
- Suggested slicer settings: 0.2 mm layer, 3 walls, 15 % infill for structure;
  flaps print flat, glyph-side up. Print **one** module's worth first:
  2 spools, 48 flaps, body sides, motor mount, sensor mount.

Print settings and every dimension are consolidated in
[`02-dimensions.md`](02-dimensions.md).

### 1b. Assemble the drum

1. File a small **D-flat** on one end of the 5 mm shaft so the spool can't slip.
2. Press the **4 mm magnet** into its pocket in one spool hub (this is home).
3. Clip the **48 flaps** in around the two spools — each flap's side pins sit in
   consecutive slots. Order matters: start at the **blank** flap (that's index 0,
   the home position) and go `A, B, C …` in the order in
   [`../hardware/flaps/charset.json`](../hardware/flaps/charset.json).
4. Slide the drum onto the shaft; seat the shaft in the body sides (608 bearing
   on the non-motor side if you're using one).
5. Couple the motor shaft to the drum. Add a nylon washer if there's axial play
   — the reference build specifically fought **0.5–1.5 mm of shaft play** this way.

### 1c. Wire the electronics (breadboard, no PCB yet)

```
ESP32            ULN2003 board          28BYJ-48
GPIO16 ─────────► IN1
GPIO17 ─────────► IN2
GPIO18 ─────────► IN3
GPIO19 ─────────► IN4
                  motor + (5V)  ◄──── 5V supply (NOT the ESP32 3V3!)
GND ───┬────────► GND (common) ◄───── supply GND
       │
A3144 hall:  VCC→3V3   GND→GND   OUT→GPIO21   (10k pull-up; INPUT_PULLUP used in fw)
```

The full pinout and the eventual PCB wiring live in
[`03-electronics.md`](03-electronics.md). Power the motor from the 5 V supply,
share grounds, and keep the ESP32 on USB for now.

### 1d. Flash the bring-up firmware

```bash
cd firmware/splitflap-esp32
python3 tools/embed_webapp.py         # inline the web app into the firmware
# edit src/main.cpp -> set WIFI_SSID / WIFI_PASS
pio run -e bringup -t upload          # ROWS=1 COLS=1, DRIVER_DIRECT_GPIO
pio device monitor                    # note the printed IP / http://splitflap.local
```

On boot the module **homes**: it spins until the hall sensor sees the magnet,
then calls that position flap 0 (blank). If it spins forever, the sensor isn't
triggering — see Troubleshooting.

### 1e. Drive it from the web app

Open `http://<esp32-ip>/` (served by the firmware) **or** open
[`webapp/index.html`](../webapp/index.html) locally and type the ESP32 host in
the Connection panel. Type a letter, hit **Send** — the drum should step forward
to that glyph. The browser preview mirrors what the hardware reports over the
WebSocket.

### 1f. Calibrate home

If the module lands one flap off (shows `A` when you asked for blank), set
`HOME_OFFSET_STEPS` in `src/main.cpp` (steps between the magnet trigger and the
blank flap being centered), re-flash, re-home. One number, done. There are
`4096 / 48 ≈ 85` steps per flap, so nudge in ~85-step units.

**Milestone:** one module, any of the 48 glyphs on command, from a browser.
You've now proven mechanism + motor + homing + firmware + web app + WiFi. The
remaining 63 are copies.

---

## 4. Phase 2 — The driver board (make 64 tractable)

Wiring 64 motors straight to an ESP32 is impossible (it has ~25 usable GPIO).
The fix is a small **shift-register driver board**, chained. See
[`03-electronics.md`](03-electronics.md) and [`../hardware/pcb/`](../hardware/pcb/)
for the schematic, the JLCPCB order notes, and the exact BOM. In short:

- Each board drives **6 modules** (matches the reference Chainlink capacity).
- Outputs: `74HC595` shift registers → `ULN2003` arrays → motor coils.
- Inputs: `74HC165` shift register reads the 6 hall sensors back to the ESP32.
- Boards chain over a 6-wire ribbon (data/clock/latch out, data in, +V logic, GND).
- **~11 boards** cover 64 modules.
- Order 5 at a time from JLCPCB; through-hole assembly is easy, or pay for
  assembly.

Firmware already supports this: build `-e board` (`DRIVER_SHIFT_CHAIN`).

---

## 5. Phase 3 — The black enclosure

Render and print the frame from
[`../hardware/openscad/enclosure.scad`](../hardware/openscad/enclosure.scad):

- It generates **one bezel tile per module** — so a 4 × 16 wall is 64 identical
  tiles that **snap together** with dovetail edge-clips. This is the "modular"
  in modular: want 4 × 20 later? Print more tiles.
- Dual color: print the face in **black**, set `ACCENT=true` for a second-color
  inlay groove around each window (a thin bright frame per character).
- Each tile has a rebate for an **optional 2 mm acrylic sheet** over the window
  for the clean glass look, plus side walls that make the assembly fully enclosed
  and a cable pass-through on the bottom.
- Print tiles in black PLA; they clip over the module bodies and hide all the
  mechanism.

```bash
# render / export from the CLI (or just open in the OpenSCAD GUI)
openscad -o bezel_tile.stl hardware/openscad/enclosure.scad
openscad -D ACCENT=true -o bezel_accent.stl hardware/openscad/enclosure.scad
```

> Note: OpenSCAD isn't run in this repo's CI, so treat these as **parametric
> source you render and test-print** — print **one** tile, check the window frames
> your printed flaps and the acrylic seats, then batch. Tune `MODULE_PITCH_X/Y`
> and `WINDOW_W/H` in [`params.scad`](../hardware/openscad/params.scad) to match
> the module you actually printed.

---

## 6. Phase 4 — Batch the other 63 modules

Now it's production. Tips that save real time:

- **Print in batches.** A Bambu plate fits several spools + a few dozen flaps at
  once. 64 modules ≈ 128 spools + 3072 flaps — plan multi-day print farming and
  ~5 kg of filament. Print flaps in big dual-color batches.
- **Jig your assembly.** Once you've clipped 48 flaps once, you'll want a small
  printed jig to hold spools at the right spacing. Build one, then repeat.
- **Test each module on the bench** with the bring-up firmware *before* it goes
  in the wall. A dead module is 5 minutes to fix on a breadboard and an hour to
  fix inside a finished frame.
- **Match motors.** Same batch/seller for all 64 (torque consistency).

---

## 7. Phase 5 — Assemble the full board & power it

1. Clip the 64 bezel tiles into a 4 × 16 wall (dovetail edges).
2. Seat a module in each tile.
3. Mount the ~11 driver boards on the back; chain them with ribbon.
4. **Power budget (verified):** each module draws ~**0.25 A** while moving.
   Worst case 64 moving at once = ~16 A on the motor rail. In practice modules
   idle with coils released (the firmware does this) and you can stagger homing,
   so average draw is far lower — but **size for the worst case:**
   - 5 V build: a **5 V / 20–30 A** supply, with 5 V injected at several points
     along the chain (thick wire; 5 V sags over long runs).
   - 12 V build (Bezek's choice, more torque, thinner current): a **12 V / 20 A
     (~240 W)** supply feeds ULN2003 boards fed with 12 V motors. Easier wiring.
   - Logic (ESP32 + shift registers) runs off a separate small 5 V rail.
   Add a fuse on the motor rail. Full numbers in [`03-electronics.md`](03-electronics.md).

---

## 8. Phase 6 — Flash the board firmware & say hello

```bash
cd firmware/splitflap-esp32
python3 tools/embed_webapp.py
pio run -e board -t upload            # ROWS=4 COLS=16, DRIVER_SHIFT_CHAIN
```

- On boot all 64 modules home (staggered). Watch them settle to blank.
- Open `http://splitflap.local/` (or the IP). The web app auto-detects the 4×16
  size reported by the firmware.
- Type **`HELLO WORLD`**, choose **Center**, hit **Send** — or just press the
  **Hello World demo** button.

```
┌──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐
│  │  │  │  │ H│ E│ L│ L│ O│  │ W│ O│ R│ L│ D│  │   row 1
├──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┤
│  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │   rows 2-4 blank
└──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘
```

The board flutters to life and settles on **HELLO WORLD**. Done. 🎉

---

## 9. Support different sizes

Everything is parametric so the same design scales:

- **Firmware:** `-DROWS` / `-DCOLS` build flags (defaults 4/16). The web app reads
  the size back over the API, so no edits there.
- **Enclosure:** `ROWS`/`COLS` and `MODULE_PITCH_*` in `params.scad`; tiles are
  per-module so any grid works.
- **Web app:** the Rows/Columns fields drive the preview; "Apply size" re-lays out.
- **Character set:** edit [`charset.json`](../hardware/flaps/charset.json), keep
  `FLAP_GLYPHS` (firmware) and the `CHARSET` array (web app) in sync, and print a
  matching flap set with the MakerWorld Flap Customiser (1309545).

Common builds: **1×1** (desk clock, the bring-up unit), **1×6** (a word),
**4×16** (this guide), **6×20** (a Vestaboard-class wall).

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Module spins forever on boot | Hall never triggers | Check magnet polarity/orientation; A3144 is polarity-sensitive — flip the magnet. Verify OUT→GPIO21, INPUT_PULLUP. |
| Lands one flap off | Home offset | Tune `HOME_OFFSET_STEPS` (~85 steps/flap). |
| Skips / stalls under load | Under-powered or fast | Lower speed (raise `HALF_STEP_US`), use 12 V motors, check the 5 V rail isn't sagging. |
| Flaps jam / don't fall | Tolerance | Loosen `FIT_LOOSE` slot clearance, deburr flap pins, check drum isn't rubbing the body. |
| Wrong glyph everywhere | Flap order | Re-order flaps to match `charset.json` starting at blank. |
| Nothing on the web app | Wrong host / WiFi | Confirm the IP from serial; try the IP instead of `.local`; same network. |
| Half the chain dead | Ribbon / power injection | Reseat ribbon; inject motor power mid-chain; check a cold solder joint on that board. |

---

## 11. References (all verified during research)

- Scott Bezek **splitflap** (Apache-2.0): <https://github.com/scottbez1/splitflap>
  · Electronics wiki: <https://github.com/scottbez1/splitflap/wiki/Electronics>
  · v2 ordering: <https://github.com/scottbez1/splitflap/blob/master/docs/v2/OrderingComplete.md>
- MakerWorld modular + web UI: <https://makerworld.com/en/models/1116618>
- MakerWorld 48-flap extended charset: <https://makerworld.com/en/models/1296793>
- MakerWorld flap customiser: <https://makerworld.com/en/models/1309545>
- jp112sdl 45-flap fork: <https://github.com/jp112sdl/SplitFlap>
- OpenFlap (Path B): <https://hackaday.io/project/185107-openflap>
- ESP32 + 28BYJ-48 + ULN2003 primer: <https://randomnerdtutorials.com/esp32-stepper-motor-28byj-48-uln2003/>
- Building DIY split-flaps (overview): <https://www.partsnotincluded.com/building-diy-split-flap-displays/>
- Bambu filament material table: <https://wiki.bambulab.com/en/general/filament-guide-material-table>

Sourcing links (motors, sensors, flaps, PSU) are in [`01-bom.md`](01-bom.md).
