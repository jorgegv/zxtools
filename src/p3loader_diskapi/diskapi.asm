;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                                        ;;
;;                  FDC DRIVER FUNCTIONS                  ;;
;;                                                        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

defc FDC_CONTROL	= $3ffd
defc FDC_STATUS		= $2ffd
defc FDC_TRACK_SIZE	= 4608	;; 512 * 9

public fdc_load_bytes

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; MAIN API FUNCTION FOR THE LOADER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; load bytes sequentially from disk - same interface as
;; LD-BYTES routine from 48-ROM
;; DE = bytes to load
;; IX = destination address
;; C flag set (ignored)
;; A = 0xff (ignored)
;; Returns: C flag set if success, reset if error
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_load_bytes:
	ex de,hl		;; HL = bytes to load

	push hl			;; save remaining bytes

	;; IX maintains the current destination address during all the
	;; routine


fdc_ld_bytes_loop_full_track:
	;; HL here = remaining bytes
	;; if remaining bytes < track size, skip to partial track load
	ld de,FDC_TRACK_SIZE
	or a			;; reset carry
	sbc hl,de
	jr c,fdc_ld_bytes_partial_track

	;; load full track and restart
	pop de				;; discard old value
	push hl				;; save new remaining bytes
	ld a,(fdc_current_track)	;; track
	ld b,1				;; start sector
	ld c,9				;; end sector
	push ix
	pop hl				;; HL = current dest address
	call fdc_load_sectors

	ld bc,FDC_TRACK_SIZE
	add ix,bc			;; update dest address

	ld hl,fdc_current_track		;; inc current track
	inc (hl)

	pop hl				;; HL = remaining bytes
	push hl
	jr fdc_ld_bytes_loop_full_track	;; repeat until < full track remains

	;; load partial track
fdc_ld_bytes_partial_track:
	pop de				;; DE = remaining bytes
	push de				;; save again

	ld a,d				;; discard 9 low bits of DE
	and 0xfe
	ld d,a
	ld e,0				;; DE = remaining bytes / 512

	pop hl				;; HL = remaining bytes
	push hl				;; save again
	or a
	sbc hl,de			;; HL = remaining bytes after partial track load
					;; will be remaining bytes % 512

	push hl				;; save future remaining bytes for later

	push de				;; save bytes to load for later

	ld a,(fdc_current_track)	;; track
	ld b,1				;; start sector
	ld c,d
	srl c				;; C = remaining bytes / 512 (end sector)
	
	push ix
	pop hl				;; HL = dest address
	call fdc_load_sectors

	pop de				;; DE = bytes loaded (saved above)
	add ix,de			;; update dest address

fdc_ld_bytes_last_sector:
	pop de				;; DE = remaining bytes (always < 512)
	pop hl				;; recover remaining bytes before last load
	ld b,h
	srl b				;; B = last full sector (remaining bytes before / 512)
	inc b				;; B = last full sector + 1
	ld a,(fdc_current_track)	;; A = track

	push ix
	pop hl				;; HL = dest address
	call fdc_load_partial_sector

	scf
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; small delay
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_send_command:

	ld a,(de)					;; get command length
	ld b,a						;; B = num of bytes to send

send_cmd_next_byte:
	inc de						;; addres of next byte
	ld a,(de)					;; A = command byte
	push bc						;; save counter
	push af						;; save command byte for later

	;; wait until ready
	ld bc,FDC_STATUS

send_cmd_status_not_ready:
	in a,(c)					;; read status
	add a,a         				;; bit 7->C, bit 6->7
	jr nc,send_cmd_status_not_ready			;; bit 7 off: data register not ready

	;; check data direction is OK, abort if not
	add a,a						;; bit 7->C (old bit 6)
	jr c,send_cmd_abort				;; old bit 6 off: CPU to FDD direction OK

	;; send command byte
        pop af						;; restore command byte
	ld bc,FDC_CONTROL
	out (c),a

	;; let the FDC breathe :-)
	call fdc_small_delay

	;; continue with next byte
	pop bc						;; restore counter
	djnz send_cmd_next_byte

	scf						;; C = no error
	ret

send_cmd_abort:
	pop af		;; old BC
	pop af
	or a		;; reset C
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; receive results of previous cmd from FDC
;; not all commands generate results
;; no inputs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_receive_results:

	ld hl,fdc_status_data				;; results buffer

