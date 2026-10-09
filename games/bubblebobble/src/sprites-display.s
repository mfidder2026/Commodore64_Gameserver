; ============================================================================
; BUBBLE BOBBLE - Sprite Display and Animation System
; ============================================================================
; File: bb-sprites-display.s
; Address Range: $E3A7-$E553 (430 bytes)
;
; This module handles:
; - Sprite animation updates
; - High score display
; - Screen buffer copying
; - Player sprite positioning
; - Sprite pointer setup
; ============================================================================

; Forward references to external routines defined in bb-master.s
; D_3FB0, D_AC09, D_AC0A already defined in bb-master.s

; ============================================================================
; UPDATE_SPRITE_ANIMATIONS ($E3A7)
; ============================================================================
; Main sprite animation update routine
; Called from main game loop to update sprite animations and display
;
; This routine updates high score display by:
; 1. Reading score digits from $0400-$0405
; 2. Converting to hex digits and displaying them
; 3. Comparing and updating high score if needed
; ============================================================================
; D_E3A7 now defined as label below (update_sprite_animations)
.if .defined(COMPRESS_LEVELS) .and (.defined(BBLAN) .or .defined(ORIGLAYOUT))
.segment "CODE_LEVEL_RENDERER"
        .res    23, $EA                 ; BB-LAN: keep PRG_HIGH where the original has it
.endif
.segment "CODE_SPRITES_DISPLAY"

update_sprite_animations:
        lda     $30                     ; Get screen page
        eor     #ARYTAB_SCREEN_TOGGLE   ; Toggle between pages
        sta     $41                     ; Store high byte of pointer
        lda     #$E9                    ; Low byte for first display
        sta     $40
        ldx     #$00
        jsr     display_score_digits
        inc     $41                     ; Move to next screen area
        inc     $41
        lda     #$01
        sta     $40
        jsr     display_score_digits
        lda     #$04
        sta     $43
        lda     #$00                    ; Pointer to score data
        ldy     #$00
        jsr     check_high_score
        lda     #$03
        ldy     #$01
        jsr     check_high_score
        inc     $41
        lda     #$41
        sta     $40

; ============================================================================
; DISPLAY_SCORE_DIGITS ($E3D9)
; ============================================================================
; Converts 6 hex digits from $0400+X to screen characters
; Input: X = offset into $0400
;        $40/$41 = screen destination pointer
; ============================================================================
display_score_digits:
        ldy     #$00
        sty     $42
L_E3DD:
        lda     D_0400,x                ; Get score byte
        lsr     a                       ; Shift high nibble down
        lsr     a
        lsr     a
        lsr     a
        jsr     D_3FB0                  ; Display high digit
        lda     D_0400,x
        and     #$0F                    ; Mask low nibble
        jsr     D_3FB0                  ; Display low digit
        inx
        cpy     #$06                    ; Done 6 digits?
        bne     L_E3DD
        rts

; ============================================================================
; CHECK_HIGH_SCORE ($E3F5)
; ============================================================================
; Compares current score with high score and updates if higher
; Input: A = pointer low byte
;        Y = offset for player (0=P1, 1=P2)
;        $43 = score comparison mode
; ============================================================================
check_high_score:
        sta     $42                     ; Store score pointer
        sty     $3C                     ; Store player offset
        ldy     #$00
L_E3FB:
        lda     ($42),y                 ; Get score byte
        cmp     D_0406,y                ; Compare with stored high score
        beq     L_E405                  ; Equal, check next byte
        bcs     L_E40B                  ; Current > stored, update
        rts                             ; Current < stored, no update
L_E405:
        iny
        cpy     #$03                    ; Compare 3 bytes
        bne     L_E3FB
        nop
L_E40B:
        ldy     #$02                    ; Copy new high score
L_E40D:
        lda     ($42),y
        sta     D_0406,y
        dey
        bpl     L_E40D
        ldy     $3C
        lda     D_0409,y                ; Get player name/data
        sta     D_040B
        rts

; ============================================================================
; Unused/debug code fragment
; ============================================================================
        .byte   $D0, $04, $24, $42, $10, $04, $C6, $42
        .byte   $91, $40, $C8, $60

; ============================================================================
; DISPLAY_TEXT_STRING ($E42A)
; ============================================================================
; Displays a text string to screen with special control codes
; Input: X/Y = pointer to text string (stored in $0D/$0E)
;
; Control codes:
;   $00      = End of string
;   $01-$0F  = Direct character code (stored in $0F)
;   $10-$1E  = Character code - $20 (ASCII-like)
;   $1F xx yy= Set screen position (xx=offset, yy=page)
;   $20+     = Character code - $20
; ============================================================================
; D_E42A now defined as label below (display_text_string)
display_text_string:
        stx     $0D                     ; Store pointer low
        sty     $0E                     ; Store pointer high
        ldy     #$00
