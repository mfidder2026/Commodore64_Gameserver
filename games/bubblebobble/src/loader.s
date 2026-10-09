;===============================================================================
; bb-loader.s - Tape/Disk Loader Routines
;===============================================================================
; Address range: $4900-$4AFF (512 bytes)
;
; This module contains the game's tape/disk loading routines. It handles:
; - Timer-based data reading (turbo loader)
; - Checksumming and error detection
; - Display of loading status messages
; - IRQ handlers for data reception
;
; Called by the initialization routine (D_4800) to load additional game data.
;===============================================================================

;-------------------------------------------------------------------------------
; Main Loader Entry Point ($4900-$4939)
;-------------------------------------------------------------------------------
; Primary loader routine that sets up interrupts and begins loading process.
;
; Parameters:
;   A = Load identifier byte
;   X = Destination address low
;   Y = Destination address high
;-------------------------------------------------------------------------------

.segment "VIC_CHARSET_B"

D_4900:
        sei                                         ; $4900 - Disable interrupts
        sta     BSOUR                               ; $4901 - Store load ID
        stx     SYESSION                            ; $4903 - Store dest addr low
        sty     SHCNL                               ; $4905 - Store dest addr high
        sei                                         ; $4907 - Ensure interrupts off
        
        ; Setup NMI vector
        lda     #$C1                                ; $4908
        sta     NMINV                               ; $490A - NMI vector low
        lda     #$FE                                ; $490D
        sta     NMINV_HI                            ; $490F - NMI vector high
        
        ; Configure memory banking
        lda     R6510                               ; $4912 - Get CPU port
        and     #$DE                                ; $4914 - Clear bits 0 and 5
        sta     R6510                               ; $4916 - Update CPU port
        
        ; Setup CIA2 timer for loader timing
        lda     #$32                                ; $4918 - Timer A low byte
        sta     CIA2_TALO                           ; $491A
        lda     #$02                                ; $491D - Timer A high byte
        sta     CIA2_TAHI                           ; $491F
        lda     #$19                                ; $4922 - Start timer, continuous
        sta     CIA2_CRA                            ; $4924 - CIA2 control register A
        
        ; Setup CIA1 interrupts
        lda     #$7F                                ; $4927 - Disable all interrupts
        sta     CIA1_ICR                            ; $4929
        lda     #$91                                ; $492C - Enable timer A + FLAG
        sta     CIA1_ICR                            ; $492E
        
        ; Initialize counters
        ldy     #$00                                ; $4931
        sty     $B1                                 ; $4933 - Block counter
        sty     $B4                                 ; $4935 - Status flag
        
        jsr     D_498A                              ; $4937 - Display initial message

;-------------------------------------------------------------------------------
; Main Loading Loop ($493A-$4970)
;-------------------------------------------------------------------------------

D_493A:
        jsr     D_4A1F                              ; $493A - Wait for sync
        jsr     D_4A48                              ; $493D - Load header (7 bytes)
        lda     BAUDOF                              ; $4940 - Check block number
        cmp     $B1                                 ; $4942
        beq     L_494C                              ; $4944 - Correct block
        jsr     D_4998                              ; $4946 - Display error
        jmp     D_493A                              ; $4949 - Retry

L_494C:
        jsr     D_49B3                              ; $494C - Clear status area
        jsr     D_4A5C                              ; $494F - Load 256-byte block
        beq     L_495A                              ; $4952 - Checksum OK
        jsr     D_4998                              ; $4954 - Display error
        jmp     D_493A                              ; $4957 - Retry

L_495A:
        inc     $B1                                 ; $495A - Next block
        inc     VIC_BORDER                          ; $495C - Border flash during load
        dec     RODBS                               ; $495F - Decrement block counter
        lda     RIDBE                               ; $4961 - Load completion flag
        cmp     RODBS                               ; $4963 - Compare with counter
        bne     D_493A                              ; $4965 - Not done, continue
        
        jsr     D_4A9D                              ; $4967 - Cleanup and restore
        lda     RODBE                               ; $496A - Check for jump vector
        ora     IRQTMP                              ; $496C
        beq     L_4989                              ; $496E - No vector, return
        jmp     (RODBE)                             ; $4970 - Jump to loaded code

