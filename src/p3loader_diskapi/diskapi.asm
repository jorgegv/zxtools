;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                                        ;;
;;                  FDC DRIVER FUNCTIONS                  ;;
;;                                                        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

defc FDC_CONTROL	= $3ffd
defc FDC_STATUS		= $2ffd
defc FDC_TRACK_SIZE	= 4608	;; 512 * 9
defc FDC_SECTOR_SIZE	= 512

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
	push de				;; save for later calculation

	;; DE here = remaining bytes
	;; if remaining bytes < sector size, skip to partial last sector load
	ld hl,FDC_SECTOR_SIZE
	or a
	sbc hl,de
	jr nc,fdc_ld_bytes_last_sector

	ld a,d				;; DE = remaining bytes / 512
	and 0xfe			;; discard 9 low bits of DE
	ld d,a
	ld e,0

	push de				;; save bytes to load for later

	ld a,(fdc_current_track)	;; track
	ld b,1				;; start sector
	ld c,d
	srl c				;; C = end sector (remaining bytes/512)

	push ix
	pop hl				;; HL = dest address

	call fdc_load_sectors

	pop de				;; DE = bytes loaded (saved above)
	add ix,de			;; update dest address

	pop hl				;; HL = previous remaining bytes
	push hl				;; expected by next section

	sbc hl,de			;; HL = current remaining bytes

	ld de,hl			;; DE = current remaining bytes

fdc_ld_bytes_last_sector:
	;; DE here contains the last remaining bytes in all cases
	ld a,d
	or e
	jr z,fdc_ld_bytes_inc_track	;; if remaining bytes == 0, skip to end

	pop hl				;; HL = previous remaining bytes
	ld b,h
	srl b
	inc b				;; B = last full sector + 1

	ld a,(fdc_current_track)	;; A = track

	push ix
	pop hl				;; HL = dest address

	call fdc_load_partial_sector

fdc_ld_bytes_inc_track:
	ld hl,fdc_current_track		;; inc current track
	inc (hl)

	scf				;; signal success
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
	;; check data direction is OK, panic if not
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
;; DE = address of command
;; comand data: 1 byte for length (=N), N command bytes
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
	jr nz,fdc_rec_res_loop		;; more bytes available

	scf				;; success
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; reads ID from FDC - "resets" everything
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
fdc_read_id:
	ld de,data_cmd_read_id

	call fdc_send_command
	jp nc,fdc_panic

	call fdc_receive_results
	jp nc,fdc_panic

	ld a,(fdc_status_data)		;; read_id returns ST0 first
	or a
	jr nz,fdc_read_id		;; wait until ST0 is 0 -> All OK no errors
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; load full sectors from track A to address HL
;; A = track number
;; B = initial sector ID
;; C = final sector ID
;; HL = destination address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_load_sectors:

	push ix
	push hl
	push bc

	push af
	call fdc_read_id
	pop af

	;; A = track number
	call fdc_seek_track

	push af
	call fdc_read_id
	pop af

	;; B,C = start,end sectors
	pop bc

	;; set up data struct
	ld ix,data_cmd_read_delete
	ld (ix+3),a			;; set track nr
	ld (ix+5),b			;; set start sector
	ld (ix+7),c			;; set end sector

	;; send read cmd
	ld de,data_cmd_read_delete	;; command address
	call fdc_send_command
	jp nc,fdc_panic

	;; start reading bytes into HL
	pop hl
	call fdc_read_bytes

	;; check results
	call fdc_receive_results	;; read returns ST0, ST1 and ST2
	jp nc,fdc_panic

	ld a,(fdc_status_data+1)	;; check ST1 register status
	jr nz,fdc_ld_end		;; if any bit is set, error

	scf				;; success

fdc_ld_end:
	pop ix
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; read sector bytes
;; HL = destination address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_read_bytes:

	call fdc_wait_ready_to_send

	ld bc,FDC_STATUS
	in a,(c)
	and 0x20			;; check if we are still in execution phase
	jr z,fdc_rd_end			;; if bit 5 = 0, finished

	ld bc,FDC_CONTROL		;; still in execution phase
	ini				;; read byte into (HL) and inc HL
	jr fdc_read_bytes		;; loop

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

	push ix

	push hl
	push de
	push bc

	push af
	call fdc_read_id
	pop af

	;; A = track number
	call fdc_seek_track

	push af
	call fdc_read_id
	pop af

	pop bc

	;; set up data struct
	ld ix,data_cmd_read_delete
	ld (ix+3),a			;; set track nr
	ld (ix+5),b			;; set start sector
	ld (ix+7),b			;; end sector is the same

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
;; DE = number of bytes to read from FDC
;; HL = destination address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

fdc_read_n_bytes:

	call fdc_wait_ready_to_send

	ld bc,FDC_STATUS
	in a,(c)
	and 0x20			;; check if we are still in execution phase
	jr z,fdc_rd_n_end		;; if bit 5 = 0, finished

	ld bc,FDC_CONTROL		;; still in execution phase

	ld a,d
	or e
	jr z,fdc_rd_n_no_store		;; if DE is 0 we have already
					;; read the required bytes

	ini				;; read byte into (HL) and inc HL
	dec de				;; dec byte counter
	jr fdc_read_n_bytes		;; loop next byte

fdc_rd_n_no_store:
	in a,(c)			;; read from FDC but don't store
	jr fdc_read_n_bytes		;; loop next byte

fdc_rd_n_end:
	ret

;; HASTA AQUI ESTA REVISADO

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; seek to track N
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

;; FDC result data buffer
fdc_status_data:
	ds 10		;; reserve 10 bytes

;; current track
fdc_current_track:
	db 0x01		;; first data track is #1 (the second one)
			;; track #0 is reserved for bootloader and loader
