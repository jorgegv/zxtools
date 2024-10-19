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

Extracts graphics data (sprite/tile) from a source PNG file at a given
position and size, and generates C or ASM data definitions.  Graphics
elements are created with the given symbol name, and can be generated with
different layouts (by cells, by lines,...) and data formats (pixels only,
pixels and mask, attributes).  Some extra quirks for specialized layouts
(e.g.  SP1 sprite library) are also available, and preshifted sprites can
also be generated with various shift steps.

All coordinates and dimensions are in pixels except for --row and --col. 
Width and height must be multiples of 8.

Colors are specified in standard web format: RRGGBB values with hex digits.

Options:

    -i, --input <png_file>
    -x, --xpos <x_position>
    -y, --ypos <y_position>
        --row <row_position> (exclusive with --ypos)
        --col <column_position> (exclusive with --xpos)
    -w, --width <width>
    -h, --height <height>
    -m, --mask <mask_color> - default: FF0000 (red)
    -f, --foreground <foreground_color> - default: FFFFFF (white)
    -b, --background <background_color> - default: 000000 (black)
    -c, --code-type <c|asm>
    -s, --symbol-name <C/ASM identifier>
    -l, --layout <scanlines,rows,columns>
    -g, --gfx-type <tile,sprite>
    -p, --preshift <1|2|4>
        --extra-right-col - generate sprite extra empty right column (default: no)
        --extra-bottom-row - generate sprite extra empty bottom row, SP1 style (default: no)

EOF_USAGE
;
    exit 1;
}

#############################
##
## CLI option processing
##
#############################

my ($opt_input, $opt_xpos, $opt_ypos, $opt_width, $opt_height, $opt_mask,
    $opt_foreground, $opt_background, $opt_code_type, $opt_symbol_name,
    $opt_layout, $opt_gfx_type, $opt_preshift, $opt_extra_right_col,
    $opt_extra_bottom_row, $opt_row, $opt_col );

sub process_cli_options {
    GetOptions(
        'input=s'		=> \$opt_input,
        'xpos:i'		=> \$opt_xpos,
        'ypos:i'		=> \$opt_ypos,
        'row:i'			=> \$opt_row,
        'col:i'			=> \$opt_col,
        'width=i'		=> \$opt_width,
        'height=i'		=> \$opt_height,
        'mask:s'		=> \$opt_mask,
        'foreground:s'		=> \$opt_foreground,
        'background:s'		=> \$opt_background,
        'code-type=s'		=> \$opt_code_type,
        'symbol-name=s'		=> \$opt_symbol_name,
        'layout=s'		=> \$opt_layout,
        'gfx-type=s'		=> \$opt_gfx_type,
        'preshift=i'		=> \$opt_preshift,
        'extra-right-col'	=> \$opt_extra_right_col,
        'extra-bottom-row'	=> \$opt_extra_bottom_row,
    ) or show_usage;

    # check for mandatory options
    ( defined( $opt_input ) and ( defined( $opt_xpos ) or defined( $opt_col) ) and 
      ( defined( $opt_ypos ) or defined( $opt_row ) ) and 
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
        $opt_mask = uc( $opt_mask );
    } else {
        $opt_mask = 'FF0000';
    }

    if ( defined( $opt_background ) ) {
        ( $opt_background =~ m/^[0-9a-f]{6}$/i ) or
            die "--background must have format RRGGBB\n";
        $opt_background = uc( $opt_background );
    } else {
        $opt_background = '000000';
    }

    if ( defined( $opt_foreground ) ) {
      ( $opt_foreground =~ m/^[0-9a-f]{6}$/i ) or
        die "--foreground must have format RRGGBB\n";
        $opt_foreground = uc( $opt_foreground );
    } else {
        $opt_foreground = 'FFFFFF';
    }

    grep { m/$opt_code_type/i } qw( c asm ) or
        die "--code-type must be one of 'c' or 'asm'\n";
    $opt_code_type = lc( $opt_code_type );
      
    ( $opt_symbol_name =~ m/[A-Z][A-Z0-9_]+/i ) or
        die "--symbol-name must be a valid symbol name\n";

    grep { m/$opt_gfx_type/i } qw( tile sprite ) or
        die "--gfx-type must be one of 'tile' or 'sprite'\n";
    $opt_gfx_type = lc( $opt_gfx_type );

    if ( $opt_gfx_type eq 'tile' ) {
        grep { m/$opt_layout/i } qw( scanlines rows columns ) or
            die "--layout must be one of 'scanlines', 'rows' or 'columns' in tile mode\n";
    }
    if ( $opt_gfx_type eq 'sprite' ) {
        grep { m/$opt_layout/i } qw( columns ) or
            die "--layout can only be 'columns' in sprite mode\n";
    }
    $opt_layout = lc( $opt_layout );

    if ( defined( $opt_preshift ) ) {
        if ( not $opt_preshift =~ m/^[124]$/ ) {
            die "--preshift value must be 1, 2 or 4\n";
        }
    }

    if ( $opt_gfx_type ne 'sprite' ) {
        defined( $opt_extra_right_col ) and
            die "--extra-right-col is only valid in sprite mode\n";
        defined( $opt_extra_bottom_row ) and
            die "--extra-bottom-row is only valid in sprite mode\n";
    }

    # override xpos and ypos with col and row
    if ( defined( $opt_col ) and defined( $opt_xpos ) ) {
        die "--xpos and --col cannot be used together\n";
    }
    if ( defined( $opt_col ) ) {
        $opt_xpos = $opt_col * 8;
    }

    if ( defined( $opt_row ) and defined( $opt_ypos ) ) {
        die "--ypos and --row cannot be used together\n";
    }
    if ( defined( $opt_row ) ) {
        $opt_ypos = $opt_row * 8;
    }
}