;-------------------------------------------------------------------------------
; Hex Digit Display ($4973-$4989)
;-------------------------------------------------------------------------------
; Converts a byte to two hex digits and displays them.
;
; Parameters:
;   A = Byte to display
;   Y = Screen position
;-------------------------------------------------------------------------------

D_4973:
        pha                                         ; $4973 - Save byte
        lsr                                         ; $4974 - Shift high nibble
        lsr                                         ; $4975
        lsr                                         ; $4976
        lsr                                         ; $4977
        jsr     D_497F                              ; $4978 - Display high nibble
        pla                                         ; $497B - Restore byte
        iny                                         ; $497C - Next position
        and     #$0F                                ; $497D - Isolate low nibble

D_497F:
        ora     #$30                                ; $497F - Convert to ASCII digit
        cmp     #$3A                                ; $4981 - Check if > 9
        bcc     L_4987                              ; $4983 - 0-9, done
        ; D_4985
        sbc     #$39                                ; $4985 - Convert A-F
L_4987:
        sta     (SYESSION),y                        ; $4987 - Display on screen
L_4989:
        rts                                         ; $4989

;-------------------------------------------------------------------------------
; Display Messages ($498A-$49B1)
;-------------------------------------------------------------------------------

D_498A:
        ldx     #$00                                ; $498A - Message offset
        ldy     #$50                                ; $498C - Screen position
        jsr     D_49C2                              ; $498E - Display message
        lda     $B1                                 ; $4991 - Get block number
        ldy     #$5A                                ; $4993 - Position for number
        jmp     D_4973                              ; $4995 - Display as hex

D_4998:
        ldx     #$12                                ; $4998 - Error message offset
        ldy     #$00                                ; $499A - Screen position
        jsr     D_49C2                              ; $499C - Display message
        lda     BAUDOF                              ; $499F - Expected block
        cmp     $B1                                 ; $49A1 - Current block
        bcc     D_498A                              ; $49A3 - Show status
        ldx     #$1A                                ; $49A5 - Different message
        ldy     #$50                                ; $49A7 - Screen position
        jsr     D_49C2                              ; $49A9 - Display message
        lda     $B1                                 ; $49AC - Block number
        ldy     #$5A                                ; $49AE - Position
        jmp     D_4973                              ; $49B0 - Display as hex

D_49B3:
        ldy     #$50                                ; $49B3 - Start position
        lda     #$20                                ; $49B5 - Space character
L_49B7:
        sta     (SYESSION),y                        ; $49B7 - Clear screen area
        iny                                         ; $49B9
        cpy     #$5C                                ; $49BA - End position
        bne     L_49B7                              ; $49BC - Continue
        ldx     #$0A                                ; $49BE - Message offset
        ldy     #$00                                ; $49C0 - Screen position

D_49C2:
        lda     D_4AC4,x                            ; $49C2 - Get message byte
        sta     (SYESSION),y                        ; $49C5 - Display it
        iny                                         ; $49C7
        inx                                         ; $49C8
        cmp     #$20                                ; $49C9 - Check for space (terminator)
        bne     D_49C2                              ; $49CB - Continue
        rts                                         ; $49CD

;-------------------------------------------------------------------------------
; IRQ Handlers ($49CE-$4A02)
;-------------------------------------------------------------------------------

irq_sync_handler:                                   ; $49CE
        sei
        jsr     D_4A03                              ; Check CIA status
        lda     ROESSION
        cmp     BSOUR
        bne     D_4A00
        lda     #$01
        sta     ROESSION
        lda     #<irq_data_handler                  ; IRQ vector low
        sta     CINV
        lda     #>irq_data_handler                  ; IRQ vector high
        sta     CINV_HI
        jmp     D_4A00

