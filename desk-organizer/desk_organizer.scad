// Clamp-on desk organizer: a phone stand at the desk edge facing outward, with a keys cup,
// a Fire TV remote slot and a wallet pocket behind it on the desk.
// Clamps to a desk edge with a printed screw + nut (no hardware needed).
//
// The phone faces outward, away from the desk: clamped to the right side of a desk it faces
// right, toward a bed or chair beside the desk. Nothing sits beside the phone, so it can be
// turned sideways. The stand is the same from either side, so one STL fits a left or right
// desk edge.
//
// The body is one side profile (clamp, fin-shaped stand, pocket block) run along the desk
// edge, with the pockets cut into it, so it prints standing on its end without supports.
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
phone_sideways = false;   // assembly preview only: show the phone turned sideways

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
backrest_len = 100;       // straight part of the backrest the phone leans on
backrest_t = 5;
stand_wall = 4;           // back wall of the fin
tip_r = 4;                // rounding at the top of the fin
cable_hole = true;        // USB-C cable hole under the phone, into a side-to-side tunnel

/* [Pockets] */
row1_t = 30;              // front row (keys cup + remote slot), measured front to back
keys_depth = 40;
remote_w = 44;            // Fire TV remotes are 38 mm wide and 16-18 mm thick
remote_t = 22;
remote_depth = 60;
wallet_t = 34;            // back row: fits a bifold wallet up to ~28 mm thick
wallet_depth = 60;
rim = 0.8;                // bevel around the pocket openings

/* [Side remote pocket] */
side_pocket = false;      // extra remote pocket beside the phone; it stops the phone turning sideways
side_w = 44;              // along the desk edge; Fire TV remotes are 38 mm wide
side_t = 22;              // front to back; they are 16-18 mm thick

/* [Structure] */
wall = 2.4;
floor_t = 2.4;
spine = 10;               // outside the desk edge, from the stand down to the lower jaw
base_t = 8;               // base under the stand; it is also the clamp's top jaw
bottom_jaw_t = 18;
round_r = 6;              // rounding on the outside corners

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
width = inner_len + 2 * wall;            // length of the phone stand along the desk edge
side_len = side_pocket ? side_w + 2 * wall : 0;
total_len = width + side_len;            // whole organizer along the desk edge
screw_x = total_len / 2;
screw_y = -jaw_depth / 2 - 3;

// --- 2D helpers -------------------------------------------------------------------------

function dz_unit(v) = v / norm(v);
function dz_cross(a, b) = a[0] * b[1] - a[1] * b[0];
// Where the line through p along u meets the line through q along v.
function dz_meet(p, u, q, v) = p + u * (dz_cross(q - p, v) / dz_cross(u, v));

// Arc of radius r that rounds the corner at b between neighbours a and c (works for both
// outside corners and inside fillets).
function dz_corner_arc(a, b, c, r, n = 10) =
    let(u1 = dz_unit(a - b), u2 = dz_unit(c - b),
        half = acos(max(-1, min(1, u1 * u2))) / 2,
        d = r / tan(half),
        t1 = b + u1 * d, t2 = b + u2 * d,
        ctr = b + dz_unit(u1 + u2) * (r / sin(half)),
        a1 = atan2(t1[1] - ctr[1], t1[0] - ctr[0]),
        a2 = atan2(t2[1] - ctr[1], t2[0] - ctr[0]),
        da = ((a2 - a1 + 540) % 360) - 180)
    [for (i = [0 : n]) ctr + r * [cos(a1 + da * i / n), sin(a1 + da * i / n)]];

// Polygon whose corner i is rounded with radii[i] (0 = sharp).
function dz_rounded_poly(pts, radii) =
    let(m = len(pts))
    [for (i = [0 : m - 1])
        each (radii[i] > 0 ? dz_corner_arc(pts[(i + m - 1) % m], pts[i], pts[(i + 1) % m], radii[i])
                           : [pts[i]])];

// --- Side profile (Y-Z plane) ----------------------------------------------------------

// Phone stand: the phone's back rests on the backrest and its bottom edge sits in the
// corner p0 between the backrest and the ledge.
su = [-cos(stand_angle), sin(stand_angle)];    // up the backrest (it leans back over the desk)
sf = [sin(stand_angle), cos(stand_angle)];     // toward the screen side (outward)
lip_y = spine;                                 // the lip is flush with the outer face
p0 = [lip_y - stand_lip_t - stand_ledge * sin(stand_angle), stand_height];
p1 = p0 + stand_ledge * sf;                    // front end of the ledge
p2 = p1 + stand_lip * su;                      // top of the lip
b0 = p0 - backrest_t * sf;                     // bottom of the backrest's back face
g = b0 - ((b0[1] - base_t) / sin(stand_angle)) * su;   // back face meets the base
phone_top = p0 + phone_len * su;               // top of the phone's back
y_q = phone_top[0] - 2 - stand_wall;           // back of the fin = front of the pockets
pocket_h = max(keys_depth, remote_depth, wallet_depth) + floor_t;
q = [y_q, pocket_h];                           // where the fin's back meets the pocket rims
// Fin tip before rounding, placed so about backrest_len of the front stays straight.
apex = p0 + (backrest_len + tip_r / tan(15)) * su;