######################
##
## OUTPUT FUNCTIONS
##
######################

sub byte2bin {
    my $byte = shift;
    my $bin;
    foreach my $bit ( 0 .. 7 ) {
        $bin .= ( ( $byte & ( 1 << ( 7 - $bit ) ) ) ? '1' : '0' );
    }
    return $bin;
}

sub byte2graph {
    my $byte = shift;
    my $bin;
    foreach my $bit ( 0 .. 7 ) {
        $bin .= ( ( $byte & ( 1 << ( 7 - $bit ) ) ) ? '##' : '..' );
    }
    return $bin;
}

############################
## tile output functions
############################

my %tile_output_format = (
    preamble => {
        'c'	=> '',
        'asm'	=> "\tsection data_compiler\n\n",
    },
    comment1 => {
        'c'	=> "// tile '%s' definition\n// pixel data\n",
        'asm'	=> ";; tile '%s' definition\n;; pixel data\n",
    },
    header1 => {
        'c'	=> "uint8_t %s_pixels[ %d ] = {\n",
        'asm'	=> "PUBLIC %s_pixels\t;; %d bytes\n",
    },
    header2 => {
        'c'	=> "",
        'asm'	=> "%s_pixels:\n",
    },
    comment2 => {
        'c'	=> "\t// rows: 0-%d, col: %d\n",
        'asm'	=> "\t;; rows: 0-%d, col: %d\n",
    },
    output1 => {
        'c'	=> "\t0x%02x,\t\t// pix: %s",
        'asm'	=> "\tdb\t\$%02x\t\t;; pix: %s",
    },
    comment3 => {
        'c'	=> "\t// row: %d, col: %d\n",
        'asm'	=> "\t;; row: %d, col: %d\n",
    },
    comment4 => {
        'c'	=> "\t// row: %d, cols: 0-%d\n",
        'asm'	=> "\t;; row: %d, cols: 0-%d\n",
    },
    output2 => {
        'c'	=> "\t%s,\t\t// pix: %s\n",
        'asm'	=> "\t%s,\t\t;; pix: %s\n",
    },
    output3 => {
        'c'	=> "\t%s,\t\t// pix: %s\n",
        'asm'	=> "\t%s,\t\t;; pix: %s\n",
    },
    output4 => {
        'c'	=> "0x%02x",
        'asm'	=> "\$%02x",
    },
    footer1 => {
        'c'	=> "};\n",
        'asm'	=> "",
    },
    header3 => {
        'c'	=> "uint8_t %s_attr[ %d ] = {\n",
        'asm'	=> "PUBLIC %s_attr\t;; %d attributes\n",
    },
    header4 => {
        'c'	=> "",
        'asm'	=> "%s_attr:\n",
    },
    output5 => {
        'c'	=> "\t%s,\t// row:%2d, col:%2d, attr: %sb - %s\n",
        'asm'	=> "\tdb\t%s\t;; row:%2d, col:%2d, attr: %sb - %s\n",
    },
    footer2 => {
        'c'	=> "};\n",
        'asm'	=> ";;;;;;;;;;;;\n",
    },
);

