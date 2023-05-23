#!/usr/bin/env perl

use utf8;
use warnings;
use strict;

use Compress::Zlib;
use Data::Dumper;
use Getopt::Std;

my %machine_name = (
    0  =>  'ZX Spectrum 16K',
    1  =>  'ZX Spectrum 48K/+',
    2  =>  'ZX Spectrum 128K',
    3  =>  'ZX Spectrum +2',
    4  =>  'ZX Spectrum +2A/+2B',
    5  =>  'ZX Spectrum +3',
    6  =>  'ZX Spectrum +3E',
    7  =>  'Pentagon 128',
    8  =>  'Timex Sinclair TC2048',
    9  =>  'Timex Sinclair TC2068',
    10  =>  'Scorpion ZS-256',
    11  =>  'ZX Spectrum SE',
    12  =>  'Timex Sinclair TS2068',
    13  =>  'Pentagon 512',
    14  =>  'Pentagon 1024',
    15  =>  'ZX Spectrum 48K (NTSC)',
    16  =>  'ZX Spectrum 128Ke',
);

my $block_decode_function;
my $block_summary_function;

sub read_szx_header {
    my $fh = shift;
    my $data;
    ( read( $fh, $data, 8 ) == 8 ) or
        die "Unexpected EOF!\n";
    my ( $magic, $major_version, $minor_version, $machine_id, $flags ) =
        unpack( "A[4]CCCC", $data );
    return {
        magic		=> $magic,
        major_version	=> $major_version,
        minor_version	=> $minor_version,
        machine_id	=> $machine_id,
        flags		=> $flags,
    };
}

sub read_szx_next_block {
    my $fh = shift;
    my $data;
    ( read( $fh, $data, 8 ) == 8 ) or
        die "Unexpected EOF!\n";
    my ( $id, $size ) = unpack( "A[4]L", $data );
    ( read( $fh, $data, $size ) == $size ) or
        die "Unexpected EOF!\n";
    return {
        id	=> $id,
        size	=> $size,
        data	=> decode_szx_block( $id, $data ),
    };
}

##
## Decoding functions
##

sub decode_CRTR {
    my $data = shift;
    my ( $creator, $major, $minor ) = unpack( 'A[32]SS', $data );
    return { creator => $creator, major => $major, minor => $minor };
}

sub decode_RAMP {
    my $data = shift;
    my ( $compressed, $pageno, @page_data ) = unpack( 'SCC*', $data );
    my $compressed_data = pack( 'C*', @page_data );
    my $tmp_compressed_data = $compressed_data;
    my $zlib = inflateInit();
    my $uncompressed_data = ( $compressed ? $zlib->inflate( \$tmp_compressed_data ) : $compressed_data );
    return {
        pageno => $pageno,
        compressed => $compressed,
        compressed_data => $compressed_data,
        uncompressed_data => $uncompressed_data,
    };
}

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

## Dispatch tables

$block_decode_function = {
    'CRTR' => \&decode_CRTR,
    'RAMP' => \&decode_RAMP,
};

$block_summary_function = {
    'CRTR' => \&summary_CRTR,
    'RAMP' => \&summary_RAMP,
};

sub decode_szx_block {
    my ( $id, $data ) = @_;
    if ( defined( $block_decode_function->{ $id } ) ) {
        return $block_decode_function->{ $id }( $data );
    }
    return undef;
}

##
## Main
##

our( $opt_f, $opt_b, $opt_a );
getopts( 'b:f:a:' );

defined( $opt_f ) or
    die "
usage: $0 -f <file.szx> [-b <n>] [-a <address>]
  The SZX file is mandatory. If no -b argument is used, a summary of the SZX file structure is output.
  If -b <n> is supplied, an hex dump of memory bank number <n> is output.
  If -b and -a are supplied, the memory dump will be based on address <address> instead of 0x0000
";

my $szx_file = $opt_f;
my $bank_to_dump = $opt_b;
my $memory_dump_base_address = ( defined( $opt_a ) ? $opt_a : 0 );
if ( $memory_dump_base_address =~ /^0[xX]([\dA-Fa-f]+)/ ) {
    $memory_dump_base_address = hex( $1 );
}

open( my $fh, "<", $szx_file ) or
    die "Could not open $szx_file for reading: $!\n";
binmode $fh;

my $header = read_szx_header( $fh );
( $header->{'magic'} eq 'ZXST' ) or
    die "Error: $szx_file is not a ZXST file\n";

if ( not defined( $bank_to_dump ) ) {
    printf "ZXST file, version %d.%d, flags: %d, machine ID: %d (%s)\n",
        ( map { $header->{ $_ } } qw( major_version minor_version flags machine_id ) ),
        $machine_name{ $header->{'machine_id'} };
}

print "Data blocks:\n";
while ( not eof $fh ) {
    my $block = read_szx_next_block( $fh );
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
