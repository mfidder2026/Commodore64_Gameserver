;===============================================================================
; bb-graphics-copy.s - ROUND/READY Text Compositing
;===============================================================================
; Address range: $3C01-$3CB1
;
; This module composites "ROUND" and "READY" text with sprite graphics for
; level transition displays. It combines font bitmap data from the HUD font
; at $FE90 with sprite data using OR operations.
;
; Data tables used:
;   D_A9A8 (9 bytes) - "ROUND" + level number indices: R O U N D spc 1 0 0
;   D_AD15 (9 bytes) - "READY!" text indices: R E A D Y spc ! spc spc
;
; Output buffers:
;   $4600/$4E00 - "ROUND" composite graphics
;   $4800/$4E48 - "READY" composite graphics
;===============================================================================

;-------------------------------------------------------------------------------
; D_3C01: Graphics Compositing Entry Point
;-------------------------------------------------------------------------------
; Creates combined sprite+text images displayed during level transitions.
; Uses direct ROM access to HUD font at $FE90 (hud_font symbol).
;-------------------------------------------------------------------------------
.segment "CODE_ENTITY_TBLS"

D_3C01:
        lda     #$13                ; Graphics mode
        sta     D_A9B0
        ldx     D_A9AE              ; Check init flag
        bne     @skip_init
        sta     D_A9AE              ; Set init flag

@skip_init:
        lda     $10                 ; Level number
        cmp     #$63                ; Level 99?
        bne     @setup_ptrs
        
        ; Level 99 special case
        lda     #$01
        sta     D_A9AE
        lda     #$00
        sta     D_A9AF
        sta     D_A9B0

@setup_ptrs:
        lda     #>D_4600            ; Setup graphics pointers (page)
        sta     $0A
        sta     $0C
        ldx     #$00
        stx     $09
        lda     #<D_4648              ; READY buffer offset within page
        sta     $0B

@comp_loop:
        lda     D_519C,x            ; Get sprite index 1
        tay
        lda     D_0200,y            ; Sprite pointer low
        sta     $02
        lda     D_0300,y            ; Sprite pointer high
        ora     #>__VIC_BANK_BASE__      ; Set to VIC bank base page
        sta     $03
        lda     D_51EC,x            ; Get sprite index 2
        tay
        lda     D_0200,y
        sta     $04
        lda     D_0300,y
        ora     #>__VIC_BANK_BASE__      ; Set to VIC bank base page
        sta     $05
        lda     D_A9A8,x            ; Get "ROUND" font index
        asl
        asl
        asl
        adc     #<hud_font          ; Add low byte of font base
        sta     $11
        lda     #$00
        adc     #>hud_font          ; Add high byte of font base
        sta     $12
        lda     D_AD15,x            ; Get "READY" font index
        asl
        asl
        asl
        adc     #<hud_font          ; Add low byte of font base
        sta     $13
        lda     #$00
        adc     #>hud_font          ; Add high byte of font base
        sta     $14
        ldy     #$07                ; Composite 8 bytes

@copy_byte:
        lda     ($02),y             ; OR sprite data together
        ora     ($11),y
        sta     ($09),y
        lda     ($04),y
        ora     ($13),y
        sta     ($0B),y
        dey
        bpl     @copy_byte
        
        lda     $09                 ; Advance pointers
        clc
        adc     #$08
        sta     $09
        lda     $0B
        adc     #$08
        sta     $0B
        inx
        cpx     #$09                ; 9 sprites
        bne     @comp_loop
        
        ldx     #$47                ; Copy composited text to work RAM

@buf_loop:
        lda     D_4600,x            ; "ROUND" composited text source
        sta     D_4E00,x            ; Work RAM destination
        lda     D_4648,x            ; "READY" composited text source
        sta     D_4E48,x            ; Work RAM destination
        dex
        bpl     @buf_loop
        
        jsr     wait_one_frame              ; Wait/sync
        lda     #$02
        sta     D_A9B1              ; Set complete flag
        ldx     #<D_ACFD
        ldy     #>D_ACFD
        jmp     display_text_string ; Continue
