// Clamp-on desk organizer: phone stand, keys cup and wallet pocket.
// Clamps to a desk edge with a printed screw + nut (no hardware needed).
//
// The phone stand sits on top of the desk on the clamp's top jaw, and its screen faces
// across the desk toward you: on the left side of a desk it faces right, on the right side
// it faces left. The design is symmetric, so one STL fits either side. The keys cup and
// wallet pocket hang off the desk edge.
//
// Requires the BOSL2 library (https://github.com/BelfrySCAD/BOSL2) for the threads.
// Export:  openscad -D 'part="all_in_one"' -o organizer.stl desk_organizer.scad
// Parts: "all_in_one" (body + screw + nut on one plate), "body", "screw", "nut",
//        "assembly" (preview only, not for printing).
//
// Coordinates while in use: desk top surface is Z=0, the desk edge is Y=0 and the desk
// is on the -Y side. X runs along the desk edge.

include <BOSL2/std.scad>
include <BOSL2/threading.scad>

/* [Which part] */
part = "assembly";        // [all_in_one, body, screw, nut, assembly]

/* [Desk] */
desk_max = 40;            // thickest desk the clamp fits (mm). Thinnest is about 9 mm.
jaw_depth = 55;           // how far the clamp reaches onto / under the desk

/* [Phone stand] */
// Sized for a Galaxy S23 Ultra (163.4 x 78.1 x 8.9 mm) in a case; portrait or landscape.
phone_w_max = 84;         // widest phone + case in portrait; sets the organizer's length
stand_angle = 65;         // backrest angle from horizontal
stand_ledge = 17;         // thickest phone + case the ledge holds
stand_lip = 7;            // lip height in front of the phone
stand_lip_t = 4;
stand_height = 28;        // ledge corner height above the desk (room for a USB-C plug below)
backrest_len = 100;
backrest_t = 5;
strut_t = 4;
cable_hole = true;        // USB-C cable hole under the phone, into a side-to-side tunnel

/* [Pockets] */
keys_t = 30;              // keys cup, measured outward from the desk
keys_depth = 40;
wallet_t = 32;            // fits a bifold wallet up to ~28 mm thick
wallet_depth = 60;

/* [Structure] */
wall = 2.4;
floor_t = 2.4;
spine = 8;                // wall that sits against the desk edge
top_above_desk = 25;      // top of the pockets above the desk
top_jaw_t = 10;
bottom_jaw_t = 18;
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
inner_len = phone_w_max + 8;
width = inner_len + 2 * wall;            // length along the desk edge
screw_y = -jaw_depth / 2 - 3;

y_keys = spine;
y_wallet = y_keys + keys_t + wall;
y_out = y_wallet + wallet_t + wall;

// Phone stand profile, in the Y-Z plane, standing on the top jaw. The phone's back rests on
// the backrest and its bottom edge sits in the corner p0 between the backrest and the ledge.
su = [cos(stand_angle), sin(stand_angle)];     // up the backrest
sf = [-sin(stand_angle), cos(stand_angle)];    // toward the screen side (across the desk)
lip_y = -jaw_depth + top_jaw_t / 2 + 1;        // just behind the jaw's rounded tip
p0 = [lip_y + stand_lip_t + stand_ledge * sin(stand_angle), stand_height];
p1 = p0 + stand_ledge * sf;                    // front end of the ledge
p2 = p1 + stand_lip * su;                      // top of the lip
b0 = p0 - backrest_t * sf;                     // bottom of the backrest's back face
g = b0 - ((b0[1] - top_jaw_t) / sin(stand_angle)) * su;   // back face meets the jaw top
y_strut = -strut_t;                            // strut sits against the pockets' inner wall
function z_back(y) = b0[1] + (y - b0[0]) * tan(stand_angle);

// Cable: a channel along the phone's long axis from the USB-C port down into a tunnel
// that runs side to side under the ledge, so the cable leaves from either end.
tunnel = [lip_y + 2.5, g[0] - 3.5];            // Y range
tunnel_z = [top_jaw_t, top_jaw_t + 12];
cable_top = p0 + 6 * sf + 6 * su;
cable_len = (cable_top[1] - (tunnel_z[0] + tunnel_z[1]) / 2) / sin(stand_angle);
cable_end = cable_top - cable_len * su;
assert(cable_end[0] - 4.5 * sin(stand_angle) >= tunnel[0] - 0.01, "cable hole misses the tunnel");
assert(cable_end[0] + 4.5 * sin(stand_angle) <= tunnel[1], "cable hole misses the tunnel");

// Extrude a 2D profile drawn in (y, z) along X, from x0 to x0 + len.
module yz_extrude(x0, len) {
    multmatrix([[0, 0, 1, x0], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]])
        linear_extrude(len) children();
}

module bin_shell() {
    hull()
        for (y = [corner_r, y_out - corner_r], z = [z_bot + corner_r, z_top - corner_r])
            translate([0, y, z]) rotate([0, 90, 0]) cylinder(r = corner_r, h = width);
}

module jaw(z0, t, w) {
    r = t / 2;
    translate([(width - w) / 2, 0, 0])
        hull() {
            translate([0, -jaw_depth + r, z0]) cube([w, jaw_depth - r + spine, t]);
            translate([0, -jaw_depth + r, z0 + r]) rotate([0, 90, 0]) cylinder(r = r, h = w);
        }
}