irq_data_handler:                                   ; $49E9 - Data reception IRQ handler
        sei
        jsr     D_4A03                              ; $49EA - Check status
        bcc     D_4A00                              ; $49ED - No data
        ldy     $72                                 ; $49EF - Buffer write pointer
        lda     ROESSION                            ; $49F1 - Get received byte
        sta     D_033C,y                            ; $49F3 - Store in buffer
        lda     #$01                                ; $49F6
        sta     ROESSION                            ; $49F8
        iny                                         ; $49FA
        tya                                         ; $49FB
        and     #$1F                                ; $49FC - Wrap at 32 bytes
        sta     $72                                 ; $49FE - Update pointer

D_4A00:
        jmp     D_FEBC                              ; $4A00 - Exit IRQ

;-------------------------------------------------------------------------------
; CIA Status Check ($4A03-$4A1E)
;-------------------------------------------------------------------------------

D_4A03:
        lda     CIA1_ICR                            ; $4A03 - Read interrupt status
        pha                                         ; $4A06 - Save it
        and     #$01                                ; $4A07 - Timer A interrupt?
        ora     $B4                                 ; $4A09 - Combine with flag
        sta     $B4                                 ; $4A0B - Update flag
        pla                                         ; $4A0D - Restore status
        clc                                         ; $4A0E - Clear carry
        and     #$10                                ; $4A0F - FLAG interrupt?
        beq     L_4A1E                              ; $4A11 - No, done
        lda     #$19                                ; $4A13 - Restart timer
        sta     CIA2_CRA                            ; $4A15
        lda     CIA2_ICR                            ; $4A18 - Read CIA2 status
        lsr                                         ; $4A1B - Shift bit into carry
        rol     ROESSION                            ; $4A1C - Rotate into byte
L_4A1E:
        rts                                         ; $4A1E

;-------------------------------------------------------------------------------
; Sync and Header Loading ($4A1F-$4A71)
;-------------------------------------------------------------------------------

D_4A1F:
        sei                                         ; $4A1F
        lda     #$00                                ; $4A20 - Initialize
        sta     $72                                 ; $4A22 - Buffer pointers
        sta     FBUFPT                              ; $4A24
        sta     ROESSION                            ; $4A26
        lda     #<irq_sync_handler                  ; IRQ vector low
        sta     CINV
        lda     #>irq_sync_handler                  ; IRQ vector high
        sta     CINV_HI
        cli                                         ; $4A32 - Enable interrupts

L_4A33:
        jsr     D_4A72                              ; $4A33 - Read byte
        cmp     BSOUR                               ; $4A36 - Check sync byte
        beq     L_4A33                              ; $4A38 - Keep waiting
        eor     #$FF                                ; $4A3A - Invert
        cmp     BSOUR                               ; $4A3C - Check inverted sync
        bne     D_4A1F                              ; $4A3E - Not synced, restart
        jsr     D_4A72                              ; $4A40 - Read next byte
        cmp     BSOUR                               ; $4A43 - Verify sync
        bne     D_4A1F                              ; $4A45 - Failed, restart
        rts                                         ; $4A47 - Synced!

D_4A48:
        ldy     #$00                                ; $4A48 - Byte counter
L_4A4A:
        jsr     D_4A72                              ; $4A4A - Read byte
        sta     a:BAUDOF,y                          ; $4A4D - Store in header buffer
        iny                                         ; $4A50
        cpy     #$07                                ; $4A51 - 7 bytes read?
        bne     L_4A4A                              ; $4A53 - Continue
        lda     BAUDOF                              ; $4A55 - Get block number
        ldy     #$0A                                ; $4A57 - Display position
        jmp     D_4973                              ; $4A59 - Display as hex

