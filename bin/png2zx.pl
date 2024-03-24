#!/usr/bin/env perl

# applies a color transformation to a PNG so that only 2 colors are used in
# 8x8 cells (ZX attributes)

use Modern::Perl;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Std;
use File::Basename qw( basename );
use Data::Dumper;

use ZXGfx;

#################
## Main
#################

our ( $opt_i, $opt_o );
getopts("i:o:");

( defined( $opt_i ) and defined( $opt_o ) ) or
    die "usage: ".basename( $0 ). "-i <input_png> -o <output_png>\n";
my $input_file = $opt_i;
my $output_file = $opt_o;

# load source PNG
my $gfx = zxgfx_extract_from_png( $input_file );

# apply color transformation
foreach my $row ( 0 .. zxgfx_get_height_cells( $gfx ) - 1 ) {
    foreach my $col ( 0 .. zxgfx_get_width_cells( $gfx ) - 1 ) {
        zxgfx_convert_cell_colors_to_attr( $gfx, $col * 8, $row * 8 );
    }
}

# output destination PNG
zxgfx_write_png( $output_file, $gfx );
