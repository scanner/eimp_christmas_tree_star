// The enclosure for the controller box for the electric imp christmas star
//
use <OpenSCAD_Rounded_primitives/rcube.scad>;
use <MCAD/nuts_and_bolts.scad>;

version = "v0.5";
$fn = 40;

// The internal dimensions needed to account for the circuit board,
// and wires to fit inside the case.
//
// The X dimension is determined by the length of the pcb plus how
// much beyond it the eimp pcb extends. The eimp extends beyond that
// and we want to make sure it sure it pokes out far enuogh beyond the
// outside edge of the case so you can do a push-pop of the eimp to
// reset it (or remove it)
//
pcb_x = 51;
eimp_x_extension = 7;
int_x = pcb_x + eimp_x_extension + 6;
int_y = 44;
int_z = 50;

// The gap between the internal dimensions needed and the internal walls.
//
int_pad = 1.5;

// How thick are the walls of the enclosure?
//
wall_thickness = 2;

// The external dimensions of our enclosure
//
ext_x = int_x + int_pad + wall_thickness;
ext_y = int_y + int_pad + wall_thickness;
ext_z = int_z + int_pad + wall_thickness;

// The mounting posts are this tall above the floor
//
mt_post_h = 26;
mt_post_r = 2.55;
mt_post_base_h = 15;
mt_post_base_r = mt_post_r * 2 + 1;
m3_bolt_r = 1.7; // Internal radius for M3 bolt


// The offset from the Y-axis for the mounting posts
//
mt_post_y_offset = 35.5/2;

// The offset from the X-axis for the mounting posts (note: 25.5mm is
// how far the mounting posts are from either side of the PCB, pcb_x
// is the size of the PCB in mm along the X-axis)
//
mt_post_x_offset = -eimp_x_extension + 4.5;

// The eimp card is this far above the top of the mounting post
//
eimp_pcb_h_offset = 12;

// How tall the bottom half of the enclosure is - this is the wall
// thickness, plus the height of the mounting posts, plus the height
// of the eimp offset.
//
bottom_z = wall_thickness + mt_post_h + eimp_pcb_h_offset;

// power connector radius
// 
pwr_r = 6.5;

// Rotary switch elements
//
rotary_r = 2.2;
rotary_side = 10.1;
rotary_h = 5.72;
rotary_x_offset = 14;
rotary_z_offset = -int_z/2;

// Notches for the eimp and the cable back to the star.
//
eimp_notch_width = 40;
eimp_notch_height = 7;

cable_notch_width = 10;
cable_notch_height = 2;

// Sticking up in the top of the box is basically a piece of plastic
// to give support to the back of the eimp april board so if you push
// against the eimp this takes some of the load.
//
eimp_back_support_from_wall = 14;
eimp_back_support_w = 35;
eimp_back_support_h = 15;
eimp_back_support_d = 4;

//***************************************************************************
//
// Many things are meant to be clipped to the external cube. So we
// will be doing a lot of 'intersection() {}'s with the cube's
// outside. So make a handy way of drawing this cube.
//
module ext_cube_ref() {
    rcube(Size = [ext_x, ext_y, ext_z], b=2);
}

//***************************************************************************
//
// Also the size of the internal space of the enclosure is defined by
// the internal x,y,z dimensions + internal padding.
//
module int_cube_ref() {
    rcube(Size = [int_x + int_pad, int_y + int_pad, int_z + int_pad], b=2);
}

//***************************************************************************
//
module mounting_post() {
    union() {
        cylinder(h=mt_post_h, r=mt_post_r, center = true);
        translate(v=[0, mt_post_r, 0]) {
            cube(size=[mt_post_r, mt_post_r*2, mt_post_h], center = true);
        }
        translate(v=[0, 0, (-mt_post_h/2) + (mt_post_base_h/2)]) {
            cylinder(h=mt_post_base_h, r1 = mt_post_base_r,
                r2=mt_post_r, center = true);
        }
    }
}

//***************************************************************************
//
module hexagon(r) {
    scale(v = [r, r, 1]) polygon(points=[[1,0],[0.5,sqrt(3)/2],[-0.5,sqrt(3)/2],[-1,0],[-0.5,-sqrt(3)/2],[0.5,-sqrt(3)/2]], paths=[[0,1,2,3,4,5,0]]);
}

//***************************************************************************
//
// Make a hexagon suitable for differencing out a hex nut.
//
module hex_nut(r, h) {
    linear_extrude(height = h, center = true, convexity = 10, twist = 0) hexagon(r);
}

//***************************************************************************
//
module mounting_post_hole() {
    union() {
        scale(v=[1.15,1.15,1.15]) {
            nutHole(3);
        }
        cylinder(h=mt_post_h+wall_thickness+2, r=m3_bolt_r);
    }
}

//***************************************************************************
//
// The power connector hole is just a cylinder..
//
module power_connector_hole() {
    cylinder(h = 10, r = pwr_r, center = true);
}

//***************************************************************************
//
// The rotary hole is just a cylinder..
module rotary_hole() {
    cylinder(h=5, r = rotary_r, center = true);
}

