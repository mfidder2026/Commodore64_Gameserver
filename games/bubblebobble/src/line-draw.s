; ============================================================================
; BUBBLE BOBBLE - Line Drawing and Graphics Routines
; ============================================================================
; File: bb-line-draw.s
; Address Range: $E554-$E751 (510 bytes)
;
; This module contains:
; - Bresenham line drawing algorithm
; - Animated sprite drawing to screen buffers
; - Screen copying and masking operations
; - Color RAM clearing
; ============================================================================

; ============================================================================
; DRAW_ANIMATED_SPRITE ($E554)
; ============================================================================
; Draws animated sprites for both players, using line-based rendering
; Clears sprite buffers at $8B00-$8E00 and draws player trails/effects
;
; Uses Bresenham algorithm to draw lines between previous and current positions
; Creates motion blur / animation trail effect for player sprites
; ============================================================================
.segment "CODE_LINE_DRAW"

draw_animated_sprite:
        lda     #$60                    ; RTS opcode
        sta     L_E539                  ; Disable sprite display during draw
        lda     #$00
        tax
        sta     $39                     ; Clear buffer index
        
; Clear 4 pages of sprite buffer memory
L_E55E:
        sta     D_8B00,x                ; Clear buffer page 0
        sta     D_8C00,x                ; Clear buffer page 1
        sta     D_8D00,x                ; Clear buffer page 2
        sta     D_8E00,x                ; Clear buffer page 3
        dex
        bne     L_E55E
        
        ldx     #$01                    ; Start with player 1
        
; Loop through both players
L_E56F:
        lda     $BA,x                   ; Get player X position
        sta     $23                     ; Store start X
        lda     $C2,x                   ; Get player Y position
        sta     $24                     ; Store start Y
        lda     $B2,x                   ; Check player state
        beq     L_E591                  ; Skip if inactive
        
        lda     #$01
        sta     $B2,x                   ; Set player state to active
        stx     $38                     ; Save player index
        
        ; Set up line drawing parameters from table
        lda     L_E5C0,x                ; Get buffer pointer low
        pha                             ; Save on stack
        lda     L_E5C2,x                ; Get buffer offset
        tax                             ; Move to X
        pla                             ; Restore buffer pointer
        ldy     #$DD                    ; Y increment/mode
        jsr     draw_bresenham_line     ; Draw line
        ldx     $38                     ; Restore player index
        
L_E591:
        dex                             ; Next player (1 -> 0)
        bpl     L_E56F
        
; Display all drawn sprites from buffer
L_E594:
        ldy     $39                     ; Get buffer index
        lda     D_8B00,y                ; Check buffer 0
        ora     D_8D00,y                ; OR with buffer 2
        beq     L_E5BD                  ; Done if both empty
        
        ; Update player 1 position if buffer 0 has data
        lda     D_8B00,y
        beq     L_E5AA
        sta     $BA                     ; Update P1 X
        lda     D_8C00,y
        sta     $C2                     ; Update P1 Y
        
L_E5AA:
        ; Update player 2 position if buffer 2 has data
        lda     D_8D00,y
        beq     L_E5B6
        sta     $BB                     ; Update P2 X
        lda     D_8E00,y
        sta     $C3                     ; Update P2 Y
        
L_E5B6:
        jsr     update_player_sprite_positions  ; Update VIC-II sprite regs
        inc     $39                     ; Next buffer entry
        bne     L_E594
        
L_E5BD:
        sta     $20                     ; Clear mode flag
        rts

; ============================================================================
; Data tables for line drawing
; ============================================================================
L_E5C0:
        .byte   $8B, $8D                ; Buffer pointers for P1/P2
L_E5C2:
        .byte   $2C, $EC                ; Buffer offsets

; ============================================================================
; DRAW_BRESENHAM_LINE ($E5C4)
; ============================================================================
; Bresenham line drawing algorithm
; Draws a line from ($23,$24) to ($04,$05)
; Writes coordinates to buffers pointed to by ($02/$04) and A/Y
;
; Input:
;   $23/$24 = Start X/Y position
;   $04/$05 = End X/Y position (target)
;   A = Buffer pointer (high byte)
;   X = X offset modifier
;   Y = Y offset modifier
; ============================================================================
draw_bresenham_line:
L_E5C4:
        stx     $04                     ; Store target X
        sty     $05                     ; Store target Y
        tay                             ; Buffer pointer to Y
        ldx     #$FF
        stx     $40                     ; X direction flag (-1)
        stx     $41                     ; Y direction flag (-1)
        ldx     #$01
        
; Calculate deltas and set direction flags
L_E5D1:
        lda     $23,x                   ; Get start coordinate
        sec
        sbc     $04,x                   ; Subtract end coordinate
        bcs     L_E5E0                  ; Positive delta
        
        ; Negative delta - negate and set direction
        inc     $40,x                   ; Change direction (+1)
        inc     $40,x
        eor     #$FF                    ; Two's complement
        adc     #$01
        
