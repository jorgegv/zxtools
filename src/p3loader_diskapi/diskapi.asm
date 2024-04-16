;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                                        ;;
;;                  FDC DRIVER FUNCTIONS                  ;;
;;                                                        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

defc FDC_CONTROL	= 0x3ffd
defc FDC_CONTROL_H	= 0x3f
defc FDC_STATUS		= 0x2ffd
defc FDC_STATUS_H	= 0x2f

defc FDC_TRACK_SIZE	= 4608	;; 512 * 9
;; sector size is assumed = 512


;; this is the only function that should be used from this API
public fdc_load_bytes

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; MAIN API FUNCTION FOR THE LOADER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; load bytes sequentially from disk - same interface as
;; LD-BYTES routine from 48-ROM
;;
;; INPUTS:
;; DE = bytes to load
;; IX = destination address
;; C flag set (ignored)
;; A = 0xff (ignored)
;; Returns: C flag set if success, reset if error
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_load_bytes:

	;; IX maintains the current destination address during all the
	;; routine. The subroutines that are called by this one all
	;; preserve IX

	;; A and IX registers are preserved across function calls
	;; BC,DE,HL are not preserved
	;; IY and the alternate register bank are not used

fdc_ld_bytes_loop_full_track:
	;; DE = remaining bytes
	ld hl,FDC_TRACK_SIZE
	sbc hl,de			;; if track_size > remaining bytes, skip to partial track load
	jr nc,fdc_ld_bytes_partial_track

	push de				;; save remaining bytes

	;; load full track and restart
	ld a,(fdc_current_track)	;; track
	ld b,1				;; start sector
	ld c,9				;; end sector
	push ix
	pop hl				;; HL = current dest address
	ld de,FDC_TRACK_SIZE		;; bytes to load

	call fdc_load_sectors

	ld bc,FDC_TRACK_SIZE
	add ix,bc			;; update dest address
	pop hl				;; recover remaining bytes
	sbc hl,bc
	ld de,hl			;; DE = updated remaining bytes

	ld hl,fdc_current_track		;; inc current track
	inc (hl)

	jr fdc_ld_bytes_loop_full_track	;; repeat until remaining bytes < full track

	;; load partial track
fdc_ld_bytes_partial_track:
	;; DE = remaining bytes
	push de				;; save for later calculation

	ld a,d
	or e
	jr z,fdc_ld_bytes_inc_track	;; end if remaining bytes = 0

	ld a,(fdc_current_track)	;; track
	ld b,1				;; start sector
	ld c,d
	srl c
	inc c				;; C = end sector (remaining bytes/512 + 1)
	push ix
	pop hl				;; HL = dest address
	call fdc_load_sectors

	pop de				;; DE = bytes loaded (saved above)
	add ix,de			;; update dest address

fdc_ld_bytes_inc_track:
	ld hl,fdc_current_track		;; inc current track
	inc (hl)

	scf				;; signal success
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; read N bytes in track A from sectors B to C, store to
;; HL - only stores up to N bytes, without overwriting after that
;;
;; INPUTS:
;; A = track number
;; B = start sector ID
;; C = end sector ID
;; DE = number of bytes to read
;; HL = destination address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_load_sectors:

	push ix

	push hl
	push de
	push bc

	call fdc_read_id

	;; A = track number
	call fdc_seek_track

	call fdc_read_id

	pop bc

	;; set up data struct
	ld ix,data_cmd_read_delete
	ld (ix+3),a			;; set track nr
	ld (ix+5),b			;; set start sector
	ld (ix+7),c			;; set end sector

	;; send read cmd
	ld de,data_cmd_read_delete
	call fdc_send_command
	jp nc,fdc_panic

	;; start reading bytes
	pop de
	pop hl
	call fdc_read_n_bytes

	;; when finished, dump results to buffer
	;; read sends back ST0, ST1 and ST2
	call fdc_receive_results
	jp nc,fdc_panic

	ld a,(fdc_status_data+1)	;; check ST1 register status
	jr nz,fdc_ld_p_end		;; if any bit is set, error

	scf				;; success