// Right-triangle fillet in the Y-Z plane, full width.
module fillet(y0, z0, dy, dz) {
    yz_extrude(0, width) polygon([[y0, z0], [y0, z0 + dz], [y0 + dy, z0]]);
}

// Each piece is extruded on its own: merging them as one 2D outline first leaves a
// non-closed mesh in OpenSCAD 2021.
module stand() {
    // ledge and lip, sitting on the top jaw
    yz_extrude(0, width)
        polygon([[lip_y, top_jaw_t - 0.5], [lip_y, p2[1]], p2, p1, p0,
                 p0 + 2 * su, b0 + 2 * su, g, [g[0], top_jaw_t - 0.5]]);   // overlaps the backrest
    // backrest with a rounded top
    yz_extrude(0, width)
        hull() {
            polygon([p0, b0, b0 + 0.1 * su, p0 + 0.1 * su]);
            translate(p0 + backrest_len * su - backrest_t / 2 * sf) circle(d = backrest_t);
        }
    // strut from the top jaw up to the back of the backrest
    yz_extrude(0, width)
        polygon([[y_strut, top_jaw_t - 0.5], [y_strut + strut_t + 0.5, top_jaw_t - 0.5],
                 [y_strut + strut_t + 0.5, z_back(y_strut + strut_t + 0.5) + 1],
                 [y_strut, z_back(y_strut) + 1]]);
}

module cable_2d() {
    polygon([cable_top + 4.5 * sf, cable_top - 4.5 * sf, cable_end - 4.5 * sf, cable_end + 4.5 * sf]);
}

module pocket(y, t, depth) {
    floor_z = z_top - depth;
    translate([wall, y, floor_z]) cube([inner_len, t, depth + 1]);
    // open-bottom cavity under the floor saves plastic and print time
    translate([wall, y, z_bot - 1]) cube([inner_len, t, floor_z - floor_t - z_bot + 1]);
}

module underside_taper() {
    // below the pockets only the spine has to reach the lower jaw
    z_hi = z_top - wallet_depth - floor_t - 1;
    slope = (z_hi - z_bot) / (y_out - spine);
    yz_extrude(-1, width + 2)
        polygon([[spine, z_bot], [y_out + 1, z_hi + slope],
                 [y_out + 1, z_bot - 1], [spine, z_bot - 1]]);
}

module teardrop2d(d) {
    // points toward +X, which is "up" in the print orientation
    hull() {
        circle(d = d);
        translate([d / 2 * sqrt(2), 0]) square(0.01, center = true);
    }
}

module body() {
    difference() {
        union() {
            bin_shell();
            stand();
            jaw(0, top_jaw_t, width);
            jaw(z_bot, bottom_jaw_t, width);   // full width so it prints without supports
            fillet(0, top_jaw_t, -10, 10);      // brace between the top jaw and the bin wall
            fillet(0, -gap, -6, 6);             // inside lower corner of the clamp
        }
        pocket(y_keys, keys_t, keys_depth);
        pocket(y_wallet, wallet_t, wallet_depth);
        if (cable_hole) {
            yz_extrude(width / 2 - 7, 14) cable_2d();
            yz_extrude(-1, width + 2)
                translate([tunnel[0], tunnel_z[0]])
                    square([tunnel[1] - tunnel[0], tunnel_z[1] - tunnel_z[0]]);
        }
        underside_taper();
        // hex pocket for the printed nut, open toward the clamp gap; flat side faces +X so
        // it prints as a short bridge
        translate([width / 2, screw_y, -gap - nut_h - 0.5])
            rotate([0, 0, 30]) cylinder(d = (nut_af + 0.4) / cos(30), h = nut_h + 1, $fn = 6);
        // screw clearance through the rest of the jaw
        translate([width / 2, screw_y, z_bot - 1])
            linear_extrude(bottom_jaw_t + 2) teardrop2d(screw_d + 1);
    }
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

module body_print() {
    // standing on its end: the clamp and stand profiles lie flat on the plate, no supports
    rotate([0, -90, 0]) body();
}

if (part == "all_in_one") {
    // body, screw and nut laid out together for one P2S plate (256 x 256)
    body_print();
    translate([-50, y_out + 10 + knob_d / 2, 0]) screw();
    translate([0, y_out + 10 + knob_d / 2, 0]) nut();
} else if (part == "body") {
    body_print();
} else if (part == "screw") {
    screw();
} else if (part == "nut") {
    nut();
} else {
    // assembled preview on a 25 mm desk
    desk = 25;
    color("#c8a27a") translate([-60, -260, -desk]) cube([width + 120, 260, desk]);
    color("#5b8def") body();
    color("#f2a33a") translate([width / 2, screw_y, -gap - nut_h]) nut();
    color("#f2a33a") translate([width / 2, screw_y, -desk - knob_h - screw_len]) screw();
    // stand-ins: Galaxy S23 Ultra in a case, and a wallet
    color("#333", 0.9)
        translate([(width - 82) / 2, p0[0], p0[1]])
            rotate([stand_angle - 90, 0, 0]) translate([0, -12, 0]) cube([82, 12, 167]);
    color("#7a4a2a", 0.9)
        translate([wall + 2, y_wallet + 3, z_top - wallet_depth]) cube([88, 22, 112]);
}
