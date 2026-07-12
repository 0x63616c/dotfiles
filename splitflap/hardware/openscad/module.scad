// ============================================================
// module.scad — the split-flap MECHANISM (parametric starter).
//
// >>> READ THIS FIRST <<<
// A split-flap drum is a tolerance-critical mechanism. This file is a
// fully-parametric STARTING POINT, not a guaranteed print. Plan on 1-2
// test iterations of the spool<->flap fit on YOUR printer/filament
// before a drum flips cleanly. If you want zero iteration, print the
// community-proven module linked in docs/00-build-guide.md and use this
// only to regenerate flaps or resize the set.
//
// Parts (render one at a time, then arrange on the plate):
//   flap();            // x FLAP_COUNT — the cards
//   spool();           // x2 per module (mirror for the second)
//   motor_mount();     // holds the 28BYJ-48
//   sensor_mount();    // holds the hall breakout + defines home
//   side_a(); side_b();// the two body sides that carry the shaft
// ============================================================
include <params.scad>

// ---------- FLAP ----------
// A rectangular card. Two pins on the upper edge ride the spool slots.
// The horizontal centre line is where the physical fold/split sits.
module flap() {
    difference() {
        union() {
            // card body
            linear_extrude(FLAP_T)
                offset(r=1.5) offset(delta=-1.5)
                    square([FLAP_W, FLAP_H], center=true);
            // side pins
            for (s=[-1,1])
                translate([s*(FLAP_W/2), FLAP_H/2 - 3, FLAP_T/2])
                    rotate([0,90,0])
                        cylinder(h=FLAP_PIN_L, d=FLAP_PIN_D, center=(s<0));
        }
        // thin score line at the split so the printed flap folds crisply
        translate([0,0,FLAP_T])
            cube([FLAP_W+2, 0.4, FLAP_T], center=true);
    }
}

// ---------- SPOOL ----------
// A disc with FLAP_COUNT slots around the rim to capture flap pins,
// a keyed shaft bore, and a magnet pocket for homing.
module spool() {
    difference() {
        union() {
            // rim
            linear_extrude(DRUM_WALL) circle(r=DRUM_R);
            // hub
            cylinder(h=8, d=SHAFT_D+6);
            // spokes
            for (i=[0:DRUM_SPOKES-1]) rotate([0,0,i*360/DRUM_SPOKES])
                translate([0,-1.2,0]) cube([DRUM_R, 2.4, DRUM_WALL]);
        }
        // slots for flap pins around the rim
        for (i=[0:FLAP_COUNT-1]) rotate([0,0,i*DRUM_SLOT_PITCH])
            translate([DRUM_R-1.5, 0, -0.1])
                cylinder(h=DRUM_WALL+0.2, d=FLAP_PIN_D + 2*FIT_LOOSE);
        // keyed shaft bore (D-flat)
        translate([0,0,-0.1]) difference() {
            cylinder(h=10, d=SHAFT_D + 2*FIT_LOOSE);
            translate([SHAFT_D/2 - SHAFT_FLAT, -SHAFT_D, 0]) cube([SHAFT_D, 2*SHAFT_D, 20]);
        }
        // magnet pocket in the hub face (homing)
        translate([DRUM_R*0.45, 0, DRUM_WALL - MAGNET_T + 0.01])
            cylinder(h=MAGNET_T+1, d=MAGNET_D + 2*FIT_SNUG);
    }
}

// ---------- MOTOR MOUNT (28BYJ-48) ----------
module motor_mount() {
    difference() {
        cube([MOTOR_BODY_D+2*WALL, MOTOR_BODY_D+2*WALL, WALL], center=true);
        // body clearance
        cylinder(h=WALL*3, d=MOTOR_BODY_D + 2*FIT_LOOSE, center=true);
        // shaft boss
        cylinder(h=WALL*3, d=MOTOR_BOSS_D + 2*FIT_LOOSE, center=true);
        // M3 mount holes
        for (s=[-1,1]) translate([s*MOTOR_MOUNT_W/2, 0, 0])
            cylinder(h=WALL*3, d=MOTOR_M3_D, center=true);
    }
}

// ---------- SENSOR MOUNT ----------
module sensor_mount() {
    difference() {
        cube([HALL_PCB_W+2*WALL, HALL_PCB_H+2*WALL, WALL+4], center=true);
        translate([0,0,2]) cube([HALL_PCB_W+2*FIT_LOOSE, HALL_PCB_H+2*FIT_LOOSE, 6], center=true);
    }
}

// ---------- BODY SIDES ----------
// Two plates that sandwich the drum, carry the shaft, motor and sensor.
module side_a() { _side(mirror_motor=false); }
module side_b() { _side(mirror_motor=true); }
module _side(mirror_motor) {
    difference() {
        // plate
        linear_extrude(WALL)
            offset(r=3) offset(delta=-3)
                square([MODULE_D, MODULE_H], center=true);
        // shaft bore (or bearing seat)
        translate([-MODULE_D/2 + DRUM_R + 4, 0, 0])
            cylinder(h=WALL*3, d = (mirror_motor ? BEARING_OD+2*FIT_SNUG : SHAFT_D+2*FIT_LOOSE), center=true);
    }
    // motor boss on side_b
    if (mirror_motor)
        translate([-MODULE_D/2 + DRUM_R + 4, 0, WALL])
            difference() {
                cylinder(h=6, d=MOTOR_BOSS_D+2*WALL);
                cylinder(h=20, d=MOTOR_SHAFT_D+2*FIT_LOOSE, center=true);
            }
}

// ---- pick ONE to render / export as STL ----
flap();
// spool();
// motor_mount();
// sensor_mount();
// side_a();
// side_b();