fdc_ld_p_end:
	pop ix
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; read N sector bytes - bytes after N are read but discarded
;;
;; Internally, this function may overwrite up to 511 bytes after the
;; expected memory area where the data will be loaded.  But it saves this
;; area if needed in a 512 byte buffer before starting the transfer, and
;; restores it at the end.  The net result is that no memory is corrupted
;; after the exact last byte loaded.
;;
;; This hack is done to avoid having to read sectors one by one in the
;; buffer, which makes loading much slower.  Data load times using this
;; method vs.  reading sector by sector have been reduced by 75% (!!) in
;; real game loads.
;;
;; INPUTS:
;; DE = number of bytes to read from FDC
;; HL = destination address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_read_n_bytes:

	push hl
	push de

	;; save 512 bytes after dest buffer, which may be overwritten
	;; but only if it's not a multiple of 512
	call check_de_multiple_512
	jr c, fdc_read_skip_save_buf

	;; save bytes block
	exx
	pop de
	pop hl
	push hl
	push de
	add hl,de	;; source addr
	ld de,fdc_read_sector_buffer
	ld bc,512
	ldir
	exx

fdc_read_skip_save_buf:
	pop de
	pop hl
	push hl
	push de

	;; load sector in temporary buffer, transfer later
	;; wait for FDC ready to send
	ld bc,FDC_STATUS

	;; The following loop may overwrite up to 511 bytes just after the
	;; destination area but we have saved them before

	; This loop must run FAST AS HELL to avoid losing bytes!
fdc_read_wait_send_status_not_ready:
	in a,(c)					;; BC = FDC_STATUS
	jp p,fdc_read_wait_send_status_not_ready	;; bit 7 = 0 : data register not ready
	and 0x20					;; check for execution phase
	jp z,fdc_read_restore_last_block		;; if Z, finished

	;; load data byte
	ld b,FDC_CONTROL_H
	ini						;; read and store data byte
	ld b,FDC_STATUS_H
	jr fdc_read_wait_send_status_not_ready
	; end of FAST-AS-HELL loop :-)

	;; restore 512 bytes after dest buffer, which may have been
	;; overwritten but again, only if it's not a multiple of 512
fdc_read_restore_last_block:
	pop de
	push de
	call check_de_multiple_512
	jr c, fdc_read_skip_restore_buf

	;; restore bytes block
	exx
	pop de
	pop hl
	push hl
	push de
	add hl,de
	ex de,hl	;; dst addr
	ld hl,fdc_read_sector_buffer
	ld bc,512
	ldir
	exx

fdc_read_skip_restore_buf:
	pop de
	pop hl
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; small delay
;; no inputs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_small_delay:
	ld a,0x05
fdc_small_delay_loop:
        dec a
	nop
	jr nz,fdc_small_delay_loop
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; waits until FDC is ready to receive commands
;; no inputs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_wait_ready_to_receive:
	push af
	ld bc,FDC_STATUS
fdc_wait_rec_status_not_ready:
	in a,(c)					;; read status
	add a,a         				;; bit 7->C, bit 6->7
	jr nc,fdc_wait_rec_status_not_ready		;; bit 7 off: data register not ready
	add a,a						;; bit 7->C (old bit 6)
	jp c,fdc_panic					;; old bit 6 off: CPU to FDD direction OK
	pop af
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; waits until FDC is ready to send data
;; no inputs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_wait_ready_to_send:
	push af
	ld bc,FDC_STATUS
