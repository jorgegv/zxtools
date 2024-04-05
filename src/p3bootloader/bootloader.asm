;; Bootloader code for +3 boot disks, by ZXjogv <zx@jogv.es>
;; Heavily based on code from Xor_A [Fer], esp. wrt magic numbers

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

defc LOADER_ADDRESS		= 0x8000

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
	ld hl,LOADER_ADDRESS
	call fdc_load_track0
	ret

;; This routine is copied to the end of page 2, just below 0xc000, so that
;; it is not disturbed when switching to USR0 mode (which unmaps page 3). 
;; The final instruction jumps to the loader that has previously been loaded
;; at 0x8000
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

defc FDC_CONTROL 		= $3f
defc FDC_CONTROLW		= $3ffd
defc FDC_STATUS			= $2f
defc FDC_STATUSW		= $2ffd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; small delay utility function
fdc_small_delay:
	ld a,$05
fdc_small_delay_loop:
        dec a
	nop
	jr nz,fdc_small_delay_loop
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; sends command to FDC
;; DE = address of command
;; comand data: 1 byte for length, N command bytes
fdc_send_command:
	ld a,(de)					;; get command length
	ld b,a						;; B = num of bytes to send

send_cmd_next_byte:
	inc de						;; addres of next byte
	ld a,(de)					;; A = command byte
	push bc						;; save counter
	push af						;; save command byte for later

	;; wait until ready
	ld bc,FDC_STATUSW
send_cmd_status_not_ready:
	in a,(c)					;; read status
	add a,a         				;; bit 7->C, bit 6->7
	jr nc,send_cmd_status_not_ready			;; bit 7 off: data register not ready

	;; check data direction is OK, abort if not
	add a,a						;; bit 7->C (old bit 6)
	jr c,send_cmd_abort				;; old bit 6 off: CPU to FDD direction OK

	;; send command byte
        pop af						;; restore command byte
	ld bc,FDC_CONTROLW
	out (c),a

	;; delay
	call fdc_small_delay

	;; go with the next byte
	pop bc						;; restore counter
	djnz send_cmd_next_byte

	scf						;; C = no error
	ret

send_cmd_abort:
	pop af		;; old BC
	pop af
	ret


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; receive results of previous cmd from FDC
;; no inputs
fdc_receive_results:
	ld hl,fdc_status_data				;; results buffer
fdc_rec_res_loop:
	ld bc,FDC_STATUSW
	in a,(c)
	cp 0xc0						;; bits 6-7 are 1 ?
	jr c,fdc_rec_res_loop				;; if not, FDC still busy, retry

	ld bc,FDC_CONTROLW
	ini						;; read byte and inc HL
	
	call fdc_small_delay

	ld bc,FDC_STATUSW				;; check status again
	in a,(c)
	and 0x10					;; nz: command in progress
	jr nz,fdc_rec_res_loop

	ld a,(fdc_status_data+1)			;; ST2 register status
	and 0x04					;; bit 2 = error ?
	ret nz						;; ret with error (not found)

	scf						;; C = no error
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; load all sectors from track 0  to HL, starting from 2
;; Sector 1 is this bootloader
;; HL = destination address
fdc_load_track0:

	push hl

	xor a						;; seek to track 0
	call fdc_seek_track

	;; all data is ready in the struct
	ld de,data_cmd_read_delete
	call fdc_send_command
	jp nc,fdc_panic

	;; start reading bytes
	pop hl
	call fdc_read_bytes

	call fdc_receive_results
	jp nc,fdc_panic

	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; read sector bytes
;; HL = destination address
fdc_read_bytes:
	ld bc,FDC_STATUSW

fdc_rd_wait_ok:
	in a,(c)
	jp p,fdc_rd_wait_ok				;; wait until bit 7 = 1
	and 0x20					;; check for execution phase
	jr z,fdc_rd_end					;; if Z, finished

	ld bc,FDC_CONTROLW
	ini						;; read byte into (HL) and inc HL

	jr fdc_read_bytes
fdc_rd_end:
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; seek to track N
;; A = track number
fdc_seek_track:
	;; set track in command data struct
	ld (data_cmd_seek_track+3),a

	;; send command
	ld de,data_cmd_seek_track
	call fdc_send_command
	jp nc,fdc_panic

	;; receive results
	call fdc_receive_results
	jp nc,fdc_panic

	ret

;; unrecoverable errors end here
fdc_panic:
	di
	halt


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; FDC Driver data
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; command blocks
;; comand data: 1 byte for length, N command bytes
data_cmd_read_delete:
	db 0x09		;; length = 9 bytes
	db 0x46		;; command id
	db 0x00		;; disk unit
	db 0x00		;; track
	db 0x00		;; head
	db 0x02		;; initial sector to read
	db 0x02		;; sector size - 2=512
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
