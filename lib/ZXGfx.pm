#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use GD::Image;

# standard ZX Spectrum color palette
my %zx_color = (
    '000000' => 'BLACK',
    '0000C0' => 'BLUE',
    '00C000' => 'GREEN',
    '00C0C0' => 'CYAN',
    'C00000' => 'RED',
    'C000C0' => 'MAGENTA',
    'C0C000' => 'YELLOW',
    'C0C0C0' => 'WHITE',
    '0000FF' => 'BLUE',
    '00FF00' => 'GREEN',
    '00FFFF' => 'CYAN',
    'FF0000' => 'RED',
    'FF00FF' => 'MAGENTA',
    'FFFF00' => 'YELLOW',
    'FFFFFF' => 'WHITE',
);

my %zx_color_value = (
    'BLACK'	=> 0,
    'BLUE'	=> 1,
    'RED'	=> 2,
    'MAGENTA'	=> 3,
    'GREEN'	=> 4,
    'CYAN'	=> 5,
    'YELLOW'	=> 6,
    'WHITE'	=> 7,
);

# Extracts attribute values for a 8x8 cell out of PNG data, in RGB and text form
# returns: fg and bg RGB values, and also attribute text representation and integer value:
#   { fg => <fg_color>, bg => <bg_color>, as_text => 'INK_xxx | PAPER_yyy | BRIGHT', as_integer => zzz, all_colors => [ ... ] }
sub zxgfx_extract_attr_from_cell {
    my ( $gfx, $xpos, $ypos ) = @_;

    # create a color histogram for the whole cell
    my %histogram;
    foreach my $x ( $xpos .. ( $xpos + 7 ) ) {
        foreach my $y ( $ypos .. ( $ypos + 7 ) ) {
            my $pixel_color = $gfx->{'pixels'}[$y][$x];
            $histogram{$pixel_color}++;
        }
    }

    # sort the colors by descending frequency of occurence get the 2 most frequent
    my @all_colors = sort { $histogram{ $b } <=> $histogram{ $a } } keys %histogram;
    my $bg = $all_colors[0];
    my $fg = $all_colors[1] || $all_colors[0];    # just in case there is only 1 color

    # if one of them is black, it is preferred as bg color, swap them if needed
    if ( $fg eq '000000' ) {
        my $tmp = $bg;
        $bg = $fg;
        $fg = $tmp;
    }

    # generate the text representation
    my $attr_text = sprintf "INK_%s | PAPER_%s", $zx_color{ $fg }, $zx_color{ $bg };
    my $attr_value = $zx_color_value{ $zx_color{ $fg } } + 8 * $zx_color_value{ $zx_color{ $bg } };
    if ( ( $fg =~ /FF/ ) or ( $bg =~ /FF/ ) ) {
        $attr_text .= " | BRIGHT";
        $attr_value += 64;
    }

    # return data
    my $data = {
        'bg'		=> $bg,			# RRGGBB
        'fg'		=> $fg,			# RRGGBB
        'as_text'	=> $attr_text,		# 'INK_xxxx | PAPER_yyyy | BRIGHT'
        'as_integer'	=> $attr_value,		# integer
        'all_colors'	=> \@all_colors,	# list of all identified colors
        'histogram'	=> \%histogram,		# color histogram
    };
    return $data;
}

sub zxgfx_color_distance {
    my ( $color_a, $color_b ) = @_;

    $color_a =~ m/(\w\w)(\w\w)(\w\w)/;
    my ( $ra, $ga, $ba ) = map { hex } ( $1, $2, $3 );
    $color_b =~ m/(\w\w)(\w\w)(\w\w)/;
    my ( $rb, $gb, $bb ) = map { hex } ( $1, $2, $3 );

    return sqrt( ( $ra - $rb )**2 + ( $ga - $gb )**2 + ( $ba - $bb )**2 );
}

# for a given color, returns the nearest color from the standard ZX color palette
# returns: nearest color in RRGGBB format
my %color_map_cache;
sub zxgfx_zxcolors_best_fit {
    my $color = shift;

    # if the mapping has not been calculated before, calculate and put it
    # into the cache
    if ( not exists $color_map_cache{ $color } ) {
        $color =~ m/(\w\w)(\w\w)(\w\w)/;
        my ( $color_r, $color_g, $color_b ) = map { hex } ( $1, $2, $3 );
        my %distance = map {
            my $zxc = $_;
            $zxc =~ m/(\w\w)(\w\w)(\w\w)/;
            my ( $zx_r, $zx_g, $zx_b ) = map { hex } ( $1, $2, $3 );
            ( $zxc => ( ( $zx_r - $color_r )**2 + ( $zx_g - $color_g )**2 + ( $zx_b - $color_b )**2 ) );
        } keys %zx_color;
        my @sorted = sort { $distance{ $a } <=> $distance{ $b } } keys %zx_color;
        $color_map_cache{ $color } = $sorted[0];
    }

    # now it is positively in the cache, return it
    return $color_map_cache{ $color };
}