fdc_wait_send_status_not_ready:
	in a,(c)					;; BC = FDC_STATUS
	add a,a						;; bit 7->C, bit 6->7
	jr nc,fdc_wait_send_status_not_ready		;; bit 7 off: data register not ready
	add a,a						;; bit 7->C (old bit 6)
	jp nc,fdc_panic					;; old bit 6 on: FDD to CPU direction OK
	pop af
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; sends command to FDC
;; comand data: 1 byte for length (=N), N command bytes
;;
;; INPUTS:
;; DE = address of command
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_send_command:

	ld a,(de)					;; get command length
	ld b,a						;; B = num of bytes to send
send_cmd_next_byte:
	inc de						;; addres of next byte
	ld a,(de)					;; A = command byte
	push bc						;; save counter

	call fdc_wait_ready_to_receive

	;; send command byte
	ld bc,FDC_CONTROL
	out (c),a

	;; let the FDC breathe :-)
	call fdc_small_delay

	;; continue with next byte
	pop bc						;; restore counter
	djnz send_cmd_next_byte

	scf						;; success
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; receive results of previous cmd from FDC
;; not all commands generate results
;; no inputs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_receive_results:

	ld hl,fdc_status_data		;; results buffer
fdc_rec_res_loop:
	call fdc_wait_ready_to_send	;; wait until FDC wants to send

	ld bc,FDC_CONTROL
	ini				;; read byte from FDC and inc HL
	
	call fdc_small_delay

	ld bc,FDC_STATUS		;; check status again
	in a,(c)
	and 0x10			;; bit 4 = 1: command in progress
					;; CHECK: +3DOS comprueba si bit 6 = 0 (?)
	jr nz,fdc_rec_res_loop		;; more bytes available

	scf				;; success
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; reads ID from FDC - "resets" everything
;; no inputs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_read_id:
	push af

	ld de,data_cmd_read_id

	call fdc_send_command
	jp nc,fdc_panic

	call fdc_receive_results
	jp nc,fdc_panic

	ld a,(fdc_status_data)		;; read_id returns ST0 first
	or a
	jr nz,fdc_read_id		;; wait until ST0 is 0 -> All OK no errors

	pop af
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; checks if DE is a multiple of 512
;; Carry set if it is
;; preserves everything
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
check_de_multiple_512:
	;; a multiple of 512 has all bits 0-8 = 0
	push af
	push de
	ld a,e
	or a
	jr nz,check_de_multiple_512_end		;; if any bit 0-7 is set, not multiple
	rrc d
	jr c,check_de_multiple_512_end		;; if bit 8 is set, not multiple
	pop de
	pop af
	scf					;; set C = 1: it is a multiple
	ret

check_de_multiple_512_end:
	pop de
	pop af
	or a					;; set C = 0: it is not a multiple
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; seek to track N
;;
;; INPUTS:
;; A = track number
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_seek_track:

	push af				;; save A

	;; set track in command data struct
	ld (data_cmd_seek_track+3),a

	;; send command
	ld de,data_cmd_seek_track
	call fdc_send_command
	jp nc,fdc_panic

	;; check status - prev cmd does not receive results
	ld bc,FDC_STATUS
	in a,(c)
	and 0x81			;; bit 0 = seek mode
	jp z,fdc_panic

	;; sense interrupt status after seek
fdc_seek_rec_res_loop:
	ld de,data_cmd_sense_interrupt_status
	call fdc_send_command
	jp nc,fdc_panic

	;; this cmd receives results
	call fdc_receive_results
	ld a,(fdc_status_data)		;; ST0 register status
	bit 5,a				;; bit 5 = seek complete ?
	jr z,fdc_seek_rec_res_loop	;; no => retry

	pop af
	scf
	ret

;; unrecoverable errors end here
fdc_panic:
	ld a,0x03	;; set magenta border
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

;; FDC results data buffer
fdc_status_data:
	ds 10		;; reserve 10 bytes

;; current track
fdc_current_track:
	db 0x01		;; first data track is #1 (the second one)
			;; track #0 is reserved for bootloader and loader

fdc_read_sector_buffer:
	ds 512		;; read buffer
