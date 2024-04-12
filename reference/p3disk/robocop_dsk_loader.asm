define uPD755A_control $3f
define uPD755A_status $2f
define sector_size_512b $02
define sector_size_1024b $03


	org $fc80
l_fc80:
                ld sp, l_fc80                   ; R3/5/2/3

	ld a, sector_size_512b
	ld (command_read_delete.SECTOR_SIZE), a   ; N en datos read_delete (512 bytes) $feb5
	call check_protection           ; l_fd4b

	ld hl, l_fec1                   ; PTR a buffer (tablas para loads posteriores)
	ld d, $00                       ; track number
	ld c, $09                       ; sector number
	call load_sector                ; datos cargados desde el sector 9 pista 0
                                                ; $01,$03,$01,$07
                                                ; $02,$04,$03,$10
                                                ; $03,$07,$04,$0C
                                                ; $04,$0A,$01,$04
                                                ; $05,$0A,$05,$10
                                                ; $06,$0E,$01,$10
                                                ; $07,$11,$02,$10
                                                ; $08,$14,$03,$0E
	ld a, sector_size_1024b 
	ld (command_read_delete.SECTOR_SIZE), a  ; N en datos read_delete (1024 bytes) $feb5
	call set_page3_rom48k           ; R3/5/2/3 l_fd3d

	ld a, $01                       ; bloque a cargar (pantalla) INDEX DE LA TABLA
	ld hl, $8000                    ; buffer
	call load_from_table            ; (TRACK $1, SECTOR $7 TO TRACK $4, SECTOR $2 7KB PAGE 2) l_fd81

	ld hl, $8000
	ld de, $4000
	ld bc, $1b00
	ldir

	ld a, $08
	ld hl, $7ffe
	call load_from_table            ; (TRACK $14, SECTOR 3 TO TRACK $17, SECTOR 1 14KB PAGE 2) l_fd81 
	ld a, $03
	ld hl, $c000
	call load_from_table            ; (TRACK $7, SECTOR 4 TO TRACK $9, SECTOR 5 12KB PAGE 3) l_fd81
	call set_special_mem_0_1_2_3    ; 0/1/2/3 l_fd35
	ld a, $02
	ld hl, $4000
	call load_from_table            ; (TRACK $4, SECTOR 3 TO TRACK $7, SECTOR 3 16KB PAGE 1) l_fd81
	call set_special_mem_4_7_6_3    ; 4/7/6/3 l_fd31
	ld a, $05
	ld hl, $0000
	call load_from_table            ; (TRACK $A, SECTOR 5 TO TRACK $D, SECTOR 5 16KB PAGE 4) l_fd81
	ld a, $07
	ld hl, $4000
	call load_from_table            ; (TRACK $11, SECTOR 2 TO TRACK $14, SECTOR 2 16KB PAGE 7) l_fd81
	ld a, $06
	ld hl, $8000
	call load_from_table            ; (TRACK $E, SECTOR 1 TO TRACK $11, SECTOR 1 16KB PAGE 6) l_fd81
	call set_page3_rom48k           ; R3/5/2/3 l_fd3d
	ld hl, $5800
	ld de, $5801
	ld bc, $02ff
	ld (hl), l
	ldir                            ; borra attrs (pantalla a negro)
	ld a, $04
	ld hl, $4000
	call load_from_table            ; (TRACK $A, SECTOR A TO TRACK $A, SECTOR 4 4KB PAGE 5) l_fd81
;=====================================================
	ld d, $10
	ld hl, $8119                    ; VECTOR ENTRY!!!!!!!!!!!!
	exx
	ld sp, $6978
	ld hl, a_trasladar              ; l_fd14
	ld de, $5f00
	ld bc, $001d                    ; 29 bytes
	ldir
	jp $5f00
;=====================================================                
;l_fd14
a_trasladar                                     ; entra con R3/5/2/3
                ld bc, $1ffd
	ld a, $04                       ; 0000 0100 (BIT H ROM ON/MOTOR OFF)
	out (c), a                      ;

	ld hl, $4000
	ld de, $f000                    ; $f000 to $ffff
	ld bc, $1000                    ; 4096 bytes
	ldir

	ld hl, $2758
	exx
	ld bc, $7ffd
	ld a, d                         ; D=$10 (BIT L ROM ON/PAGE 0)
	out (c), a                      ; establece R3/5/2/0                      
	jp (hl)
