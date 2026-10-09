;===============================================================================
; game-init-early.s - Early Game Initialization and Title Screen Data
;===============================================================================
; Address range: $4460-$47FF (928 bytes)
;
; This module contains early initialization code that was originally embedded
; in charset.bin. It performs critical setup before the main initialization:
;
; KEY FUNCTIONALITY:
; 1. Random number generation (using VIC raster and CIA timer)
; 2. Copies game data from $4000-$43FF to $4800-$4BFF (4 pages, 1024 bytes)
; 3. Initializes lookup tables at $0200-$03FF:
;    - $0200-$02FF: Multiplication by 8 table (0, 8, 16, 24, ...)
;    - $0300-$03FF: Division by 32 table (0x00 repeated 32 times,
;                   0x01 repeated 32 times, 0x02 repeated 32 times, etc.)
; 4. Sets up memory banking and interrupt configuration
; 5. Handles title screen display and fire button detection
; 6. Checks for cheat code key sequence
; 7. Transfers control to the main game loop
;
; LOOKUP TABLES CREATED:
; $0200-$02FF contains values [0, 8, 16, 24, 32, ...] for fast *8 multiplication
; $0300-$03FF contains high bytes for 16-bit multiplication result
;===============================================================================

;-------------------------------------------------------------------------------
; D_4460: Early Initialization Entry Point
;-------------------------------------------------------------------------------
; Called from init-routines.s (via jmp D_4460).
; Sets up random seed, copies game data, and initializes lookup tables.
;-------------------------------------------------------------------------------

.segment "TMP_INIT_CODE"

D_4460:
        sei                                         ; Disable interrupts

L_4461:
        lda     VIC_RASTER                          ; Read VIC raster line
        sta     $26                                 ; Store in zero page (random seed)
        asl     a                                   ; Multiply by 2
        eor     $DC04                               ; XOR with CIA timer A low byte
        sta     $27                                 ; Store result in $27
        beq     L_4461                              ; If zero, try again (avoid seed=0)

        ;-----------------------------------------------------------------------
        ; Stack Setup
        ;-----------------------------------------------------------------------
        ldx     #$FF                                ; Set stack pointer to top
        txs                                         ; Transfer X to stack pointer

        ;-----------------------------------------------------------------------
        ; Backup charset: $4000-$43FF -> $4800-$4BFF (1024 bytes = 128 characters)
        ; This preserves the charset while allowing the region to be used as work RAM
        ;-----------------------------------------------------------------------
        inx                                         ; X = 0 (byte index)

L_4472:
        lda     charset,x                           ; Copy page 1: $4000 -> $4800
        sta     __VIC_CHARSET_B__,x
        lda     charset + $100,x                    ; Copy page 2: $4100 -> $4900
        sta     __VIC_CHARSET_B__ + $100,x
        lda     charset + $200,x                    ; Copy page 3: $4200 -> $4A00
        sta     __VIC_CHARSET_B__ + $200,x
        lda     charset + $300,x                    ; Copy page 4: $4300 -> $4B00
        sta     __VIC_CHARSET_B__ + $300,x

        ;-----------------------------------------------------------------------
        ; Clear Lookup Tables: $0200-$03FF
        ;-----------------------------------------------------------------------
        lda     #$00
        sta     D_0200,x                            ; Clear $0200-$02FF
        sta     D_0300,x                            ; Clear $0300-$03FF

        inx
        bne     L_4472                              ; Loop for all 256 bytes

        ;-----------------------------------------------------------------------
        ; Build Lookup Tables at $0200-$03FF
        ;-----------------------------------------------------------------------
        ; Creates a 16-bit multiplication table where:
        ;   result = $0300[index] * 256 + $0200[index] = index * 8

        inx                                         ; X = 0 (wrapped around)
        clc
        ldy     #$00                                ; Y = high byte accumulator

L_4499:
        adc     #$08                                ; Add 8 to accumulator
        sta     D_0200,x                            ; Store low byte in table
        bcc     L_44A2                              ; If no carry, skip high byte update
        iny                                         ; Increment high byte
        clc