L_E430:
        lda     ($0D),y                 ; Get next character
        cmp     #$10
        bcs     L_E43A                  ; >= $10, process normal char
        sta     $0F                     ; < $10, store directly
        bcc     L_E491                  ; Advance to next char
L_E43A:
        bne     L_E43D                  ; Non-zero, continue
        rts                             ; $00 = end of string
L_E43D:
        cmp     #$1F
        bne     L_E46F                  ; Not $1F, normal character
        
        ; $1F = Set cursor position command
L_E441:
        iny
        lda     ($0D),y                 ; Get X offset
        tax
        iny
        lda     ($0D),y                 ; Get page number
        stx     L_E451                  ; Self-modifying: store offset
        asl     a                       ; Page * 2
        tax
        lda     D_AC09,x                ; Get screen address low
        adc     #$0C                    ; Immediate byte from self-mod code
L_E451  = * - 1                         ; Label points to ADC operand
        sta     L_E473                  ; Store in three locations
        sta     L_E476
        sta     L_E47B
        lda     D_AC0A,x                ; Get screen address high
        adc     #>__VIC_SCREEN_A__          ; Add screen A page base
        sta     L_E474
        adc     #ARYTAB_SCREEN_TOGGLE   ; Advance to screen B page
        sta     L_E477
        adc     #(>$D800 - >__VIC_SCREEN_B__) ; Advance to color RAM ($D800) page
        sta     L_E47C
        bcc     L_E491
        
        ; Normal character output (>= $20)
L_E46F:
        sec
        sbc     #$20                    ; Convert ASCII to screen code
        sta     D_51D3                  ; STA (self-modified address)
L_E473  = * - 2                         ; Points to low byte of address ($D3)
L_E474  = * - 1                         ; Points to high byte of address ($51)
        sta     D_55D3                  ; STA (self-modified address)
L_E476  = * - 2                         ; Points to low byte of address ($D3)
L_E477  = * - 1                         ; Points to high byte of address ($55)
        lda     $0F                     ; Get stored character/color
        sta     D_D9D3                  ; STA (self-modified address)
L_E47B  = * - 2                         ; Points to low byte of address ($D3)
L_E47C  = * - 1                         ; Points to high byte of address ($D9)
        inc     L_E473                  ; Advance screen pointers
        inc     L_E476
        inc     L_E47B
        bne     L_E491
        inc     L_E474                  ; Increment high bytes if needed
        inc     L_E477
        inc     L_E47C
L_E491:
        iny                             ; Next character
        bne     L_E430

; ============================================================================
; WAIT_ONE_FRAME ($E494)
; ============================================================================
; Waits for exactly one frame by monitoring the frame counter
; The IRQ handler increments $08 (ENDCHR) every frame
; This is the fundamental timing routine used throughout the game
; ============================================================================
; D_E494 now defined as label below (wait_one_frame)
wait_one_frame:
.ifdef BBLAN
        jmp     vframe                  ; BB-LAN: advance one logical frame
        BB_PATCH_END wait_one_frame, 7
.else
        lda     $08                     ; Get current frame counter
L_E496:
        cmp     $08                     ; Compare with current value
        beq     L_E496                  ; Loop until it changes
        rts
.endif

; ============================================================================
; COPY_SCREEN_BUFFERS ($E49B)
; ============================================================================
; Copies 4 pages of screen data from $5000-$5400 to both:
; - Display buffer at $8B00-$8E00
; - Working buffer at $5400-$5700
; Used for double-buffering screen updates
; ============================================================================
; D_E49B now defined as label below (copy_screen_buffers)
copy_screen_buffers:
        ldx     #$00
L_E49D:
        lda     D_5000,x                ; Screen data page 0
        sta     D_8B00,x                ; Copy to display
        sta     D_5400,x                ; Copy to working
        lda     D_5100,x                ; Screen data page 1
        sta     D_8C00,x
        sta     D_5500,x
        lda     D_5200,x                ; Screen data page 2
        sta     D_8D00,x
        sta     D_5600,x
        lda     D_5300,x                ; Screen data page 3
        sta     D_8E00,x
        sta     D_5700,x
        inx
        bne     L_E49D
        rts

; ============================================================================
; COPY_CHARSET_DATA ($E4C5)
; ============================================================================
; Copies 16 bytes of character set data from $40D0 to $48D0
; Then sets up screen with two specific characters ($1A, $1B)
; ============================================================================
copy_charset_data:
        ldx     #$0F
L_E4C7:
        lda     D_40D0,x
        sta     CHARSETB_D0,x
        dex
        bpl     L_E4C7
        ldy     #$1A                    ; Character code
        sty     D_5400                  ; Store at screen position
        iny
        sty     D_5401                  ; Store next character
        rts

