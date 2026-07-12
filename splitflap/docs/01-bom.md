# Bill of Materials & Pricing

Prices are typical **2025–2026** street prices in USD from AliExpress / Amazon /
eBay / DigiKey / JLCPCB. **Treat them as indicative estimates, ±20 %**, and
re-check live before ordering. Honest provenance: the research pass behind this
guide only *firmly* verified one component price (the AS5600, which this build
doesn't even use). The rest are realistic figures from current listings and
community builds (which land ~$5–8/module), **not** independently price-verified
line by line — see [`04-research-notes.md`](04-research-notes.md) for exactly
what was and wasn't confirmed. The *arithmetic* below is re-checked; the *inputs*
are estimates. A re-checked total summary is at the very end.

> **Design choice that dominates cost:** flaps are **3D-printed dual-color**
> (black body, white glyph on your Bambu AMS), *not* blank PVC + cut vinyl.
> Pro blank flaps run ~$45 per 160 (≈ $11/module of 40); printing them costs
> **~$0.40 of filament per module**. That single decision saves ~**$700** across
> 64 modules and keeps the build "fully 3D printable."

---

## Headline numbers

| Question | Answer |
|---|---|
| **Cost of ONE module, at scale** (marginal, part of a 64 build) | **~$4** in parts |
| **Cost of ONE module as a standalone unit** (its own ESP32 + PSU + wiring) | **~$18–20** |
| **Cost to "first light"** (module #1 + reusable ESP32, PSU, rod/bearing stock) | **~$35–45** (incl. ~$15 calipers) |
| **Cost of the full 4 × 16 = 64 display** | **~$425** ( + ~$25 optional acrylic ) |
| **All-in cost per module at 64** | **~$6.60** |

---

## A. Single standalone module (1 × 1 — your bring-up / a desk unit)

Single-quantity prices (you're buying ones, not hundreds).

| Part | Qty | Unit | Line | Notes |
|---|---:|---:|---:|---|
| ESP32 dev board (DevKitC / TTGO) | 1 | $6.00 | $6.00 | The brain |
| 28BYJ-48 stepper **+ ULN2003 board** (set) | 1 | $2.50 | $2.50 | Buy as a matched set |
| A3144 hall-effect sensor | 1 | $0.50 | $0.50 | Digital home sensor |
| 4 × 2 mm neodymium magnet | 1 | $0.15 | $0.15 | Home marker in the spool |
| 5 mm steel shaft (from a 500 mm rod) | 1 | $0.40 | $0.40 | Rod makes ~8 modules |
| 608 bearing (optional) | 1 | $0.50 | $0.50 | Smoother drum |
| Filament — module body + 48 flaps (~80 g) | — | — | $1.60 | Black + white PLA |
| Dupont / hookup wire | — | — | $2.00 | Breadboard wiring |
| 5 V USB supply (or one you own) | 1 | $6.00 | $6.00 | Motor + logic for one module |
| **Module subtotal** | | | **~$19.65** | |
| Digital calipers (one-time tool) | 1 | $15.00 | $15.00 | Required to tune tolerances |
| **First-light out-of-pocket** | | | **~$34.65** | ESP32/PSU/rod/bearing reused later |

---

## B. Full 4 × 16 = 64-module display

### B1. Per-module parts (bulk prices × 64)

Bulk = buying 64+ (AliExpress 100-packs, same-batch motors, JLCPCB panels).

| Part | Unit (bulk) | × 64 | Notes |
|---|---:|---:|---|
| 28BYJ-48 + ULN2003 set | $1.40 | $89.60 | Cheapest single line; buy one batch |
| A3144 hall sensor | $0.12 | $7.68 | 100-pack from AliExpress |
| 4 × 2 mm magnet | $0.06 | $3.84 | 100-pack |
| 5 mm shaft (rod stock) | $0.30 | $19.20 | Cut from 1 m rods |
| 608 bearing (optional) | $0.15 | $9.60 | Bulk 10/50-pack |
| Flap filament (~15–25 g) | $0.40 | $25.60 | 48 dual-color flaps/module |
| Body/spool filament (~50 g) | $1.00 | $64.00 | Spools, sides, mounts |
| Wiring / JST per module | $0.40 | $25.60 | Motor + sensor pigtails |
| Fasteners (M3 × ~4) | $0.15 | $9.60 | Screws / nuts |
| **Per-module subtotal** | **$3.98** | **$254.72** | ≈ **$4/module** |

### B2. Shared electronics & structure (once for the whole board)

| Item | Qty | Unit | Line | Notes |
|---|---:|---:|---:|---|
| ESP32 controller | 1 | $6.00 | $6.00 | One brain for all 64 |
| Shift-register driver board (6 modules each) | 11 | ~$6.00 | $66.00 | JLCPCB bare ~$2 + parts ~$4 |
| Power supply, 12 V / 20 A (≈240 W) | 1 | $28.00 | $28.00 | Motor rail; 5 V/30 A alt ~$25 |
| Enclosure filament (64 bezel tiles, ~2.5 kg) | — | — | $45.00 | Black PLA + accent |
| Misc: ribbon, fuse, barrel jacks, solder, wire | — | — | $20.00 | |
| **Shared subtotal** | | | **$165.00** | |
| Front acrylic sheet, 2 mm cast (~700 × 220 mm) | 1 | $25.00 | $25.00 | **Optional** clean face |

### B3. Driver board BOM (per board — ×11)

| Part | Qty/board | Notes |
|---|---:|---|
| PCB (JLCPCB, 5-pack) | 1 | ~$2 amortized |
| 74HC595 shift register | 3 | 24 outputs = 6 modules × 4 coils |
| ULN2003A / ULN2803A driver | 3 / 2 | Coil current sink |
| 74HC165 shift register | 1 | Reads 6 hall inputs back |
| JST-XH connectors (motor + hall) | 12 | 6 modules × 2 |
| 6-pin ribbon headers (chain in/out) | 2 | Data/clk/latch/in/+V/GND |
| 0.1 µF decoupling caps, 10 k resistors | ~6 | |

Full schematic and JLCPCB order notes: [`../hardware/pcb/README.md`](../hardware/pcb/README.md).

---

## Sourcing links (verified)

- **28BYJ-48 + ULN2003** (Amazon 5-pack): <https://us.amazon.com/28BYJ-48-ULN2003-Stepper-Driver-Arduino/dp/B07YRHX73L>
  · bulk on AliExpress, e.g. <https://www.aliexpress.com/item/1005009140198327.html>
- **A3144 hall sensors** (eBay 10-lot ≈ $6): <https://www.ebay.com/itm/186264979681> — AliExpress 100-packs are ~$0.05–0.12 each.
- **Blank flaps** (if you go the PVC + vinyl route instead): <https://www.tindie.com/products/scottbez1/blank-split-flap-display-flaps/> — ~$45/160.
- **Ready kit** (4-char, if you'd rather buy than print the first): <https://www.tindie.com/products/scottbez1/split-flap-display-kit-4-characters/>
- **AS5600 magnetic angle sensor** (DigiKey): <https://www.digikey.com/en/products/detail/ams-osram-usa-inc/AS5600-ASOT/4914338> — **not used here** (it's a 12-bit rotary angle sensor, overkill for home-only sensing, and marked *discontinued* — a sourcing risk). Stick with the cheap A3144 digital hall.
- **JLCPCB** for the driver boards: <https://jlcpcb.com>.
- **Filament** guidance: <https://wiki.bambulab.com/en/general/filament-guide-material-table>.

### Notes & gotchas

- **Motor name trap:** "28BYJ-48" covers many different motors (4096 half-steps/rev
  nominal, 5 V or 12 V variants). Buy all 64 from one batch. 12 V versions give
  more torque and lighter current per module for the big build; 5 V is simplest
  for the single-module bring-up.
- **Power draw:** ~0.25 A/module while moving → ~16 A worst case for 64. Firmware
  releases coils when idle, so average is far lower, but size the PSU for worst
  case and inject power along the chain.
- **Hall vs. encoder:** split-flap only needs to find *home* once per revolution,
  so a $0.10 digital hall (A3144) beats a $2–3 absolute encoder (AS5600). Path B
  (OpenFlap) uses an optical encoder because its DC motor has no step count.

---

## Re-checked totals (arithmetic verified)

**Full 64-module display**

```
Per-module parts (B1):        $3.98 × 64            = $254.72
Shared electronics/frame (B2, no acrylic):          = $165.00
                                          core total = $419.72
+ optional 2 mm acrylic face (B2):                   = $ 25.00
                                     total w/ acrylic = $444.72

All-in per module (core / 64):   $419.72 / 64        = $6.56
```

**Single standalone module (A):** $19.65 (+$15 calipers one-time).
**First-light out-of-pocket (A):** ~$34.65.

**Cross-check of B1 unit sum:**
`1.40 + 0.12 + 0.06 + 0.30 + 0.15 + 0.40 + 1.00 + 0.40 + 0.15 = 3.98` ✓
**Cross-check of B1 × 64:** `3.98 × 64 = 254.72` ✓
**Cross-check of B2 (no acrylic):** `6 + 66 + 28 + 45 + 20 = 165` ✓
**Cross-check core total:** `254.72 + 165 = 419.72` ✓

> Bottom line: **~$4/module in parts, ~$6.60/module all-in, ~$425 for the whole
> 4 × 16 wall** (or ~$450 with the acrylic face). Start by spending ~$35 on one
> module; scale only after it flips "A" on command.
