# Electronics — Wiring, Driver Chain & Power

Everything electrical, from the 5-wire breadboard for module #1 to the
shift-register chain and power budget for 64.

---

## 1. Module #1 — direct to ESP32 (bring-up)

No PCB. This matches the `bringup` firmware profile (`DRIVER_DIRECT_GPIO`).

```
ESP32 GPIO16 ─► ULN2003 IN1 ┐
ESP32 GPIO17 ─► ULN2003 IN2 ├─► 28BYJ-48 coils
ESP32 GPIO18 ─► ULN2003 IN3 │
ESP32 GPIO19 ─► ULN2003 IN4 ┘
5 V supply + ─► ULN2003 motor V+     (NOT the ESP32 3V3/5V pin)
5 V supply – ─► ULN2003 GND ─┬─ ESP32 GND      (common ground is essential)
A3144  VCC ─► 3V3            │
A3144  GND ─► GND ───────────┘
A3144  OUT ─► GPIO21         (firmware enables INPUT_PULLUP; add 10 k if your
                              breakout has no pull-up)
```

Pins are set at the top of `firmware/splitflap-esp32/src/main.cpp`
(`COIL_PINS`, `HALL_PIN`) — change them if these clash with your board's
strapping pins.

> **Golden rule:** motor current never flows through the ESP32. The ESP32 only
> sends logic-level signals to the ULN2003, which switches the motor rail.

---

## 2. Scaling: why a shift-register chain

| Approach | Modules | Verdict |
|---|---|---|
| ESP32 GPIO direct | ≤ ~5 (out of ~25 usable pins ÷ 4) | Fine for 1, hopeless for 64 |
| MCP23017 I²C expanders | 8/bus × 4 modules = 32/bus | Works (proven), but slower, needs ≥2 buses + a mux for 64 |
| **74HC595/165 shift chain** | **100+** | Reference "Chainlink" pattern; what this build uses |

The chain needs just **3 output signals** (data, clock, latch) from the ESP32
regardless of module count, plus **1 input** (the returning hall data). Everything
else is daisy-chained.

---

## 3. The driver board (6 modules each)

One board per 6 modules → **11 boards** for 64. Matches `board` firmware profile
(`DRIVER_SHIFT_CHAIN`).

```
        ┌────────────────── Driver board (×11) ──────────────────┐
 chain  │  74HC595 ─► 74HC595 ─► 74HC595   (24 outputs = 6×4 coils)│  chain
 in ───►│     │          │          │                             ├──► out
 (SPI)  │     ▼          ▼          ▼                             │  (to next)
        │  ULN2003    ULN2003    ULN2003   ─► 6× JST → 28BYJ-48    │
        │                                                          │
        │  74HC165  ◄─ 6× hall inputs (JST) ◄── A3144 × 6          │
        └──────────────────────────────────────────────────────────┘
 Ribbon carries: SER_OUT, SRCLK, RCLK (595 latch), SER_IN (165), +5V_logic, GND
```

**ESP32 → chain wiring**

| ESP32 pin | Signal | Goes to |
|---|---|---|
| GPIO13 | `OUT_DATA` (SER) | first 74HC595 SER |
| GPIO14 | `OUT_CLK` (SRCLK) | all 595 + 165 shift clock |
| GPIO27 | `OUT_LATCH` (RCLK) | all 595 storage latch |
| GPIO34 | `IN_DATA` | 74HC165 QH (returning) |
| GPIO26 | `IN_CLK` | 165 clock (can share OUT_CLK) |
| GPIO25 | `IN_LATCH` | 165 shift/load |

These are the defaults in `main.cpp` under `DRIVER_SHIFT_CHAIN`. The firmware
packs 4 coil bits per module into the 595 stream and reads 1 hall bit per module
back from the 165 stream, in module order.

**Board bring-up order:** populate + test **one** board driving 6 bench modules
before you order the other 10. JLCPCB min order is 5 boards, so one order covers
your prototype; a second covers the build.

See [`../hardware/pcb/README.md`](../hardware/pcb/README.md) for the schematic
netlist, KiCad starting point, and JLCPCB Gerber/order notes.

---

## 4. Power budget

Verified figure: **~0.25 A per module while moving.**

| Build | Motor rail | PSU | Notes |
|---|---|---|---|
| 1 module | 5 V, <0.3 A | USB / any 5 V 1 A | Trivial |
| 4×16 = 64, 5 V motors | 5 V, up to ~16 A worst case | **5 V / 30 A** (~$25) | Inject 5 V at ~3 points; 5 V sags over long runs |
| 4×16 = 64, 12 V motors | 12 V, up to ~5.5 A worst case | **12 V / 20 A** (~$28) | Lower current = easier wiring; Bezek's choice |

Worst case = all 64 moving simultaneously. Real average is much lower because:

- The firmware **releases coils** the instant a module reaches its target (the
  28BYJ-48's 64:1 gearing holds position with zero holding current).
- You can **stagger homing** on boot rather than spinning all 64 at once.

Still, **size the supply for worst case** and add an inline **fuse** on the motor
rail. Keep the **logic rail separate**: run the ESP32 + shift registers off a
small clean 5 V (a buck from the 12 V rail, or a second 5 V/2 A brick). Tie all
grounds together at one star point.

**Wiring gauge:** for a 5 V/16 A rail use ≥16 AWG for the trunk and inject power
into the chain in 2–3 places so no single ribbon segment carries all 16 A.

---

## 5. Custom PCB — is it worth it?

**Yes, for the driver boards.** Hand-wiring 64 motors × (4 coils + power) + 64
hall sensors is hundreds of solder joints and a debugging nightmare. Eleven small
boards with JST connectors turn it into "plug in a pigtail." At ~$6/board it's
~$66 — cheap insurance for the whole build.

**Not per-module** (Path A). A per-module PCB only pays off if you go the OpenFlap
route (DC motor + optical encoder + per-module MCU), which is a different, more
advanced project. For steppers, the off-the-shelf ULN2003 board on a $1.50 motor
is already the cheapest possible per-module driver — the shared driver board just
tidies the wiring to it, or replaces it with an on-board ULN2003 to save the
per-motor breakout cost at scale.

**JLCPCB reality:** 5 boards from ~$2 + shipping; add SMD assembly for a few
dollars if you don't want to solder 74HC595s by hand (they're through-hole
friendly too). Export Gerbers from the KiCad project in `../hardware/pcb/`.