;====================================================
;l_fd31
set_special_mem_4_7_6_3
                ld a, $0f                       ; 0000 1111 (MOTOR ON/SPECIAL MEMORY (1,1) PAGES 4,7,6,3)
	jr l_fd37
;l_fd35
set_special_mem_0_1_2_3
                ld a, $09                       ; 0000 1001 (MOTOR ON/SPECIAL MEMORY (0,0) PAGES 0,1,2,3)
l_fd37:         ld bc, $1ffd
	out (c), a
	ret
;l_fd3d
set_page3_rom48k
                ld a, $13                       ; 0001 0011 (page 3 BL rom ON)
	ld bc, $7ffd
	out (c), a
	ld a, $0c                       ; 0000 1100 (motor ON BH rom ON -ROM 48k-)
	ld b, $1f
	out (c), a
	ret

;===============================================================

;l_fd4b
check_protection
                ld b, $03                       ; 3 reitentos
;l_fd4d
2               push bc
	ld hl, $8000                    ; PTR a buffer
	push hl
	ld d, $00                       ; track number
	ld c, $02                       ; sector number
	call load_sector

	ld hl, $8500                    ; PTR a buffer
	push hl
	ld d, $00                       ; track number
	ld c, $02                       ; sector number
	call load_sector

	ld bc, $0200                    ; 512 bytes (sector lenght)
	pop hl                          ; PTR a segundo buffer
	pop de                          ; PTR a primer buffer
;l_fd69
1               ld a, (de)
	xor (hl)
	jr nz, salida
	inc hl
	inc de
	dec bc
	ld a, b
	or c
	jr nz,1b
	pop bc
	djnz 2b
; SI LLEGA AQUI, DISCO PIRATON ==> BORRA TODA LA MEMORIA.....
	ld hl, salida
;l_fd7a
3               ld (hl), $23
	inc hl
	jr 3b
;l_fd7f
salida
                pop bc
	ret
;===============================================================
; A= codigo datos a cargar
;               structure table:
;                               +0: codigo
;                               +1: unit, head and track
;                               +2: sector init
;                               +3: sector final
; $01,$03,$01,$07
; $02,$04,$03,$10
; $03,$07,$04,$0C
; $04,$0A,$01,$04  <====== a>b !!!!!
; $05,$0A,$05,$10
; $06,$0E,$01,$10
; $07,$11,$02,$10
; $08,$14,$03,$0E
; HL= PTR A DATOS
;===============================================================

;l_fd81
load_from_table
                ld ix, l_fec1
;	ld c, a
;l_fd86
;1               ld a, (ix+$00)                                  ; cojo codigo
;	cp c                                            ; es el que queremos?
1               cp (ix+0)
	jr z,2f                                         ; Z=>SI, a cargar.       l_fd96
	inc ix
	inc ix
	inc ix
	inc ix                                          ; siguiente structura
	jr 1b                                           ; l_fd86
;l_fd96
2               ld d, (ix+$01)                                  ; unit, head and track (0 usually)
	ld e, (ix+$02)                                  ; sector init
	ld b, (ix+$03)                                  ; sector final (included) num sectores????????
;l_fd9f
otro
                ld a, $06                                       ; max num sector
	sub e                                           ; A= sectores a cargar de la pista
	cp b                                            ; sectores a cargar de la pista < sectorers totales?
	jr c,3f                                         ; carry=>si, salto a cargar toda la pista desde el sector actual  l_fdac
; no, solo me quedan un num de sectores de la pista
	ld a, e                                         ; sector inicial (normalmente E=1 desde JR OTRO)
	add a, b                                        ; sector init+num sectores que quedan por cargar
	dec a                                           ; -1
	ld c, a                                         ; sector final to load (included)
	jp set_data_and_load                            ; l_fdc9