//***************************************************************************
//
// Basically a square that the rotary switch fits snugly into.
//
module rotary_mount() {
    difference() {
        cube(size=[rotary_side + 3, rotary_side + 3, rotary_h], center=true);
        cube(size=[rotary_side, rotary_side, rotary_h+1], center=true);
    }
}

//***************************************************************************
//
module eimp_notch() {
    translate(v=[0,0,-5]) {
        cube(size=[10, eimp_notch_width, eimp_notch_height+10], center=true);
    }
}

//***************************************************************************
//
module star_cable_notch() {
    translate(v=[0,0,-5]) {
        cube(size=[10, cable_notch_width, cable_notch_height+10], center=true);
    }
}

//***************************************************************************
//
module eimp_xmas_star_controller() {

    // The complete box is all of the elements inside it.. the box the
    // mounting posts, the backstop for the electric imp, the mount
    // for the rotary switch with subtractions for the mounting post
    // screw holes and hex nut, the opening for the power connetor,
    // the opening for the rotary switch.
    //
    difference() {
        union() {
            // It is a hollow rounded cube with a round hole for where the
            // power connector goes, a slot for where the electric imp
            // sticks out, a slot for the cable to the christmas tree star
            // goes, and a rounded hole in the bottom, with a mount frame
            // for the rotary switch.
            //
            // NOTE: The slots are integrate with where the top and bottom
            // of the controller box meet so we need to block them out of
            // the top and bottom so that they are not interfered with by
            // the notch/edge we use to make connecting the top to the
            // bottom.
            //
            difference() {
                ext_cube_ref();
                int_cube_ref();
            }

            translate(v=[rotary_x_offset, 0, rotary_z_offset+(rotary_h/2)-1]) {
                rotary_mount();
            }
        
            // We have two mounting posts for our main PCB.
            //
            intersection() {
                ext_cube_ref();
                union() {
                    translate(v=[mt_post_x_offset, mt_post_y_offset, (-mt_post_h/2)-0.5]) {
                        mounting_post();
                    }
                    translate(v=[mt_post_x_offset, -mt_post_y_offset, (-mt_post_h/2)-0.5]) {
                        rotate(a=[0, 0, 180]) {
                            mounting_post();
                        }
                    }
                }
            }
        }
        translate(v=[mt_post_x_offset, mt_post_y_offset, (-mt_post_h/2)-14.3]) {
            mounting_post_hole();
        }
        translate(v=[mt_post_x_offset, -mt_post_y_offset, (-mt_post_h/2)-14.3]) {
            mounting_post_hole();
        }
        translate(v=[-30, 0, -15]) {
            rotate(a=[0, 90, 0]) {
                power_connector_hole();
            }
        }
        translate(v=[rotary_x_offset, 0, rotary_z_offset]) {
            rotary_hole();
        }
    }
}

//***************************************************************************
//
module eimp_xmas_star_controller_box_top() {
    // Flip the top part upside down, and move it to the build platform (z=0)
    //
    rotate(a=[0,180,0]) {
        // Render the entire controller box and lop off the bottom part
        //
        difference() {
            union() {
                difference() {
                    eimp_xmas_star_controller();
                    translate(v=[0, 0, -((ext_z - bottom_z)/2)]) {
                        cube(size=[ext_x + 1, ext_y + 1, bottom_z + 1],
                            center=true);
                    }
                }
                difference () {
                    int_cube_ref();
                    rcube(Size = [(int_x-3) + int_pad, (int_y-3) + int_pad, (int_z-1) + int_pad], b=2);
                    translate(v=[0, 0, -((ext_z - bottom_z)/2)-5]) {
                        cube(size=[ext_x + 1, ext_y + 1, bottom_z + 1],
                            center=true);
                    }
                }
                translate(v=[(int_x/2)-(eimp_back_support_from_wall-(eimp_back_support_d/2)),5,(int_z/2)-(eimp_back_support_h/2)]) {
                    cube(size=[eimp_back_support_d, eimp_back_support_w, eimp_back_support_h], center=true);
                }
            }
            translate(v=[-(int_x/2),0,(int_z/2)-(int_z - bottom_z)]) {
                eimp_notch();
            }
            translate(v=[(int_x/2),0,(int_z/2)-(int_z - bottom_z)]) {
                star_cable_notch();
            }
        }
    }
}

//***************************************************************************
//
module eimp_xmas_star_controller_box_bottom() {
    // Render the entire controller box and lop off the top part
    //
    difference() {
        eimp_xmas_star_controller();
        translate(v=[0, 0, bottom_z/2]) {
            cube(size=[ext_x + 1, ext_y + 1, ext_z - bottom_z + 1],
                center=true);
        }
    }
}

//***************************************************************************
//
module eimp_xmas_star_controller_box_top_and_bottom() {
    // Move to be on the surface of our print bed.
    //
    translate(v = [0, 0, ext_z/2]) {
        // Place bottom
        translate(v = [-((ext_x/2)+2),0,0]) {
            eimp_xmas_star_controller_box_bottom();
        }
        // Place top
        translate(v = [((ext_x/2)+2),0,0]) {
            eimp_xmas_star_controller_box_top();
        }
    }
}

eimp_xmas_star_controller_box_top_and_bottom();
// eimp_xmas_star_controller_box_bottom();
// eimp_xmas_star_controller_box_top();
