; ============================================================================
; rebb64 - Sprite Management and Initialization
; ============================================================================
; This file contains sprite positioning routines, IRQ setup, and game
; initialization code.
;
; ADDRESS RANGE: $078C - $08E3
;
; KEY ROUTINES:
;   L_078C - Sprite setup with bank switching
;   D_07E1 - Sprite position update (handles sprites 2-7 with X MSB)
;   D_0840 - Ending sequence animation
;   D_0885 - Game initialization (screen setup, random level fill)
; ============================================================================

.setcpu "6502"
.segment "CODE_IRQ"

; ============================================================================
; SPRITE SETUP / IRQ HANDLER CODE ($078C - $07E0)
; ============================================================================
; This section contains sprite positioning routines and IRQ setup code.
; Includes ending sequence animation and initialization routines.
; ============================================================================

L_078C:
        ldx     #<irq_frame_update              ; $078C
        ldy     #>irq_frame_update              ; $078E
        lda     #$fb                            ; $0790
        jmp     D_0717                          ; $0792 - Jump to earlier routine
        
        ; Stack preservation and bank switching
irq_super_bonus:                                ; $0795
        pha                                     ; $0795
        txa                                     ; $0796
        pha                                     ; $0797
        tya                                     ; $0798
        pha                                     ; $0799
        cld                                     ; $079A - Clear decimal mode
        lda     $01                             ; $079B - Save current memory config
        sta     $2e                             ; $079D
        lda     #$35                            ; $079F - Set memory config (I/O visible)
        sta     $01                             ; $07A1
        
        ; Sprite Y-position adjustment
        lda     VIC_SPR2_Y                      ; $07A3 - VIC_SPR2_Y
        clc                                     ; $07A6
        adc     #$2a                            ; $07A7
D_07A9:
        sta     VIC_SPR2_Y                      ; $07A9 - VIC_SPR2_Y
        sta     VIC_SPR3_Y                      ; $07AC - VIC_SPR3_Y
        sta     VIC_SPR4_Y                      ; $07AF - VIC_SPR4_Y
        
        ; Sprite pointer updates
        lda     D_53FA                          ; $07B2 - Sprite pointer
        adc     #$08                            ; $07B5
        ldx     #$02                            ; $07B7
L_07B9:
        sta     D_53FA,x                        ; $07B9 - Update sprite pointers
        sta     D_57FA,x                        ; $07BC
        sec                                     ; $07BF
        sbc     #$01                            ; $07C0
        dex                                     ; $07C2
        bpl     L_07B9                          ; $07C3
        
        ; IRQ vector setup
        ldx     #<irq_frame_update              ; $07C5
        ldy     #>irq_frame_update              ; $07C7
        lda     #$fb                            ; $07C9
        sta     VIC_RASTER                      ; $07CB - VIC_RASTER
        stx     IRQ_VEC                         ; $07CE - IRQ_VEC low
        sty     IRQ_VEC_HI                      ; $07D1 - IRQ_VEC high
        dec     VIC_IRQ                         ; $07D4 - VIC_IRQ (acknowledge)
        
        ; Restore bank and stack
        lda     $2e                             ; $07D7
        sta     $01                             ; $07D9
        pla                                     ; $07DB
        tay                                     ; $07DC
        pla                                     ; $07DD
        tax                                     ; $07DE
        pla                                     ; $07DF
D_07E0:
        rti                                     ; $07E0

; ============================================================================
; SPRITE POSITION UPDATE ROUTINE ($07E1)
; ============================================================================
; Updates sprite X/Y positions for multiple sprites (2-7)
; Handles X MSB (extended positioning beyond 255)
;
; This routine is called frequently to position sprites on screen.
; It handles the VIC-II's extended X-coordinate system where sprites
; can be positioned beyond X=255 using the MSB register.
; ============================================================================
D_07E1:
        ldx     #$00                            ; $07E1
        stx     VIC_SPR_XMSB                    ; $07E3 - VIC_SPR_XMSB
        lda     $bc                             ; $07E6 - Base X position
        sta     VIC_SPR2_X                      ; $07E8 - VIC_SPR2_X
        sta     VIC_SPR5_X                      ; $07EB - VIC_SPR5_X
        clc                                     ; $07EE
        adc     #$18                            ; $07EF - Add 24 pixels
        sta     VIC_SPR3_X                      ; $07F1 - VIC_SPR3_X
        sta     VIC_SPR6_X                      ; $07F4 - VIC_SPR6_X
        bcc     L_07FF                          ; $07F7 - No carry? Skip MSB update
        ldy     #$d8                            ; $07F9 - Enable MSB for sprites 3,4,6,7
        sty     VIC_SPR_XMSB                    ; $07FB - VIC_SPR_XMSB
        clc                                     ; $07FE
