#!/usr/bin/env perl

use Modern::Perl;

use Getopt::Std;
use Data::Dumper;

sub show_usage {
    die <<EOF_USAGE
usage: $0 -b <bootloader.bin> -l <loader.bin> -o <output.dsk> <file1.bin> <file2.bin> ...
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
        2,						# num directory blocks
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

sub load_binary {
    my $file = shift;
    open my $bin, $file or
        die "Could not open $file for reading: $@\n";
    binmode( $bin );
    my $code;
    my $size = read( $bin, $code, 65536 );	# max size
    defined( $size ) or
        die "Error reading from $file\n";
    close $bin;
    return $code;
}

# splits a binary in tracks of the needed track size.  The returned tracks
# are all full size.  The unused bytes in the final track are padded with
# the configured filler byte
sub split_binary_in_tracks {
    my $binary = shift;
    my $track_size = $dsk->{'num_sectors'} * $dsk->{'sector_size'};

    my @tracks;
    my $offset = 0;
    my $remaining_bytes = length( $binary );
    while ( $remaining_bytes ) {
        my $real_size = ( $remaining_bytes > $track_size ? $track_size : $remaining_bytes );
        my $track_bytes = substr( $binary, $offset, $real_size );
        $offset += $real_size;
        $remaining_bytes -= $real_size;
        # if the final track is less than track size, pad with filler byte
        if ( length( $track_bytes ) < $track_size ) {
            $track_bytes .= pack( "C*", ( $dsk->{'filler_byte'} ) x ( $track_size - length( $track_bytes ) ) );
        }
        push @tracks, $track_bytes;
    }
    return @tracks;
}

#####################
## Main
#####################

our ( $opt_b, $opt_o, $opt_l );
getopts("b:o:l:");
( defined( $opt_b ) and defined( $opt_o ) and defined( $opt_l ) ) or
    show_usage;
my $bootloader = $opt_b;
my $output_dsk = $opt_o;
my $loader = $opt_l;
my @binaries = @ARGV;

my $bootloader_code = load_binary( $bootloader );

my $loader_code = load_binary( $loader );

say "";
say "DSKTOOL - Generate a bootable ZX Spectrum +3 disc image";
say "  Bootloader:      $bootloader";
printf "  Bootloader size: %d bytes\n", length( $bootloader_code );
say "  Loader:          $loader";
printf "  Loader size:     %d bytes\n", length( $loader_code );
print "  Binaries:        ";
say join( "\n                   ", @binaries );
say "  Output image:    $output_dsk";

# start generating the disk image
open DSK, ">$output_dsk" or
    die "Could not open $output_dsk for writing: $@\n";
binmode(DSK);

# image header
print DSK disk_info_block_bytes;

# track 0
print DSK track_info_block_bytes( 0, 0 );
print DSK build_boot_sector( $bootloader_code );
print DSK $loader_code;
# pad to 9 sectors
print DSK pack( "C*", ( $dsk->{'filler_byte'} ) x ( $dsk->{'sector_size'} * 8 - length( $loader_code ) ) );

# generate the data tracks
my @data_tracks;
my %tracks_per_bin;
foreach my $bin ( @binaries ) {
    my @tracks = split_binary_in_tracks( load_binary( $bin ) );
    push @data_tracks, @tracks;
    $tracks_per_bin{ $bin } = scalar( @tracks );
}

# output tracks 1 to end of disk - data tracks first
my $current_track = 1;

foreach my $track_bytes ( @data_tracks ) {
    print DSK track_info_block_bytes( $current_track, 0 );
    print DSK $track_bytes;
    $current_track++;
}

# if 40 tracks were not output, output the remaining tracks with filler byte
printf "  Last used track: %d\n", $current_track - 1;
printf "  Used:            %d tracks\n", $current_track;
printf "  Available:       %d tracks\n", 40 - $current_track;
while ( $current_track < 40 ) {
    print DSK track_info_block_bytes( $current_track, 0 );
    print DSK pack( "C*", ( $dsk->{'filler_byte'} ) x ( $dsk->{'sector_size'} * $dsk->{'num_sectors'} ) );
    $current_track++;
}
close DSK;

# report num tracks per binary
print "  Tracks per binary:\n";
foreach my $bin ( @binaries ) {
    printf "    %s: %d track(s)\n", $bin, $tracks_per_bin{ $bin };
}
