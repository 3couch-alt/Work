// Clamp-on desk organizer: phone stand, keys cup and wallet pocket.
// Clamps to a desk edge with a printed screw + nut (no hardware needed).
//
// Requires the BOSL2 library (https://github.com/BelfrySCAD/BOSL2) for the threads.
// Export:  openscad -D 'part="all_in_one"' -o organizer.stl desk_organizer.scad
// Parts: "all_in_one" (body + screw + nut on one plate), "body", "screw", "nut",
//        "assembly" (preview only, not for printing).
//
// Coordinates while in use: desk top surface is Z=0, the desk edge is Y=0 and the desk
// is on the -Y side. X runs along the desk edge, front (nearest you) at X=0.

include <BOSL2/std.scad>
include <BOSL2/threading.scad>

/* [Which part] */
part = "assembly";        // [all_in_one, body, screw, nut, assembly]
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

/* [Phone stand] */
// Sized for a Galaxy S23 Ultra (163.4 x 78.1 x 8.9 mm) with a case; works in portrait or landscape.
stand_angle = 65;         // backrest angle from horizontal
stand_ledge = 17;         // deepest phone + case the ledge holds
stand_lip = 7;            // lip height in front of the phone
stand_lip_t = 4;
backrest_len = 100;
backrest_t = 5;
strut_t = 4;
strut_at = 50;            // where the support strut meets the backrest
cable_hole = true;        // USB-C cable hole under the phone

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

// Phone stand profile, in the X-Z plane. The phone's back rests on the backrest and its
// bottom edge sits in the corner P0 between the backrest and the ledge.
su = [cos(stand_angle), sin(stand_angle)];     // up the backrest
sf = [-sin(stand_angle), cos(stand_angle)];    // toward the screen side
stand_front = corner_r + 1;
p0 = [stand_front + stand_lip_t + stand_ledge * sin(stand_angle), z_top + 3];
p1 = p0 + stand_ledge * sf;                    // front end of the ledge
p2 = p1 + stand_lip * su;                      // top of the lip
b0 = p0 - backrest_t * sf;                     // bottom of the backrest's back face
x_strut = b0[0] + strut_at * cos(stand_angle);
function z_back(x) = b0[1] + (x - b0[0]) * tan(stand_angle);

x_keys = x_strut + strut_t;
x_wallet = x_keys + keys_w + wall;
width = x_wallet + wallet_w + wall;
x_rib = (wall + x_strut) / 2;                  // rib that splits the cavity under the stand
screw_y = -jaw_depth / 2 - 3;

// Cable channel follows the phone's long axis down from the USB-C port into the cavity.
cable_top = p0 + 6 * sf + 6 * su;
cable_len = (cable_top[1] - (z_top - floor_t - 3)) / sin(stand_angle);
cable_end = cable_top - cable_len * su;
assert(cable_end[0] - 4.5 * sin(stand_angle) > wall + 1, "cable hole would break the front wall");
assert(cable_end[0] + 4.5 * sin(stand_angle) < x_rib - wall, "cable hole would hit the rib");

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

// Extrude a 2D profile drawn in (x, z) along Y, from y0 to y0 + len.
module xz_extrude(y0, len) {
    translate([0, y0 + len, 0]) rotate([90, 0, 0]) linear_extrude(len) children();
}

// Each piece is extruded on its own: merging them as one 2D outline first leaves a
// non-closed mesh in OpenSCAD 2021.
module stand() {
    g = b0 - ((b0[1] - z_top) / sin(stand_angle)) * su;   // back face meets the bin top
    lip_x = p1[0] - stand_lip_t;
    // ledge and lip
    xz_extrude(0, y_out)
        polygon([[lip_x, z_top - 0.5], [lip_x, p2[1]], p2, p1, p0,
                 p0 + 2 * su, b0 + 2 * su, g, [g[0], z_top - 0.5]]);   // overlaps the backrest
    // backrest with a rounded top
    xz_extrude(0, y_out)
        hull() {
            polygon([p0, b0, b0 + 0.1 * su, p0 + 0.1 * su]);
            translate(p0 + backrest_len * su - backrest_t / 2 * sf) circle(d = backrest_t);
        }
    // strut from the bin top up to the back of the backrest
    xz_extrude(0, y_out)
        polygon([[x_strut, z_top - 0.5], [x_strut + strut_t, z_top - 0.5],
                 [x_strut + strut_t, z_back(x_strut + strut_t) + 1], [x_strut, z_back(x_strut) + 1]]);
}

module cable_2d() {
    polygon([cable_top + 4.5 * sf, cable_top - 4.5 * sf, cable_end - 4.5 * sf, cable_end + 4.5 * sf]);
}

module pocket(x, w, depth) {
    floor_z = z_top - depth;
    translate([x, spine, floor_z]) cube([w, pocket_len, depth + 1]);
    // open-bottom cavity under the floor saves plastic and print time
    translate([x, spine, z_bot - 1]) cube([w, pocket_len, floor_z - floor_t - z_bot + 1]);
}

module underside_taper() {
    z_hi = z_top - wallet_depth - floor_t - 1;          // stay under the deepest pocket floor
    slope = (z_hi - z_bot) / (y_out - spine);
    translate([width + 1, 0, 0]) rotate([0, -90, 0])
        linear_extrude(width + 2)
            polygon([[z_bot, spine], [z_hi + slope, y_out + 1],
                     [z_bot - 1, y_out + 1], [z_bot - 1, spine]]);
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
            stand();
            jaw(0, top_jaw_t, width);
            jaw(z_bot, bottom_jaw_t, bottom_jaw_w);
            fillet(0, top_jaw_t, -10, 10, width);        // brace between the top jaw and the bin wall
            fillet(0, -gap, -6, 6, bottom_jaw_w);        // inside lower corner of the clamp
        }
        pocket(x_keys, keys_w, keys_depth);
        pocket(x_wallet, wallet_w, wallet_depth);
        // open-bottom cavities under the stand, split by a rib
        for (xr = [[wall, x_rib - wall / 2], [x_rib + wall / 2, x_strut]])
            translate([xr[0], spine, z_bot - 1])
                cube([xr[1] - xr[0], pocket_len, z_top - floor_t - z_bot + 1]);
        if (cable_hole)
            xz_extrude(spine + pocket_len / 2 - 7, 14) cable_2d();
        // taper the underside: below the pockets only the spine has to reach the lower jaw
        underside_taper();
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

module body_print() {
    // lying on its outer face: no supports needed
    translate([0, 0, y_out]) rotate([-90, 0, 0]) body_sided();
}

if (part == "all_in_one") {
    // body, screw and nut laid out together for one P2S plate (256 x 256)
    body_print();
    translate([width + 10 + knob_d / 2, z_bot + knob_d / 2, 0]) screw();
    translate([width + 10 + knob_d / 2, z_bot + knob_d + 25, 0]) nut();
} else if (part == "body") {
    body_print();
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
    // stand-ins: Galaxy S23 Ultra in a case, and a wallet (left-side layout)
    if (mount_side == "left") {
        color("#333", 0.9)
            translate([p0[0], spine + (pocket_len - 82) / 2, p0[1]])
                rotate([0, 90 - stand_angle, 0]) translate([-12, 0, 0]) cube([12, 82, 167]);
        color("#7a4a2a", 0.9)
            translate([x_wallet + 3, spine + 2, z_top - wallet_depth]) cube([22, 88, 112]);
    }
}
