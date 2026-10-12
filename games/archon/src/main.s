; =============================================================================
; Archon OME - patches to the original RAM image
; (orig/archon-6100.bin: the RAM when the tape version's file jumps into the
; game, JMP $6100; tools/snapshot.py, from the file without the cracker's line).
; framework/tools/imagebuild.py places every segment P_xxxx at $xxxx;
; src/areas*.json list where patches may go.
;
; Without ONLINE: the game as one PRG (title, options, the demo).
; With ONLINE (DETTEST for now): virtual frames. The raster IRQ (one per frame,
; line $FB) runs the frame logic through ($BCCC): moving the icons, the board's
; animations, the battle in the arena (via ($BD30)); the main program starts
; such a task ($BCD0 = 0) and waits until it is done ($BCD0 negative). Here
; the IRQ only counts real frames (arch_due); the frame logic runs as a "tick"
; only where the main program waits, one per real frame (arch_tick). The
; SID's noise (the game's random numbers, 18 places) is our own generator; the
; joysticks (11 places) are this tick's inputs (arch_in).
; DETTEST: HALT_AT=n stops before tick n (tools/dettest.py); JITTER waits 0-3
; frames more per tick.
; =============================================================================

        .export game_entry

GAME_START = $6100      ; the game's own start

.if .defined(DETTEST) .or .defined(NET_UCI) .or .defined(NET_WIC) .or .defined(NET_RR)
ONLINE = 1
.endif

; =============================================================================
; Entry, called by the framework's unpacker: low memory and the I/O set-up as
; the tape version's start left them (the KERNAL's: its timer IRQ on)
; =============================================================================
        .segment "P_C400"
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
        lda     #0                      ; VIC as orig/archon-6100-io.bin
        sta     $D01A
        sta     $D015
        lda     #$1B
        sta     $D011
        lda     #$C8
        sta     $D016
        lda     #$15
        sta     $D018
        lda     #$0E
        sta     $D020
        lda     #$06
        sta     $D021
        lda     #$C7
        sta     $DD00
        lda     #$3F
        sta     $DD02
.ifdef ONLINE
        lda     #0
        sta     arch_due
        sta     arch_ticks
        sta     arch_ticks+1
        sta     arch_fifth
.endif
.ifdef ONLINE
        lda     #$40                    ; no key (the KERNAL no longer scans the
        sta     $C5                     ; keyboard: its timer IRQ is ours)
        sta     $CB
.endif
        lda     #$37                    ; BASIC, KERNAL, I/O
        sta     $01
        ldx     #$F6                    ; the stack as the start left it
        txs
        cli
        jmp     GAME_START

        .segment "P_C000"
low:    .incbin "low.bin"               ; $0000-$03FF of the snapshot

.ifdef ONLINE
; =============================================================================
; The raster IRQ: count the frame; the frame logic runs in ticks
; =============================================================================
        .segment "P_6388"
        jmp     arch_irq                ; was JMP ($BCCC): the frame logic
; the CIA timer IRQ (the KERNAL's: the jiffy clock $A0-$A2, which the game uses
; for waits, timers and random numbers, and the keyboard): only acknowledged;
; the clock runs in ticks
        .segment "P_638B"
        jmp     arch_timer              ; was JMP ($BCCE): the KERNAL's IRQ

; --- the SID's noise: our random numbers ---------------------------------------------
        .segment "P_65EA"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_65F9"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_6B4C"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_6F5F"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_70D7"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_763F"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_7667"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_77FA"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_7801"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_7893"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_9C4E"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_9C7C"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_9F66"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_9FAE"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_9FBC"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_9FEF"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_A000"
        jsr     arch_rnd                ; was LDA $D41B
        .segment "P_A036"
        jsr     arch_rnd                ; was LDA $D41B

; --- the joysticks (X or Y: 0 port 2, 1 port 1): this tick's inputs ------------------
        .segment "P_6BE5"
        lda     arch_in,x               ; was LDA $DC00,X
        .segment "P_6BF2"
        lda     arch_in,x               ; was LDA $DC00,X
        .segment "P_6C00"
        lda     arch_in,x               ; was LDA $DC00,X
        .segment "P_83F6"
        lda     arch_in,x               ; was LDA $DC00,X
        .segment "P_846C"
        lda     arch_in,x               ; was LDA $DC00,X
        .segment "P_9502"
        lda     arch_in,y               ; was LDA $DC00,Y
        .segment "P_9558"
        lda     arch_in,y               ; was LDA $DC00,Y
        .segment "P_95FC"
        lda     arch_in,y               ; was LDA $DC00,Y
        .segment "P_964B"
        lda     arch_in,y               ; was LDA $DC00,Y
        .segment "P_96A5"
        lda     arch_in,y               ; was LDA $DC00,Y
        .segment "P_96F8"
        lda     arch_in,y               ; was LDA $DC00,Y