D_4A5C:
        ldy     #$00                                ; $4A5C - Byte counter
        sty     $B0                                 ; $4A5E - Checksum
L_4A60:
        jsr     D_4A72                              ; $4A60 - Read byte
        sta     ($AA),y                             ; $4A63 - Store in dest
        eor     $B0                                 ; $4A65 - Update checksum (XOR)
        sta     $B0                                 ; $4A67
        iny                                         ; $4A69
        bne     L_4A60                              ; $4A6A - 256 bytes
        jsr     D_4A72                              ; $4A6C - Read checksum byte
        cmp     $B0                                 ; $4A6F - Compare
        rts                                         ; $4A71 - Return with Z flag

;-------------------------------------------------------------------------------
; Read Byte from Buffer ($4A72-$4A99)
;-------------------------------------------------------------------------------

D_4A72:
        sty     $B5                                 ; $4A72 - Save Y register
L_4A74:
        lda     ISTOP                               ; $4A74 - Check stop key
        cmp     #$B2                                ; $4A77
        beq     L_4A86                              ; $4A79 - Stopped
        lda     $B4                                 ; $4A7B - Check status
        beq     L_4A86                              ; $4A7D
        lda     #$00                                ; $4A7F - Clear status
        sta     $B4                                 ; $4A81
        jsr     D_4A9A                              ; $4A83 - Call handler
L_4A86:
        ldx     FBUFPT                              ; $4A86 - Read pointer
        cpx     $72                                 ; $4A88 - Compare write pointer
        beq     L_4A74                              ; $4A8A - Buffer empty, wait
        lda     D_033C,x                            ; $4A8C - Get byte from buffer
        pha                                         ; $4A8F - Save it
        inx                                         ; $4A90 - Advance pointer
        txa                                         ; $4A91
        and     #$1F                                ; $4A92 - Wrap at 32
        sta     FBUFPT                              ; $4A94 - Update pointer
        pla                                         ; $4A96 - Restore byte
        ldy     $B5                                 ; $4A97 - Restore Y
        rts                                         ; $4A99

D_4A9A:
        jmp     ($0311)                             ; $4A9A - Indirect jump

;-------------------------------------------------------------------------------
; Loader Cleanup and Restore ($4A9D-$4AC3)
;-------------------------------------------------------------------------------

D_4A9D:
        lda     VIC_CTRL1                           ; $4A9D - Get VIC control
        ora     #$10                                ; $4AA0 - Enable screen
        sta     VIC_CTRL1                           ; $4AA2
        lda     R6510                               ; $4AA5 - Get CPU port
        ora     #$20                                ; $4AA7 - Set bit 5 (KERNAL ROM)
        sta     $C0                                 ; $4AA9 - Side effect (unused)
        sta     R6510                               ; $4AAB - Restore CPU port
        lda     #$7F                                ; $4AAD - Disable interrupts
        sta     CIA1_ICR                            ; $4AAF
        lda     #$81                                ; $4AB2 - Enable timer A
        sta     CIA1_ICR                            ; $4AB4
        sei                                         ; $4AB7
        lda     #$31                                ; $4AB8 - Restore IRQ vector
        sta     CINV                                ; $4ABA
        lda     #$EA                                ; $4ABD
        sta     CINV_HI                             ; $4ABF
        cli                                         ; $4AC2
        rts                                         ; $4AC3

;-------------------------------------------------------------------------------
; Message Data ($4AC4-$4AFF)
;-------------------------------------------------------------------------------
; Screen code strings displayed during loading.
; Strings are terminated by space ($20).
;-------------------------------------------------------------------------------

