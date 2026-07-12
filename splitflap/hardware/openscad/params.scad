// ============================================================
// params.scad — every tunable dimension for the split-flap build.
// Units: millimetres. Import this from module.scad / enclosure.scad.
//
// The three numbers you actually tune for YOUR printer are the
// *_CLEARANCE values near the bottom. Everything else is geometry.
// ============================================================

// ---- character / flap geometry ----
FLAP_COUNT      = 48;      // flaps on the drum (matches charset.json)
FLAP_W          = 42;      // printed flap width  (visible glyph area a touch narrower)
FLAP_H          = 46;      // printed flap height (top+bottom halves together)
FLAP_T          = 0.6;     // flap material thickness (0.5mm PET / sticker card)
FLAP_PIN_D      = 1.8;     // diameter of the two side pins that ride the drum slots
FLAP_PIN_L      = 2.2;     // how far each pin sticks out per side

// ---- drum (the two slotted spools the flaps clip into) ----
// Radius is derived so FLAP_COUNT flaps sit evenly around the circle.
DRUM_SLOT_PITCH = 360 / FLAP_COUNT;          // angular pitch between flaps (deg)
DRUM_R          = (FLAP_H/2) / sin(DRUM_SLOT_PITCH/2) * 0.86; // pack radius
DRUM_WALL       = 2.0;
DRUM_SPOKES     = 6;
SHAFT_D         = 5.0;     // 5 mm steel rod through the drum
SHAFT_FLAT      = 0.5;     // D-flat depth so the drum keys to a filed shaft

// ---- module body ----
MODULE_W        = FLAP_W + 8;    // interior width (flap + side walls clearance)
MODULE_H        = 66;            // front bezel height of one unit
MODULE_D        = 62;            // depth front-to-back (drum + motor stack)
WALL            = 2.4;           // printed wall thickness of the module body

// ---- motor: 28BYJ-48 + ULN2003 ----
MOTOR_BODY_D    = 28.25;   // stepper body diameter
MOTOR_BOSS_D    = 9.2;     // centre boss around the shaft
MOTOR_SHAFT_D   = 5.0;     // 5 mm flatted output shaft (couples to drum)
MOTOR_MOUNT_W   = 35.0;    // centre-to-centre of the two M3 mount tabs
MOTOR_TAB_H     = 7.0;
MOTOR_M3_D      = 3.2;

// ---- hall sensor + home magnet ----
HALL_PCB_W      = 12.0;    // small hall-sensor breakout footprint
HALL_PCB_H      = 15.0;
MAGNET_D        = 4.0;     // 4x2 mm neodymium disc pressed into the drum hub
MAGNET_T        = 2.0;

// ---- front acrylic window (optional clean face) ----
ACRYLIC_T       = 2.0;
WINDOW_W        = FLAP_W - 2;
WINDOW_H        = FLAP_H - 4;

// ---- enclosure grid ----
ROWS            = 4;
COLS            = 16;
MODULE_PITCH_X  = MODULE_W + 2*WALL + 1.0;   // horizontal centre spacing
MODULE_PITCH_Y  = MODULE_H + 3.0;            // vertical centre spacing
BEZEL           = 6;       // black frame border around the whole array
PANEL_GAP       = 0.4;     // gap between neighbouring bezels (dual-color seam)

// ---- print tolerances (TUNE THESE for your Bambu + filament) ----
// Print hardware/openscad/fit_test.scad first and dial these in.
FIT_LOOSE       = 0.30;    // rotating / sliding fits (drum on shaft holder)
FIT_SNUG        = 0.15;    // press / clip fits (flap pins, bearing seats)
BEARING_OD      = 16.0;    // 608 bearing OD (optional, for a smoother drum)
BEARING_ID      = 8.0;
BEARING_T       = 7.0;

$fn = 64;
