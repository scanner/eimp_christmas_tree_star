//for (i=[0:29]) translate([round(i/5-0.49)*18-45,(i%5)*13-31.5,0]) griper();
//for (i=[0:5]) translate([round(i/3-0.49)*60-30,(i%3)*60-60,0]) star2();

star2();
// griper();
// grippers();
// starbase();
// bullet_pixel();
// star_mount();

//////////////////////////////////////////////////////////////////////
//
module grip() {
        translate([-5,0,5])cube([4,10,10],center=true);
        translate([0,0,5])cube([10,4,10],center=true);
        translate([5,0,5])cube([4,10,10],center=true);
}

//////////////////////////////////////////////////////////////////////
//
module griper() {
        // translate([-5.2,0,2.5])scale(0.85) cube([3.5,9.5,4],center=true);
        // translate([0,0,2.5]) scale(0.85) cube([11,3,4],center=true);
        // translate([5.2,0,2.5]) scale(0.85) cube([3.5,9.5,4],center=true);
        translate([-5,0,2.5])scale(0.85) cube([3.5,9.5,4],center=true);
        translate([0,0,2.5]) scale(0.85) cube([11,3.1,4],center=true);
        translate([5,0,2.5]) scale(0.85) cube([3.5,9.5,4],center=true);
}

//////////////////////////////////////////////////////////////////////
//
module griperEnd() {
        translate([-2,0,2]) {
            scale(0.85) {
                cube([6,4,4],center=true);
            }
        }
}

//////////////////////////////////////////////////////////////////////
//
module star() {
    difference() {
        rotate([0,0,18])translate([-24,-24,10]) {
          import(file="ChristmasStarPiece_thin_v4.stl",layer="",convexity=15);
        }
        bullet_pixel();
    }
}

//////////////////////////////////////////////////////////////////////
//
module star2() {
    difference() {
        star();
        union() {
            for (i=[0:5]) rotate([0,0,i*72]) translate([15,0,-5]) rotate([0,30,0])grip();
        }
    }
}

//////////////////////////////////////////////////////////////////////
//
module starbase() {
    difference() {
        union() {
            star();

            // The gripper ends that mate in to the empty gripper holes..
            //
            union() {
                for (i=[0:5]) {
                    rotate([0,0,i*72]) {
                        translate([19,0,-1]) {
                            rotate([0,30,0]) {
                                griperEnd();
                            }
                        }
                    }
                }
            }
        }

        // A hole for the wires to enter the star..
        //
        translate([0,0,0]) {
            rotate([0,0,18.75]) {
                translate([0,19.5,0]) {
                    rotate([-38,0,0]) {
                          cylinder(40,3.5,3.5,center=true,$fn=20);
                    }
                }
            }
        }

        // a cube to cut off the parts of the gripper ends that extend below
        // the z 0 plane.
        //
        translate([0,0,-50]) {
            cube([100,100,100],center=true);
        }
    }
}


//////////////////////////////////////////////////////////////////////
//
// lay out a grid of a bunch of grippers.
//
module grippers() {
    for( i = [-1:1]) {
        for( j = [-1:1] ) {
            translate([19 * i, 12 * j, 0]) {
                griper();
            }
        }
    }
}

//////////////////////////////////////////////////////////////////////
//
// the 'bullet' shaped pixel led light from adafruit. We need this so we can
// difference it out of the base of the star.
//
// It is a big cylinder which is the body of the pixel topped by a small
// cylinder topped by a hemisphere. Normally 23mm up from the bottom of the
// pixel is the mounting hole but we are sticking pretty much the whole thing
// in to the star so all we care about is the top part of the pixel being
// capped properly.
//
module bullet_pixel() {
    bullet_r = 14/2;
    bullet_led_r = 9.5/2;
    bullet_h = 23;
    bullet_top_h = (11 - bullet_led_r);

    $fn = 20;

    union() {
        cylinder(bullet_h, bullet_r, bullet_r - 0.5, center = false);
        translate([0,0,bullet_h - 0.01]) {
            cylinder(bullet_top_h, bullet_r - 0.5, bullet_led_r, center = false);
            translate([0,0,bullet_top_h]) {
                sphere(r = bullet_led_r);
            }
        }
    }
}

//////////////////////////////////////////////////////////////////////
//
// since the star has 12 points on all sides it has no easy way to mount it
// on the tree so make this mount for it. The mount attaches to the top of
// the tree, and the star rests in the mount.
//
module star_mount() {
    // This is the hole for the mount where it goes on top of the tree.
    //
    // tree_mount_h = 30;
    tree_mount_h = 20;
    tree_mount_r = 10;

    // This is the height of the star point off of z0. Also indicate
    // how tall the total mount is.
    // star_point_h = 45;
    star_point_h = 25;

    // Distance between the tip of the star point and the top of the
    //tree mount hole.
    //
    spacer = 4;

    // The radius of the top and bottom of the tree mount. 20 is good
    // for a default. For a stable base without a tree mount you can go larger.
    //
    mount_r_top = 20;
    // mount_r_bottom = 20;
    mount_r_bottom = 30;

    // The offset from the ground for the point of the star
    // star_ground_offset = 82;
    star_ground_offset = 35 + star_point_h;

    difference() {
         union() {
           cylinder(tree_mount_h + star_point_h + spacer, mount_r_bottom,mount_r_top, center = false, $fn = 40);
           translate([0,0,5]) {
               cube(size = [90,10,10], center = true);
               cube(size = [10,90,10], center = true);
           }
         }
        // translate([0,0,-0.05]) {
        //     cylinder(tree_mount_h, tree_mount_r, tree_mount_r, center = false, $fn = 40);
        // }
        translate([0,0,star_point_h + spacer + star_ground_offset]) {
            rotate([0,180,0]) {
                scale(1) {
                    star();
                }
            }
        }
    }
}