L_44A2:
        pha                                         ; Save low byte accumulator
        tya                                         ; Transfer high byte to A
        sta     D_0300,x                            ; Store high byte in table
        tay                                         ; Restore Y from A
        pla                                         ; Restore low byte accumulator

        inx
        bne     L_4499                              ; Loop until X wraps to 0

        ;-----------------------------------------------------------------------
        ; Zero Page Initialization
        ;-----------------------------------------------------------------------
        lda     #$00
        ldx     #$02                                ; Start at $02 (preserve CPU port)

L_44B0:
        sta     $00,x                               ; Clear zero page
        inx
        bne     L_44B0                              ; Loop until X wraps

        ;-----------------------------------------------------------------------
        ; Memory Banking Configuration
        ;-----------------------------------------------------------------------
        lda     #$35                                ; Memory config: I/O + KERNAL
        sta     R6510                               ; Set processor port

        lda     #<__CIA2_PRA_GAME__                      ; CIA2 Port A: VIC bank + serial
        sta     CIA2_PRA                            ; Configure VIC bank and serial

        lda     #<__VIC_MEMPTR_INIT__                    ; VIC memory: screen at charset B, charset at A
        sta     VIC_MEMPTR                          ; Set character/screen memory

        ;-----------------------------------------------------------------------
        ; VIC Control Register Setup
        ;-----------------------------------------------------------------------
        lda     #$7F                                ; Clear bit 7
        and     VIC_CTRL1                           ; Read VIC control 1
        sta     VIC_CTRL1                           ; Clear raster MSB

        ;-----------------------------------------------------------------------
        ; Interrupt Configuration
        ;-----------------------------------------------------------------------
        sta     CIA1_ICR                            ; Disable CIA1 interrupts
        lda     CIA1_ICR                            ; Read/acknowledge CIA1 interrupts

        lda     #$01
        sta     VIC_IRQ                             ; Clear raster interrupt flag
        sta     VIC_ICTRL                           ; Enable raster interrupt

        lda     #$FB                                ; Raster line $FB (251)
        sta     VIC_RASTER                          ; Set raster compare line

        ;-----------------------------------------------------------------------
        ; Hardware IRQ Vector Setup ($FFFE-$FFFF in banked RAM)
        ;-----------------------------------------------------------------------
        lda     #<irq_frame_update                  ; IRQ handler address low byte
        sta     IRQ_VEC                             ; Set hardware IRQ vector low
        lda     #>irq_frame_update                  ; IRQ handler address high byte
        sta     IRQ_VEC_HI                          ; Set hardware IRQ vector high
                                                    ; IRQ vector now points to $06AB

        ;-----------------------------------------------------------------------
        ; VIC Display Configuration
        ;-----------------------------------------------------------------------
        lda     #$00
        sta     VIC_SPR_PRI                         ; Sprite priority register

        lda     #$D8                                ; VIC control 2 value
        sta     VIC_CTRL2                           ; Set horizontal scroll/width

        lda     #>__VIC_SCREEN_B__
        sta     $30                                 ; Screen pointer high byte
        lda     #>__VIC_CHARSET_B__
        sta     $2F                                 ; Screen pointer low byte

        ;-----------------------------------------------------------------------
        ; NMI Vector Setup
        ;-----------------------------------------------------------------------
        lda     #<nmi_handler                       ; NMI handler address low byte
        sta     NMI_VEC                             ; Set NMI vector low
        lda     #>nmi_handler                       ; NMI handler address high byte
        sta     NMI_VEC_HI                          ; Set NMI vector high
                                                    ; NMI vector now points to $072D

        ;-----------------------------------------------------------------------
        ; Game Variables Initialization
        ;-----------------------------------------------------------------------
        lda     #$00
        sta     $37
        sta     D_5AFF

        jsr     sound_init                              ; Sound initialization routine
        cli                                         ; Enable interrupts
        jsr     clear_screen                         ; Screen initialization routine

        lda     #$05
        sta     D_8548                              ; Game state variable
        lda     #$03
        sta     D_8548+1                            ; Game state variable

        ;-----------------------------------------------------------------------
        ; Copy Data from Internal Tables
        ;-----------------------------------------------------------------------
        ldx     #$07                                ; Copy 8 bytes

L_451E:
        lda     D_47B5,x                            ; Load from table 1
        sta     D_8570,x                            ; Store destination 1
        lda     D_47BD,x                            ; Load from table 2
        sta     D_8598,x                            ; Store destination 2
        lda     D_47C5,x                            ; Load from table 3
        sta     D_85C0,x                            ; Store destination 3
        dex
        bpl     L_451E                              ; Loop while positive

        ldx     #$0C                                ; Copy 13 bytes