; =============================================================================
; New code in $C500-$CFFF, which the game never touches
; =============================================================================
        .segment "ARCH"

arch_due:       .byte   0               ; real frames not yet run as ticks
arch_ticks:     .word   0               ; ticks so far
arch_rng:       .byte   $5A, $C3        ; random generator (16 bit LFSR)
arch_in:        .byte   $FF, $FF        ; this tick's joysticks: port 2, port 1
arch_a:         .byte   0
arch_fifth:     .byte   0               ; jiffies: 6 per 5 ticks (60 Hz on PAL)

; --- the raster IRQ: a frame (then the KERNAL's IRQ exit, $638E) ---------------------
arch_irq:
        inc     arch_due
        jmp     $638E

; --- the CIA timer IRQ: acknowledge (then the KERNAL's IRQ exit, $638E) ------------------
arch_timer:
        lda     $DC0D
        jmp     $638E

; --- a random byte (was LDA $D41B: A and the flags N, Z; X, Y kept) ------------------
arch_rnd:
        lda     arch_rng+1              ; Galois LFSR, x^16+x^14+x^13+x^11+1
        lsr     a
        sta     arch_rng+1
        lda     arch_rng
        ror     a
        sta     arch_rng
        bcc     :+
        lda     arch_rng+1
        eor     #$B4
        sta     arch_rng+1
:       lda     arch_rng
        eor     arch_rng+1
        rts

; --- one tick: wait for a real frame, then the frame logic (A, X, Y kept) ------------
arch_tick:
        sta     arch_a
.ifdef DETTEST
        jsr     dt_step
.endif
:       lda     arch_due                ; one tick per real frame
        beq     :-
        lda     #0
        sta     arch_due
        jsr     arch_jiffy              ; the KERNAL's clock: one jiffy, and
        dec     arch_fifth              ; one more every fifth tick
        bpl     :+
        lda     #4
        sta     arch_fifth
        jsr     arch_jiffy
:       inc     arch_ticks
        bne     arch_frame
        inc     arch_ticks+1
; the frame logic as the IRQ ran it: the KERNAL's interrupt frame (A, X, Y),
; then ($BCCC), which ends with $638E (PLA TAY PLA TAX PLA RTI)
arch_frame:
        lda     #>@back
        pha
        lda     #<@back
        pha
        php
        lda     arch_a
        pha
        txa
        pha
        tya
        pha
        jmp     ($BCCC)
@back:  rts

arch_jiffy:                             ; as the KERNAL's UDTIM: the clock
        lda     #$FF                    ; ($A0-$A2), and $91, the STOP key's
        sta     $91                     ; row: nothing pressed
        inc     $A2
        bne     :+
        inc     $A1
        bne     :+
        inc     $A0
:       rts

; --- the main program's wait loops (tools/waits.py) ----------------------------------
        .include "waits.inc"
        .segment "ARCH"

; --- determinism test ----------------------------------------------------------------
.ifdef DETTEST
dt_n:           .byte   0

dt_step:                                ; (X and Y are the caller's)
        txa
        pha
        tya
        pha
.ifdef HALT_AT
        lda     arch_ticks
        cmp     #<HALT_AT
        bne     :+
        lda     arch_ticks+1
        cmp     #>HALT_AT
        bne     :+
arch_halt:
        jmp     arch_halt               ; tools/dettest.py saves the RAM here
:
.endif
.ifdef JITTER                           ; wait 0-3 whole frames more, as a
        lda     $D012                   ; network would
        eor     arch_ticks
        and     #3
        beq     @nowait
        sta     dt_n
@frame: lda     arch_due
        beq     @frame
        lda     #0
        sta     arch_due
        dec     dt_n
        bne     @frame
@nowait:
.endif
        pla
        tay
        pla
        tax
        rts
.endif
.endif ; ONLINE
