# DSKTOOL - A tool for creating ZX Spectrum +3 game discs

## Introduction

The motivation behind DSKTOOL is to make creating disc versions of Spectrum
games as easy as it is to create TAP versions, and _using the same game
binaries_ as the TAP version.

The main design choice is to _not use regular +3DOS_ formatted discs for
storage, but to use a custom disc format and layout that makes it trivial to
write a loader for the disc version (this is the only thing that needs to
change with respect to the TAP version).

This means that the discs generated with this tool will not be readable by
+3 BASIC nor any other software, but they will just boot the game when you
select the "LOADER" option in the +3 start menu.

This tool generates the DSK disc image file that can be later used to boot
it in +3 emulators, or used as a master for physical media generation.

## Design

The generated disc is of the +3 bootable type, and so it has a tiny generic
bootloader with a special signature that the +3 ROM expects, at track 0
sector 0 (512 bytes). This generic bootloader is provided with the tool and
you don0t need to create it.

The disc geometry is the standard +3/Amstrad format: single sided, 40
tracks, 9 sectors per track, 512-byte sectors. In this document, tracks are
numbered 0-39, and sectors 1-9.

The bootloader is detected and invoked by the ROM when the LOADER option is
selected, and the bootloader in turn loads the real game specific loader at
a given position in RAM (0x8000).

This loader must use a special provided API for loading the game binaries
from the disc, with a function that is mostly compatible with the LD-BYTES
ROM routine for loading from tape, i.e.  it receives the same parameters and
loads the bytes from media (just from disc instead of tape).  This makes it
trivial to adapt the existing TAP loader for the disc version.

The API to load the data blocks from disc is provided as an ASM file that
must be linked together with the specific loader code.  This API talks
directly to the FDC (Floppy Drive Controller) and makes no use of ROM calls
or interrupts. It runs with interrupts disabled.

## Disc Layout

The layout of the disc is as follows:

- Track 0, sector 1: generic bootloader (512 bytes max)
- Track 0, sectors 2-9: specific game loader (4096 bytes max)
- Tracks 1-38 to the end of disc: game data blocks

The data blocks are laid out in the following way:

- Each data block always starts at the beginning of a track, and uses the
needed number of sectors from that track

- If the data block size is bigger than one track, the following tracks are
  used automatically and sequentially up to the length of the data block

## Tool Usage

Example usage:

```
dsktool.pl -b bootloader.bin -o image.dsk -l loader.bin screen.scr bank1.bin bank3.bin main.bin
```

- Option `-b` selects the bootloader binary to use
- Option `-o` sets the output file name
- Option `-l` selects the game loader binary to use
- The remaining files (`screen.scr`, `bank1.bin`, `bank3.bin`, `main.bin`, etc.)
are the game data binaries in the same order that the loader expects them.

All the binaries will be laid out on the disc according to the rules
indicated in the previous section.

## References

- Bootable disks: https://retrocomputing.stackexchange.com/questions/14574/how-does-the-spectrum-3-know-whether-a-disk-is-bootable-or-not

- More: https://retrocomputing.stackexchange.com/questions/14575/how-do-i-know-where-the-file-directory-is-stored-on-a-spectrum-3-disk-layout/14601#14601

- Plus 3 User Manual: https://worldofspectrum.org/ZXSpectrum128%2B3Manual/

- Amstrad/+3 Disk format: https://www.seasip.info/Cpm/amsform.html