L_4535:
        lda     D_47CD,x                            ; Load from table 4
        sec
        sbc     #$20                                ; Convert screen code
        sta     $6B,x                               ; Store in zero page
        dex
        bpl     L_4535                              ; Loop while positive

        ;-----------------------------------------------------------------------
        ; VIC and Sprite Configuration
        ;-----------------------------------------------------------------------
        stx     $D01C                               ; Sprite multicolor register
        ldx     #$01
        stx     $D026                               ; Sprite 1 color
        inx
        stx     $D025                               ; Sprite 0 color

        lda     #$01
        sta     $1C                                 ; Game variable
        sta     $1E                                 ; Game variable

        ;-----------------------------------------------------------------------
        ; Display Setup
        ;-----------------------------------------------------------------------
        ldx     #<D_462D                            ; Title screen data low
        ldy     #>D_462D                            ; Title screen data high

L_4556:
        jsr     display_text_string                  ; Call routine with params
        ldx     #<credits_page_2                    ; Credits text low
        ldy     #>credits_page_2                    ; Credits text high
        jsr     display_text_string                  ; Call routine with params

        ldy     #(song_title_screen - music_song_table)
        jsr     D_05AD                              ; Start title music

        ;-----------------------------------------------------------------------
        ; Title Screen Wait Loop - Check for Fire Button or Cheat Code
        ;-----------------------------------------------------------------------
L_4565:
.ifdef BBLAN
        jsr     bb_boot_title                       ; BB-LAN: skipped in a session
.elseif .defined(DETTEST)
        jmp     L_45A1                              ; test: no fire needed
.else
        jsr     wait_one_frame                              ; Display title screen
.endif

        lda     CIA1_PRA                            ; Read joystick port 2
        and     #$10                                ; Test fire button bit
        beq     L_4590                              ; Fire pressed, continue

        lda     CIA1_PRB                            ; Read joystick port 1
        and     #$10                                ; Test fire button bit
        beq     L_4590                              ; Fire pressed, continue

        lda     #$FD                                ; Select keyboard row
        sta     CIA1_PRA
        lda     CIA1_PRB                            ; Read keyboard
        cmp     #$DF                                ; Check for specific key
        beq     L_45A7                              ; Key pressed, check cheat code

L_4582:
        lda     #$7F                                ; Select different keyboard row
        sta     CIA1_PRA
        ora     #$80
        sta     CIA1_PRB
        lda     $A4                                 ; Check game state
        bne     L_4565                              ; Loop back if not zero

L_4590:
        jsr     wait_one_frame                              ; Update display

        lda     CIA1_PRA                            ; Check fire button again
        and     #$10
        beq     L_4590                              ; Wait for release

        lda     CIA1_PRB                            ; Check other fire button
        and     #$10
        beq     L_4590                              ; Wait for release

L_45A1:
        jsr     sound_init                              ; Sound routine
        jmp     D_F005                              ; Jump to main game loop

;-------------------------------------------------------------------------------
; L_45A7: Cheat Code Key Sequence Detection
;-------------------------------------------------------------------------------
; Checks for a specific multi-key sequence to enable cheat mode.
; Returns to L_4582 if sequence is incorrect.
;-------------------------------------------------------------------------------

L_45A7:
        lda     #$F7                                ; Keyboard row for key 1
        sta     CIA1_PRA
        lda     CIA1_PRB
        cmp     #$BF                                ; Check for specific key
        bne     L_4582                              ; Wrong key, abort

        lda     #$DF                                ; Keyboard row for key 2
        sta     CIA1_PRA
        lda     CIA1_PRB
        cmp     #$FD                                ; Check for specific key
        bne     L_4582                              ; Wrong key, abort

        lda     #$EF                                ; Keyboard row for key 3
        sta     CIA1_PRA
        lda     CIA1_PRB
        cmp     #$BF                                ; Check for specific key
        bne     L_4582                              ; Wrong key, abort

        lda     #$FB                                ; Keyboard row for key 4
        sta     CIA1_PRA
        lda     CIA1_PRB
        cmp     #$FD                                ; Check for specific key
        bne     L_4582                              ; Wrong key, abort

        lda     #$7F                                ; Keyboard row for key 5
        sta     CIA1_PRA
        lda     CIA1_PRB
        cmp     #$DF                                ; Check for specific key
        bne     L_4582                              ; Wrong key, abort

        ;-----------------------------------------------------------------------
        ; Cheat Mode Activated - Modify Color Table
        ;-----------------------------------------------------------------------
        lda     #$02
        sta     VIC_BORDER                          ; Change border color (visual feedback)

        lda     #<enemy_spawns                      ; Pointer low byte
        sta     $40
        lda     #>enemy_spawns                      ; Pointer high byte
        sta     $41

        ldx     #$63                                ; Counter = 99