# processes a gfx replacing each pixel's color with the nearest ZX color
sub zxgfx_convert_to_zx_colors {
    my $gfx = shift;
    foreach my $r ( 0 .. $#{ $gfx->{'pixels'} } ) {
        foreach my $c ( 0 .. $#{ $gfx->{'pixels'}[$r] } ) {
            $gfx->{'pixels'}[$r][$c] = zxgfx_zxcolors_best_fit( $gfx->{'pixels'}[$r][$c] );
        }
    }
}

# Extracts a rectangular region from a PNG image and returns a structure
# with ZX Spectrum graphic data in the following format ($gfx ir the
# returned structure):
#
#   $gfx->{'pixels'}[<height>][<width>] = '<RRGGBB>' - for each pixel
#
# The colors in 'pixels' are converted by approximation to ZX colors
#
# If xpos,ypos are not provided, they are set to 0,0
#
# If width,height are not provided, they are set to the PNG dimensions minus xpos,ypos

sub zxgfx_extract_from_png {
    my ( $png_file, $xpos, $ypos, $width, $height ) = @_;

    my $png = GD::Image->newFromPng( $png_file );
    defined( $png ) or
        die "Could not load PNG file $png_file\n";

    # ensure default values
    $xpos   = $xpos   || 0;
    $ypos   = $ypos   || 0;
    $width  = $width  || ( $png->width - $xpos );
    $height = $height || ( $png->height - $ypos );

    # ensure the requested zone is inside the image
    ( ( $xpos + $width <= $png->width ) and ( $ypos + $height <= $png->height ) ) or
        die "The specified image is outside the bounds of the source image\n";

    # extract pixels from PNG - generates $graphic->{'pixels'}
    # bidimencional array of pixel colors in 'RRGGBB' format, row-major form
    my $gfx;
    foreach my $row ( 0 .. ($height - 1) ) {
      foreach my $col ( 0 .. ($width - 1) ) {
          $gfx->{'pixels'}[ $row ][ $col ] = sprintf( '%02x%02x%02x', $png->rgb( $png->getPixel( $xpos + $col, $ypos + $row ) ) );
      }
    }

    # convert pixels to spectrum colors - modifies $gfx->{'pixels'}
    zxgfx_convert_to_zx_colors( $gfx );

    # return result
    return $gfx;
}

# Extracts pixel values (8 bytes, top-down) for a 8x8 cell out of a $gfx, as an arrayref of 8 values
# We should have previously extracted the colors with zxgfx_extract_attr_from_cell() function and use the 
# fg and bg colors from there.
sub zxgfx_extract_tile_pixels_from_cell {
    my ( $gfx, $xpos, $ypos, $fg, $bg ) = @_;
    my @bytes;
    foreach my $row ( 0 .. 7 ) {
        my $byte = 0;
        foreach my $col ( 0 .. 7 ) {
            my $color = $gfx->{'pixels'}[ $ypos + $row ][ $xpos + $col ];
            if ( $color eq $bg ) {
                $byte += 0;			# add bg bit
            } elsif ( $color eq $fg ) {
                $byte += 1 << ( 7 - $col );	# add fg bit
            } else {
                warn sprintf("** Unexpected color $color found at (%d,%d)!\n", $xpos + $col, $ypos + $row );
            }
        }
        push @bytes, $byte;
    }
    return \@bytes;
}

# Processes a $gfx and adds tile data:
#     $gfx->{'cells'}[<rows>][<cols>] = { 'bytes' => [ <pixel_bytes> ], 'attr' => <attribute> } - for each 8x8 cell
# in row-major form
sub zxgfx_extract_tile_cells {
    my $gfx = shift;
    foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            my $attr = zxgfx_extract_attr_from_cell( $gfx, $col * 8, $row * 8 );
            my $pixels = zxgfx_extract_tile_pixels_from_cell( $gfx, $col * 8, $row * 8, $attr->{'fg'}, $attr->{'bg'} );
            $gfx->{'cells'}[ $row ][ $col ] = {
                bytes	=> $pixels,
                attr	=> $attr,
            };
        }
    }
}

# Extracts pixel and mask values (8 bytes, top-down) for a 8x8 cell out of a $gfx, as:
#     { pixels => [ ..pixel_bytes.. ], mask => [ ..mask_bytes.. ] }
# fg, bg and mask color are normally supplied by the user
sub zxgfx_extract_sprite_pixels_from_cell {
    my ( $gfx, $xpos, $ypos, $fg, $bg, $mask ) = @_;
    my @bytes;
    my @masks;
    foreach my $row ( 0 .. 7 ) {
        my $cur_byte = 0;
        my $cur_mask = 0;
        foreach my $col ( 0 .. 7 ) {
            my $color = $gfx->{'pixels'}[ $ypos + $row ][ $xpos + $col ];
            if ( $color eq $fg ) {
                $cur_byte += 1 << ( 7 - $col );	# add fg bit to pixels
            } elsif ( $color eq $bg ) {
                $cur_byte += 0;			# add bg bit to pixels
            } elsif ( $color eq $mask ) {
                $cur_mask += 1 << ( 7 - $col );	# add bit to mask
            } else {
                warn sprintf("** Unexpected color $color found at (%d,%d)!\n", $xpos + $col, $ypos + $row );
            }
        }
        push @bytes, $cur_byte;
        push @masks, $cur_mask;
    }
    return ( \@bytes, \@masks );
}

