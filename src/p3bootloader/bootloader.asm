;; Bootloader code for +3 boot disks, by ZXjogv <zx@jogv.es>

;; This code is stored in the boot sector (track 0, sector 0) of a bootable +3 disk,
;; at offset 0x10. The first 16 bytes are a disk identification record that
;; describes the format of the disk.

;; +3 Startup sequence:
;;
;; - ALLRAM-4-7-6-3 configuration is set
;; - Boot sector is loaded by ROM at 0xfe00
;; - Interrupts are disabled
;; - Execution jumps to bootloader code at 0xfe10 (this program)

;; This bootloader does the following:
;;
;; - Switch to ALLRAM-0-1-2-3 configuration: we need to have bank 2 in the
;;   same position as USR0 mode 5-2-0, that is, page 2 at 0x8000.
;; - Load sectors 2-9 from track 0 (loader must be stored there) to 0x8000
;; - Copy the set_mode_usr0 routine to just below 0xc000 (page 2) and jump
;;   to it. This routine does the following 2 steps
;; - Switch to USR0 mode 5-2-0 configuration
;; - Jump to 0x8000 with interrupts disabled

defc USR0_ROUTINE_SIZE		= end_set_mode_usr0 - set_mode_usr0
defc USR0_ROUTINE_FINAL_ADDR	= 0xc000 - USR0_ROUTINE_SIZE

defc SECTOR_SIZE		= 512

	;; start here with allram-4763, di
	org 0xfe10
	ld sp,0xfdff			;; stack below this bootloader

	;; switch mode and start motor
	call set_mode_allram_0123	;; page 3 still at top, stack safe

	;; load loader to 0x8000
	call load_loader_from_disk

	;; transfer usr0 routine to page 2
	call copy_usr0_routine

	;; switch to USR0 and jump to loader
	jp USR0_ROUTINE_FINAL_ADDR

;; copies USR0 routine to final destination
copy_usr0_routine:
	ld hl,set_mode_usr0
	ld de,USR0_ROUTINE_FINAL_ADDR
	ld bc,USR0_ROUTINE_SIZE
	ldir
	ret

;; set RAM pages to 0-1-2-3
set_mode_allram_0123:
	ld bc,0x1ffd
	ld a,0x09			;; 00001001 - b0: special paging; b1-b2: paging config 0; b3: motor on
	out (c),a
	ret

load_loader_from_disk:
	ret




;; This routine is copied to the end of page 2, just below 0xC000, so that
;; it is not disturbed when switching to USR0 mode (which unmaps page 3).
;; THe final instruction is to jump to the loader that has already been
;; loaded at 0x8000
set_mode_usr0:

	ld bc,0x7ffd
	ld a,0x10			;; b0-b2: page 0 at $C000; b3: screen at page 5; b4: 48K rom
	out (c),a

	ld sp,0x7fff			;; stack below loader
	jp 0x8000			;; jump to loader

end_set_mode_usr0:
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; FDC driver functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; load a sector from track 0 to HL
;; A = sector ID (2-9) - Sector 1 is this bootloader
;; HL = destination address
load_sector:
	ret


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; FDC Driver data
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; command blocks
data_cmd_read_delete:
	db 0x09		;; length = 9 bytes
	db 0x46		;; command id
	db 0x00		;; disk unit
	db 0x00		;; track
	db 0x00		;; head
	db 0x02		;; initial sector to read
	db 0x02		;; sector size - 2=512b
	db 0x09		;; last sector to read
	db 0x2A		;; gap length
	db 0xff		;; unused here

data_cmd_seek_track:
	db 0x03		;; length = 3 bytes
	db 0x0f		;; command id
	db 0x00		;; disk unit
	db 0x00		;; track

data_cmd_sense_status:
	db 0x01		;; length = 1 byte
	db 0x08		;; command id

data_cmd_read_unit_id:
	db 0x02		;; length = 2 byes
	db 0x4a		;; command id
	db 0x00		;; param

;; FDC result data buffer
fdc_status_data:
	ds 10		;; reserve 10 bytes
