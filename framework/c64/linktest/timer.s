; ============================================================================
; Link test: a 32-bit cycle counter, CIA 2 timer A (every cycle, from $FFFF)
; chained into timer B (counts timer A's underflows). Both count down; the C
; side gets the elapsed cycles as an up-counting value. No interrupts.
; ============================================================================

        .export _timer_init, _timer_now
        .importzp sreg

CIA2_TA_LO      = $DD04
CIA2_TA_HI      = $DD05
CIA2_TB_LO      = $DD06
CIA2_TB_HI      = $DD07
CIA2_ICR        = $DD0D
CIA2_CRA        = $DD0E
CIA2_CRB        = $DD0F

; void timer_init(void)
_timer_init:
        lda     #$7F                    ; no CIA 2 interrupts (NMIs)
        sta     CIA2_ICR
        lda     #0
        sta     CIA2_CRA                ; stop both
        sta     CIA2_CRB
        lda     #$FF
        sta     CIA2_TA_LO
        sta     CIA2_TA_HI
        sta     CIA2_TB_LO
        sta     CIA2_TB_HI
        lda     #%01010001              ; B: count A underflows, load, start
        sta     CIA2_CRB
        lda     #%00010001              ; A: count cycles, continuous, load, start
        sta     CIA2_CRA
        rts

; unsigned long timer_now(void): cycles since timer_init (wraps after ~72 minutes)
_timer_now:
@again: lda     CIA2_TB_HI              ; read B, A, then B again: if B changed,
        sta     hi                      ; A wrapped in between, read again
        lda     CIA2_TB_LO
        sta     lo
        ldy     CIA2_TA_HI
        ldx     CIA2_TA_LO
        cpy     CIA2_TA_HI              ; A's high byte changed while reading the low byte?
        bne     @again
        lda     CIA2_TB_LO
        cmp     lo
        bne     @again
        lda     CIA2_TB_HI
        cmp     hi
        bne     @again
        txa                             ; up-counting: invert all 32 bits
        eor     #$FF
        pha
        tya
        eor     #$FF
        tax
        lda     lo
        eor     #$FF
        sta     sreg
        lda     hi
        eor     #$FF
        sta     sreg+1
        pla
        rts

        .bss
lo:     .res    1
hi:     .res    1
