# Dimensions, Tolerances & Print Settings

Every measurement you need, in one place. Values marked **(tune)** are the ones
you dial in for *your* Bambu + filament with a test print — do that once and the
rest of the build is repeatable. The parametric source for all of this is
[`../hardware/openscad/params.scad`](../hardware/openscad/params.scad); this doc
is the human-readable version with the *why*.

> Reality check: these are the design targets. The mechanism from MakerWorld
> 1116618/1296793 ships pre-toleranced STLs — if you print those, you mostly need
> the **enclosure** and **fit** numbers below. If you render the parametric
> `module.scad`, expect 1–2 test iterations on the spool↔flap fit.

---

## 1. The flap

Based on the proven reference flap geometry (Bezek measures each flap at
**54 × 42.8 mm**; this build uses a slightly smaller card for a denser wall).

| Dimension | Value | Note |
|---|---|---|
| Flap width | 42.0 mm (`FLAP_W`) | Visible glyph slightly narrower |
| Flap height (both halves) | 46.0 mm (`FLAP_H`) | Split line at 23.0 mm |
| Flap thickness | 0.6 mm (`FLAP_T`) | 3D-printed; reference PVC is 0.76 mm (30 mil) |
| Side pin diameter | 1.8 mm (`FLAP_PIN_D`) | Rides the spool slots |
| Side pin length (each) | 2.2 mm (`FLAP_PIN_L`) | |
| Fold/score line | 0.4 mm deep | Crisp fold at the split |
| Count per drum | 48 (`FLAP_COUNT`) | = the character set |

Dual-color print: flap body **black**, glyph **white**, glyph on the top face.
No vinyl. Generate custom glyph sheets with MakerWorld 1309545 if you change the
set.

## 2. The drum (two spools + shaft)

| Dimension | Value | Note |
|---|---|---|
| Flaps around drum | 48 | `DRUM_SLOT_PITCH = 360/48 = 7.5°` |
| Pin-slot diameter | 1.8 mm + 2×`FIT_LOOSE` | Flaps must drop freely |
| Spool wall | 2.0 mm (`DRUM_WALL`) | |
| Hub bore (shaft) | 5.0 mm + 2×`FIT_LOOSE`, with D-flat | Keys to filed shaft |
| Magnet pocket | 4.0 mm ⌀ × 2.0 mm deep | Press-fit 4×2 mm magnet |
| Spokes | 6 (`DRUM_SPOKES`) | Stiffness vs. print time |

**Shaft:** 5 mm steel rod. File a **0.5 mm D-flat** (`SHAFT_FLAT`) where the
spool hub grips so the drum can't slip on the shaft. Length ≈ module interior
width + motor coupling + bearing (≈ 55–60 mm per module).

## 3. The motor — 28BYJ-48

| Spec | Value | Source |
|---|---|---|
| Rated voltage | 5 V (also 12 V variant) | Datasheet; Bezek uses 12 V for torque |
| Steps / revolution | 2048 full-step / **4096 half-step** | 64:1 internal gear |
| Step angle | 0.18°/step (output) | |
| Body diameter | 28.25 mm (`MOTOR_BODY_D`) | |
| Centre boss | 9.2 mm ⌀ (`MOTOR_BOSS_D`) | |
| Output shaft | 5 mm, flatted (`MOTOR_SHAFT_D`) | Couples to drum |
| Mount tabs | 35.0 mm centres, M3 (`MOTOR_MOUNT_W`) | |
| Current (moving) | ~0.25 A/module | Drives PSU sizing |

Firmware constant `STEPS_PER_REV = 4096`, half-step 8-phase sequence. Homing each
revolution corrects the ~0.5 % real-world gear error, so exactness isn't needed.
Steps per flap: `4096 / 48 ≈ 85.3`.

## 4. Hall sensor + magnet (homing)

| Item | Value | Note |
|---|---|---|
| Sensor | A3144 (digital, open-collector) | 10 k pull-up; firmware uses INPUT_PULLUP |
| Trigger | Active LOW when magnet present | Polarity-sensitive — flip magnet if it never triggers |
| Magnet | 4 mm ⌀ × 2 mm neodymium | In the spool hub |
| Mount pocket | 12 × 15 mm PCB slot (`HALL_PCB_*`) | Adjust to your breakout |

## 5. Module body

| Dimension | Value |
|---|---|
| Interior width | `FLAP_W + 8` = 50 mm (`MODULE_W`) |
| Front bezel height | 66 mm (`MODULE_H`) |
| Depth (drum + motor stack) | 62 mm (`MODULE_D`) |
| Printed wall | 2.4 mm (`WALL`) |

## 6. Enclosure / bezel tiles

| Dimension | Value | Note |
|---|---|---|
| Module pitch X | `MODULE_W + 2·WALL + 1` = 55.8 mm | Horizontal centre spacing |
| Module pitch Y | `MODULE_H + 3` = 69 mm | Vertical centre spacing |
| Bezel border | 6 mm (`BEZEL`) | Black frame around the array |
| Face thickness | 3.0 mm (`face_t`) | |
| Window (per char) | `FLAP_W-2 × FLAP_H-4` = 40 × 42 mm | Rounded 3 mm corners |
| Acrylic rebate | 2.0 mm deep (`ACRYLIC_T`) | Optional front sheet |
| Panel gap | 0.4 mm (`PANEL_GAP`) | Seam between tiles |
| Full 4×16 face | ≈ 893 × 276 mm | = 16·55.8 + 12 border, tiled |

Tiles are **per-module** and snap together with dovetail edge-clips, so the wall
is 64 identical prints. Nothing here needs to fit the build plate whole.

## 7. Fit tolerances — **(tune these first)**

Print [`../hardware/openscad/fit_test.scad`](../hardware/openscad/fit_test.scad)
(a strip of holes/pins at ±0.05 mm steps) and read off what actually slides vs.
grips on your printer.

| Tolerance | Default | Used for |
|---|---|---|
| `FIT_LOOSE` | 0.30 mm | Rotating/sliding: drum-on-shaft, flap pins in slots |
| `FIT_SNUG` | 0.15 mm | Press/clip: magnet pocket, bearing seat |
| `SHAFT_FLAT` | 0.5 mm | D-flat depth so the drum keys to the shaft |

Reference builds found flap tolerances *critical* — the original author iterated
enclosure kerf from 0.18 mm down to 0.10 mm and added nylon washers to kill
0.5–1.5 mm of motor-shaft axial play. Expect to spend one evening here; it's the
difference between "flips like butter" and "jams every third flap."

## 8. Print settings (Bambu, PLA)

| Setting | Value | Why |
|---|---|---|
| Layer height | 0.20 mm | Good speed/quality; 0.12 mm for flap glyphs if you want crisp text |
| Walls | 3 | Strength on thin spool spokes |
| Infill | 15 % (body) / 100 % (pins) | |
| Supports | Minimal; flaps & bezels print flat | |
| Material | PLA (PETG only if hot/sunny — PLA softens ~50–60 °C) | Bambu material table |
| AMS colors | Black (body/flap) + white (glyph/accent) | The "dual color" |

---

### Quick regeneration

```bash
# render any part after editing params.scad
openscad -o flap.stl        hardware/openscad/module.scad          # edit which module is called
openscad -o bezel_tile.stl  hardware/openscad/enclosure.scad
openscad -D 'FLAP_COUNT=40' -o flap40.stl hardware/openscad/module.scad  # smaller set
```
