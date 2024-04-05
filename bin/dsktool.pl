#!/bin/env perl

use Modern::Perl;

use Getopt::Std;
use Data::Dumper;

sub show_usage {
    die <<EOF_USAGE
usage: $0 -b <bootloader.bin> -o <output.dsk>
EOF_USAGE
;
}

####################
## Disk profiles
####################

# disk creator, must be 14 bytes
my $dsk_creator = 'DSKTOOL.ZXJOGV';

my $dsk_profiles = {
    # standard values for Amstrad PCW/Spectrum+3 disc
    default	=> {
            num_tracks	=> 40,
            num_sides	=> 1,
            num_sectors => 9,
            sector_size	=> 512,
            rw_gap	=> 0x2a,
            fmt_gap	=> 0x52,
            filler_byte	=> 0xe5,
        },
};

# set default disk profile
my $dsk = $dsk_profiles->{'default'};


####################################
## DSK File Format functions
####################################

# create the Disc Information Block - 256 bytes
sub disk_info_block_bytes {
    my $dib_bytes = pack('C[34]C[14]CCvC[204]',
        ( map { ord } split( //, "MV - CPCEMU Disk-File\r\nDisk-Info\r\n" ) ), # fixed, must be this
        ( map { ord } split( //, $dsk_creator ) ),
        $dsk->{'num_tracks'},
        $dsk->{'num_sides'},
        ( 256 + $dsk->{'num_sectors'} * $dsk->{'sector_size'} ),	# track data size
        ( 0x00 ) x 204	# unused bytes at the end
    );
    return $dib_bytes;
}

# create the Track Information Block - 256 bytes
sub track_info_block_bytes {
    my ( $track, $side ) = @_;
    my $tib_bytes = pack('C[24]',
        ( map { ord } split( //, "Track-Info\r\n" ) ),	# fixed, must be this ) )
        ( 0x00 ) x 4,					# 4 unused bytes
        $track,						# track nr
        $side,						# side nr
        ( 0x00 ) x 2,					# 2 unused bytes
        $dsk->{'sector_size'} / 256,			# 1=256, 2=512, 3=1024...
        $dsk->{'num_sectors'},
        $dsk->{'rw_gap'},
        $dsk->{'filler_byte'}
    );
    foreach my $sector_id ( 1 .. $dsk->{'num_sectors'} ) {
        $tib_bytes .= pack( 'C[8]',
            $track,
            $side,
            $sector_id,
            $dsk->{'sector_size'} / 256,		# 1=256, 2=512, 3=1024...
            0x00,					# FDC status register 1 after reading
            0x00,					# FDC status register 2 after reading
            ( 0x00 )  x 2,					# 2 unused bytes
        );
    }
    # remaining bytes up to 256 are zero
    $tib_bytes .= pack( "C*",
        ( 0x00 ) x ( 256 - scalar( split( //, $tib_bytes ) ) )
    );
    return $tib_bytes;
}

#####################
## PCW boot sector
#####################

sub pcw_boot_record {
    return pack( "C*",
        0,						# SS SD
        0,						# Single sided
        $dsk->{'num_tracks'},
        $dsk->{'num_sectors'},
        $dsk->{'sector_size'} / 256,			# 1=256, 2=512, 3=1024...
        1,						# nr reserved tracks
        3,						# 1K blocks
        0,						# num directory blocks
        $dsk->{'rw_gap'},
        $dsk->{'fmt_gap'},
        (0) x 5,					# 5 unused bytes
        0,						# checksum (needs to be updated later)
    );
}

sub build_boot_sector {
    my $code_bytes = shift;
    my $sector_bytes = pcw_boot_record . $code_bytes;

    $sector_bytes .= pack( 'C*', ( $dsk->{'filler_byte'} ) x ( $dsk->{'sector_size'} - scalar( split( //, $sector_bytes ) ) ) );

    # we need to fix checksum byte at pos 0x0F
    my @sector_bytes = ( map { ord } split( //, $sector_bytes ) );
    my $cksum;
    foreach my $b ( @sector_bytes ) {
        $cksum += $b;
    }
    $cksum %= 256;

    # new cksum must be 3
    my $fiddle_byte =  ( 256 + 3 - $cksum ) % 256;
    $sector_bytes[ 0x0F ] = $fiddle_byte;

    # repack sector
    $sector_bytes = pack( 'C*', @sector_bytes );
    return $sector_bytes;
}

#####################
## Main
#####################

our ( $opt_b, $opt_o );
getopts("b:o:");
( defined( $opt_b ) and defined( $opt_o ) ) or
    show_usage;
my $bootloader = $opt_b;
my $output_dsk = $opt_o;

open DSK, ">$output_dsk" or
    die "Could not open $output_dsk for writing: $@\n";

binmode(DSK);
print DSK disk_info_block_bytes;

# test bootloader
#     2   000000 210080                  ld hl,$8000
#     3   000003 362f                    ld (hl),47
#     4   000005 f3                      di
#     5   000006 76                      halt
my $test_bootloader_code = pack("C*",0x21,0x00,0x80,0x36,0x2f,0xf3,0x76 );

my $boot_sector = build_boot_sector( $test_bootloader_code );

foreach my $track ( 0 .. 39 ) {
    print DSK track_info_block_bytes( $track, 0 );

    print DSK $boot_sector;

    # remaining sectors
    print DSK pack( "C*", (0) x ( $dsk->{'sector_size'} * 8 ) );
}

close DSK;
