#!/usr/bin/env perl

use Modern::Perl;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Std;
use File::Basename qw( basename );
use Data::Dumper;

use SZXFile;

# binary name for easy access
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

sub compile_script {
    my $file = shift;

    my @script;
    my $errors = 0;

    open SCRIPT, $file or
        die "Could not open file $file for reading\n";

    my $line_number = 0;
    while ( my $line = <SCRIPT> ) {
        $line_number++;
        chomp( $line );
        $line =~ s/\s*#.*//g;
        next if $line =~ m/^$/;

        # start matching lines


        # pb, pw and pl commands
        if ( $line =~ m/^(p[bwl])\s+(.+)/i ) {
            push @script, { cmd => lc($1), addr => $2 };

        # everything unknown is an error
        } else {
            warn "** Line $line_number: unrecognized syntax\n";
            $errors++;
        }

    }
    close SCRIPT;
    return ( ( not $errors ) ? \@script : undef );
}

###############
## Main
###############

our ( $opt_m, $opt_i, $opt_s );
getopts("m:i:s:");

( defined( $opt_i ) and defined( $opt_s ) ) or
    die "usage: $exe [-m <map_file>] -i <szx_file> -s <script>\n";

# load symbols from map file if supplied
if ( defined( $opt_m ) ) {
    load_map_symbols( $opt_m ) or
        die "** Error: could not load map file $opt_m\n";
#    print Dumper( $map_symbols );
    printf "%d symbols loaded from file %s\n", scalar keys %$map_symbols, basename( $opt_m );
}

# compile the script
my $script = compile_script( $opt_s );
defined( $script ) or
    die "** Error: could not parse script $opt_i\n";
#print Dumper( $script );

# load the SZX file

# run the script
run_script( $szx_file, $script );