D_4AC4:
        .byte   $13,$05,$01,$12,$03                 ; $4AC4 - "SEARC"
        .byte   $08,$09,$0E,$07,$20                 ; $4AC9 - "HING "
        .byte   $0C,$0F,$01,$04,$09                 ; $4ACE - "LOADI"
        .byte   $0E,$07,$20,$02,$0C                 ; $4AD3 - "NG BL"
        .byte   $0F,$03,$0B,$60,$3F                 ; $4AD8 - "OCK`?"
        .byte   $20,$12,$05,$17,$09                 ; $4ADD - " REWI"
        .byte   $0E,$04,$60,$14,$0F                 ; $4AE2 - "ND`TO"
        .byte   $20,$FF,$FF,$00,$28                 ; $4AE7 - " " + padding data
        .byte   $FF,$FF,$00,$00,$FF                 ; $4AEC - Padding data
        .byte   $FF,$00,$00,$FF,$FF                 ; $4AF1 - Padding data
        .byte   $00,$00,$FF,$FF,$00                 ; $4AF6 - Padding data
        .byte   $00,$FF,$FF,$00,$00                 ; $4AFB - Final padding data

;-------------------------------------------------------------------------------
; Charset B Overwrite Zone ($4B00-$4BFF)
;-------------------------------------------------------------------------------
; This 256-byte region completes the 1024-byte VIC charset B area ($4800-$4BFF).
; The charset backup loop in game-init-early.s overwrites this entire region
; with character bitmap data from charset A ($4300-$43FF).
;
; The initial byte values here are the original game binary contents, preserved
; for hash verification. At runtime they are immediately overwritten.
;
; The work_ram_init label is referenced by init-routines.s as the destination
; for tape loader memory copies (using >work_ram_init for the high byte).
;-------------------------------------------------------------------------------
work_ram_init:
        .byte   $0c, $0f, $01, $04, $09, $0e, $07, $20, $0f, $f2, $34, $33, $c0, $02, $cf, $f7
        .byte   $ef, $f2, $c0, $07, $e0, $02, $cf, $f7, $ef, $f2, $c0, $07, $e0, $02, $cf, $f7
        .byte   $ef, $f2, $c0, $07, $c0, $02, $cf, $f7, $8f, $f2, $c0, $07, $80, $02, $c0, $07
        .byte   $00, $02, $c0, $00, $00, $02, $c0, $00, $00, $02, $c0, $07, $00, $02, $c0, $07
        .byte   $00, $02, $c0, $00, $00, $02, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00
        .byte   $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $00, $00, $40, $00
        .byte   $00, $00, $00, $00, $3f, $ff, $30, $80, $3f, $ff, $30, $84, $30, $00, $3f, $ff
        .byte   $30, $84, $30, $04, $3f, $ff, $30, $84, $30, $04, $3f, $ff, $30, $84, $30, $84
        .byte   $3f, $ff, $30, $84, $3f, $ff, $00, $00, $00, $00, $00, $00, $c0, $00, $00, $00
        .byte   $ca, $00, $60, $50, $d5, $00, $d0, $a8, $d1, $0f, $c0, $88, $ca, $3f, $e0, $50
        .byte   $c4, $7f, $f0, $20, $c0, $7f, $f8, $00, $c0, $ff, $f8, $00, $c0, $ff, $dc, $00
        .byte   $c0, $ff, $bc, $00, $c0, $af, $be, $00, $e0, $af, $bf, $04, $c0, $af, $de, $00
        .byte   $c0, $af, $e7, $00, $f0, $7f, $f8, $0c, $c0, $0e, $70, $00, $c0, $0e, $70, $00
        .byte   $f8, $0e, $70, $1c, $c0, $0e, $70, $00, $c0, $3e, $7c, $00, $fc, $fe, $7f, $3c
        .byte   $c0, $00, $00, $00, $c0, $00, $00, $00, $ff, $ff, $ff, $fc, $e0, $40, $40, $d4
        .byte   $ef, $5f, $5e, $d4, $ef, $df, $5f, $d4, $e0, $5f, $40, $d4, $ff, $5f, $7e, $d4

;===============================================================================
; End of bb-loader.s
;===============================================================================