// Pockets behind the stand: keys cup and remote slot in the front row, wallet behind them.
y_row1 = [y_q - row1_t, y_q];
y_wallet = [y_row1[0] - wall - wallet_t, y_row1[0] - wall];
y_end = y_wallet[0] - wall;
x_remote = width - wall - remote_w;

// Cable: a channel along the phone's long axis from the USB-C port down into a tunnel
// that runs side to side under the ledge and out either end (only the far end when the side
// pocket is on).
tunnel = [g[0] + 3.5, lip_y - 2.5];            // Y range
tunnel_z = [base_t, base_t + 14];
cable_top = p0 + 6 * sf + 4 * su;
cable_len = (cable_top[1] - (tunnel_z[0] + tunnel_z[1]) / 2) / sin(stand_angle);
cable_end = cable_top - cable_len * su;
assert(cable_end[0] - 4.5 * sin(stand_angle) >= tunnel[0], "cable hole misses the tunnel");
assert(cable_end[0] + 4.5 * sin(stand_angle) <= tunnel[1], "cable hole misses the tunnel");
assert(y_q < phone_top[0], "pockets would sit under the phone");

// Clamp: spine outside the desk edge and the lower jaw, with rounded corners.
module clamp_2d() {
    polygon(dz_rounded_poly(
        [[lip_y, 1], [lip_y, z_bot], [-jaw_depth, z_bot], [-jaw_depth, -gap], [0, -gap], [0, 1]],
        [0, round_r, bottom_jaw_t / 2 - 0.1, bottom_jaw_t / 2 - 0.1, 6, 0]));
}

// Stand: base on the desk, ledge and lip at the edge, and a fin whose front is the backrest
// and whose back drops into the front row of pockets.
module fin_2d() {
    polygon(dz_rounded_poly(
        [[lip_y, 0], [lip_y, p2[1]], p2, p1, p0, apex, q, [y_q, 0]],
        [0, 1.5, 1, 1, 1, tip_r, 10, 0]));
}

// Window through the fin, leaving the backrest and a stand_wall-thick back.
module fin_window_2d() {
    back_dir = dz_unit(q - apex);
    inner_back = q + stand_wall * [-back_dir[1], back_dir[0]];   // back line moved inward
    v1 = g;
    v2 = dz_meet(b0, su, inner_back, back_dir);
    v3 = dz_meet(inner_back, back_dir, [y_q + stand_wall, 0], [0, 1]);
    v4 = [y_q + stand_wall, base_t];
    polygon(dz_rounded_poly([v1, v2, v3, v4], [3, 1.5, 6, 4]));
}

// Pocket block behind the fin, with a rounded top-back edge.
module pocket_block_2d() {
    polygon(dz_rounded_poly(
        [[y_q + 0.5, 0], [y_q + 0.5, pocket_h], [y_end, pocket_h], [y_end, 0]],
        [0, 0, round_r, 2]));
}

// Wallet pocket; its back wall follows the rounded edge at an even thickness.
module wallet_cut_2d() {
    c = [y_end + round_r, pocket_h - round_r];
    difference() {
        translate([y_wallet[0], pocket_h - wallet_depth])
            square([wallet_t, wallet_depth + 1]);
        difference() {
            translate([y_end - 1, c[1]]) square([c[0] - y_end + 1, round_r + 2]);
            translate(c) circle(r = round_r - wall);
        }
    }
}

module tunnel_2d() {
    offset(r = 2) offset(delta = -2)
        translate([tunnel[0], tunnel_z[0]])
            square([tunnel[1] - tunnel[0], tunnel_z[1] - tunnel_z[0]]);
}

module cable_2d() {
    polygon([cable_top + 4.5 * sf, cable_top - 4.5 * sf, cable_end - 4.5 * sf, cable_end + 4.5 * sf]);
}

module teardrop2d(d) {
    // points toward -X, which is "up" in the print orientation
    hull() {
        circle(d = d);
        translate([-d / 2 * sqrt(2), 0]) square(0.01, center = true);
    }
}

// Extrude a 2D profile drawn in (y, z) along X, from x0 to x0 + len.
module yz_extrude(x0, len) {
    multmatrix([[0, 0, 1, x0], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]])
        linear_extrude(len) children();
}