L_E5E0:
        sta     $42,x                   ; Store absolute delta
        dex
        bpl     L_E5D1                  ; Do for both X and Y
        
        ; Set up Bresenham algorithm parameters
        sty     $03                     ; Save buffer high byte
        iny
        sty     $05                     ; Increment for next buffer
        inx                             ; X = 0
        ldy     #$00
        sty     $02                     ; Clear buffer pointer low
        sty     $04
        
        lda     $42                     ; Get delta X
        cmp     $43                     ; Compare with delta Y
        bcs     L_E606                  ; Delta X >= delta Y
        
        ; Delta Y > delta X (steep line)
        sta     $44                     ; Store minor delta
        lda     $40                     ; Get X direction
        sta     $11                     ; Store X step
        lda     $41                     ; Get Y direction
        sta     $12                     ; Store Y step
        stx     $40                     ; Clear X accumulator
        jmp     L_E61D                  ; Continue algorithm
        
L_E606:
        ora     $43                     ; Check if both deltas are zero
        bne     L_E60B
        rts                             ; No line to draw
        
L_E60B:
        ; Delta X >= delta Y (gentle line)
        lda     $43                     ; Get delta Y
        sta     $44                     ; Store minor delta
        lda     $42                     ; Get delta X
        sta     $43                     ; Store major delta
        lda     $40                     ; Get X direction
        sta     $11                     ; Store major step
        lda     $41                     ; Get Y direction
        sta     $12                     ; Store minor step
        stx     $41                     ; Clear Y accumulator
        
; Main Bresenham loop
L_E61D:
        lda     $43                     ; Major delta
        sta     $45                     ; Copy for threshold
        lsr     a                       ; Divide by 2 (initial error)
        
L_E622:
        clc
        adc     $44                     ; Add minor delta (error term)
        bcs     L_E62B                  ; Error >= threshold
        cmp     $45                     ; Compare with threshold
        bcc     L_E638                  ; Error < threshold
        
L_E62B:
        ; Step in minor direction
        sbc     $45                     ; Subtract threshold
        sta     $42                     ; Store new error
        lda     $11                     ; Get major step
        sta     $3C
        lda     $12                     ; Get minor step
        jmp     L_E640                  ; Apply step
        
L_E638:
        ; Step only in major direction
        sta     $42                     ; Store error
        lda     $40                     ; Get major step
        sta     $3C
        lda     $41                     ; Get minor step (0)
        
L_E640:
        clc
        adc     $24                     ; Update Y position
        sta     $24
        sta     ($04),y                 ; Write to buffer
        lda     $3C
        clc
        adc     $23                     ; Update X position
        sta     $23
        sta     ($02),y                 ; Write to buffer
        iny                             ; Next point
        lda     $42                     ; Get error term
        dec     $43                     ; Decrement counter
        bne     L_E622                  ; Continue line
        rts

; ============================================================================
; COPY_AND_MASK_GRAPHICS ($E658)
; ============================================================================
; Copies graphics data with masking operations
; Used for compositing sprite graphics with background
;
; Copies data from $4087/$408F/$4097/$409F to $0107-$011F
; Then performs masked blitting using lookup tables
; ============================================================================
copy_and_mask_graphics:
        lda     #<(D_4200 + $50)        ; Graphics work buffer pointer low
        sta     $02
        lda     #>(D_4200 + $50)        ; Graphics work buffer pointer high
        sta     $03
        ldx     #$08
        
; Copy 32 bytes of graphics data
L_E662:
        lda     D_4087,x                ; Source data 1
        sta     D_0107,x                ; Destination 1
        lda     D_408F,x                ; Source data 2
        sta     D_010F,x                ; Destination 2
        lda     D_4097,x                ; Source data 3
        sta     D_0117,x                ; Destination 3
        lda     D_409F,x                ; Source data 4
        sta     D_011F,x                ; Destination 4
        dex
        bne     L_E662
        
; Process 5 rows of graphics with masking
L_E67D:
        ldy     #$1F                    ; 32 bytes per row
        
; Copy row to screen
L_E67F:
        lda     D_0108,y                ; Get graphics byte
        sta     ($02),y                 ; Write to screen
        dey
        bpl     L_E67F
        
        ; Calculate pointer table offset
        txa                             ; Row index
        asl     a                       ; * 2
        asl     a                       ; * 4
        adc     #$18                    ; Add base offset
        tay
        
        ; Load mask/data pointers from tables
        lda     D_AA54,y                ; OR mask low
        sta     $40
        lda     D_AA8E,y                ; OR mask high
        sta     $41
        lda     D_AAC8,y                ; AND mask low
        sta     $42
        lda     D_AB02,y                ; AND mask high
        sta     $43
        
        ldy     #$1F
        
