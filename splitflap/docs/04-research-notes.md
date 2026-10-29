# Research Notes & Sources (verified)

This appendix records what the build decisions in this repo are grounded in. It
comes from a fan-out deep-research pass: 5 search angles → 20 sources fetched →
73 claims extracted → 25 top claims adversarially verified (3 independent votes
each). **24 confirmed, 1 refuted.** Where the evidence was thin, this doc says so
plainly — that honesty is the point of the appendix.

## Confirmed findings (each 3-0 verified)

1. **Scott Bezek `splitflap` is the leading open-source reference, Apache-2.0.**
   Full mechanical (OpenSCAD), PCB (KiCad), and firmware (Arduino/C++) source on
   GitHub; free to use, modify, and sell.
   — <https://github.com/scottbez1/splitflap> ·
   <https://github.com/scottbez1/splitflap/blob/master/README.md>

2. **The "Chainlink" driver scales to 64.** Each Chainlink Driver board drives
   **6 modules**; boards chain to **100+** from a single ESP32 (TTGO T-Display on
   a Chainlink Buddy, only ~4 GPIO). A real build used 18 boards for 108 modules;
   **64 needs ~11 boards.** Chainlink uses MIC5842 shift-register drivers + a
   74HC165 to read halls — i.e. the same shift-in/shift-out pattern this repo's
   driver board and firmware use (with 74HC595 + ULN2003 as the discrete
   equivalent).
   — <https://github.com/scottbez1/splitflap/wiki/Electronics> ·
   <https://github.com/scottbez1/splitflap/blob/master/docs/v2/OrderingComplete.md>

3. **Motor: 12 V 28BYJ-48 + ULN2003A-style driver.** The **12 V** variant is
   specified (not the common 5 V). Sourcing is a documented pitfall — many
   different motors ship under the "28BYJ-48" name; buy vetted/matched ones.
   *(This is why the guide recommends 12 V for the 64-build and buying all from
   one batch; 5 V is fine for the single-module bring-up.)*

4. **Homing: one hall sensor + 4 mm magnet per module.** Bezek's recommended
   parts are **HX6286 (LCSC C495736)** or **AH3391Q**; the `jp112sdl` fork and
   the wider ecosystem use the cheap **A3144** (what this guide's BOM lists).
   Firmware auto-calibrates at startup and re-homes on drift — matching this
   repo's per-revolution homing.

5. **Flap count sets the character set.** Bezek: **40** (original, still
   supported) or **52** ("Epilogue" printed-flap set, stable 2025-01-19) for a
   bigger glyph/symbol set. This build uses **48** (from the MakerWorld extended
   charset). ⚠️ **No source confirmed a stock flap set that simultaneously
   includes all four currencies `$ £ ¥ €`** — glyph assignment is a design
   choice, which is exactly why `charset.json` is canonical here and the flap
   sheet is generated to match.

6. **Ready alternative: `jp112sdl/SplitFlap` fork.** 45 flaps (adds German
   chars), 28BYJ-48 + bundled ULN2003 + **A3144** halls, up to 12 modules per
   Arduino Mega2560 PRO MINI. Same electronics family as this guide.
   — <https://github.com/jp112sdl/SplitFlap>

7. **Alt architecture: OpenFlap (Path B).** Geared DC motor (60 rpm @ 12 V) + a
   6-bit optical encoder, modules that stack/chain and **self-address**. Elegant
   and fully 3D-printable but a per-module SMD build.
   — <https://hackaday.io/project/185107-openflap> ·
   <https://github.com/ToonVanEyck/OpenFlap>

8. **Only firmly-verified price: AS5600** (DigiKey, 2026): $3.09 @1, $1.91 @100,
   $1.85 @250. Noted here precisely because it's the *one* confirmed price — and
   because this build **deliberately does not use it** (it's an absolute-angle
   encoder, overkill for home-only sensing; a $0.10 A3144 digital hall is right).
   — <https://www.digikey.com/en/products/detail/ams-osram-usa-inc/AS5600-ASOT/4914338>

## Refuted (did NOT survive verification)

- ✗ *"Bezek's design is driven by an Arduino."* The current recommended
  controller is an **ESP32** (Arduino was the older prototyping path). 1-2 vote.
  — source that made the claim: ponoko.com blog (secondary).

## Honest caveats (straight from the research)

- **Pricing is largely unverified.** The research could only *firmly* confirm the
  AS5600 price. **The BOM figures in [`01-bom.md`](01-bom.md) for the 28BYJ-48 +
  ULN2003, ESP32, halls, magnets, PCBs and the per-unit / 64-unit totals are
  indicative estimates from typical current listings — treat them as ±20 % and
  re-check live prices before ordering.** They're realistic (and consistent with
  community builds landing ~$5–8/module), but they are not independently
  price-verified line by line.
- **Currency-symbol set** is user-configurable; no stock set is proven to carry
  all four currencies at once. Generate a matching flap sheet (MakerWorld 1309545).
- **Sensor part** — HX6286/AH3391Q are Bezek's picks; A3144 is the cheap, common,
  ecosystem-proven equivalent used here.
- **Not deeply sourced in this pass** (design decisions in this repo lean on the
  linked proven projects + engineering judgement rather than a verified citation):
  exact Bambu AMS tolerances, PLA-vs-PETG for the drum, drum/spool clearances,
  and the ESP32 firmware/web path — this repo *provides* the last one directly.

## Open questions worth a follow-up

1. Live, verified bulk pricing for 12 V 28BYJ-48+ULN2003, ESP32/TTGO, halls,
   magnets, and JLCPCB Chainlink fab/assembly → firm per-module and 64-total cost.
2. Confirmed Bambu AMS print params + drum/spool clearances for reliable flipping.
3. A stock 52/48-flap mapping that includes `$ £ ¥ €` + A-Z + 0-9 + punctuation.

## All sources fetched

Primary: scottbez1/splitflap (repo, README, Electronics wiki, OrderingComplete),
Tindie kit + blank-flaps, jp112sdl/SplitFlap, OpenFlap (hackaday.io + GitHub),
DigiKey AS5600. Secondary/blog: partsnotincluded.com, randomnerdtutorials.com,
ponoko.com, Raspberry Pi forums (MCP23017 discussion). Lower-confidence:
makerworld model pages, grokipedia, AliExpress/eBay listings (used for
ballpark pricing only). Full URL list is in
[`00-build-guide.md`](00-build-guide.md#11-references-all-verified) and
[`01-bom.md`](01-bom.md).