// 45-degree bevel around the top of a pocket opening (x0..x1, y0..y1).
module rim_bevel(x0, x1, y0, y1) {
    hull() {
        translate([x0, y0, pocket_h - rim]) cube([x1 - x0, y1 - y0, 0.01]);
        translate([x0 - rim, y0 - rim, pocket_h]) cube([x1 - x0 + 2 * rim, y1 - y0 + 2 * rim, 0.01]);
    }
}

module body() {
    difference() {
        union() {
            yz_extrude(0, total_len) clamp_2d();
            yz_extrude(0, total_len) fin_2d();
            yz_extrude(0, total_len) pocket_block_2d();
            // side remote pocket, at the outer edge beside the phone
            if (side_pocket)
                translate([width, spine - 2 * wall - side_t, 0])
                    cube([side_len, 2 * wall + side_t, pocket_h]);
        }
        yz_extrude(-1, total_len + 2) fin_window_2d();

        // keys cup, with an open space under its raised floor
        translate([wall, y_row1[0], pocket_h - keys_depth])
            cube([x_remote - 2 * wall, row1_t, keys_depth + 1]);
        translate([wall, y_row1[0], -1])
            cube([x_remote - 2 * wall, row1_t, pocket_h - keys_depth - floor_t + 1]);
        rim_bevel(wall, x_remote - wall, y_row1[0], y_row1[1]);
        // remote slot, at the back of the front row so the remote can't lean onto the phone
        translate([x_remote, y_row1[0], pocket_h - remote_depth])
            cube([remote_w, remote_t, remote_depth + 1]);
        rim_bevel(x_remote, x_remote + remote_w, y_row1[0], y_row1[0] + remote_t);
        // wallet pocket
        yz_extrude(wall, inner_len) wallet_cut_2d();
        rim_bevel(wall, wall + inner_len, y_end + round_r, y_wallet[1]);

        if (side_pocket) {
            translate([width + wall, spine - wall - side_t, base_t]) cube([side_w, side_t, pocket_h]);
            // open-bottom spaces under the pocket block beside the pockets save plastic
            for (yr = [y_row1, y_wallet])
                translate([width, yr[0], -1])
                    cube([side_len - wall, yr[1] - yr[0], pocket_h - floor_t + 1]);
        }
        if (cable_hole) {
            yz_extrude(width / 2 - 7, 14) cable_2d();
            yz_extrude(-1, side_pocket ? width + 1 : width + 2) tunnel_2d();
        }
        // hex pocket for the printed nut, open toward the clamp gap; flat sides face along X
        // so it prints as a short bridge
        translate([screw_x, screw_y, -gap - nut_h - 0.5])
            rotate([0, 0, 30]) cylinder(d = (nut_af + 0.4) / cos(30), h = nut_h + 1, $fn = 6);
        // screw clearance through the rest of the jaw
        translate([screw_x, screw_y, z_bot - 1])
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
    // standing on its end (the side-pocket end, if there is one): the profile lies flat on
    // the plate, so nothing needs supports
    translate([0, 0, total_len]) rotate([0, 90, 0]) body();
}

if (part == "all_in_one") {
    // body, screw and nut on one P2S plate (256 x 256); the screw and nut sit in the empty
    // space under the pockets, beside the clamp
    body_print();
    translate([z_bot / 2, y_end + 22, 0]) screw();
    translate([-24, -64, 0]) nut();
} else if (part == "body") {
    body_print();
} else if (part == "screw") {
    screw();
} else if (part == "nut") {
    nut();
} else {
    // assembled preview on a 25 mm desk
    desk = 25;
    color("#c8a27a") translate([-60, -400, -desk]) cube([total_len + 120, 400, desk]);
    color("#5b8def") body();
    color("#f2a33a") translate([screw_x, screw_y, -gap - nut_h]) nut();
    color("#f2a33a") translate([screw_x, screw_y, -desk - knob_h - screw_len]) screw();
    // stand-ins: Galaxy S23 Ultra in a case, a Fire TV remote and a wallet
    color("#333", 0.9) {
        if (phone_sideways)
            translate([(width - 167) / 2, p0[0], p0[1]])
                rotate([90 - stand_angle, 0, 0]) cube([167, 12, 82]);
        else
            translate([(width - 82) / 2, p0[0], p0[1]])
                rotate([90 - stand_angle, 0, 0]) cube([82, 12, 167]);
    }
    color("#222") {
        if (side_pocket)
            translate([width + wall + 3, spine - wall - side_t + 2.5, base_t]) cube([38, 17, 150]);
        else
            translate([x_remote + 3, y_row1[0] + 2.5, floor_t]) cube([38, 17, 150]);
    }
    color("#7a4a2a", 0.9)
        translate([wall + 2, y_wallet[0] + 4, floor_t]) cube([88, 24, 112]);
}
