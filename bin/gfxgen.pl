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
are also available, and preshifted sprites can also be generated with various shift steps.

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
    -p, --preshift <1|2|4>
        --extra-right-col - generate empty extra right column (default: no)
        --extra-bottom-row - generate SP1 empty extra bottom row (default: no)

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
    $opt_extra_bottom_row );

sub process_cli_options {
    GetOptions(
        'input=s'		=> \$opt_input,
        'xpos=i'		=> \$opt_xpos,
        'ypos=i'		=> \$opt_ypos,
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
    $opt_code_type = lc( $opt_code_type );
      
    ( $opt_symbol_name =~ m/[A-Z][A-Z0-9_]+/i ) or
        die "--symbol-name must be a valid symbol name\n";

    grep { m/$opt_layout/i } qw( scanlines rows columns ) or
        die "--layout must be one of 'scanlines', 'rows' or 'columns'\n";
    $opt_layout = lc( $opt_layout );

    grep { m/$opt_gfx_type/i } qw( tile sprite ) or
        die "--gfx-type must be one of 'tile' or 'sprite'\n";
    $opt_gfx_type = lc( $opt_gfx_type );

    if ( defined( $opt_preshift ) ) {
        if ( not $opt_preshift =~ m/^[124]$/ ) {
            die "--preshift value must be 1, 2 or 4\n";
        }
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

my %tile_output_fn = (
    'c'		=> \&output_tiles_c,
    'asm'	=> \&output_tiles_asm,
);

sub output_tiles {
    my $gfx = shift;
    $tile_output_fn{ $opt_code_type }( $gfx );
}

sub output_tiles_c {
    my $gfx = shift;

    # pixels: header
    printf "// tile '%s' definition\n// pixel data\n", $opt_symbol_name;
    printf "uint8_t %s_pixels[ %d ] = {\n", $opt_symbol_name, zxgfx_get_width_cells( $gfx )  *  zxgfx_get_height_cells( $gfx ) * 8;

    # pixels: data
    if ( $opt_layout eq 'columns' ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            printf "\t// rows: 0-%d, col: %d\n", (zxgfx_get_height_cells( $gfx ) - 1), $col;
            foreach my $row (0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
                print join("\n", map {
                    sprintf "\t0x%02x,\t\t// pix: %s", $_, byte2graph( $_ )
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
                printf "\t// row: %d, col: %d\n", $row, $col;
                print join("\n", map {
                    sprintf "\t0x%02x,\t\t// pix: %s", $_, byte2graph( $_ )
                } @{ $gfx->{'cells'}[ $row ][ $col ]{'bytes'} } );
                print "\n\n";
            }
        }
    }
    if ( $opt_layout eq 'scanlines' ) {
        foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
            printf "\t// row: %d, cols: 0-%d\n", $row, (zxgfx_get_width_cells( $gfx ) - 1);
            foreach my $scan ( 0 .. 7 ) {
                my @scan_bytes = map {
                    $gfx->{'cells'}[ $row ][ $_ ]{'bytes'}[ $scan ];
                } ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) );
                printf "\t%s,\t\t// pix: %s\n",
                    join( ", ", map { sprintf( "0x%02x", $_ ) } @scan_bytes ),
                    join( '', map { byte2graph( $_ ) } @scan_bytes );
            }
            print "\n";
        }
    }


    # pixels: footer
    print "};\n";

    # attr: header
    printf "uint8_t %s_attr[ %d ] = {\n", $opt_symbol_name, zxgfx_get_width_cells( $gfx ) * zxgfx_get_height_cells( $gfx );
    
    # attr: data
    # column-major order for 'columns' mode, row-major order for 'rows' and 'scanlines' modes
    if ( $opt_layout eq 'columns' ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            foreach my $row (0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
                printf "\t%s,\t// row:%2d, col:%2d, attr: %s\n",
                    $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_text'},
                    $row,$col,
                    byte2bin( $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_integer'} );
            }
        }
    }
    if ( ( $opt_layout eq 'rows' ) or ( $opt_layout eq 'scanlines' ) ) {
        foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
            foreach my $col (0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
                printf "\t%s,\t// row:%2d, col:%2d, attr: %sb\n",
                    $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_text'},
                    $row,$col,
                    byte2bin( $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_integer'} );
            }
        }
    }
    
    # attr: footer
    print "};\n";
    print "\n";

}

sub output_tiles_asm {
    my $gfx = shift;

    # pixels: header
    print ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n";
    printf ";; tile '%s' definition\n;; pixel data\n\n", $opt_symbol_name;
    printf "PUBLIC %s_pixels\n", $opt_symbol_name;
    printf "%s_pixels:\n", $opt_symbol_name;

    # pixels: data
    if ( $opt_layout eq 'columns' ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            printf "\t;; rows: 0-%d, col: %d\n", (zxgfx_get_height_cells( $gfx ) - 1), $col;
            foreach my $row (0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
                print join("\n", map {
                    sprintf "\tdb\t\$%02x\t\t;; pix: %s", $_, byte2graph( $_ )
                } @{ $gfx->{'cells'}[ $row ][ $col ]{'bytes'} } );
                print "\n";
            }
            print "\n";
        }
    }
    if ( $opt_layout eq 'rows' ) {
        foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
            foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
                printf "\t// row: %d, col: %d\n", $row, $col;
                print join("\n", map {
                    sprintf "\tdb\t\$%02x\t\t;; pix: %s", $_, byte2graph( $_ )
                } @{ $gfx->{'cells'}[ $row ][ $col ]{'bytes'} } );
                print "\n\n";
            }
        }
    }
    if ( $opt_layout eq 'scanlines' ) {
        foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
            printf "\t// row: %d, cols: 0-%d\n", $row, (zxgfx_get_width_cells( $gfx ) - 1);
            foreach my $scan ( 0 .. 7 ) {
                my @scan_bytes = map {
                    $gfx->{'cells'}[ $row ][ $_ ]{'bytes'}[ $scan ];
                } ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) );
                printf "\tdb\t%s\t\t;; pix: %s\n",
                    join( ",", map { sprintf( "\$%02x", $_ ) } @scan_bytes ),
                    join( '', map { byte2graph( $_ ) } @scan_bytes );
            }
            print "\n";
        }
    }

    # pixels: footer
    # nothing special needed

    # attr: header
    print ";; attribute data\n";
    printf "PUBLIC %s_attr\n", $opt_symbol_name;
    printf "%s_attr:\n", $opt_symbol_name;
    
    # attr: data
    # column-major order for 'columns' mode, row-major order for 'rows' and 'scanlines' modes
    if ( $opt_layout eq 'columns' ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            foreach my $row (0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
                printf "\tdb\t\$%02x\t\t;; row:%2d, col:%2d, attr: %s\n",
                    $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_integer'},
                    $row,$col,
                    $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_text'};
            }
        }
    }
    if ( ( $opt_layout eq 'rows' ) or ( $opt_layout eq 'scanlines' ) ) {
        foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
            foreach my $col (0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
                printf "\tdb\t\$%02x,\t\t;; row:%2d, col:%2d, attr: %s\n",
                    $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_integer'},
                    $row,$col,
                    $gfx->{'cells'}[ $row ][ $col ]{'attr'}{'as_text'};
            }
        }
    }
    
    # attr: footer
    print ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n";
    print "\n";

}

