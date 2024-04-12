# DSKTOOL - A tool for creating ZX Spectrum +3 game disks in VTAPE format

## Introduction

The motivation behind DSKTOOL is to allow creating disk versions of ZX games
for the Spectrum +3 as easily as TAP versions, and _reusing the same game
binaries_ from the TAP version.  The easies way to achieve this is to use
the disk as a sort of "virtual tape", or VTAPE, in which the game data is
stored and read sequentially, the same way as a real tape would be used.

VTAPE is just a way to format the disk and data inside it, and a convention
for accessing that data in an easy way from the game loader.

This tool generates the VTAPE disk image file (in standard DSK format) that
can be later used to boot the game in +3 emulators, or used as a master for
physical media generation.

A loader API is also provided to access the VTAPE disk and load the game
data.

## Requirements

The tool itself is written in Perl with no dependencies, and the ASM files
and Makefiles for the needed support code is intended to be compiled with
Z88DK.

## Design

The main design choice is to _not use regular +3DOS_ formatted disks for
storage, but to use a custom disk format and layout that makes it trivial to
write a loader for the disk version (this is the only thing that needs to
change with respect to the TAP version).

This means that the disks generated with this tool will not be readable by
+3 BASIC nor any other software, but they will just boot the game when you
select the "LOADER" option in the +3 start menu.

The generated disk is of the +3 bootable type, and so it has a tiny generic
bootloader with a special signature that the +3 ROM expects, at track 0
sector 0 (512 bytes).  This generic bootloader is provided with DSKTOOL and
you don't need to create it.

The disk geometry is the standard +3/Amstrad format: single sided, 40
tracks, 9 sectors per track, 512-byte sectors. In this document, tracks are
numbered 0-39, and sectors 1-9.

The bootloader is detected and invoked by the ROM when the LOADER option is
selected, and the bootloader in turn loads the real game specific loader at
a given position in RAM (0x8000). The game loader is a binary (i.e. machine
code) program, and NOT a BASIC program. No BASIC is involved when using the
VTAPE schema.

The game loader must use a special provided disk API for loading the game
binaries from the disk, with a function that is fully compatible with the
LD-BYTES ROM routine for loading from tape, i.e.  it receives the same
parameters and loads the bytes from media (just from disk instead of tape). 
Each successful call to the API function leaves the VTAPE pointer ready for
loading the next data block, exactly the same as a regular tape would.  This
makes it trivial to adapt an existing TAP loader for the disk version.

The API to load the data blocks from disk is provided as an ASM file
(diskapi.asm) that must be linked together with the specific loader code. 
This API talks directly to the FDC (Floppy Drive Controller) and makes no
use of ROM calls or interrupts.  It runs with interrupts disabled.

The game loader is called in USR0 mode (i.e.  ROM48-5-2-0 bank configuration
and paging enabled), with SP at 0x8000 and interrupts disabled

The maximum loader size is 4K.

## Disc Layout

The layout of the disk is as follows:

- Track 0, sector 1: generic bootloader (512 bytes max)
- Track 0, sectors 2-9: specific game loader (4096 bytes max)
- Tracks 1-38 to the end of disk: game data blocks

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

All the binaries will be laid out on the disk according to the rules
indicated in the previous section.

In the previous example, the `loader.asm` file which is compiled to
`loader.bin` must include the proper instructions to load the SCREEN$ to the
display file, switch banks and load their data to 0xC000 (`bankX.bin`
files), and finally set the final memory configuration, load the main code
(`main.bin`) and jump to the entry point for game execution.  That is,
everything a regular loader would do.

## Source Code

Source code for this tool is available in my [ZXTOOLS github repository](https://github.com/jorgegv/zxtools):

- Disk generation tool `dsktool.pl` can be found in the `bin` directory
- Source code for the generic bootloader is in directory `src/p3bootloader`
- Source code for the loader disk API and some trivial example loader is in
directory `src/p3loader_diskapi`
- Reference documentation (other loader's disassembly, datasheets and
application notes for the NEC Floppy Disc Controller) can be found in the
`reference/p3disk` directory

## Special acknowledgement

I'd like to thank `Xor_A [Fer]` from the spanish "Ensamblador Z80" Telegram
channel for his support in disassemblying the Robocop disk loader (on
which this work is loosely based) and his guidance in my initial steps in
programming the Floppy Disk Controller in the Speccy.

It would have taken me ages to do this without your hints :-) Thanks so
much.

## References

- Bootable disks: https://retrocomputing.stackexchange.com/questions/14574/how-does-the-spectrum-3-know-whether-a-disk-is-bootable-or-not

- More: https://retrocomputing.stackexchange.com/questions/14575/how-do-i-know-where-the-file-directory-is-stored-on-a-spectrum-3-disk-layout/14601#14601

- Plus 3 User Manual: https://worldofspectrum.org/ZXSpectrum128%2B3Manual/

- Plus 3 commented ROM disassembly: https://github.com/ZXSpectrumVault/rom-disassemblies

- Amstrad/+3 Disk format: https://www.seasip.info/Cpm/amsform.html

- Intel 8272 FDC Datasheet: https://datasheetspdf.com/pdf-down/8/2/7/8272_IntelCorporation.pdf
  (NEC uPD765 compatible)

- NEC uPD765 application note: https://hxc2001.com/download/datasheet/floppy/thirdparty/FDC/NEC/uPD765_App_Note_Mar79.pdf
  (_this_ is a really useful resource!)