;l_fdac
3               ld c, $05                                       ; sector final=5
	push bc
	push af
	push hl
	push de
	call set_data_and_load                          ; D= TRACK             l_fdc9
                                                                ; E= SECTOR INIT
                                                                ; C= SECTOR END
                                                                ; HL= PUNTERO A BUFFER
	pop de
	pop hl
	pop af
	pop bc
	ld e, a                                         ; E= sectores a cargar de la pista
	ld a, b                                         ; num sectores a cargar
	sub e                                           ; A= sectores que quedan por cargar
	ld b, a                                         ; guardo para ss loop
	sla e                                           ; x512
	sla e                                           ; x1024 al ir al BH (long -KBs- de datos cargados)
	ld a, h                                         ; BH PTR a datos
	add a, e                                        ; BH+long=nuevo BH de buffer
	ld h, a                                         ; guardo
	ld e, $01                                       ; sector init=1
	inc d                                           ; inc TRACK
	jr otro                                         ; l_fd9f

;l_fdc9
set_data_and_load
                ld a, d
	ld (command_seek_track.TRACK), a                ; unit and head l_fea9
	ld (command_read_delete.TRACK), a               ; track number l_feb2
	ld (ptr_data+1), hl                               ; $FE0A
	ld a, e
	ld (command_read_delete.SECTOR_I), a            ; num sector init l_feb4
	ld a, c
	ld (command_read_delete.SECTOR_END), a          ; num sector final (included) $feb6
	jr load_data_calls                              ; l_fdee

;===============================================================

;===============================================================
;l_fddd
; D=trak
; C=sector
; HL=ptr a buffer datos
;===============================================================

load_sector
                ld a, d
	ld (command_seek_track.TRACK), a                       ; unit and head (SEEK TRACK) l_fea9
	ld (command_read_delete.TRACK), a                      ; track number (READ) l_feb2
	ld (ptr_data+1), hl                                    ; PTR a buffer
	ld a, c
	ld (command_read_delete.SECTOR_I), a                   ; num sector init (READ) l_feb4
	ld (command_read_delete.SECTOR_END), a                 ; num sector final (included) (READ) $feb6

;l_fdee
load_data_calls
                ld de, command_read_id                          ;$feac
	call exit_con_fdd_result

	ld a, (fdd_status_data)
	or a
	jr nz,load_data_calls                           ; l_fdee

	ld de, command_seek_track                       ; l_fea6
	call l_fe10

	ld de, command_read_id                          ;$feac
	call exit_con_fdd_result

	ld de, command_read_delete                      ;l_feaf
;$fe09
ptr_data	ld hl, $0000                                    ; PTR buffer datos
	call exit_con_check_read_task
	ret

;===============================================================

l_fe10:         call exit_con_r_status_main
l_fe13:         ld de, command_sense_interrupt_status           ;l_feaa
	call exit_con_fdd_result
	ld hl, fdd_status_data
	bit 5, (hl)
	jr z, l_fe13
	ret

;===============================================================

exit_con_r_status_main:
                ld bc, r_status_main
	jr run_command

;===============================================================

exit_con_fdd_result:
                ld bc, fdd_result                               ; ptr a la rutina con la que se sale
	ld hl, fdd_status_data                          ; buffer para datos resultados
	jr run_command

exit_con_check_read_task
                ld bc, check_read_task
run_command:    ld (aqui+1), bc                                 ; $fe48
	ld a, (de)                                      ; cojo long del command
	ld b, a                                         ; B= num items
	inc de
;l_fe38
1               push bc                                         ; guardo num items
	ld a, (de)                                      ; dato del command
	inc de
	call send_byte_command                          ;l_fe7f
	pop bc                                          ; recupero num items
	djnz 1b                                         ; l_fe38
	ld bc, $2ffd                                    ; uPD755A status main 
	ld de, $2010                                    ; mascara de comprobacion
;$fe47
aqui	jp check_read_task                              ; esto se automodifica
;==============================================================
; LEE LOS DATOS DEL DISCO
;==============================================================
lee_sector_byte
                ld b, uPD755A_control                           ; uPD755A control
	ini                                             ; leo dato del sector de disco
	ld b, uPD755A_status                            ; uPD755A status main