fdc_rec_res_loop:
	ld bc,FDC_STATUS
	in a,(c)
	cp 0xc0						;; bits 6-7 are 1 ?
	jr c,fdc_rec_res_loop				;; if not, FDC still busy, retry

	ld bc,FDC_CONTROL
	ini						;; read byte and inc HL
	
	call fdc_small_delay

	ld bc,FDC_STATUS				;; check status again
	in a,(c)
	and 0x10					;; nz: command in progress
	jr nz,fdc_rec_res_loop

	ld a,(fdc_status_data+1)			;; ST2 register status
	and 0x04					;; bit 2 = error ?
	ret nz						;; ret with error (not found)

	scf						;; C = no error
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; load sectors from track A  to HL
;; A = track number
;; B = initial sector ID
;; C = final sector ID
;; HL = destination address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_load_sectors:

	push hl
	push bc
	push af

	;; A = track number
	call fdc_seek_track

	pop af
	pop bc

	;; set up data struct
	ld ix,data_cmd_read_delete
	ld (ix+3),a			;; set track nr
	ld (ix+5),b			;; set start sector
	ld (ix+7),c			;; set end sector
	ld de,data_cmd_read_delete
	call fdc_send_command
	jp nc,fdc_panic

	;; start reading bytes
	pop hl
	call fdc_read_bytes

	;; when finished, dump results
	call fdc_receive_results
	jp nc,fdc_panic

	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; read sector bytes
;; HL = destination address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_read_bytes:

	ld bc,FDC_STATUS

fdc_rd_wait_ok:
	in a,(c)
	jp p,fdc_rd_wait_ok				;; wait until bit 7 = 1
	and 0x20					;; check for execution phase
	jr z,fdc_rd_end					;; if Z, finished

	ld bc,FDC_CONTROL
	ini						;; read byte into (HL) and inc HL

	jr fdc_read_bytes
fdc_rd_end:
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; read N bytes from a given sector in track A  to HL - only
;; stores up to N bytes, without overwriting after that
;; A = track number
;; B = sector ID
;; DE = number of bytes to read
;; HL = destination address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_load_partial_sector:

	push hl
	push de
	push bc
	push af

	;; A = track number
	call fdc_seek_track

	pop af
	pop bc

	;; set up data struct
	ld ix,data_cmd_read_delete
	ld (ix+3),a			;; set track nr
	ld (ix+5),b			;; set start sector
	ld (ix+7),b			;; end sector is the same
	ld de,data_cmd_read_delete
	call fdc_send_command
	jp nc,fdc_panic

	;; start reading bytes
	pop de
	pop hl
	call fdc_read_n_bytes

	;; when finished, dump results
	call fdc_receive_results
	jp nc,fdc_panic

	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; read N sector bytes - bytes after N are read but discarded
;; DE = number of bytes to read from FDC
;; HL = destination address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_read_n_bytes:

	ld bc,FDC_STATUS

fdc_rd_n_wait_ok:
	in a,(c)
	jp p,fdc_rd_n_wait_ok				;; wait until bit 7 = 1
	and 0x20					;; check for execution phase
	jr z,fdc_rd_n_end				;; if Z, finished

	ld bc,FDC_CONTROL
	ld a,d
	or e
	jr z,fdc_rd_n_no_store				;; if DE is 0 we have already
							;;  read the required bytes, so skip

	ini						;; read byte into (HL) and inc HL
	dec de						;; decrement byte counter
	jr fdc_rd_n_next				

fdc_rd_n_no_store:
	in a,(c)					;; read and discard

fdc_rd_n_next:
	jr fdc_read_n_bytes
fdc_rd_n_end:
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; seek to track N
;; A = track number
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_seek_track:

	;; set track in command data struct
	ld (data_cmd_seek_track+3),a

	;; send command
	ld de,data_cmd_seek_track
	call fdc_send_command
	jp nc,fdc_panic

	;; check status - prev cmd does not receive results
	ld bc,FDC_STATUS
	in a,(c)
	and 0x80
	jp z,fdc_panic

	;; sense interrupt status after seek
	ld de,data_cmd_sense_interrupt_status
	call fdc_send_command
	jp nc,fdc_panic

	;; this cmd receives results
	call fdc_receive_results
	jp nc,fdc_panic

	ret

;; unrecoverable errors end here
fdc_panic:
	ld a,2		;; set red border
	out (0xfe),a
	di
	halt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; FDC Driver data
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; In the following data structs, DNC = Do Not Change

;; command data blocks
;; comand data: 1 byte for length, N command bytes
data_cmd_read_delete:
	db 0x09		;; length = 9 bytes	- DNC
	db 0x46		;; command id		- DNC
	db 0x00		;; disk unit		- DNC
	db 0x00		;; track
	db 0x00		;; head			- DNC
	db 0x00		;; initial sector to read
	db 0x02		;; sector size: 2=512	- DNC
	db 0x00		;; last sector to read
	db 0x2A		;; gap length		- DNC
	db 0xff		;; unused		- DNC

data_cmd_seek_track:
	db 0x03		;; length = 3 bytes	- DNC
	db 0x0f		;; command id		- DNC
	db 0x00		;; disk unit		- DNC
	db 0x00		;; track

data_cmd_sense_interrupt_status:
	db 0x01		;; length = 1 byte	- DNC
	db 0x08		;; command id		- DNC

data_cmd_read_id:
	db 0x02		;; length = 2 byes	- DNC
	db 0x4a		;; command id		- DNC
	db 0x00		;; param		- DNC

;; FDC result data buffer
fdc_status_data:
	ds 10		;; reserve 10 bytes

;; current track
fdc_current_track:
	db 0x01		;; first data track is #1 (the second one)
			;; track #0 is reserved for bootloader and loader
