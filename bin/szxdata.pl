#!/usr/bin/env perl

use Modern::Perl;

use Getopt::Std;
use File::Basename qw( basename );
use Data::Dumper;

my $exe = basename( $0 );

# symbols loaded from the map. Values are stored as numbers (no hex, etc.)
my $map_symbols;

sub load_map_symbols {
    my $file = shift;
    open MAP, $file or do {
        warn "Could not open file $file for reading\n";
        return undef;
    };

    while ( my $line = <MAP> ) {
        chomp( $line );
        if ( $line =~ m/^(\w+)\s+=\s+\$([0-9a-fA-F]+)\s+;\s+addr,/ ) {
            $map_symbols->{ $1 } = hex( $2 );
        }
    }

    close MAP;
    1;
}

###############
## Main
###############

our ( $opt_m, $opt_i, $opt_s );
getopts("m:i:s:");

( defined( $opt_i ) and defined( $opt_s ) ) or
    die "usage: $exe [-m <map_file>] -i <szx_file> -s <script>\n";

if ( defined( $opt_m ) ) {
    load_map_symbols( $opt_m ) or
        die "**Error: could not load map file $opt_m\n";
    print Dumper( $map_symbols );
}