check_read_task
                in a, (c)                                       ; leo status main
	jp p, check_read_task                           ; si BIT 7 OFF=ERROR. Wait
	and d                                           ; D=$20 (0010 0000)
	jr nz,lee_sector_byte                           ; NZ=> esta aun en fase ejecucion, salto a leer byte
;==============================================================
	ld hl, fdd_status_data                          ; buffer para datos resultados
                                                                ; FASE DE RESULTADOS
fdd_result:     in a, (c)                                       ; lee status  main
	cp $c0                                          ; bits 7 y 6 a 1?
	jr c, fdd_result                                ; C=>no, reitero lectura
	ld b, uPD755A_control                           ; uPD755A CONTROL
	ini                                             ; cojo registro de estatus y lo guardo en (HL)
	ld b, uPD755A_status                            ; uPD755A status main
;delay
	ld a, $05                                       ; \
1               dec a                                           ; | delay
	jr nz,1b                                        ; /

	in a, (c)                                       ; leo status main
	and e                                           ; e=$10 (0001 0000)
	jr nz, fdd_result                               ; NZ=> command in progress
	ld a, (fdd_status_data+1)                       ; l_feba
	and $04                                         ; bit 2 status register 2 
	ret nz                                          ; NZ=> ERROR (no encontrado)
	scf                                             ; C=> NO ERROR
	ret

;===============================================================

r_status_main:  in a, (c)                                       ; leo status main
	jp p, r_status_main                             ; BIT 7 OFF=>ERROR
	ret

;l_fe7f
send_byte_command
                ld bc, $2ffd                                    ; status main port
	push af                                         ; salvo dato del command
;l_fe83
1               in a, (c)                                       ; leo status main
	add a, a                                        ; bit 7 al carry|bit 6 al bit 7
	jr nc, 1b                                       ; NC=> bit 7 OFF=> data register no ready l_fe83
	add a, a                                        ; bit 7 al carry
	jr nc,2f                                        ; NC=> BIT 7 OFF (CPU to FDD direction) ALL OK l_fe8d
	pop af                                          ; recupero dato del command
	ret
;l_fe8d
2               pop af                                          ; recupero dato del command
	ld b, uPD755A_control
	out (c), a                                      ; envio dato del command al FDC
	ld b, uPD755A_status
	ld a, $05
;l_fe96
3               dec a                                           ; \
	nop                                             ; | delay
	jr nz,3b                                        ; /             l_fe96
	ret

; B= numero de repeticiones
delay_b
	ld hl, $0000
1               dec hl
	ld a, h
	or l
	jr nz, 1b
	djnz 1b
	ret


STRUCT read_command
LONG	BYTE $09
COMMAND_ID	BYTE $4C
UNIT	BYTE $00
TRACK	BYTE $00
HEAD	BYTE $00
SECTOR_I	BYTE $03
SECTOR_SIZE	BYTE $02
SECTOR_END	BYTE $08
GPL	BYTE $2A
DTL	BYTE $FF
	ENDS

STRUCT seek_command
LONG	BYTE $03
COMMAND_ID	BYTE $0f
UNIT	BYTE $00
TRACK	BYTE $00
	ENDS

command_read_delete read_command
command_seek_track seek_command
;l_fea6
command_seek_track
                db $03,$0F,$00,$00
;l_feaa
command_sense_interrupt_status
                db $01,$08
 ;l_feac
command_read_id
                db $02,$4A,$00
;l_feaf
command_read_delete
                db $09 ,$4C ,$00 ,$00 ,$00 ,$01 ,$02 ,$09 ,$2A ,$FF             ; <======$feb8
;l_feb9
fdd_status_data
                db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00


;=============== CODIGO BASURA =================

;                add hl, bc
;	ld c, h
;	nop
;l_feb2:         nop
;	nop
;l_feb4:         ld bc, $0902
;	ld hl, ($00ff)
;l_feba:         nop
;	nop
;	nop
;	nop
;	nop
;	nop
;	nop

;===============================================


; BUFFER PARA LOS DATOS DE CARGA

l_fec1: nop