L_07FF:
        adc     #$18                            ; $07FF - Add another 24 pixels
        sta     VIC_SPR4_X                      ; $0801 - VIC_SPR4_X
        sta     VIC_SPR7_X                      ; $0804 - VIC_SPR7_X
        bcc     L_080F                          ; $0807 - No carry? Skip MSB update
        lda     #$90                            ; $0809 - Enable MSB for sprites 4,7
        sta     VIC_SPR_XMSB                    ; $080B - VIC_SPR_XMSB
        clc                                     ; $080E
L_080F:
        lda     $bd                             ; $080F - Base Y position
D_0811:
        sta     VIC_SPR2_Y                      ; $0811 - VIC_SPR2_Y
        sta     VIC_SPR3_Y                      ; $0814 - VIC_SPR3_Y
        sta     VIC_SPR4_Y                      ; $0817 - VIC_SPR4_Y
        adc     #$15                            ; $081A - Add 21 pixels
        sta     VIC_SPR5_Y                      ; $081C - VIC_SPR5_Y
D_081F:
        sta     VIC_SPR6_Y                      ; $081F - VIC_SPR6_Y
        sta     VIC_SPR7_Y                      ; $0822 - VIC_SPR7_Y
        
        ; Update sprite pointers
        ; Base sprite pointer for Grumple Gromit left-facing sprites (ending sequence).
        ; Value = (sprite_data_7440 + $200 - VIC_bank) / 64, computed as hibyte(X*4).
        lda     #>(sprite_data_7440 + $200 - __VIC_BANK_BASE__ + sprite_data_7440 + $200 - __VIC_BANK_BASE__ + sprite_data_7440 + $200 - __VIC_BANK_BASE__ + sprite_data_7440 + $200 - __VIC_BANK_BASE__)
        adc     $be                             ; $0827 - Offset
L_0829:
        sta     D_53FA,x                        ; $0829 - Sprite pointer buffer 1
        sta     D_57FA,x                        ; $082C - Sprite pointer buffer 2
        adc     #$01                            ; $082F - Next sprite
        inx                                     ; $0831
        cpx     #$06                            ; $0832
D_0834:
        bne     L_0829                          ; $0834
        
        ; Set sprite colors
        ldx     #$05                            ; $0836
        lda     $c0                             ; $0838 - Color value
L_083A:
        sta     VIC_SPR2_COL,x                  ; $083A - VIC_SPR2_COL+
        dex                                     ; $083D
        bpl     L_083A                          ; $083E
        
        ; Ending sequence animation check
D_0840:
        lda     $10                             ; $0840 - SUBFLG (level number)
        cmp     #$64                            ; $0842 - Check if ending sequence
        bne     L_0867                          ; $0844
        
        ; Ending animation movement logic
        lda     $bf                             ; $0846 - Direction flag
        bne     L_0854                          ; $0848
        dec     $bc                             ; $084A - Move left
        lda     $bc                             ; $084C
        cmp     #$23                            ; $084E - Check boundary
        bne     L_0866                          ; $0850
        beq     L_085A                          ; $0852
L_0854:
        inc     $bc                             ; $0854 - Move right
        bne     L_0866                          ; $0856
        dec     $bc                             ; $0858 - Undo if wrapped
L_085A:
        lda     $bf                             ; $085A - Toggle direction
        eor     #$01                            ; $085C
        sta     $bf                             ; $085E
        lda     $be                             ; $0860 - Toggle sprite frame
        eor     #$18                            ; $0862
        sta     $be                             ; $0864
