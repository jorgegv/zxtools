#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use Getopt::Long;

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
}

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