sub output_tiles {
    my $gfx = shift;
    my $ct = $opt_code_type;

    # preamble
    print $tile_output_format{'preamble'}{ $ct };

    # pixels: header
    printf $tile_output_format{'comment1'}{ $ct }, $opt_symbol_name;
    printf $tile_output_format{'header1'}{ $ct }, $opt_symbol_name, zxgfx_get_width_cells( $gfx )  *  zxgfx_get_height_cells( $gfx ) * 8;
    if ( $tile_output_format{'header2'}{ $ct } ) {
        printf $tile_output_format{'header2'}{ $ct }, $opt_symbol_name;
    }

    # pixels: data
    if ( $opt_layout eq 'columns' ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            printf $tile_output_format{'comment2'}{ $ct }, (zxgfx_get_height_cells( $gfx ) - 1), $col;
            foreach my $row (0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
                print join("\n", map {
                    sprintf $tile_output_format{'output1'}{ $ct }, $_, byte2graph( $_ )
                } @{ $gfx->{'cells'}[ $row ][ $col ]{'bytes'} } );
                print "\n";
            }
            print "\n";
        }
        print "\n";
    }

    if ( $opt_layout eq 'rows' ) {
        foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
            foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
                printf $tile_output_format{'comment3'}{ $ct }, $row, $col;
                print join("\n", map {
                    sprintf $tile_output_format{'output1'}{ $ct }, $_, byte2graph( $_ )
                } @{ $gfx->{'cells'}[ $row ][ $col ]{'bytes'} } );
                print "\n\n";
            }
        }
    }
    if ( $opt_layout eq 'scanlines' ) {
        foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
            printf $tile_output_format{'comment4'}{ $ct }, $row, (zxgfx_get_width_cells( $gfx ) - 1);
            foreach my $scan ( 0 .. 7 ) {
                my @scan_bytes = map {
                    $gfx->{'cells'}[ $row ][ $_ ]{'bytes'}[ $scan ];
                } ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) );
                printf $tile_output_format{'output3'}{ $ct },
                    join( ", ", map { sprintf( $tile_output_format{'output4'}{ $ct }, $_ ) } @scan_bytes ),
                    join( '', map { byte2graph( $_ ) } @scan_bytes );
            }
            print "\n";
        }
    }


    # pixels: footer
    print $tile_output_format{'footer1'}{ $ct };

    # attr: header
    printf $tile_output_format{'header3'}{ $ct }, $opt_symbol_name, zxgfx_get_width_cells( $gfx ) * zxgfx_get_height_cells( $gfx );
    if ( $tile_output_format{'header4'}{ $ct } ) {
        printf $tile_output_format{'header4'}{ $ct }, $opt_symbol_name;
    }
    
    # attr: data
    # column-major order for 'columns' mode, row-major order for 'rows' and 'scanlines' modes
    if ( $opt_layout eq 'columns' ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            foreach my $row (0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
                printf $tile_output_format{'output5'}{ $ct },
                    $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_integer'},
                    $row,$col,
                    byte2bin( $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_integer'} ),
                    $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_text'},
                ;
            }
        }
    }
    if ( ( $opt_layout eq 'rows' ) or ( $opt_layout eq 'scanlines' ) ) {
        foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
            foreach my $col (0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
                printf $tile_output_format{'output5'}{ $ct },
                    $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_integer'},
                    $row,$col,
                    byte2bin( $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_integer'} ),
                    $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_text'},
                ;
            }
        }
    }
    
    # attr: footer
    print $tile_output_format{'footer2'}{ $ct };
    print "\n";

}

#############################
## sprite output functions
#############################

my %sprite_output_format = (
    preamble => {
        'c'	=> '',
        'asm'	=> "\tsection data_compiler\n\n",
    },
    comment1 => {
        'c'	=> "// sprite '%s' definition\n// pixel data\n// %s\n// %s\n",
        'asm'	=> ";; sprite '%s' definition\n;; pixel data\n;; %s\n;; %s\n",
    },
    header1 => {
        'c'	=> "uint8_t %s_pixels[ %d ] = {\n",
        'asm'	=> "PUBLIC %s_pixels\t;; %d bytes \n",
    },
    header2 => {
        'c'	=> "",
        'asm'	=> "%s_pixels:\n",
    },
    comment2 => {
        'c'	=> "\t// rows: 0-%d, col: %d\n",
        'asm'	=> "\t;; rows: 0-%d, col: %d\n",
    },
    output1 => {
        'c'	=> "\t0x%02x, 0x%02x,\t\t// mask: %s   pix: %s",
        'asm'	=> "\tdb\t\$%02x,\$%02x\t\t;; mask: %s   pix: %s",
    },
    comment3 => {
        'c'	=> "\t// extra right column\n",
        'asm'	=> "\t;; extra right column\n",
    },
    footer => {
        'c'	=> "};\n",
        'asm'	=> ";;;;;;\n",
    },
);