L_45F2:
        ldy     #$00

L_45F4:
        lda     ($40),y                             ; Load byte
        beq     L_4619                              ; If zero, end of block
        sta     $42                                 ; Save byte
        and     #$07                                ; Get lower 3 bits
        pha
        lda     $42
        and     #$F8                                ; Get upper 5 bits
        sta     $42
        pla
        bne     L_460A
        lda     #$01                                ; Replace 0 with 1
        bne     L_4610

L_460A:
        cmp     #$06
        bne     L_4610
        lda     #$05                                ; Replace 6 with 5

L_4610:
        ora     $42                                 ; Combine with upper bits
        sta     ($40),y                             ; Store modified byte
        iny
        iny
        iny                                         ; Advance by 3
        bne     L_45F4                              ; Continue if not wrapped

L_4619:
        iny
        tya
        clc
        adc     $40                                 ; Advance pointer
        sta     $40
        bcc     L_4624
        inc     $41

L_4624:
        dex                                         ; Decrement counter
        bne     L_45F2                              ; Continue if more blocks
        stx     VIC_BORDER                          ; Reset border color
        jmp     L_45A1                              ; Return to normal game start

;===============================================================================
; Title Screen Data and Tables
;===============================================================================
; Data from $462D to $47FF contains title screen graphics and text

D_462D:
        .byte   $1F,$00,$00,$0B                     ; Control codes

;-------------------------------------------------------------------------------
; Title Screen Logo Data
;-------------------------------------------------------------------------------
        .byte   $80,$81,$82,$40,$40,$40,$80,$81
        .byte   $82,$80,$81,$82,$93,$40,$40,$97
        .byte   $98,$99,$40,$40,$40,$40,$80,$81
        .byte   $82,$40,$40,$40,$80,$81,$82,$80
        .byte   $81,$82,$93,$40,$40,$97,$98,$99
        .byte   $83,$84,$85,$8C,$40,$8D,$83,$84
        .byte   $85,$83,$84,$85,$8E,$40,$40,$9A
        .byte   $9B,$9C,$40,$40,$40,$40,$83,$84
        .byte   $85,$A3,$A4,$A5,$83,$84,$85,$83
        .byte   $84,$85,$8E,$40,$40,$9A,$9B,$9C
        .byte   $86,$87,$88,$8E,$40,$8F,$86,$87
        .byte   $88,$86,$87,$88,$8E,$40,$40,$9D
        .byte   $9E,$9F,$40,$40,$40,$40,$86,$87
        .byte   $88,$A6,$A7,$A8,$86,$87,$88,$86
        .byte   $87,$88,$8E,$40,$40,$9D,$9E,$9F
        .byte   $89,$8A,$8B,$90,$91,$92,$89,$8A
        .byte   $8B,$89,$8A,$8B,$94,$95,$96,$A0
        .byte   $A1,$A2,$40,$40,$40,$40,$89,$8A
        .byte   $8B,$A9,$AA,$AB,$89,$8A,$8B,$89
        .byte   $8A,$8B,$94,$95,$96,$A0,$A1,$A2
        .byte   $1F,$07,$07,$05

;-------------------------------------------------------------------------------
; Credits Text Data
;-------------------------------------------------------------------------------
D_46B1:
        .byte   $57,$52,$49,$54,$54,$45,$4E,$40     ; "WRITTEN@"
        .byte   $42,$59,$40,$40,$53,$54,$45,$50     ; "BY@@STEP"
        .byte   $48,$45,$4E,$40,$52,$55,$44,$44     ; "HEN@RUDD"
        .byte   $59,$5B,$10                         ; "Y[."
