// Clamp-on desk organizer: a phone stand at the desk edge facing outward, with a keys cup,
// a Fire TV remote slot and a wallet pocket behind it on the desk.
// Clamps to a desk edge with a printed screw + nut (no hardware needed).
//
// The phone faces outward, away from the desk: clamped to the right side of a desk it faces
// right, toward a bed or chair beside the desk. The pockets sit behind the stand on the desk.
// The stand is the same from either side, so one STL fits a left or right desk edge.
//
// Requires the BOSL2 library (https://github.com/BelfrySCAD/BOSL2) for the threads.
// Export:  openscad -D 'part="all_in_one"' -o organizer.stl desk_organizer.scad
// Parts: "all_in_one" (body + screw + nut on one plate), "body", "screw", "nut",
//        "assembly" (preview only, not for printing).
//
// Coordinates while in use: desk top surface is Z=0, the desk edge is Y=0, the desk is on
// the -Y side and +Y points outward. X runs along the desk edge.

include <BOSL2/std.scad>
include <BOSL2/threading.scad>

/* [Which part] */
part = "assembly";        // [all_in_one, body, screw, nut, assembly]

/* [Desk] */
desk_max = 40;            // thickest desk the clamp fits (mm). Thinnest is about 9 mm.
jaw_depth = 55;           // how far the lower jaw reaches under the desk

/* [Phone stand] */
// Sized for a Galaxy S23 Ultra (163.4 x 78.1 x 8.9 mm) in a case; portrait or landscape.
phone_w_max = 84;         // widest phone + case in portrait; sets the organizer's length
phone_len = 167;          // phone + case length; keeps the pockets clear of the phone's top
stand_angle = 75;         // backrest angle from horizontal (75 = leans back 15 degrees)
stand_ledge = 17;         // thickest phone + case the ledge holds
stand_lip = 7;            // lip height in front of the phone
stand_lip_t = 4;
stand_height = 28;        // ledge corner height above the desk (room for a USB-C plug below)
backrest_len = 100;
backrest_t = 5;
stand_wall = 4;           // lid and back wall of the stand
cable_hole = true;        // USB-C cable hole under the phone, into a side-to-side tunnel

/* [Pockets] */
row1_t = 30;              // front row (keys cup + remote slot), measured front to back
keys_depth = 40;
remote_w = 44;            // Fire TV remotes are 38 mm wide and 16-18 mm thick
remote_t = 22;
remote_depth = 60;
wallet_t = 32;            // back row: fits a bifold wallet up to ~28 mm thick
wallet_depth = 60;

/* [Structure] */
wall = 2.4;
floor_t = 2.4;
spine = 10;               // outside the desk edge, from the stand down to the lower jaw
base_t = 8;               // base under the stand; it is also the clamp's top jaw
bottom_jaw_t = 18;

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
z_bot = -(gap + bottom_jaw_t);
inner_len = phone_w_max + 8;
width = inner_len + 2 * wall;            // length along the desk edge
screw_y = -jaw_depth / 2 - 3;

// Phone stand profile, in the Y-Z plane. The phone's back rests on the backrest and its
// bottom edge sits in the corner p0 between the backrest and the ledge.
su = [-cos(stand_angle), sin(stand_angle)];    // up the backrest (it leans back over the desk)
sf = [sin(stand_angle), cos(stand_angle)];     // toward the screen side (outward)
lip_y = spine;                                 // the lip is flush with the outer face
p0 = [lip_y - stand_lip_t - stand_ledge * sin(stand_angle), stand_height];
p1 = p0 + stand_ledge * sf;                    // front end of the ledge
p2 = p1 + stand_lip * su;                      // top of the lip
b0 = p0 - backrest_t * sf;                     // bottom of the backrest's back face
g = b0 - ((b0[1] - base_t) / sin(stand_angle)) * su;   // back face meets the base
top_back = b0 + backrest_len * su;             // top of the backrest's back face
phone_top = p0 + phone_len * su;               // top of the phone's back
y_back = phone_top[0] - 2;                     // front face of the stand's back wall
z_lid = top_back[1];                           // top of the stand's lid

// Pockets behind the stand: keys cup and remote slot in the front row, wallet behind them.
pocket_h = max(keys_depth, remote_depth, wallet_depth) + floor_t;
y_row1 = [y_back - stand_wall - row1_t, y_back - stand_wall];
y_wallet = [y_row1[0] - wall - wallet_t, y_row1[0] - wall];
y_end = y_wallet[0] - wall;
x_remote = width - wall - remote_w;

// Cable: a channel along the phone's long axis from the USB-C port down into a tunnel
// that runs side to side under the ledge, so the cable leaves from either end.
tunnel = [g[0] + 3.5, lip_y - 2.5];            // Y range
tunnel_z = [base_t, base_t + 14];
cable_top = p0 + 6 * sf + 4 * su;
cable_len = (cable_top[1] - (tunnel_z[0] + tunnel_z[1]) / 2) / sin(stand_angle);
cable_end = cable_top - cable_len * su;
assert(cable_end[0] - 4.5 * sin(stand_angle) >= tunnel[0], "cable hole misses the tunnel");
assert(cable_end[0] + 4.5 * sin(stand_angle) <= tunnel[1], "cable hole misses the tunnel");
assert(y_row1[1] < phone_top[0], "pockets would sit under the phone");

