# SZXDATA Reference

SZXDATA is a tool that parses a SZX snapshot file and dumps data at specific positions in memory
according to a script which is passed as a parameter.

Usage: `szxdata.pl [-m <map_file>] -i <snapshot_file> -s <script_file>`

## Script File Syntax

- Text file, instructions are contained in a single line
- Comments start with # up to the end of the line
- Blank lines are ignored
- Line syntax: `<command> <args>`
- <addr> arguments can be specified as:
  - Decimal number
  - Hex number with $ or 0x prefix
  - Binary number with % prefix
  - Symbol (to be resolved with the optional map file)
  - Additionally, a positive or negative increment can be added in decimal
  - No spaces are allowed between prefixes, numbers and/or increments
  - Examples: 32768 / $C010 / %11110000 / _all_sprites / _all_sprites+10 /
    _all_sprites-5

Commands:

- `pb <addr>` - Prints 8-bit number at address <addr>
- `pw <addr>` - Prints 16-bit number at address <addr> (Little Endian)
- `pl <addr>` - Prints 32-bit number at address <addr> (LE)
