#!/usr/bin/perl

use utf8;
use warnings;
use strict;

use Data::Dumper;

( scalar( @ARGV ) == 1 ) or
    die "usage: $0 <file.szx>\n";

my $szx_file = $ARGV[0];

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
        data	=> $data,
    };
}

##
## Decoding functions
##

sub decode_CRTR {
    my $data = shift;
    my ( $creator, $major, $minor ) = unpack( 'A[32]SS', $data );
    return sprintf( "Creator: %s; Major: %d; Minor: %d", $creator, $major, $minor );
}

sub decode_RAMP {
    my $data = shift;
    my ( $compressed, $pageno, $page_data ) = unpack( 'SCC*', $data );
    return sprintf( "Page Number: %d; Compressed: %d", $pageno, $compressed );
}

my $decode_block_function = {
    'CRTR' => \&decode_CRTR,
    'RAMP' => \&decode_RAMP,
};

sub decode_szx_block {
    my $block = shift;

    if ( defined( $decode_block_function->{ $block->{'id'} } ) ) {
        return $decode_block_function->{ $block->{'id'} }( $block->{'data'} );
    }
    return undef;
}

##
## Main
##

open( my $fh, "<", $szx_file ) or
    die "Could not open $szx_file for reading: $!\n";
binmode $fh;

my $header = read_szx_header( $fh );
( $header->{'magic'} eq 'ZXST' ) or
    die "Error: $szx_file is not a ZXST file\n";

printf "ZXST file, version %d.%d, machine ID: %d, flags: %d\nData blocks:\n",
    map { $header->{ $_ } } qw( major_version minor_version machine_id flags );

while ( not eof $fh ) {
    my $block = read_szx_next_block( $fh );
    printf "[ Block type: %-4s; Size: %d bytes ]\n", map { $block->{ $_ } } qw( id size );
    my $decoded = decode_szx_block( $block );
    if ( defined( $decoded ) ) {
        printf "  %s\n", $decoded;
    }
}
