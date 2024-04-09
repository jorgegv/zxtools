	extern fdc_load_bytes
	org 0x8000

loader_start:
	;; first data track, 187 bytes
	;; test single last sector read
	;; This data file contains byte 0xa1 repeated
	ld a,0xff
	ld ix,0x9000
	ld de,187
	scf
	call fdc_load_bytes
	jp nc,load_error

	;; second data track, 1 track + 187 bytes = 4795 bytes
	;; test full track read + last sector read
	;; This data file contains byte 0xb2 repeated
	ld a,0xff
	ld ix,0xb000
	ld de,4795
	scf
	call fdc_load_bytes
	jp nc,load_error

	;; third data track, 1 track + 4 sectors + 187 bytes = 6843 bytes
	;; test full track read + partial track read + last sector read
	;; This data file contains byte 0xc3 repeated
	ld a,0xff
	ld ix,0xd000
	ld de,6843
	scf
	call fdc_load_bytes
	jp nc,load_error

load_success:
	ld a,0x04	;; green
	out (0xfe),a	;; set border
	di
	halt

load_error:
	ld a,0x02	;; red
	out (0xfe),a	;; set border
	di
	halt
