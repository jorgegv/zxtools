.SILENT:

all: bootloader testloader testbins testdsk

bootloader:
	make -C ../p3bootloader/

testloader:
	zcc +zx --no-crt testloader.asm diskapi.asm -o testloader.bin --list -m

# the sizes of these binaries is special, see testloader.asm!
testbins:
	perl -e 'binmode(STDOUT);print pack("C*",( 0xa1 ) x 187 );' >test1.bin
	perl -e 'binmode(STDOUT);print pack("C*",( 0xb2 ) x 4795 );' >test2.bin
	perl -e 'binmode(STDOUT);print pack("C*",( 0xc3 ) x 6843 );' >test3.bin

testdsk:
	../../bin/dsktool.pl -b ../p3bootloader/bootloader.bin -l testloader.bin -o test.dsk test1.bin test2.bin test3.bin

clean:
	-rm -f *.bin *.lis *.o *.map

run:
	fuse test.dsk

BREAKPOINT	= 8000
debug:
	fuse --debugger-command 'br $$$(BREAKPOINT)' test.dsk