; ============================================================================
; SETUP_PLAYER_SPRITES ($E4DA)
; ============================================================================
; Sets up sprite display mode and calls positioning routine
; Enables sprite rendering by setting up JSR at $E539
; ============================================================================
setup_player_sprites:
        lda     #$A9                    ; LDA immediate opcode
        sta     L_E539                  ; Modify code to enable sprites
        
; ============================================================================
; UPDATE_PLAYER_SPRITE_POSITIONS ($E4DF)
; ============================================================================
; Updates VIC-II sprite registers with player positions
; Handles both players (up to 4 sprites each: 2x2 multicolor sprites)
; ============================================================================
update_player_sprite_positions:
        jsr     wait_one_frame          ; Wait one frame
        ldx     #$10                    ; Clear sprite registers
        lda     #$00
L_E4E6:
        sta     VIC_SPR0_X,x            ; Clear sprite X/Y positions
        dex
        bpl     L_E4E6
        ldx     #$01                    ; Player index (1=P1, 0=P2)
        
L_E4EE:
        ldy     D_0200,x                ; Get sprite index for player
        lda     $B2,x                   ; Check player state
        beq     L_E527                  ; Player inactive, skip
        
        ; Position player sprites (4 sprites = 2x2 multicolor)
        lda     $BA,x                   ; Player X position
        sec
        sbc     #$0A                    ; Adjust for sprite offset
        sta     VIC_SPR0_X,y            ; Sprite 0 X
        sta     VIC_SPR2_X,y            ; Sprite 2 X
        adc     #$17                    ; Offset for right sprites
        sta     VIC_SPR1_X,y            ; Sprite 1 X
        sta     VIC_SPR3_X,y            ; Sprite 3 X
        bcc     L_E513
        
        ; Handle X MSB (for X > 255)
        lda     VIC_SPR_XMSB            ; VIC sprite X MSB register
        ora     L_E552,x                ; OR with sprite mask
        sta     VIC_SPR_XMSB
        
L_E513:
        lda     $C2,x                   ; Player Y position
        sec
        sbc     #$08                    ; Adjust for sprite offset
        sta     VIC_SPR0_Y,y            ; Sprite 0 Y
        sta     VIC_SPR1_Y,y            ; Sprite 1 Y
        clc
        adc     #$15                    ; Offset for bottom sprites
        sta     VIC_SPR2_Y,y            ; Sprite 2 Y
        sta     VIC_SPR3_Y,y            ; Sprite 3 Y
        
L_E527:
        dex                             ; Next player
        bpl     L_E4EE
        
        ; Set sprite colors
        ldx     #$03
L_E52C:
        lda     #$05                    ; Green
        sta     VIC_SPR0_COL,x          ; Sprites 0-3 color
        lda     #$03                    ; Cyan
        sta     VIC_SPR4_COL,x          ; Sprites 4-7 color
        dex
        bpl     L_E52C
        
; ============================================================================
; Sprite display control point
; Modified by code at $E4DA - changes RTS to JSR
; ============================================================================
L_E539:
        rts                             ; May be modified to LDA #$xx

        ; Sprite pointer base for bubble-dragon-in-bubble sprites (sprite 3 of 8).
        ; set_sprite_pointers steps -1/+4 to fill sprites 0-7 with pointers $D1-$D8.
        ; Value = (sprite_data_7440 + 3*64 - VIC_bank) / 64, computed as hibyte(X*4).
        .byte   >(sprite_data_7440 + $C0 - __VIC_BANK_BASE__ + sprite_data_7440 + $C0 - __VIC_BANK_BASE__ + sprite_data_7440 + $C0 - __VIC_BANK_BASE__ + sprite_data_7440 + $C0 - __VIC_BANK_BASE__)

; ============================================================================
; SET_SPRITE_POINTERS ($E53B)
; ============================================================================
; Sets sprite pointers in screen memory
; Input: A = base sprite pointer value
; Sets up 8 sprites (4 at $53F8-$53FB, 4 at $57F8-$57FB)
; ============================================================================
set_sprite_pointers:
        ldx     #$03
L_E53D:
        sta     D_53F8,x                ; Sprite pointers screen 1
        sta     D_57F8,x                ; Sprite pointers screen 2
        clc
        adc     #$04                    ; Advance 4 sprite frames
        sta     D_53FC,x                ; Next set of pointers
        sta     D_57FC,x
        sbc     #$04                    ; Restore base value
        dex
        bpl     L_E53D
        rts

; ============================================================================
; Data table for sprite X MSB masks
; ============================================================================
L_E552:
        .byte   $0A, $A0

; ============================================================================
; End of bb-sprites-display.s
; ============================================================================
