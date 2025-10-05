#!/usr/bin/env perl

# reads a .c.lis file and a .map file and outputs the .c.lis file replacing
# the offsets with the final linked addresses extracted from the map file,
# for easier debugging

use Modern::Perl;
use Getopt::Std;
use Data::Dumper;

sub help_and_exit {
    die "usage: $0 [-h] -l <file.c.lis> -m <main.map>\n";
}

our ( $opt_l, $opt_m, $opt_h );
getopts("l:m:h");
( defined( $opt_h ) or ( not defined( $opt_m ) ) or ( not defined( $opt_l ) ) ) and
    help_and_exit;

my %symbols;

open MAP, $opt_m or
    die "Could not open MAP file $opt_m for reading\n";
while( my $line = <MAP> ) {
    chomp $line;
    if ( $line =~ /^(_\w+)\s+=\s+\$([\da-f]+)\s+;\s+addr,/i ) {
        $symbols{ $1 } = hex( $2 );
    }
}
close MAP;

#print Dumper( \%symbols );

my $current_addr = 0;
my $current_start = undef;

open LIS, $opt_l or
    die "Could not open LIS file for reading\n";
while ( my $line = <LIS> ) {
    chomp $line;
    if ( $line =~ /^\s+\d+\s+(_[\w]+):$/ )  {
        $current_addr = $symbols{ $1 };
        $current_start = undef;
        printf "$line     ;; final address: \$%06X\n", $current_addr;
        next;
    }
    if ( $line =~ /^(\s+\d+\s+)([\da-f]+)(\s+[\da-f]+)(.*)$/ ) {
        my ( $num_line, $offset, $code, $src ) = ($1, $2, $3, $4 );
        if ( not defined( $current_start ) ) {
            $current_start = hex( $offset );
        }
        printf "%s%06X%s%s\n", $num_line, $current_addr + hex( $offset ) - $current_start, $code, $src;
    } else {
        print "$line\n";
    }
}
close LIS;