; Apply masking operation: (src AND mask1) OR mask2 AND mask3
L_E6A3:
        lda     ($02),y                 ; Get screen byte
        and     ($42),y                 ; AND with mask
        ora     ($40),y                 ; OR with pattern
        and     D_A988,y                ; AND with final mask
        sta     ($02),y                 ; Write back
        dey
        bpl     L_E6A3
        
        ; Advance to next row (80 bytes = 40 cols * 2)
        lda     $02
        clc
        adc     #$20                    ; +32 bytes
        sta     $02
        bcc     L_E6BC
        inc     $03                     ; Increment page
        
L_E6BC:
        inx                             ; Next row
        cpx     #$05                    ; Done 5 rows?
        bne     L_E67D
        
        ; Copy result to final location
        ldx     #$00
L_E6C3:
        lda     D_4200,x                ; Source
        sta     CHARSETB_200,x           ; Destination (charset B work buffer)
        inx
        bne     L_E6C3
        rts

; ============================================================================
; DRAW_PLAYER_DIGITS ($E6CD)
; ============================================================================
; Draws player score/life digits on screen
; Calls digit drawing routine for both players
; ============================================================================
draw_player_digits:
        ldx     #$00                    ; Player 1
        lda     #$51                    ; Screen page
        ldy     #$90                    ; Position offset
        jsr     draw_digit_sprite
        
        ldx     #$01                    ; Player 2
        lda     #$51                    ; Screen page
        ldy     #$AE                    ; Position offset
        
; ============================================================================
; DRAW_DIGIT_SPRITE ($E6DC)
; ============================================================================
; Draws digit sprites for a player
; Input: A = screen page, X = player index, Y = position offset
; ============================================================================
draw_digit_sprite:
        sta     $41                     ; Screen pointer high
        ora     #ARYTAB_SCREEN_TOGGLE   ; Advance to screen B page
        sta     $43                     ; Screen B pointer high
        and     #$03                    ; Mask to page
        clc
        adc     #>__SCREEN_BACKUP__     ; Convert to backup buffer page
        sta     $3D                     ; Buffer pointer high
        sty     $40                     ; Screen pointer low
        sty     $42                     ; Color pointer low
        sty     $3C                     ; Buffer pointer low
        lda     $54,x                   ; Get digit pattern
        sta     $44                     ; Store pattern
        ldx     #$05                    ; 6 digits
        
; Draw each digit character (2x2 tiles)
L_E6F5:
        lda     L_E73A,x                ; Get character code
        lsr     $44                     ; Shift pattern bit
        bcc     L_E724                  ; Skip if bit clear
        
        ; Draw 2x2 character block
        ldy     #$00
        sta     ($40),y                 ; Top-left
        sta     ($42),y                 ; Color top-left
        sta     ($3C),y                 ; Buffer top-left
        
        ldy     #$28                    ; +40 bytes (next row)
        clc
        adc     #$01                    ; Next character
        sta     ($40),y                 ; Bottom-left
        sta     ($42),y                 ; Color bottom-left
        sta     ($3C),y                 ; Buffer bottom-left
        
        ldy     #$01                    ; +1 byte (next column)
        adc     #$01                    ; Next character
        sta     ($40),y                 ; Top-right
        sta     ($42),y                 ; Color top-right
        sta     ($3C),y                 ; Buffer top-right
        
        ldy     #$29                    ; +41 bytes (next row, next col)
        adc     #$01                    ; Next character
        sta     ($40),y                 ; Bottom-right
        sta     ($42),y                 ; Color bottom-right
        sta     ($3C),y                 ; Buffer bottom-right
        clc
        
L_E724:
        ; Advance to next digit position (80 bytes = 2 rows)
        lda     $40
        adc     #$50                    ; +80 bytes
        sta     $40
        sta     $42
        sta     $3C
        bcc     L_E736
        inc     $41                     ; Increment page
        inc     $43
        inc     $3D
        
L_E736:
        dex
        bpl     L_E6F5
        rts

; ============================================================================
; Digit character codes (2x2 tiles each)
; ============================================================================
L_E73A:
        .byte   $5A, $56, $4A, $52, $4E, $4A

; ============================================================================
; FILL_COLOR_RAM ($E740)
; ============================================================================
; Fills entire color RAM area ($D800-$DBFF)
; Input: A = color value to fill
; Called from multiple locations to set color RAM
; ============================================================================
; fill_color_ram - fills color RAM with value in A
fill_color_ram:
        ldx     #$00
L_E742:
        sta     D_D800,x                ; Color RAM page 0
        sta     D_D900,x                ; Color RAM page 1
        sta     D_DA00,x                ; Color RAM page 2
        sta     D_DB00,x                ; Color RAM page 3
        inx
        bne     L_E742
        rts

; ============================================================================
; End of bb-line-draw.s
; ============================================================================
