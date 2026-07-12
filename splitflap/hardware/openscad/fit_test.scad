// ============================================================
// fit_test.scad — print THIS first.
// A strip of pin/hole pairs at stepped clearances so you can read off
// the exact FIT_LOOSE / FIT_SNUG your Bambu + filament actually produce.
// Print once, try each pin in its hole, pick the clearance that "just
// slides" (-> FIT_LOOSE) and the one that "grips" (-> FIT_SNUG), then set
// those in params.scad. Saves you from re-printing whole spools to tune.
// ============================================================
include <params.scad>

steps      = [0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40];
base_pin_d = FLAP_PIN_D;   // test the flap-pin fit (1.8 mm nominal)
plate_t    = 3;
pitch      = 10;

// row of holes labelled by clearance
module holes() {
    for (i = [0:len(steps)-1]) {
        c = steps[i];
        translate([i*pitch, 0, 0]) difference() {
            cube([pitch-1, pitch-1, plate_t]);
            translate([(pitch-1)/2, (pitch-1)/2, -0.1])
                cylinder(h=plate_t+0.2, d=base_pin_d + 2*c);
        }
    }
}
// matching loose pins you snap out and try
module pins() {
    for (i = [0:len(steps)-1])
        translate([i*pitch, -pitch, 0]) {
            cylinder(h=plate_t+3, d=base_pin_d);
            // little grip tab
            translate([0,0,plate_t+3]) sphere(d=base_pin_d+1.5);
        }
}

holes();
pins();
// Reminder to self after printing:
// FIT_LOOSE = smallest clearance a pin drops through under its own weight.
// FIT_SNUG  = largest clearance a pin needs a firm push to enter.
