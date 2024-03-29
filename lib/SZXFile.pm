#!/usr/bin/env perl

use utf8;
use warnings;
use strict;

use Compress::Zlib;
use Data::Dumper;

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

sub szx_get_machine_description {
    my $id = shift;
    return ( $machine_name{ $id } || '(unknown)' );
}

sub szx_read_header {
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

sub szx_read_next_block {
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
        data	=> szx_decode_block( $id, $data ),
    };
}

##
## Decoding functions
##

# Creator record
sub szx_decode_CRTR {
    my $data = shift;
    my ( $creator, $major, $minor ) = unpack( 'A[32]SS', $data );
    return { creator => $creator, major => $major, minor => $minor };
}

# RAM Page record
sub szx_decode_RAMP {
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

# Spectrum Registers record
sub szx_decode_SPCR {
    my $data = shift;
    my ( $border, $port_7ffd, $port_1ffd, $port_fe, $reserved ) = unpack( "CCCCN", $data );
    return {
        border		=> $border,
        port_7ffd	=> $port_7ffd,
        port_1ffd	=> $port_1ffd,
        port_fe		=> $port_fe,
    }
}

# Z80 Registers record
sub szx_decode_Z80R {
    my $data = shift;
    my ( $af,$bc,$de,$hl,$af1,$bc1,$de1,$hl1,$ix,$iy,$sp,$pc,$i,$r,$iff1,$iff2,$im,
        $cycles_start,$hold_int_req_cycles,$flags,$mem_ptr ) = unpack( "SSSSSSSSSSSSCCCCCLCCS", $data );
    return {
        af			=> $af,
        bc			=> $bc,
        de			=> $de,
        hl			=> $hl,
        af1			=> $af1,
        bc1			=> $bc1,
        de1			=> $de1,
        hl1			=> $hl1,
        ix			=> $ix,
        iy			=> $iy,
        sp			=> $sp,
        pc			=> $pc,
        i			=> $i,
        r			=> $r,
        iff1			=> $iff1,
        iff2			=> $iff2,
        im			=> $im,
        cycles_start		=> $cycles_start,
        hold_int_req_cycles	=> $hold_int_req_cycles,
        flags			=> $flags,
        mem_ptr			=> $mem_ptr,
    };
}

## Dispatch tables
$block_decode_function = {
    'CRTR' => \&szx_decode_CRTR,
    'RAMP' => \&szx_decode_RAMP,
    'SPCR' => \&szx_decode_SPCR,
    'Z80R' => \&szx_decode_Z80R,
};

sub szx_decode_block {
    my ( $id, $data ) = @_;
    if ( defined( $block_decode_function->{ $id } ) ) {
        return $block_decode_function->{ $id }( $data );
    }
    return undef;
}

# returns hashref: { header => ..., blocks => [ ] }
sub szx_parse_file {
    my $szx_file = shift;

    open( my $fh, "<", $szx_file ) or
        die "Could not open $szx_file for reading: $!\n";
    binmode $fh;

    my $header = szx_read_header( $fh );
    ( $header->{'magic'} eq 'ZXST' ) or
        die "Error: $szx_file is not a ZXST file\n";

    my @blocks;
    while ( not eof $fh ) {
        push @blocks, szx_read_next_block( $fh );
    }

    return { header => $header, blocks => \@blocks };
}

1;