credits_page_2:
        .byte   $1F,$05,$09,$07                     ; Set cursor + row/col

        .byte   $47,$52,$41,$50,$48,$49,$43,$53     ; "GRAPHICS"
        .byte   $40,$42,$59,$40,$40,$41,$4E,$44     ; "@BY@@AND"
        .byte   $52,$45,$57,$40,$54,$48,$52,$45     ; "REW@THRE"
        .byte   $4C,$46,$41,$4C,$4C,$5B,$1F,$08     ; "LFALL[.."
        .byte   $0C,$04                             ; ".."

        .byte   $43,$4F,$4D,$4D,$4F,$44,$4F,$52     ; "COMMODOR"
        .byte   $45,$40,$43,$4F,$4E,$56,$45,$52     ; "E@CONVER"
        .byte   $53,$49,$4F,$4E,$40,$40,$42,$59     ; "SION@@BY"
        .byte   $1F,$0B,$0D                         ; "..."

        .byte   $53,$4F,$46,$54,$57,$41,$52,$45     ; "SOFTWARE"
        .byte   $40,$43,$52,$45,$41,$54,$49,$4F     ; "@CREATIO"
        .byte   $4E,$53,$1F,$09,$0F,$02             ; "NS....."

        .byte   $50,$52,$4F,$44,$55,$43,$45,$44     ; "PRODUCED"
        .byte   $40,$42,$59,$40,$40,$46,$49,$52     ; "@BY@@FIR"
        .byte   $45,$42,$49,$52,$44,$5B,$1F,$0A     ; "EBIRD[.."
        .byte   $12,$05                             ; ".."

        .byte   $4C,$49,$43,$45,$4E,$53,$45,$44     ; "LICENSED"
        .byte   $40,$42,$59,$40,$46,$49,$52,$45     ; "@BY@FIRE"
        .byte   $42,$49,$52,$44,$1F,$08,$13         ; "BIRD..."

        .byte   $46,$52,$4F,$4D,$40,$40,$54,$41     ; "FROM@@TA"
        .byte   $49,$54,$4F,$40,$45,$4C,$45,$43     ; "ITO@ELEC"
        .byte   $54,$52,$4F,$4E,$49,$43,$53,$5B     ; "TRONICS["
        .byte   $1F,$04,$17,$01                     ; "...."

        .byte   $5C,$40,$50,$52,$45,$53,$53,$40     ; "\@PRESS@"
        .byte   $46,$49,$52,$45,$40,$46,$4F,$52     ; "FIRE@FOR"
        .byte   $40,$42,$55,$42,$42,$4C,$45,$40     ; "@BUBBLE@"
        .byte   $42,$4F,$42,$42,$4C,$45,$40,$5C     ; "BOBBLE@\"
        .byte   $10                                 ; Control code

;-------------------------------------------------------------------------------
; Data Tables Referenced by Initialization Code
;-------------------------------------------------------------------------------
D_47B5:
        .byte   $05,$03,$0A,$0A,$0A,$0A,$0A,$0A

D_47BD:
        .byte   <__SPRITE_PTR_BASE__, <__SPRITE_PTR_BASE__, $00,$00,$00,$00,$00,$00

D_47C5:
        .byte   $FF,$FF,$00,$00,$00,$00,$00,$00

D_47CD:
        .byte   $47,$41,$4D,$45,$40,$40,$4F,$56     ; "GAME@@OV"
        .byte   $45,$52,$41,$4C,$4C                 ; "ERALL"

;-------------------------------------------------------------------------------
; Additional Data (GAME OVER display data)
;-------------------------------------------------------------------------------
        .byte   $0A,$0A,$0A,$60,$60,$00             ; Control/timing data
        .byte   $00,$00,$00,$00,$00,$FF,$FF,$00     ; Pattern data
        .byte   $00,$00,$00,$00,$00,$47,$41,$4D     ; "GAM"
        .byte   $45,$40,$40,$4F,$56,$45,$52,$41     ; "E@@OVERA"
        .byte   $4C,$4C,$00,$20,$20,$00,$00,$00     ; "LL" + padding

;===============================================================================
; End of game-init-early.s ($4460-$47FF, 928 bytes total)
;===============================================================================
