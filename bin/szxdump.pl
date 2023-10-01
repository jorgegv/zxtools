#!/usr/bin/env perl

use utf8;
use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Std;

use SZXFile;

##
## Summary functions
##

sub summary_RAMP {
    my $block = shift;
    my $data = $block->{'data'};
    return sprintf( "Page Number: %d, Compressed: %s, Compressed Data Size: %d, Uncompressed Data Size: %d",
        $data->{'pageno'}, ( $data->{'compressed'} ? 'Yes' : 'No' ),
        length( $data->{'compressed_data'} ), length( $data->{'uncompressed_data'} ) );
}

sub summary_CRTR {
    my $block = shift;
    my $data = $block->{'data'};
    return sprintf( "Creator: %s, Major: %d, Minor: %d", map { $data->{ $_ } } qw( creator major minor ) );
}


my %colors = (
    0 => 'BLACK',
    1 => 'BLUE',
    2 => 'RED',
    3 => 'MAGENTA',
    4 => 'GREEN',
    5 => 'CYAN',
    6 => 'YELLOW',
    7 => 'WHITE',
);
sub summary_SPCR {
    my $block = shift;
    my $data = $block->{'data'};
    return sprintf( "Border: %d (%s), Port_7ffd: %d (0x%02x), Port_1ffd: %d (0x%02x), Port_fe: %d (0x%02x)",
        $data->{'border'},
        $colors{ $data->{'border'} } || '(unknown)',
        $data->{'port_7ffd'},
        $data->{'port_7ffd'},
        $data->{'port_1ffd'},
        $data->{'port_1ffd'},
        $data->{'port_fe'},
        $data->{'port_fe'},
    );
}

## Dispatch table
my $block_summary_function = {
    'CRTR' => \&summary_CRTR,
    'RAMP' => \&summary_RAMP,
    'SPCR' => \&summary_SPCR,
};

##
## Main
##

our( $opt_i, $opt_b, $opt_a );
getopts( 'b:i:a:' );

defined( $opt_i ) or
    die "
usage: $0 -i <file.szx> [-b <n>] [-a <address>]
  The SZX file is mandatory. If no -b argument is used, a summary of the SZX file structure is output.
  If -b <n> is supplied, an hex dump of memory bank number <n> is output.
  If -b and -a are supplied, the memory dump will be based on address <address> instead of 0x0000
";

my $szx_file = $opt_i;
my $bank_to_dump = $opt_b;
my $memory_dump_base_address = ( defined( $opt_a ) ? $opt_a : 0 );
if ( $memory_dump_base_address =~ /^0[xX]([\dA-Fa-f]+)/ ) {
    $memory_dump_base_address = hex( $1 );
}

my $szx = szx_parse_file( $szx_file );

my $header = $szx->{'header'};
( $header->{'magic'} eq 'ZXST' ) or
    die "Error: $szx_file is not a ZXST file\n";

if ( not defined( $bank_to_dump ) ) {
    printf "ZXST file, version %d.%d, flags: %d, machine ID: %d (%s)\n",
        ( map { $header->{ $_ } } qw( major_version minor_version flags machine_id ) ),
        szx_get_machine_description( $header->{'machine_id'} );
}

print "Data blocks:\n";
foreach my $block ( @{ $szx->{'blocks'} } ) {
    if ( not defined( $bank_to_dump ) ) {
        printf "[ Type: %-4s, Block Size: %d bytes ]\n", map { $block->{ $_ } } qw( id size );
        if ( defined( $block_summary_function->{ $block->{'id'} } ) ) {
            my $summary = $block_summary_function->{ $block->{'id'} }( $block );
            printf "   %s\n", $summary;
        }
    } else {
        if ( ( $block->{'id'} eq 'RAMP' ) and ( $block->{'data'}{'pageno'} == $bank_to_dump ) ) {
            printf "[ Type: %-4s, Block Size: %d bytes ]\n", map { $block->{ $_ } } qw( id size );
            my $summary = $block_summary_function->{ $block->{'id'} }( $block );
            printf "   %s\n", $summary;

            my @dump_lines;
            my @dump_bytes = unpack( 'C*', $block->{'data'}{'uncompressed_data'} );
            my $current_address = $memory_dump_base_address;
            my $current_line = sprintf( '%06X: ', $current_address );
            my $cnt = 1;
            foreach my $byte ( @dump_bytes ) {
                $current_line .= sprintf( '%02X', $byte ) . ' ';
                if ( ( $cnt++ % 16 ) == 0 ) {
                    push @dump_lines, $current_line;
                    $current_address += 16;
                    $current_line = sprintf( '%06X: ', $current_address );
                }
            }

            print  "   Memory dump:\n      ";
            print join( "\n      ", @dump_lines );
            print "\n";
        }
    }
}
