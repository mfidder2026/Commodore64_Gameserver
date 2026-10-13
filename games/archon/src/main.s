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

        .import net_hb, net_start, net_step, net_idle, net_end, net_in0, net_in1, net_keys
        .importzp HB_SEED, END_GAMEOVER, END_QUIT
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
        sta     arch_session
.ifndef DETTEST
        jsr     net_start               ; C=1: no handoff: the demo
        bcs     @nosession
        inc     arch_session
        lda     net_hb+HB_SEED          ; the session's random numbers (an LFSR
        sta     arch_rng                ; state of 0 would stay 0)
        lda     net_hb+HB_SEED+1
        ora     #1
        sta     arch_rng+1
        and     #2                      ; who moves first
        beq     @nosession
        lda     #$AA
        sta     arch_first
@nosession:
.endif
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
.ifdef ONLINE
        lda     #0                      ; the clock from 0, and no KERNAL IRQ
        sta     $A0                     ; (it would count jiffies, PAL and NTSC
        sta     $A1                     ; differently) until the game's own IRQ
        sta     $A2                     ; set-up ($632D) allows interrupts
.else
        cli
.endif
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

; --- the start of a game: the options as F3/F5/F7 set them (no title, no demo) ---------
        .segment "P_6129"
        jsr     arch_options            ; was JSR $632D (the IRQ set-up)

; --- the end of a game: online back to the lobby --------------------------------------
        .segment "P_6746"
        jmp     arch_over               ; was LDA $A1 / STA $BD27: the wait
        nop                             ; for a key (or the demo) after the result
        nop

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
        jsr     arch_joytick            ; was LDA $DC00,X: in a loop until the
                                        ; button is let go (the spell menu)
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
arch_session:   .byte   0               ; 1: a session (two players over the network)
arch_first:     .byte   $55             ; who moves first: $55 light, $AA dark
arch_wait:      .byte   0

; --- the raster IRQ: a frame (then the KERNAL's IRQ exit, $638E) ---------------------
arch_irq:
        inc     arch_due
        jmp     $638E

; --- the options of a game: two players (the session's), or the test's ---------------
arch_options:
        jsr     $632D                   ; the IRQ set-up (what $6129 called)
.if .defined(DETTEST) .and .defined(HUMANS)
.if HUMANS = 1
        lda     #$55                    ; the computer plays light (F3 once)
        sta     $BCC0
        sta     $BCC5
        lda     #1
        sta     $BCC1
        lda     #0
.else
        lda     #0
        sta     $BCC0                   ; the computer plays no side (F3: two players)
        sta     $BCC1
        sta     $BCC5
.endif
        sta     $BCC3                   ; not the options screen (F7)
        sta     $BCCB
        sta     $BCD1                   ; not the demo (any F key)
        lda     #$55
        sta     $BCC2                   ; light first (F5)
        rts
.else
        lda     arch_session            ; no session: the demo, as the original
        beq     @done
        lda     #0
        sta     $BCC0                   ; the computer plays no side (F3: two players)
        sta     $BCC1
        sta     $BCC5
        sta     $BCC3                   ; not the options screen (F7)
        sta     $BCCB
        sta     $BCD1                   ; not the demo (any F key)
        lda     arch_first
        sta     $BCC2                   ; who moves first (F5): the session's
@done:  rts
.endif

; --- the game is over: the result for 3 s, then back to the lobby ----------------------
arch_over:
.ifndef DETTEST
        lda     arch_session
        beq     @orig
        lda     #150                    ; 3 s (PAL; NTSC 2.5 s)
        sta     arch_wait
:       jsr     net_idle
        lda     arch_due
        beq     :-
        lda     #0
        sta     arch_due
        dec     arch_wait
        bne     :-
        lda     #<END_GAMEOVER
        jmp     net_end
.endif
@orig:  lda     $A1                     ; no session: as the original
        sta     $BD27
        jmp     $674B

; --- a joystick read in a wait loop: a tick first ------------------------------------
arch_joytick:
        jsr     arch_tick
        lda     arch_in,x
        rts

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
.ifndef DETTEST
        lda     arch_session            ; a session: this tick's inputs
        beq     @inputs
        txa
        pha
        tya
        pha
        jsr     net_step                ; slot 0 plays light, slot 1 dark
        lda     net_keys
        and     #$40                    ; Q (either player): the session ends
        beq     :+
        lda     #<END_QUIT
        jmp     net_end
:       lda     net_in0                ; light reads port 1 (index 1), dark
        ora     #$E0                    ; port 2 (index 0); bits 0-4 as $DC00
        sta     arch_in+1
        lda     net_in1
        ora     #$E0
        sta     arch_in
        pla
        tay
        pla
        tax
@inputs:
.endif
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
dt_rng:         .byte   $35, $A7
dt_dirs:        .byte   $0F, $0E, $0D, $0B, $07, $0A, $06, $09 ; none, up, down, left,
                                        ; right, up+left, up+right, down+left

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
.ifdef HUMANS
        lda     arch_ticks              ; the bot, as a person: a direction for
        and     #31                     ; 6 ticks (a square or two), nothing,
        cmp     #24                     ; then 4 ticks the button (as $DC00:
        bcs     @fire                   ; bits 0-3 directions, 4 fire, active
        cmp     #6                      ; low)
        beq     @still
        cmp     #0
        bne     @keep
        ldx     #1
@bot:   lda     dt_rng,x                ; LFSR per player
        asl     a
        bcc     :+
        eor     #$1D
:       sta     dt_rng,x
        and     #7
        tay
        lda     dt_dirs,y
        ora     #$F0
        sta     arch_in,x
        dex
        bpl     @bot
        bmi     @keep
@still: ldx     #$FF                    ; (6-23: nothing)
        bne     @set
@fire:  ldx     #$EF                    ; the button, no direction (24-27),
        cmp     #28                     ; then nothing (28-31)
        bcc     @set
        ldx     #$FF
@set:   stx     arch_in
        stx     arch_in+1
@keep:
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
