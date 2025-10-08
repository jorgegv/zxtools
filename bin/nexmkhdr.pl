#!/usr/bin/env perl

# creates a .NEX header (512 bytes) to a binary file with the parameters provided

use Modern::Perl;
use Getopt::Long;
use File::Basename qw( basename );
use File::Slurp    qw(write_file );

my $exe = basename( $0 );

my @errors;

sub help_and_exit {
    print <<EOF_HELP;

Usage: $exe [options]

Options:

    --help			Shows this help
    --ram			Sets RAM size in kB (768 or 1792) [default: 768]
    --load-screen-blocks	One of: PAL, HIC, HIR, LOR, ULA, L2, none [default: none]
    --border-colour		Colour of the border ;-) [default: BLACK]
    --sp			Initial Stack Pointer [mandatory]
    --pc			Entry point address [mandatory]
    --num-extra-files		Number of extra files [default: 0]
    --present-banks		List of comma-separated banks [default: 5,2,0]
    --loading-bar		Show loading bar [default: no]
    --loading-bar-colour	Loading bar colour [default: BLACK]
    --bank-load-delay		Load delay between banks [default: 0]
    --start-delay		Delay before starting the program after loading [default: 0]
    --preserve-state		Preserve Next state before loading [default: 0 -> Reset Next!]
    --required-core-version	Required Core version [default: 0.0.0]
    --timex-hires-colour	Timex HiRes colour [default: WHITE]
    --entry-bank		Bank that will be mapped at 0xC000 at program start [default: 0]
    --file-handle-address	File handle address (see https://wiki.specnext.dev/NEX_file_format) [default: 0]
    --output			Output file name [mandatory]

Remarks:

- Addresses and register values can be specified in decimal or hex with 0x... prefix
- Colours can be specified by number (0-7) or by name (BLACK, BLUE, RED, YELLOW, etc.)

EOF_HELP

    foreach ( @errors ) { say; }
    exit 1;
}

# command line options that can be specified
my (
    $ram,                   $load_screen_blocks, $border_colour, $sp,
    $pc,                    $num_extra_files,    $present_banks, $loading_bar,
    $loading_bar_colour,    $bank_load_delay,    $start_delay,   $preserve_state,
    $required_core_version, $timex_hires_colour, $entry_bank,    $file_handle_address,
    $help,                  $output,
);

my $num_present_banks;
# an array of 112 elements, no more no less, with 1/0 for present/no present flag for each bank
my @present_banks = ( 0 x 112 );

GetOptions(
    "help"                    => \$help,
    "ram:i"                   => \$ram,
    "load-screen-blocks=s"    => \$load_screen_blocks,
    "border-colour=s"         => \$border_colour,
    "sp=i"                    => \$sp,
    "pc=i"                    => \$pc,
    "num-extra-files=i"       => \$num_extra_files,
    "present-banks=s"         => \$present_banks,
    "loading-bar"             => \$loading_bar,
    "loading-bar-colour=s"    => \$loading_bar_colour,
    "bank-load-delay=i"       => \$bank_load_delay,
    "start-delay=i"           => \$start_delay,
    "preserve-state"          => \$preserve_state,
    "required-core-version=s" => \$required_core_version,
    "timex-hires-colour=s"    => \$timex_hires_colour,
    "entry-bank=i"            => \$entry_bank,
    "file-handle-address=s"   => \$file_handle_address,
    "output=s"                => \$output,
);

# check params
$help and help_and_exit;

$ram = $ram || 768;
if ( ( $ram != 768 ) and ( $ram != 1792 ) ) {
    push @errors, "*** Error: --ram must be 768 or 1792";
}

if ( not defined( $output ) ) {
    push @errors, "*** Error: --output is mandatory";
}

my %lsb_values = (
    'PAL'  => 0x80,
    'HIC'  => 0x10,
    'HIR'  => 0x08,
    'LOR'  => 0x04,
    'ULA'  => 0x02,
    'L2'   => 0x01,
    'none' => 0,
);
if ( defined( $load_screen_blocks ) ) {
    if ( exists( $lsb_values{$load_screen_blocks} ) ) {
        $load_screen_blocks = $lsb_values{$load_screen_blocks};
    } else {
        push @errors, "*** Error: --load-screen-blocks value must be one of " . join( ", ", keys %lsb_values );
    }
} else {
    $load_screen_blocks = $lsb_values{'none'};
}

my %zx_colours = (
    'BLACK'   => 0,
    'BLUE'    => 1,
    'RED'     => 2,
    'MAGENTA' => 3,
    'GREEN'   => 4,
    'CYAN'    => 5,
    'YELLOW'  => 6,
    'WHITE'   => 7,
);
if ( defined( $border_colour ) ) {
    if ( $border_colour =~ m/^\d+$/ ) {
        if ( ( $border_colour < 0 ) or ( $border_colour > 7 ) ) {
            push @errors, "*** Error: --border-colour value must be an integer between 0-7 or one of "
                . join( ", ", keys %zx_colours );
        }
    } else {
        if ( exists( $zx_colours{ uc( $border_colour ) } ) ) {
            $border_colour = $zx_colours{ uc( $border_colour ) };
        } else {
            push @errors, "*** Error: --border-colour value must be an integer between 0-7 or one of "
                . join( ", ", keys %zx_colours );
        }
    }
} else {
    $border_colour = $zx_colours{'BLACK'};
}

