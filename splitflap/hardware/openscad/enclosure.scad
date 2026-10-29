// ============================================================
// enclosure.scad — the black, fully-enclosed modular frame.
//
// Prints as TILES: one bezel tile per module (or per small cluster),
// so a 4x16 wall is an array of identical tiles that clip together.
// This keeps every part inside a Bambu A1/P1/X1 build volume and makes
// the design "modular" — add columns by printing more tiles.
//
// Render one tile:            enclosure_tile();
// Preview a 4x16 wall:        wall_preview();
// Dual color: the FACE is one filament (black), the ACCENT inlay a
// second (set ACCENT=true and slice with a filament change / AMS).
// ============================================================
include <params.scad>

ACCENT       = false;   // true -> render only the accent inlay body for a 2-color slice
TILE_COLS    = 1;       // modules per tile horizontally (1 = fully modular)
TILE_ROWS    = 1;       // modules per tile vertically

tile_w = TILE_COLS * MODULE_PITCH_X + 2*BEZEL;
tile_h = TILE_ROWS * MODULE_PITCH_Y + 2*BEZEL;
face_t = 3.0;           // thickness of the front bezel plate

// A single window cut-out for the flaps to show through.
module window_cut() {
    // rounded rectangle window
    r = 3;
    hull() for (sx=[-1,1], sy=[-1,1])
        translate([sx*(WINDOW_W/2 - r), sy*(WINDOW_H/2 - r), 0])
            cylinder(h = face_t*3, r = r, center=true);
}

// The recessed shelf that holds the optional acrylic sheet.
module acrylic_rebate() {
    translate([0,0, face_t - ACRYLIC_T])
        cube([WINDOW_W+6, WINDOW_H+6, ACRYLIC_T*2], center=true);
}

// Clip features so neighbouring tiles snap together (dovetail rails).
module edge_clips(w, h) {
    clip = 4;
    // right-edge male dovetail
    translate([w/2, 0, -6]) rotate([0,0,0])
        linear_extrude(6) polygon([[0,-clip],[clip,-clip*1.6],[clip,clip*1.6],[0,clip]]);
    // left-edge female pocket
    translate([-w/2 - clip - FIT_LOOSE, 0, -6])
        linear_extrude(6+0.1) offset(delta=FIT_LOOSE)
            polygon([[0,-clip],[clip,-clip*1.6],[clip,clip*1.6],[0,clip]]);
}

module bezel_face() {
    difference() {
        // front plate
        translate([0,0,0])
            linear_extrude(face_t)
                offset(r=2) offset(delta=-2)
                    square([tile_w, tile_h], center=true);
        // windows per module
        for (cx = [0:TILE_COLS-1], cy = [0:TILE_ROWS-1]) {
            x = (cx - (TILE_COLS-1)/2) * MODULE_PITCH_X;
            y = (cy - (TILE_ROWS-1)/2) * MODULE_PITCH_Y;
            translate([x, y, 0]) window_cut();
            translate([x, y, 0]) acrylic_rebate();
        }
    }
}

// A shallow accent groove around each window — printed in filament #2.
module accent_inlay() {
    for (cx = [0:TILE_COLS-1], cy = [0:TILE_ROWS-1]) {
        x = (cx - (TILE_COLS-1)/2) * MODULE_PITCH_X;
        y = (cy - (TILE_ROWS-1)/2) * MODULE_PITCH_Y;
        translate([x, y, face_t-0.6])
            linear_extrude(0.6)
                difference() {
                    offset(r=2.4) window2d();
                    offset(r=0.8) window2d();
                }
    }
}
module window2d() {
    r=3; offset(r=r) offset(delta=-r) square([WINDOW_W, WINDOW_H], center=true);
}

// Side walls that turn the bezel into a fully-enclosed box shell.
module shell_walls() {
    difference() {
        translate([0,0,-MODULE_D/2])
            linear_extrude(MODULE_D)
                difference() {
                    square([tile_w, tile_h], center=true);
                    square([tile_w-2*WALL, tile_h-2*WALL], center=true);
                }
        // cable pass-throughs on the bottom wall
        translate([0,-tile_h/2, -MODULE_D/2 + 8])
            rotate([90,0,0]) cylinder(h=WALL*3, d=10, center=true);
    }
}

module enclosure_tile() {
    if (ACCENT) {
        accent_inlay();
    } else {
        union() {
            bezel_face();
            translate([0,0,-0.01]) shell_walls();
            edge_clips(tile_w, tile_h);
        }
    }
}

module wall_preview() {
    for (cx=[0:COLS-1], cy=[0:ROWS-1])
        translate([cx*(MODULE_PITCH_X), -cy*(MODULE_PITCH_Y), 0])
            color(cy%2 ? "#111" : "#161616") enclosure_tile();
}

enclosure_tile();