L_0866:
        rts                                     ; $0866
        
L_0867:
        cmp     #$ff                            ; $0867 - Check for special mode
        bne     L_0866                          ; $0869
        
        ; Data copy routine (palette/tileset?)
        lda     $08                             ; $086B - Frame counter
        lsr                                     ; $086D
        lsr                                     ; $086E
        lsr                                     ; $086F
        lsr                                     ; $0870
        lsr                                     ; $0871
        and     #$01                            ; $0872 - Get bit 5
        tax                                     ; $0874
        ldy     D_3F84,x                        ; $0875 - Load index
        ldx     #$09                            ; $0878
L_087A:
        lda     D_57D4,y                        ; $087A - Copy 10 bytes
        sta     D_50AF,x                        ; $087D
D_0880:
        dey                                     ; $0880
        dex                                     ; $0881
        bpl     L_087A                          ; $0882
        rts                                     ; $0884

; ============================================================================
; INITIALIZATION ROUTINE ($0885)
; ============================================================================
; Sets up game state, screen buffers, and initializes level data.
;
; This routine is called at game start to:
;   - Set up screen memory pointers
;   - Copy sprite and character set data
;   - Initialize game state variables
;   - Fill level with random tiles (200 tiles for demo/attract mode)
; ============================================================================
D_0885:
        jsr     clear_screen                     ; $0885 - Screen setup
        lda     #>__VIC_SCREEN_B__                ; $0888
        sta     $30                             ; $088A - ARYTAB+1
        lda     #>__VIC_CHARSET_B__              ; $088C
        sta     $2f                             ; $088E - ARYTAB
        
        ; Copy sprite/charset data
        ldx     #$0f                            ; $0890
L_0892:
        lda     D_AE41,x                        ; $0892
        sta     D_47F0,x                        ; $0895
        dex                                     ; $0898
        bpl     L_0892                          ; $0899
        
        ; Initialize game state
        lda     #$00                            ; $089B
        sta     $20                             ; $089D - Game mode flag
        sta     VIC_SPR_ENA                     ; $089F - VIC_SPR_ENA (disable sprites)
        jsr     fill_color_ram                  ; $08A2
        
        ; Set up random level fill
        lda     #$06                            ; $08A5
        sta     $1d                             ; $08A7
        sta     $1c                             ; $08A9
        lda     #$03                            ; $08AB
        sta     $1f                             ; $08AD
        sta     $1e                             ; $08AF
        
        ; Fill level with random tiles (200 iterations)
        ldx     #$c8                            ; $08B1 - 200 tiles
L_08B3:
        jsr     D_E9EA                          ; $08B3 - Random number generator
        cmp     #$19                            ; $08B6 - Limit to 0-24
        bcs     L_08B3                          ; $08B8 - Retry if >= 25
        asl                                     ; $08BA - Multiply by 2 (table index)
        tay                                     ; $08BB
        lda     #$00                            ; $08BC
        adc     D_AC09,y                        ; $08BE - Level data pointer low
        sta     $11                             ; $08C1 - INPFLG
        lda     #>__VIC_SCREEN_A__                  ; $08C3
        adc     D_AC0A,y                        ; $08C5 - Level data pointer high
        sta     $12                             ; $08C8 - TANSGN
L_08CA:
        jsr     D_E9EA                          ; $08CA - Random Y coordinate
        cmp     #$28                            ; $08CD - Limit to 0-39
D_08CF:
        bcs     L_08CA                          ; $08CF - Retry if >= 40
        tay                                     ; $08D1
        jsr     D_E9EA                          ; $08D2 - Random tile data
        ora     #$fe                            ; $08D5 - Set upper bits
        sta     ($11),y                         ; $08D7 - Write to level buffer
        dex                                     ; $08D9
        bne     L_08B3                          ; $08DA - Loop 200 times
        
        ; Finish initialization
        jsr     wait_one_frame                          ; $08DC - Wait one frame
        lda     #$09                            ; $08DF
        jmp     fill_color_ram                  ; $08E1