# Processes a $gfx and adds sprite data:
#     $gfx->{'cells'}[<rows>][<cols>] = { 'bytes' => [ <pixel_bytes> ], 'masks' => <mask_bytes> } - for each 8x8 cell
# in row-major form
sub zxgfx_extract_sprite_cells {
    my ( $gfx, $fg, $bg, $mask ) = @_;
    foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            my ( $bytes, $masks ) = zxgfx_extract_sprite_pixels_from_cell( $gfx, $col * 8, $row * 8, $fg, $bg, $mask );
            $gfx->{'cells'}[ $row ][ $col ] = {
                bytes	=> $bytes,
                masks	=> $masks,
            };
        }
    }
}

# get gfx dimensions in pixels and cells
sub zxgfx_get_width_pixels {
    my $gfx = shift;
    return scalar( @{ $gfx->{'pixels'}[0] } );
}

sub zxgfx_get_height_pixels {
    my $gfx = shift;
    return scalar( @{ $gfx->{'pixels'} } );
}

sub zxgfx_get_width_cells {
    my $gfx = shift;
    return zxgfx_get_width_pixels( $gfx ) / 8;
}

sub zxgfx_get_height_cells {
    my $gfx = shift;
    return zxgfx_get_height_pixels( $gfx ) / 8;
}

# Validates that all cells in the provided gfx have at most the requested
# number of colors
sub zxgfx_validate_cell_colors {
    my ( $gfx, $num_colors ) = @_;

    my @errors;
    foreach my $row ( 0 .. (zxgfx_get_height_cells( $gfx ) - 1) ) {
        foreach my $col ( 0 .. (zxgfx_get_width_cells( $gfx ) - 1) ) {
            my $attr_info = zxgfx_extract_attr_from_cell( $gfx, $col * 8, $row * 8 );
            if ( scalar( @{ $attr_info->{'all_colors'} } ) > $num_colors ) {
                push @errors, sprintf( "** Cell ($row,$col) has %d colors: %s - Expected at most %d",
                    scalar( @{ $attr_info->{'all_colors'} } ),
                    join( ',', @{ $attr_info->{'all_colors'} } ),
                    $num_colors );
            }
        }
    }
    return \@errors;
}

sub zxgfx_split_rgb {
    my $color = shift;
    $color =~ m/^(\w\w)(\w\w)(\w\w)$/;
    my @rgb = map { hex } ( $1, $2, $3 );
    return @rgb;
}


# writes a PNG file from a ZXGFX data structure
sub zxgfx_write_png {
    my ( $output_file, $gfx ) = @_;

    my $height = zxgfx_get_height_pixels( $gfx );
    my $width = zxgfx_get_width_pixels( $gfx );

    my $img = GD::Image->new( $width, $height );

    # allocate color indexes and set image pixels
    my %colors;
    foreach my $x ( 0 .. $width - 1 ) {
        foreach my $y ( 0 .. $height - 1 ) {
            my $pix_color = $gfx->{'pixels'}[ $y ][ $x ];
            if ( not defined $colors{ $pix_color } ) {
                $colors{ $pix_color } = $img->colorAllocate( zxgfx_split_rgb( $pix_color ) );
            }
            $img->setPixel( $x, $y, $colors{ $pix_color } );
        }
    }

    my $png_data = $img->png;
    open OUT, ">$output_file" or
        die "Could not open $output_file for writing\n";
    binmode OUT;
    print OUT $png_data;
    close OUT;
}

# sets all pixels in an 8x8 cell to either INK or PAPER color, accordng to the minimum color distance to both
sub zxgfx_convert_cell_colors_to_attr {
    my ( $gfx, $xpos, $ypos ) = @_;

    my $cell_colors = zxgfx_extract_attr_from_cell( $gfx, $xpos, $ypos );

    # if the number of found colors is 1 or 2, there is nothing to do
    return if ( scalar( @{ $cell_colors->{'all_colors'} } ) <= 2 );

    # calculate the distance from all colors to BG and FG color
    my %distance;
    foreach my $c ( @{ $cell_colors->{'all_colors'} } ) {
        $distance{ $c }{'fg'} = zxgfx_color_distance( $c, $cell_colors->{'fg'} );
        $distance{ $c }{'bg'} = zxgfx_color_distance( $c, $cell_colors->{'bg'} );
    }

    # now remap all pixels
    foreach my $x ( $xpos .. $xpos + 7 ) {
        foreach my $y ( $ypos .. $ypos + 7 ) {
            my $pix_color = $gfx->{'pixels'}[ $y ][ $x ];
            next if ( $pix_color eq $cell_colors->{'fg'} );
            next if ( $pix_color eq $cell_colors->{'bg'} );
            $gfx->{'pixels'}[ $y ][ $x ] = (
                $distance{ $pix_color }{'fg'} < $distance{ $pix_color }{'bg'} ?
                $cell_colors->{'fg'} :
                $cell_colors->{'bg'}
            );
        }
    }
}

1;
