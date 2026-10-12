; =============================================================================
; M.U.L.E. OME - patches to the original RAM image
; (orig/mule-972b.bin: the RAM when the disk's first part, title and options,
; jumps into the game itself, JMP $972B; tools/snapshot.py). framework/tools/
; imagebuild.py places every segment P_xxxx at $xxxx; src/areas*.json list
; where patches may go.
;
; Without ONLINE: the game as the snapshot's options left it (beginner, four
; computer players), as one PRG.
; With ONLINE (DETTEST for now): virtual frames. In the original the raster
; IRQ runs the frame logic: the clocks ($14/$13/$12), the random mix ($FD),
; the inputs of the four players ($49/$54/$C5), count-downs ($5A, $60CF), the
; button latch ($4D/$2C/$35), the music and the frame task of the phase ($58,
; table $60D1: the players walking, the auction ...). The main program waits
; for it, and which of the two gets how far depends on timing. Here the IRQ
; only draws and counts real frames (mule_due); the frame logic runs as a
; "tick" only where the main program waits, one per real frame (mule_tick).
; DETTEST: HALT_AT=n stops before tick n (tools/dettest.py); JITTER waits 0-3
; frames more per tick.
; =============================================================================

        .export game_entry

GAME_START = $972B      ; the game's own start: stack, init, the colony ...

.if .defined(DETTEST) .or .defined(NET_UCI) .or .defined(NET_WIC) .or .defined(NET_RR)
ONLINE = 1
.endif

; =============================================================================
; Entry, called by the framework's unpacker: low memory and the I/O set-up as
; the first part left them (the unpacker used $0200-$03BF; BASIC and the
; KERNAL enabled the CIA timer IRQ). The game's init clears $EC55-$FEFE, so
; this code and the copy of low memory may lie there.
; =============================================================================
        .segment "P_EC60"
game_entry:
        sei
        ldx     #0
@copy:  lda     low+$0100,x
        sta     $0100,x
        lda     low+$0200,x
        sta     $0200,x
        lda     low+$0300,x
        sta     $0300,x
        cpx     #2                      ; not the CPU port $00/$01
        bcc     :+
        lda     low,x
        sta     $00,x
:       inx
        bne     @copy
        lda     #$7F                    ; no CIA interrupts (the first part
        sta     $DC0D                   ; turned them off)
        sta     $DD0D
        lda     $DC0D
        lda     $DD0D
        lda     #0                      ; VIC as orig/mule-972b-io.bin: no
        sta     $D01A                   ; raster IRQ, no sprites, screen off,
        sta     $D015                   ; bank 0
        lda     #$0B
        sta     $D011
        lda     #$D8
        sta     $D016
        lda     #$E3
        sta     $D018
        lda     #$C7
        sta     $DD00
        lda     #$3F
        sta     $DD02
        lda     #$07
        sta     $D020
        sta     $D021
.ifdef ONLINE
        lda     #0
        sta     mule_due
        sta     mule_ticks
        sta     mule_ticks+1
.endif
        ldx     #tramp_len-1            ; $01 = $37 as the first part left it
:       lda     tramp,x                 ; (KERNAL in): from the stack page, as
        sta     $0100,x                 ; this code lies under the KERNAL
        dex
        bpl     :-
        jmp     $0100
tramp:  lda     #$37
        sta     $01
        jmp     GAME_START
tramp_len = * - tramp

        .segment "P_ED00"
low:    .incbin "low.bin"               ; $0000-$03FF of the snapshot

.ifdef ONLINE
; =============================================================================
; The raster IRQ ($5F17): after its raster chain set-up only the display
; ($5F54-$5F68) and a frame count; the rest is the frame logic (mule_frame)
; =============================================================================
        .segment "P_5F34"
        jmp     mule_irq                ; was LDA $58 / CMP #$FE / BEQ $5F54
        .segment "P_5F54"
        jmp     $5F6B                   ; frame logic: the display is the IRQ's
        .segment "P_5F6B"
        lda     mule_rnd                ; was LDA $D41B: the SID's noise
        .segment "P_5FDB"
        jmp     $5FF7                   ; was LDA $02FF / BPL: attract mode
        .segment "P_6084"
        jmp     $60C9                   ; was LDA $A8 / CMP #$3F: the pause key

; the keyboard and both fire buttons read directly ($6911: A = 0 when something
; is pressed): on this machine only, so never pressed here (the players'
; buttons come through the frame logic, $49,X)
        .segment "P_6911"
        lda     #1
        rts

; the main program's "wait n frames" (A = n): n ticks
        .segment "P_44EE"
        jmp     mule_waitn

; =============================================================================
; New code in $CC00-$CDFF, which the game never touches
; =============================================================================
        .segment "MULE"

mule_due:       .byte   0               ; real frames not yet run as ticks
mule_ticks:     .word   0               ; ticks so far
mule_rnd:       .byte   $5A             ; random byte, a new one per tick
mule_cnt:       .byte   0
mule_a:         .byte   0

; --- the IRQ's display part, then RTI ($60C9) -----------------------------------
mule_irq:
        lda     $D018
        and     #$F0
        ora     $02F4
        sta     $D018
        lda     $02C6
        sta     $D021
        lda     $02C8
        sta     $D020
        inc     mule_due
        jmp     $60C9

; --- wait n frames (was $44EE: A = n, waits on the clock $14) ---------------------
mule_waitn:
        cmp     #0
        beq     @done
        sta     mule_cnt
@tick:  jsr     mule_tick
        dec     mule_cnt
        bne     @tick
@done:  lda     $14
        rts

; --- one tick: wait for a real frame, then the frame logic (A, X, Y kept) ------------
mule_tick:
        sta     mule_a
.ifdef DETTEST
        jsr     dt_step
.endif
:       lda     mule_due                ; one tick per real frame (no catching
        beq     :-                      ; up after a slow stretch)
        lda     #0
        sta     mule_due
        lda     mule_rnd                ; LFSR: the random mix of this tick
        asl     a
        bcc     :+
        eor     #$1D
:       sta     mule_rnd
        inc     mule_ticks
        bne     mule_frame
        inc     mule_ticks+1
; the frame logic ($5F34-$60CE) as the IRQ ran it: an interrupt's stack frame
mule_frame:
        lda     #>@back
        pha
        lda     #<@back
        pha
        php
        lda     mule_a
        pha
        tya
        pha
        txa
        pha
        lda     $58
        cmp     #$FE
        beq     :+
        jmp     $5F3A                   ; the clocks, then the rest
:       jmp     $5F6B                   ; (phase $FE: no clocks)
@back:  rts

; --- the main program's tight wait loops (tools/waits.py) --------------------------
        .include "waits.inc"
        .segment "MULE"

; --- determinism test ---------------------------------------------------------------
.ifdef DETTEST
dt_n:           .byte   0

dt_step:
.ifdef HALT_AT
        lda     mule_ticks
        cmp     #<HALT_AT
        bne     :+
        lda     mule_ticks+1
        cmp     #>HALT_AT
        bne     :+
mule_halt:
        jmp     mule_halt               ; tools/dettest.py saves the RAM here
:
.endif
.ifdef JITTER                           ; wait 0-3 whole frames more, as a
        lda     $D012                   ; network would
        eor     mule_ticks
        and     #3
        beq     @nowait
        sta     dt_n
@frame: lda     mule_due
        beq     @frame
        lda     #0
        sta     mule_due
        dec     dt_n
        bne     @frame
@nowait:
.endif
        rts
.endif
.endif ; ONLINE
