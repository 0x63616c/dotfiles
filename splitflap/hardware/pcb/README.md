# Driver Board — Schematic, Netlist & JLCPCB Notes

A small board that drives **6 split-flap modules** and chains to the next board.
Eleven of these cover the 4 × 16 = 64 display. This is the "make 64 motors
tractable" part of the build.

> **Status / honesty:** this directory documents the board as a complete,
> buildable **netlist + schematic description** — enough to lay out in KiCad and
> order. It does **not** yet contain generated Gerbers/`*.kicad_pcb` (those are a
> binary CAD artifact that has to be drawn and, ideally, once-verified on a real
> board before being published as "known good"). Laying it out from the netlist
> below is ~an evening in KiCad; that's Phase 2 of the build. If you'd rather not
> lay out a board at all, the off-the-shelf **ULN2003 breakout per motor** wired
> to the shift-register signals works identically — the board just tidies it.

---

## What it does

- Takes the 3-wire shift chain from the ESP32 (or the previous board) and drives
  **6 × 28BYJ-48** coils via `74HC595 → ULN2003`.
- Reads **6 × A3144** hall sensors back up the chain via `74HC165`.
- Passes the chain on to the next board over a 6-pin ribbon.

## Block diagram

```
 CHAIN-IN (6p)                                            CHAIN-OUT (6p)
 ┌─────────────┐                                          ┌─────────────┐
 │ SER_OUT ────┼──► 595#1 SER  QH'─►595#2 SER QH'─►595#3   │ SER_OUT ◄── 595#3 QH'
 │ SRCLK  ─────┼──► all 595 SRCLK + 165 CLK                │ SRCLK  ◄── (buffered)
 │ RCLK   ─────┼──► all 595 RCLK (latch)                   │ RCLK   ◄──
 │ SER_IN ◄────┼── 165 QH  ◄── (6 hall bits)               │ SER_IN ──► 165 SER (from next)
 │ +5V_LOGIC ──┼──────────────┬───────────────┐            │ +5V_LOGIC ─┤
 │ GND ────────┼──────────────┴───────────────┘            │ GND ───────┤
 └─────────────┘                                          └─────────────┘

 595 outputs → 3× ULN2003 (8ch, use 4 ch each ×6 modules... see mapping)
 ULN2003 outputs → 6× JST-XH-5 (IN1..IN4 + motor V+) → 28BYJ-48
 A3144 × 6 → 6× JST-XH-3 (VCC/GND/OUT) → OUT bits into 74HC165
```

## Component list (per board)

| Ref | Part | Qty | Note |
|---|---|---|---|
| U1–U3 | 74HC595 (DIP-16 or SOIC) | 3 | 24 outputs = 6 modules × 4 coil bits |
| U4–U6 | ULN2003A (DIP-16) | 3 | Coil current sink (8 ch, 4 used ×2 modules per chip if you pack, or 1.5/module) |
| U7 | 74HC165 (DIP-16) | 1 | Parallel-load 6 hall bits → serial |
| J1,J2 | 6-pin ribbon header | 2 | Chain in / out |
| J3–J8 | JST-XH-5 | 6 | Motor pigtails (IN1–4 + V+) |
| J9–J14 | JST-XH-3 | 6 | Hall pigtails (VCC/GND/OUT) |
| Cx | 0.1 µF ceramic | ~5 | One per IC, decoupling |
| Rx | 10 k | 6 | Hall pull-ups (if breakouts lack them) |
| J15 | Screw terminal | 1 | Motor rail V+ / GND in (5 V or 12 V) |

## Netlist (the connections that matter)

**Shift-out (coils):**
- `SER_OUT → U1.SER (pin14)`; `U1.QH' (pin9) → U2.SER`; `U2.QH' → U3.SER`;
  `U3.QH' → CHAIN-OUT.SER_OUT`.
- `SRCLK → U1/U2/U3.SRCLK (pin11)` and `→ U7.CLK (pin2)`.
- `RCLK → U1/U2/U3.RCLK (pin12)`.
- `U1..U3.Qa..Qh` map, in order, to module coil bits: module *m* uses output
  bits `4m..4m+3` → `ULN2003 INx` → `ULN2003 OUTx` → motor IN1..IN4.
  (Firmware `driverSetCoils()` packs exactly this order — 4 bits/module, MSB-first
  byte order, boards shifted high-byte first.)

**Shift-in (halls):**
- `A3144.OUT (×6) → U7 parallel inputs A..F`; `U7.QH (pin9) → SER_IN`;
  `CHAIN-OUT.SER_IN → U7.SER (pin10)` (from the next board's 165).
- `U7.SH/LD (pin1) ← RCLK` (reuse the latch to load), `U7.CLK ← SRCLK`.

**Power:**
- Logic `+5V_LOGIC` → all IC VCC + hall VCC. Motor `V+` (screw terminal) → each
  JST-XH-5 pin 5 only. **Grounds common.** Decouple every IC.

## Firmware contract

The board must present bits in the order the firmware expects:

- **Outputs:** `outBuf` is shifted **high byte first**, and within the stream bit
  `4·module + coil` drives that module's coil. Wire `U3` (last in the out-chain)
  nearest CHAIN-OUT so the first board clocked is the first module.
- **Inputs:** `inBuf` reads module 0 as the first bit out of the 165 chain,
  active-LOW (magnet present = 0). Match the hall wiring order to module order.

If a board's modules come out mirrored/rotated, you either re-order the JST
pinout on the PCB or flip the bit packing in `driverSetCoils()` — pick one and
keep it consistent across all 11 boards.

## JLCPCB order notes

1. Draw it in **KiCad** from the netlist above (2-layer is plenty).
2. Export Gerbers (`*.gbr` + drill) → zip.
3. JLCPCB: 2-layer, 1.6 mm, HASL, min order **5 boards** (~$2 + shipping). One
   order covers your prototype; a second (or a 2× panel) covers all 11.
4. Optional: JLCPCB **assembly** for the SMD variant if you don't want to hand-
   solder — but 74HC595/ULN2003/74HC165 are all DIP-friendly, so through-hole +
   sockets is the beginner-safe route.
5. **Bring up ONE board** driving 6 bench modules with the `board` firmware
   before ordering the rest.
