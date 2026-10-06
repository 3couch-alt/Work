// Clamp-on desk organizer: keys cup, wallet pocket and tilted phone slot.
// Clamps to a desk edge with a printed screw + nut (no hardware needed).
//
// Requires the BOSL2 library (https://github.com/BelfrySCAD/BOSL2) for the threads.
// Export one part at a time:  openscad -D 'part="body"' -o body.stl desk_organizer.scad
// Parts: "body", "screw", "nut", "assembly" (preview only, not for printing).
//
// Coordinates while in use: desk top surface is Z=0, the desk edge is Y=0 and the desk
// is on the -Y side. X runs along the desk edge, front (nearest you) at X=0.

include <BOSL2/std.scad>
include <BOSL2/threading.scad>

/* [Which part] */
part = "assembly";        // [body, screw, nut, assembly]
mount_side = "left";      // [left, right] side of the desk, as you sit at it

/* [Desk] */
desk_max = 40;            // thickest desk the clamp fits (mm). Thinnest is about 9 mm.
jaw_depth = 55;           // how far the clamp reaches onto / under the desk

/* [Pockets] */
pocket_len = 92;          // inside length, measured outward from the desk
keys_w = 30;              // keys cup width
keys_depth = 40;
wallet_w = 32;            // fits a bifold wallet up to ~28 mm thick
wallet_depth = 60;
phone_slot = 15;          // gap for phone + case thickness
phone_depth = 55;
phone_tilt = 12;          // degrees the phone leans back
cable_hole = true;        // charging-cable hole under the phone

/* [Structure] */
wall = 2.4;
floor_t = 2.4;
spine = 8;                // wall that sits against the desk edge
top_above_desk = 25;      // how far the organizer rises above the desk top
top_jaw_t = 10;
bottom_jaw_t = 18;
bottom_jaw_w = 56;        // lower jaw only needs to hold the nut
corner_r = 4;

/* [Screw] */
screw_d = 16;
screw_pitch = 3;
screw_len = 55;
nut_af = 26;              // nut size across flats
nut_h = 12;
thread_slop = 0.15;       // extra clearance in the nut thread; raise if too tight
knob_d = 40;
knob_h = 12;

$fa = 2;
$fs = 0.4;

gap = desk_max + 6;                      // 6 mm fillet sits in the lower inside corner
z_top = top_above_desk;
z_bot = -(gap + bottom_jaw_t);
height = z_top - z_bot;
y_out = spine + pocket_len + wall;

x_keys = wall;
x_wallet = x_keys + keys_w + wall;
x_phone = x_wallet + wallet_w + wall;

// Phone slot: a slab phone_slot thick, leaning back by phone_tilt.
// zb is the front-bottom corner; the slot is phone_depth deep at its centre.
zb = z_top - phone_depth + phone_slot / 2 * sin(phone_tilt);
phone_span = phone_slot / cos(phone_tilt) + (z_top - zb) * tan(phone_tilt);
z_phone_low = zb - phone_slot * sin(phone_tilt);

width = x_phone + phone_span + wall;
screw_y = -jaw_depth / 2 - 3;

module bin_shell() {
    hull()
        for (x = [corner_r, width - corner_r], z = [z_bot + corner_r, z_top - corner_r])
            translate([x, 0, z]) rotate([-90, 0, 0]) cylinder(r = corner_r, h = y_out);
}

module jaw(z0, t, w) {
    r = t / 2;
    translate([(width - w) / 2, 0, 0])
        hull() {
            translate([0, -jaw_depth + r, z0]) cube([w, jaw_depth - r + spine, t]);
            translate([0, -jaw_depth + r, z0 + r]) rotate([0, 90, 0]) cylinder(r = r, h = w);
        }
}

// Right-triangle fillet in the Y-Z plane, w wide and centred along X.
module fillet(y0, z0, dy, dz, w) {
    translate([(width + w) / 2, 0, 0]) rotate([0, -90, 0])
        linear_extrude(w)
            polygon([[z0, y0], [z0 + dz, y0], [z0, y0 + dy]]);
}