#############################
## sprite output functions
#############################

my %sprite_output_fn = (
    'c'		=> \&output_sprite_c,
    'asm'	=> \&output_sprite_asm,
);

sub output_sprite {
    my $gfx = shift;
    $sprite_output_fn{ $opt_code_type }( $gfx );
}

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

sub output_sprite_c {
    my $gfx = shift;

    # WIP
    # pixels: header
    printf "// sprite '%s' definition\n// pixel data\n", $opt_symbol_name;
    if ( $opt_extra_bottom_row ) {
        printf "// with extra blank bottom row\n";
    }
    if ( $opt_extra_right_col ) {
        printf "// with extra blank right column\n";
    }
    printf "uint8_t %s_pixels[ %d ] = {\n", $opt_symbol_name,
        ( zxgfx_get_width_cells( $gfx ) + ( $opt_extra_right_col ? 1 : 0 ) ) * 
        ( zxgfx_get_height_cells( $gfx ) + ( $opt_extra_bottom_row ? 1 : 0 )  ) * 8 * 2;

    # pixels: data
    if ( $opt_layout eq 'columns' ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            printf "\t// rows: 0-%d, col: %d\n", (zxgfx_get_height_cells( $gfx ) - 1), $col;
            foreach my $row (0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
                print join("\n", map {
                    sprintf "\t0x%02x, 0x%02x,\t\t// mask: %s   pix: %s",
                        $_->[0], $_>[1], byte2graph( $_->[0] ), byte2graph( $_->[1] );
                } mix_mask_and_pixel( $gfx->{'cells'}[ $row ][ $col ]{'masks'}, $gfx->{'cells'}[ $row ][ $col ]{'bytes'} ) );
                print "\n";
            }
            if ( $opt_extra_bottom_row ) {
                print join("\n", map {
                    sprintf "\t0x%02x, 0x%02x,\t\t// mask: %s   pix: %s",
                        $_->[0], $_->[1], byte2graph( $_->[0] ), byte2graph( $_->[1] );
                } ( ( [ 255, 0] ) x 8 ) );
                print "\n";
            }
            print "\n";
        }
        if ( $opt_extra_right_col ) {
            print "\t// extra right column\n";
            print join("\n", map {
                sprintf "\t0x%02x, 0x%02x,\t\t// mask: %s   pix: %s",
                    $_->[0], $_->[1], byte2graph( $_->[0] ), byte2graph( $_->[1] );
            } ( ( [ 255,0 ] ) x ( ( zxgfx_get_height_cells( $gfx ) + ( $opt_extra_bottom_row ? 1 : 0 )  ) * 8 ) ) );
            print "\n";
        }
    }

    if ( $opt_layout eq 'rows' ) {
        foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
            foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
                printf "\t// row: %d, col: %d\n", $row, $col;
                print join("\n", map {
                    sprintf "\t0x%02x,\t\t// pix: %s", $_, byte2graph( $_ )
                } @{ $gfx->{'cells'}[ $row ][ $col ]{'bytes'} } );
                print "\n\n";
            }
        }
    }
    if ( $opt_layout eq 'scanlines' ) {
        foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
            printf "\t// row: %d, cols: 0-%d\n", $row, (zxgfx_get_width_cells( $gfx ) - 1);
            foreach my $scan ( 0 .. 7 ) {
                my @scan_bytes = map {
                    $gfx->{'cells'}[ $row ][ $_ ]{'bytes'}[ $scan ];
                } ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) );
                printf "\t%s,\t\t// pix: %s\n",
                    join( ", ", map { sprintf( "0x%02x", $_ ) } @scan_bytes ),
                    join( '', map { byte2graph( $_ ) } @scan_bytes );
            }
            print "\n";
        }
    }


    # pixels: footer
    print "};\n";

}

sub output_sprite_asm {
    my $gfx = shift;
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