# receives listref to masks and pixels, returns list of listrefs with 2 elemens each: [0]=mask, [1]=pixel
sub mix_mask_and_pixel {
    my ($masks,$pixels) = @_;
    my @list;
    while ( scalar( @$pixels ) ) {
        push @list, [ shift @$masks, shift @$pixels ];
    }
    return @list;
}

## at the moment, all sprite pixel data is output in interleaved format,
## that is (mask,pixel) byte pairs

sub output_sprite {
    my $gfx = shift;
    my $ct = $opt_code_type;

    # preamble
    print $sprite_output_format{'preamble'}{ $ct };

    # pixels: header
    printf( $sprite_output_format{'comment1'}{ $ct },
        $opt_symbol_name,
        ( $opt_extra_bottom_row ? 'with extra blank bottom row' : '' ),
        ( $opt_extra_right_col ? 'with extra blank right column' : '' ),
    );
    printf( $sprite_output_format{'header1'}{ $ct },
        $opt_symbol_name,
        ( zxgfx_get_width_cells( $gfx ) + ( $opt_extra_right_col ? 1 : 0 ) ) * 
        ( zxgfx_get_height_cells( $gfx ) + ( $opt_extra_bottom_row ? 1 : 0 )  ) * 8 * 2
    );
    if ( $sprite_output_format{'header2'}{ $ct } ) {
        printf $sprite_output_format{'header2'}{ $ct }, $opt_symbol_name;
    }

    # pixels: data
    if ( $opt_layout eq 'columns' ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            printf $sprite_output_format{'comment2'}{ $ct }, (zxgfx_get_height_cells( $gfx ) - 1), $col;
            foreach my $row (0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
                print join("\n", map {
                    sprintf $sprite_output_format{'output1'}{ $ct },
                        $_->[0], $_>[1], byte2graph( $_->[0] ), byte2graph( $_->[1] );
                } mix_mask_and_pixel( $gfx->{'cells'}[ $row ][ $col ]{'masks'}, $gfx->{'cells'}[ $row ][ $col ]{'bytes'} ) );
                print "\n";
            }
            if ( $opt_extra_bottom_row ) {
                print join("\n", map {
                    sprintf $sprite_output_format{'output1'}{ $ct },
                        $_->[0], $_->[1], byte2graph( $_->[0] ), byte2graph( $_->[1] );
                } ( ( [ 255, 0] ) x 8 ) );
                print "\n";
            }
            print "\n";
        }
        if ( $opt_extra_right_col ) {
            print $sprite_output_format{'comment3'}{ $ct };
            print join("\n", map {
                sprintf $sprite_output_format{'output1'}{ $ct },
                    $_->[0], $_->[1], byte2graph( $_->[0] ), byte2graph( $_->[1] );
            } ( ( [ 255,0 ] ) x ( ( zxgfx_get_height_cells( $gfx ) + ( $opt_extra_bottom_row ? 1 : 0 )  ) * 8 ) ) );
            print "\n";
        }
    }

    # pixels: footer
    print $sprite_output_format{'footer'}{ $ct };

}

#####################
##
## Main program
##
#####################

## process options
process_cli_options;

## import the PNG file, extract the region indicated and convert it into ZX color space
my $gfx = zxgfx_extract_from_png( $opt_input, $opt_xpos, $opt_ypos, $opt_width, $opt_height );

## validate max number of colors is valid in all cells
##   tile: fg, and bg
##   sprite: fg, bg and mask
my $max_colors = ( $opt_gfx_type eq 'tile' ? 2 : 3 );
my $errors = zxgfx_validate_cell_colors( $gfx, $max_colors );
if ( @$errors ) {
    die join( "\n",
        "Error: ZX incompatible color combinations were found in the source image:",
        @$errors,
        ) . "\n";
}

## create the data for the 8x8 cells according to the type of data requested, and output the generated code
if ( $opt_gfx_type eq 'tile' ) {
    zxgfx_extract_tile_cells( $gfx );
    output_tiles( $gfx );
} elsif ( $opt_gfx_type eq 'sprite' ) {
    zxgfx_extract_sprite_cells( $gfx, $opt_foreground, $opt_background, $opt_mask );
    output_sprite( $gfx );
} else {
    die "Unknown --gfx-type value ($opt_gfx_type), should not happen!\n";
}

#print Dumper( $gfx );