module phone_slot_cut() {
    up = [sin(phone_tilt), cos(phone_tilt)];
    b1 = [x_phone, zb];
    b2 = [x_phone + phone_slot * cos(phone_tilt), zb - phone_slot * sin(phone_tilt)];
    long = 200;
    translate([0, spine + pocket_len, 0]) rotate([90, 0, 0])
        linear_extrude(pocket_len)
            polygon([b1, b2, b2 + long * up, b1 + long * up]);
}

module pocket(x, w, depth) {
    floor_z = z_top - depth;
    translate([x, spine, floor_z]) cube([w, pocket_len, depth + 1]);
    // open-bottom cavity under the floor saves plastic and print time
    translate([x, spine, z_bot - 1]) cube([w, pocket_len, floor_z - floor_t - z_bot + 1]);
}

module teardrop2d(d) {
    // points toward -Y, which is "up" in the print orientation
    hull() {
        circle(d = d);
        translate([0, -d / 2 * sqrt(2)]) square(0.01, center = true);
    }
}

module body_in_use() {
    difference() {
        union() {
            bin_shell();
            jaw(0, top_jaw_t, width);
            jaw(z_bot, bottom_jaw_t, bottom_jaw_w);
            fillet(0, top_jaw_t, -10, 10, width);        // brace between the top jaw and the bin wall
            fillet(0, -gap, -6, 6, bottom_jaw_w);        // inside lower corner of the clamp
        }
        pocket(x_keys, keys_w, keys_depth);
        pocket(x_wallet, wallet_w, wallet_depth);
        phone_slot_cut();
        // cavity under the phone slot
        translate([x_phone, spine, z_bot - 1])
            cube([phone_span, pocket_len, z_phone_low - floor_t - z_bot + 1]);
        if (cable_hole) {
            xc = x_phone + phone_slot / 2 * cos(phone_tilt);
            translate([xc - 5, spine + pocket_len / 2 - 7.5, z_bot - 1])
                cube([10, 15, z_phone_low - z_bot + 4]);
        }
        // hex pocket for the printed nut, open toward the clamp gap
        translate([width / 2, screw_y, -gap - nut_h - 0.5])
            rotate([0, 0, 30])
                cylinder(d = (nut_af + 0.4) / cos(30), h = nut_h + 1, $fn = 6);
        // screw clearance through the rest of the jaw
        translate([width / 2, screw_y, z_bot - 1])
            linear_extrude(bottom_jaw_t + 2) teardrop2d(screw_d + 1);
    }
}

module body_sided() {
    if (mount_side == "right")
        translate([width, 0, 0]) mirror([1, 0, 0]) body_in_use();
    else
        body_in_use();
}

module screw() {
    difference() {
        cyl(d = knob_d, h = knob_h, chamfer = 1.5, anchor = BOT);
        for (a = [0 : 360 / 10 : 359])
            rotate([0, 0, a]) translate([knob_d / 2 + 1.5, 0, -1]) cylinder(d = 8, h = knob_h + 2);
    }
    translate([0, 0, knob_h - 0.01])
        threaded_rod(d = screw_d, l = screw_len, pitch = screw_pitch, bevel = true, anchor = BOT);
}

module nut() {
    threaded_nut(nutwidth = nut_af, id = screw_d, h = nut_h, pitch = screw_pitch,
                 bevel = true, $slop = thread_slop, anchor = BOT);
}

if (part == "body") {
    // print lying on its outer face: no supports, threads printed separately
    translate([0, 0, y_out]) rotate([-90, 0, 0]) body_sided();
} else if (part == "screw") {
    screw();
} else if (part == "nut") {
    nut();
} else {
    // assembled preview on a 25 mm desk
    desk = 25;
    color("#c8a27a") translate([-40, -260, -desk]) cube([width + 80, 260, desk]);
    color("#5b8def") body_sided();
    color("#f2a33a") translate([width / 2, screw_y, -gap - nut_h]) nut();
    color("#f2a33a") translate([width / 2, screw_y, -desk - knob_h - screw_len]) screw();
    // stand-ins for a phone and a wallet (left-side layout)
    if (mount_side == "left") {
        color("#333", 0.85)
            translate([x_phone + 1.5, spine + (pocket_len - 78) / 2, zb + 0.5])
                rotate([0, phone_tilt, 0]) cube([9, 78, 160]);
        color("#7a4a2a", 0.9)
            translate([x_wallet + 3, spine + 2, z_top - wallet_depth]) cube([22, 88, 112]);
    }
}