// Extrude a 2D profile drawn in (y, z) along X, from x0 to x0 + len.
module yz_extrude(x0, len) {
    multmatrix([[0, 0, 1, x0], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]])
        linear_extrude(len) children();
}

module jaw(z0, t) {
    r = t / 2;
    hull() {
        translate([0, -jaw_depth + r, z0]) cube([width, jaw_depth - r + spine, t]);
        translate([0, -jaw_depth + r, z0 + r]) rotate([0, 90, 0]) cylinder(r = r, h = width);
    }
}

// Each piece is extruded on its own: merging them as one 2D outline first leaves a
// non-closed mesh in OpenSCAD 2021.
module stand() {
    // ledge and lip, on the base
    yz_extrude(0, width)
        polygon([[lip_y, base_t - 0.5], [lip_y, p2[1]], p2, p1, p0,
                 p0 + 2 * su, b0 + 2 * su, g, [g[0], base_t - 0.5]]);   // overlaps the backrest
    // backrest with a rounded top
    yz_extrude(0, width)
        hull() {
            polygon([p0, b0, b0 + 0.1 * su, p0 + 0.1 * su]);
            translate(p0 + backrest_len * su - backrest_t / 2 * sf) circle(d = backrest_t);
        }
    // lid and back wall; the back wall is also the front wall of the pockets
    yz_extrude(0, width)
        polygon([[y_back - stand_wall, base_t - 0.5], [y_back, base_t - 0.5],
                 [y_back, z_lid - stand_wall], [top_back[0] + 2, z_lid - stand_wall],
                 [top_back[0] + 2, z_lid], [y_back - stand_wall, z_lid]]);
}

module cable_2d() {
    polygon([cable_top + 4.5 * sf, cable_top - 4.5 * sf, cable_end - 4.5 * sf, cable_end + 4.5 * sf]);
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
            // spine outside the desk edge, from the base down to the lower jaw
            translate([0, 0, z_bot]) cube([width, spine, base_t - z_bot]);
            // base under the stand; it rests on the desk as the clamp's top jaw
            translate([0, y_back - stand_wall - 0.5, 0])
                cube([width, spine - (y_back - stand_wall - 0.5), base_t]);
            jaw(z_bot, bottom_jaw_t);
            // fillet in the lower inside corner of the clamp
            yz_extrude(0, width) polygon([[0, -gap], [0, -gap + 6], [-6, -gap]]);
            stand();
            // pocket block
            translate([0, y_end, 0]) cube([width, y_row1[1] - y_end + 0.5, pocket_h]);
        }
        // keys cup, with an open space under its raised floor
        translate([wall, y_row1[0], pocket_h - keys_depth])
            cube([x_remote - 2 * wall, row1_t, keys_depth + 1]);
        translate([wall, y_row1[0], -1])
            cube([x_remote - 2 * wall, row1_t, pocket_h - keys_depth - floor_t + 1]);
        // remote slot, at the back of the front row so the remote can't lean onto the phone
        translate([x_remote, y_row1[0], pocket_h - remote_depth])
            cube([remote_w, remote_t, remote_depth + 1]);
        // wallet pocket
        translate([wall, y_wallet[0], pocket_h - wallet_depth])
            cube([inner_len, wallet_t, wallet_depth + 1]);
        if (cable_hole) {
            yz_extrude(width / 2 - 7, 14) cable_2d();
            yz_extrude(-1, width + 2)
                translate([tunnel[0], tunnel_z[0]])
                    square([tunnel[1] - tunnel[0], tunnel_z[1] - tunnel_z[0]]);
        }
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
    // body, screw and nut on one P2S plate (256 x 256); the screw and nut sit in the empty
    // space under the pockets, beside the clamp
    body_print();
    translate([-z_bot / 2, y_end + 22, 0]) screw();
    translate([24, -64, 0]) nut();
} else if (part == "body") {
    body_print();
} else if (part == "screw") {
    screw();
} else if (part == "nut") {
    nut();
} else {
    // assembled preview on a 25 mm desk
    desk = 25;
    color("#c8a27a") translate([-60, -400, -desk]) cube([width + 120, 400, desk]);
    color("#5b8def") body();
    color("#f2a33a") translate([width / 2, screw_y, -gap - nut_h]) nut();
    color("#f2a33a") translate([width / 2, screw_y, -desk - knob_h - screw_len]) screw();
    // stand-ins: Galaxy S23 Ultra in a case, a Fire TV remote and a wallet
    color("#333", 0.9)
        translate([(width - 82) / 2, p0[0], p0[1]])
            rotate([90 - stand_angle, 0, 0]) cube([82, 12, 167]);
    color("#222")
        translate([x_remote + 3, y_row1[0] + 3, floor_t]) cube([38, 17, 150]);
    color("#7a4a2a", 0.9)
        translate([wall + 2, y_wallet[0] + 3, floor_t]) cube([88, 22, 112]);
}
