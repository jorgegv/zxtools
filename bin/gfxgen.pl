#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Long;
use GD;
use Data::Dumper;

use ZXGfx;

sub show_usage {
    print <<EOF_USAGE
gfxgen.pl - Create ZX Spectrum graphics C/ASM data definitions from a PNG file

Extracts graphics data (sprite/tile) from a source PNG file at a given position and size, and
generates C or ASM data definitions.  Graphics elements are created with the given symbol name, and
can be generated with different layouts (by cells, by lines,...) and data formats (pixels only,
pixels and mask, attributes).  Some extra quirks for specialized layouts (e.g.  SP1 sprite library)
are also available.

All coordinates and dimensions are in pixels. Width and height must be multiples of 8.

Colors are specified in standard web format: RRGGBB values with hex digits.

Options:

    -i, --input <png_file>
    -x, --xpos <x_position>
    -y, --ypos <y_position>
    -w, --width <width>
    -h, --height <height>
    -m, --mask <mask_color> - default: FF0000 (red)
    -f, --foreground <foreground_color> - default: FFFFFF (white)
    -b, --background <background_color> - default: 000000 (black)
    -c, --code-type <c|asm>
    -s, --symbol-name <C/ASM identifier>
    -l, --layout <scanlines,rows,columns>
    -g, --gfx-type <tile,sprite>
        --extra-blank-col - generate empty extra right column (default: no)
        --extra-blank-row - generate SP1 empty extra bottom row (default: no)

EOF_USAGE
;
    exit 1;
}

#####################
##
## Main program
##
#####################

# process cli options
my ($opt_input, $opt_xpos, $opt_ypos, $opt_width, $opt_height,
    $opt_mask, $opt_foreground, $opt_background, $opt_code_type, $opt_symbol_name,
    $opt_layout, $opt_gfx_type, $opt_extra_blank_col, $opt_extra_blank_row );
GetOptions(
    'input=s'		=> \$opt_input,
    'xpos=i'		=> \$opt_xpos,
    'ypos=i'		=> \$opt_ypos,
    'width=i'		=> \$opt_width,
    'height=i'		=> \$opt_height,
    'mask:s'		=> \$opt_mask,
    'foreground:s'	=> \$opt_foreground,
    'background:s'	=> \$opt_background,
    'code-type=s'	=> \$opt_code_type,
    'symbol-name=s'	=> \$opt_symbol_name,
    'layout=s'		=> \$opt_layout,
    'gfx-type=s'	=> \$opt_gfx_type,
    'extra-blank-col'	=> \$opt_extra_blank_col,
    'extra-blank-row'	=> \$opt_extra_blank_row,
) or show_usage;

# check for mandatory options
( defined( $opt_input ) and defined( $opt_xpos ) and defined( $opt_ypos ) and 
  defined( $opt_height ) and defined( $opt_width ) and defined( $opt_code_type ) and
  defined( $opt_symbol_name ) and defined( $opt_layout ) and defined( $opt_gfx_type ) ) 
  or show_usage;

# validate some options
not ( $opt_width % 8 ) or
    die "--width must be a multiple of 8\n";

not ( $opt_height % 8 ) or
    die "--height must be a multiple of 8\n";
  
if ( defined( $opt_mask ) ) {
    ( $opt_mask =~ m/^[0-9a-f]{6}$/i ) or
        die "--mask must have format RRGGBB\n";
} else {
    $opt_mask = 'FF0000';
}

if ( defined( $opt_background ) ) {
    ( $opt_background =~ m/^[0-9a-f]{6}$/i ) or
        die "--background must have format RRGGBB\n";
} else {
    $opt_background = '000000';
}

if ( defined( $opt_foreground ) ) {
  ( $opt_foreground =~ m/^[0-9a-f]{6}$/i ) or
    die "--foreground must have format RRGGBB\n";
} else {
    $opt_foreground = 'FFFFFF';
}

grep { m/$opt_code_type/i } qw( c asm ) or
    die "--code-type must be one of 'c' or 'asm'\n";
  
( $opt_symbol_name =~ m/[A-Z][A-Z0-9_]+/i ) or
    die "--symbol-name must be a valid symbol name\n";

grep { m/$opt_layout/i } qw( scanlines rows columns ) or
    die "--layout must be one of 'scanlines', 'rows' or 'columns'\n";
  
grep { m/$opt_gfx_type/i } qw( tile sprite ) or
    die "--gfx-type must be one of 'tile' or 'sprite'\n";
  
########################
##
### do what user wants
##

my $gfx = zxgfx_extract_from_png( $opt_input, $opt_xpos, $opt_ypos, $opt_width, $opt_height );

print Dumper( $gfx );