if ( defined( $sp ) ) {
    if ( $sp =~ m/^0x([A-Fa-f0-9]{4})$/i ) {
        $sp = hex( $1 );
    } else {
        if ( $sp =~ m/^\d+$/ ) {
            my $val = $1;
            if ( ( $val < 0 ) or ( $val > 65535 ) ) {
                push @errors, "*** Error: --sp must be a decimal (0-65535) or hex (0x0000-0xffff)";
            }
        } else {
            push @errors, "*** Error: --sp must be a decimal (0-65535) or hex (0x0000-0xffff)";
        }
    }
} else {
    push @errors, "*** Error: --sp is mandatory";
}

if ( defined( $pc ) ) {
    if ( $pc =~ m/^0x([A-Fa-f0-9]{4})$/i ) {
        $pc = hex( $1 );
    } else {
        if ( $pc =~ m/^\d+$/ ) {
            my $val = $1;
            if ( ( $val < 0 ) or ( $val > 65535 ) ) {
                push @errors, "*** Error: --pc must be a decimal (0-65535) or hex (0x0000-0xffff)";
            }
        } else {
            push @errors, "*** Error: --pc must be a decimal (0-65535) or hex (0x0000-0xffff)";
        }
    }
} else {
    push @errors, "*** Error: --pc is mandatory";
}

$num_extra_files = $num_extra_files || 0;

$loading_bar = $loading_bar || 0;

if ( defined( $loading_bar_colour ) ) {
    if ( $loading_bar_colour =~ m/^\d+$/ ) {
        if ( ( $loading_bar_colour < 0 ) or ( $loading_bar_colour > 7 ) ) {
            push @errors, "*** Error: --border-colour value must be an integer between 0-7 or one of "
                . join( ", ", keys %zx_colours );
        }
    } else {
        if ( exists( $zx_colours{ uc( $loading_bar_colour ) } ) ) {
            $loading_bar_colour = $zx_colours{ uc( $loading_bar_colour ) };
        } else {
            push @errors, "*** Error: --loading-bar-colour value must be an integer between 0-7 or one of "
                . join( ", ", keys %zx_colours );
        }
    }
} else {
    $loading_bar_colour = $zx_colours{'BLACK'};
}

$bank_load_delay = $bank_load_delay || 0;

$start_delay = $start_delay || 0;

$preserve_state = $preserve_state || 0;

if ( defined( $required_core_version ) ) {
    if ( $required_core_version !~ m/^\d+\.\d+\.\d+$/ ) {
        push @errors, "*** Error: --required-core-version requires a version number in X.Y.Z format";
    }
} else {
    $required_core_version = '0.0.0';
}

if ( defined( $timex_hires_colour ) ) {
    if ( $timex_hires_colour =~ m/^\d+$/ ) {
        if ( ( $timex_hires_colour < 0 ) or ( $timex_hires_colour > 7 ) ) {
            push @errors, "*** Error: --timex-hires-colour value must be an integer between 0-7 or one of "
                . join( ", ", keys %zx_colours );
        }
    } else {
        if ( exists( $zx_colours{ uc( $timex_hires_colour ) } ) ) {
            $timex_hires_colour = $zx_colours{ uc( $timex_hires_colour ) };
        } else {
            push @errors, "*** Error: --loading-bar-colour value must be an integer between 0-7 or one of "
                . join( ", ", keys %zx_colours );
        }
    }
} else {
    $timex_hires_colour = $zx_colours{'BLACK'};
}

$entry_bank = $entry_bank || 0;

if ( defined( $file_handle_address ) ) {
    if ( $file_handle_address =~ m/^0x([A-Fa-f0-9]{4})$/i ) {
        $file_handle_address = hex( $1 );
    } else {
        if ( $file_handle_address =~ m/^\d+$/ ) {
            my $val = $1;
            if ( ( $val < 0 ) or ( $val > 65535 ) ) {
                push @errors, "*** Error: --file-handle-address must be a decimal (0-65535) or hex (0x0000-0xffff)";
            }
        } else {
            push @errors, "*** Error: --file-handle-address must be a decimal (0-65535) or hex (0x0000-0xffff)";
        }
    }
} else {
    $file_handle_address = 0;
}

help_and_exit if @errors;

# output NEX header
my $nex_header_binary_data = pack('A4A4C4S3a112C5a3C2S',
    'Next',
    'V1.2',
    ( $ram == 768 ? 0 : 1 ),
    $num_present_banks,		# FIX
    $load_screen_blocks,
    $border_colour,
    $sp,
    $pc,
    $num_extra_files,
    @present_banks,		# FIX
    $loading_bar,
    $loading_bar_colour,
    $bank_load_delay,
    $start_delay,
    $preserve_state,
    ( split( /\./, $required_core_version ) ),
    ( $timex_hires_colour << 3 ),
    $entry_bank,
    $file_handle_address,
);
# say "WIP: fake data is written!";

if ( defined( $output ) ) {
    write_file( $output, { binmode => ':raw' }, $nex_header_binary_data );
} else {
    binmode STDOUT;
    print $nex_header_binary_data;
}
