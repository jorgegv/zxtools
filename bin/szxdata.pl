#!/usr/bin/env perl

use Modern::Perl;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Std;
use File::Basename qw( basename );
use Data::Dumper;
use List::Util qw( first );

use SZXFile;

# binary name for easy access
my $exe = basename( $0 );

# symbols loaded from the map. Values are stored as numbers (no hex, etc.)
my $map_symbols;

# memory bytes
my $memory;

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

sub map_memory_array {
    my $szx = shift;

    # Get the snapshot memory mappings and decode active pages:  RAM pages 5
    # and 2 are always mapped at $4000 and $8000; ROM is paged at $0000
    # except in +2A/+3 modes, where some RAM page may be also paged at
    # $0000.
    # 
    # We arrange everything here to have a 64K element array with the
    # current memory contents, byte by byte, considering the current
    # mappings. We ignore (for the moment) the special +2A/+3 mappings.
    my @mem_bytes;

    # prepare and decode  page data

    # range $0000-$3FFF is ignored and set to 0

    # range $4000-$7FFF (page 5)
    my $page_4000 = first {
        ( $_->{'id'} eq 'RAMP' ) and ( $_->{'data'}{'pageno'} == 5 )
    } @{ $szx->{'blocks'} };

    # range $8000-$BFFF (page 2)
    my $page_8000 = first {
        ( $_->{'id'} eq 'RAMP' ) and ( $_->{'data'}{'pageno'} == 2 )
    } @{ $szx->{'blocks'} };

    # range $C000-$FFFF (depends on port $7ffd mapping)
    my $spcr = first { $_->{'id'} eq 'SPCR' } @{ $szx->{'blocks'} };
    my $active_ram_page = $spcr->{'data'}{'port_7ffd'} & 0x07;
    my $page_c000 = first {
        ( $_->{'id'} eq 'RAMP' ) and ( $_->{'data'}{'pageno'} == $active_ram_page ) 
    } @{ $szx->{'blocks'} };

    # decode and push page data at the proper memory ranges
    push @mem_bytes, (0) x 16384 ;
    push @mem_bytes, unpack('C*', $page_4000->{'data'}{'uncompressed_data'} );
    push @mem_bytes, unpack('C*', $page_8000->{'data'}{'uncompressed_data'} );
    push @mem_bytes, unpack('C*', $page_c000->{'data'}{'uncompressed_data'} );

    return \@mem_bytes;
}

sub get_byte_at {
    my ( $mem, $pos ) = @_;
    return $mem->[ $pos ];
}

sub get_word_at {
    my ( $mem, $pos ) = @_;
    return $mem->[ $pos ] +
        $mem->[ $pos + 1 ] * 256;
}

sub get_long_at {
    my ( $mem, $pos ) = @_;
    return $mem->[ $pos ] +
        $mem->[ $pos + 1 ] * 256 +
        $mem->[ $pos + 2 ] * 256 * 256 +
        $mem->[ $pos + 3 ] * 256 * 256 * 256;
}

sub decode_addr {
    my $addr = shift;
    for ( $addr ) {
        if 	( /^0x([a-fA-F0-9]+)/ )	{ return hex( $1 ); }
        elsif	( /^\$([a-fA-F0-9]+)/ )	{ return hex( $1 ); }
        elsif	( /^%([01]+)/ )		{ return oct( "0b$1" ); }
        elsif	( /^(\d+)/ )		{ return $1; }
        else	{ return -1; }
    }
}

my $script_syntax = {
    'pb' => sub {
            printf( "byte[ 0x%04X ] = 0x%02X (%d)\n",
                decode_addr( $_[0] ),
                get_byte_at( $memory, decode_addr( $_[0] ) ),
                get_byte_at( $memory, decode_addr( $_[0] ) ),
            );
        },
    'pw' => sub {
            printf( "word[ 0x%04X ] = 0x%04X (%d)\n",
                decode_addr( $_[0] ),
                get_word_at( $memory, decode_addr( $_[0] ) ),
                get_word_at( $memory, decode_addr( $_[0] ) ),
            );
        },
    'pl' => sub {
            printf( "long[ 0x%04X ] = 0x%08X (%d)\n",
                decode_addr( $_[0] ),
                get_long_at( $memory, decode_addr( $_[0] ) ),
                get_long_at( $memory, decode_addr( $_[0] ) ),
            );
        },
};

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
        if ( $line =~ m/^(\w+)\s+(.+)/i ) {
            my ( $cmd, $args ) = ( lc( $1 ), $2 );
            if ( exists( $script_syntax->{ $cmd } ) ) {
                push @script, { 'cmd' => $cmd, 'args' => [ split( /\s+/, $args ) ] };
            } else {
                warn "** Line $line_number: unrecognized command '$cmd'\n";
                $errors++;
            }
        # everything unknown is an error
        } else {
            warn "** Line $line_number: unrecognized syntax\n";
            $errors++;
        }

    }
    close SCRIPT;
    return ( ( not $errors ) ? \@script : undef );
}

sub run_script {
    my ( $szx, $script ) = @_;

#    print Dumper( $mem );

    foreach my $cmd ( @$script ) {
        if ( defined( $script_syntax->{ $cmd->{'cmd'} } ) ) {
            &{ $script_syntax->{ $cmd->{'cmd'} } }( @{ $cmd->{'args'} } );
        } else {
            printf "Command '%s' not understood\n", $cmd->{'cmd'};
        }
    }
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

# load the SZX file and set up the memory map
my $szx = szx_parse_file( $opt_i );
$memory = map_memory_array( $szx );

# run the script
run_script( $szx, $script );
