; =============================================================================
; Spy vs Spy OME - patches to the original RAM image
; (orig/spyvsspy-660f.bin: the RAM when the disk's file jumps into the game,
; JMP $660F; tools/snapshot.py). framework/tools/imagebuild.py places every
; segment P_xxxx at $xxxx; src/areas*.json list where patches may go.
;
; The game: the main loop ($66DC-$6877) runs one spy per pass ($41 = 0 white,
; 1 black; the pass starts at $674E). Its inputs are $02,X: the joystick
; ($0285/$0286, read by the IRQ), the computer's spy ($9A67), or the
; recorded demo ($CFF7 negative: the game replays inputs per pass, with a
; fixed random seed). The raster IRQ ($8FA6, two per frame, one per screen
; half, $35) draws: the spies' sprites, the colours; it also plays the sound
; ($9226) and the music ($954E), reads the joysticks and keys ($94A1) and
; counts both spies' clocks down ($9362: $8F/$91/$93 per spy, BCD; at 0
; $025F,X says "time is up").
;
; Without ONLINE: the game as one PRG (the options screen, the demo).
; With ONLINE (DETTEST for now): a tick is one pass of the main loop
; (spy_tick at $674E). The clocks run in the tick (SPY_VF_NUM / SPY_VF_DEN
; virtual frames per tick, about the original pace), the inputs come from the
; tick; the IRQ keeps drawing, the sound and the music (their memory is left
; out of the comparisons: nothing in the game logic reads it).
; A session (a table in the lobby): one network step (net_step) per round,
; white's pass and black's. The table's option: bits 0-2 the level (0-7:
; level 1-8), bit 3 "own screen" (the other spy's half is black while the
; spies are in different rooms: you do not see where the other one goes or
; what traps it sets; in one room both see it). One player at the table
; plays white against the computer, two
; play white (slot 0, the host) and black (slot 1). Q (either player) ends
; the session; after a game (both spies done, $6745) the result stays three
; seconds, then back to the lobby.
; DETTEST: HUMANS=1 (a bot as white against the computer) or 2 (two bots,
; the default), LEVEL=1-8 (default 1), PRIVATE=0/1 (own screen: white's,
; black's);
; HALT_AT=n stops before tick n
; (tools/dettest.py); JITTER waits 0-3 frames more per tick. (No demo: its
; recorded inputs, $C000-$CFFF, hold our code in these builds.)
; =============================================================================

        .import net_hb, net_start, net_step, net_idle, net_end, net_in0, net_in1, net_keys
        .importzp HB_SEED, HB_PLAYERS, HB_SLOT, END_GAMEOVER, END_QUIT
        .export game_entry

GAME_START = $660F      ; the game's own start

.if .defined(DETTEST) .or .defined(NET_UCI) .or .defined(NET_WIC) .or .defined(NET_RR)
ONLINE = 1
.endif
.ifdef DETTEST
.ifndef HUMANS
HUMANS = 2
.endif
.ifndef LEVEL
LEVEL = 1
.endif
.endif

SPY_VF_NUM = 7          ; virtual frames per tick: 7 per 5 (a pass of the main
SPY_VF_DEN = 5          ; loop takes about 1.4 frames in the original)

; =============================================================================
; Entry, called by the framework's unpacker: low memory and the I/O set-up as
; the disk's start left them. It lies in the unused ends of the demo's
; recorded inputs ($C000-$CFFF: white's values and counts, black's values and
; counts; the demo reads up to $C366, $C766, $C983, $CD83), so the original
; game keeps its demo.
; =============================================================================
        .segment "P_C984"
low_a:  .incbin "low.bin", $0200, $0200 ; $0200-$03FF of the snapshot
        .segment "P_CD84"
low_b:  .incbin "low.bin", 0, $0200     ; $0000-$01FF of the snapshot
game_entry:
        sei
        ldx     #0
@copy:  lda     low_b+$0100,x
        sta     $0100,x
        lda     low_a,x
        sta     $0200,x
        lda     low_a+$0100,x
        sta     $0300,x
        cpx     #2                      ; not the CPU port $00/$01
        bcc     :+
        lda     low_b,x
        sta     $00,x
:       inx
        bne     @copy
        lda     #0                      ; VIC as orig/spyvsspy-660f-io.bin
        sta     $D01A
        sta     $D015
        ldx     #$1B
        stx     $D011
        ldx     #$C8
        stx     $D016
        ldx     #$15
        stx     $D018
        ldx     #$0E
        stx     $D020
        ldx     #$06
        stx     $D021
        ldx     #$C7
        stx     $DD00
        ldx     #$3F
        stx     $DD02
        ldx     #$7F                    ; no CIA interrupts: the game stops
        stx     $DC0D                   ; timer A and uses the raster IRQ only,
        stx     $DD0D                   ; but never acknowledges a timer IRQ the
        ldx     $DC0D                   ; unpacker's time may have left pending
        ldx     $DD0D
.ifdef ONLINE
        jsr     spy_start
.endif
        lda     #$36                    ; KERNAL and I/O, as the start left them
        sta     $01
        ldx     #$FA                    ; the stack as the start left it
        txs
        jmp     GAME_START              ; (it starts with SEI)

; --- the options screen's help text: without the cracker's line ---------------------
        .segment "P_18E9"
        .res    14, $20                 ; was "1701 CRACKWARE"

.ifdef ONLINE
; =============================================================================
; Patches
; =============================================================================
; --- a pass of the main loop: a tick ---------------------------------------------------
        .segment "P_674E"
        jsr     spy_tick                ; was LDA $41 / STA $42 (spy_tick does it)
        nop

; --- the IRQ: no clocks (they run in the tick), no joysticks and keys (the tick's) -----
        .segment "P_91A2"
        nop                             ; was JSR $9362: the clocks
        nop
        nop
        jsr     spy_frame               ; was JSR $94A1: joysticks and keys
        .segment "P_8FD6"
        jsr     spy_frame               ; was JSR $94A1 (the IRQ before a game)

; --- the start of a game: the options -------------------------------------------------
        .segment "P_665C"
        jsr     spy_options             ; was JSR $9F7E: the options screen

; --- the random seed of a game: the session's (was $D012 plus the sum of the zero
; page, which holds the IRQ's work bytes too)
        .segment "P_8DDE"
        lda     spy_seed                ; was LDA $D012 / LDX #$FD / CLC / ADC $02,X /
        jmp     $8DE9                   ; DEX / BNE (the demo: a fixed seed)

; --- own screen (the other half black): the IRQ's start of a half, and its end ----------
        .segment "P_8FC7"
        jsr     spy_irqhalf             ; was LDA $0255,X / STA $D021: the half's
        nop                             ; background colour
        nop
        nop
        .segment "P_91B6"
        jmp     spy_irqend              ; was PLA / TAY / PLA / TAX / PLA / RTI

; --- the VIC bank set-up: CIA 2's PA2 stays an output (the WiC64's handshake line;
; the game made all but PA0/PA1 inputs) ----------------------------------------------
        .segment "P_8549"
        .byte   $07                     ; was LDA #$03 / STA $DD02

; --- no restart after a while without input (that starts the demo) -------------------
        .segment "P_66E6"
        jmp     $6718                   ; was LDA $CFF7 / BNE $6718: the idle check

; --- the end of a game (both spies done): online back to the lobby ----------------------
        .segment "P_6745"
        jmp     spy_over                ; was LDA #$FF / STA $7B (then a new game)

; =============================================================================
; Our code
; =============================================================================
        .segment "SPY"

spy_due:        .byte   0               ; real frames not yet waited for
spy_ticks:      .word   0               ; ticks so far
spy_vf:         .byte   0               ; virtual frames: the fraction
spy_x:          .byte   0
spy_y:          .byte   0
spy_in:         .byte   $FF, $FF        ; this tick's joysticks: white, black ($DC00 bits)
spy_seed:       .byte   $5A             ; the random seed of a game
spy_session:    .byte   0               ; 1: a session
spy_players:    .byte   2               ; human players: 1 (white) or 2
spy_level:      .byte   1               ; the level, 1-8
spy_wait:       .word   0
spy_hide:       .byte   $FF             ; own screen: our half (0 white, 1 black);
                                        ; $FF: the split screen as the original

; --- the start (from game_entry): the session's settings -------------------------------
spy_start:
        lda     #0
        sta     spy_due
        sta     spy_ticks
        sta     spy_ticks+1
        sta     spy_vf
        sta     spy_session
        lda     #$FF                    ; the split screen
        sta     spy_hide
.ifdef DETTEST
        lda     #HUMANS
        sta     spy_players
        lda     #LEVEL
        sta     spy_level
.ifdef PRIVATE
        lda     #PRIVATE                ; own screen: 0 white's, 1 black's
        sta     spy_hide
.endif
.else
        jsr     net_start               ; C=1: no handoff (not from the lobby)
        bcs     @done
        inc     spy_session
        lda     net_hb+HB_SEED          ; the session's random seed
        bne     :+
        lda     #$5A
:       sta     spy_seed
        lda     net_hb+HB_PLAYERS       ; the table's option: bits 0-2 the
        lsr     a                       ; level (0-7), bit 3 own screen
        lsr     a
        lsr     a
        lsr     a
        pha
        and     #7
        clc
        adc     #1
        sta     spy_level
        pla
        and     #8
        beq     :+
        lda     net_hb+HB_SLOT          ; own screen: our half is our slot's
        sta     spy_hide
:
        lda     net_hb+HB_PLAYERS       ; the players at the table (0: an old
        and     #15                     ; lobby, two)
        cmp     #1
        beq     :+
        lda     #2
:       sta     spy_players
@done:
.endif
        rts

; --- the IRQ, once per screen half: count the frames (both halves: 2 per frame) -------
spy_frame:
        inc     spy_due
        rts

; --- own screen: the IRQ starts the half X ($35) ----------------------------------------
; The other spy's half is shown in an invalid mode (ECM + bitmap: black) and
; without sprites while the spies are in different rooms ($F8 negative) and
; both still play (both clocks run: $025D/$025E); in one room ($F8: the half that shows
; it) nothing is hidden. Only the display
; changes. spy_irqhalf runs right at the split (the mode), spy_irqend after
; the IRQ's sprite work (the sprites).
spy_irqhalf:
        lda     $0255,x                 ; what the patch replaced: the colour
        sta     $D021
        jsr     spy_hidden
        lda     $D011
        bcc     :+
        ora     #$40                    ; the other spy's half: black
        and     #$7F
        sta     $D011
        rts
:       and     #$3F                    ; as the game set it (bitmap mode)
        sta     $D011
        rts

spy_irqend:
        jsr     spy_hidden
        bcc     :+
        lda     #0                      ; the other spy's half: no sprites
        sta     $D015
:       pla
        tay
        pla
        tax
        pla
        rti

spy_hidden:                             ; C=1: the half $35 is hidden
        lda     spy_hide
        bmi     @no
        lda     $025D                   ; a spy's clock stopped (it escaped,
        beq     @no                     ; or its time is up: its result shows):
        lda     $025E                   ; nothing is hidden any more
        beq     @no
        lda     $F8
        bpl     @no
        lda     $35
        cmp     spy_hide
        beq     @no
        sec
        rts
@no:    clc
        rts

; --- the options of a game (instead of the options screen) -----------------------------
spy_options:
        lda     spy_players             ; 1: white against the computer, 2: two
        sta     $022F                   ; players
        lda     spy_level               ; level 1-8
        sta     $022D
        lda     #3                      ; the computer's IQ (of 5)
        sta     $0231
        lda     #1                      ; the airport hidden till the end (Y)
        sta     $0233
        lda     #0                      ; not the demo
        sta     $CFF7
        jmp     $A123                   ; the game's options -> its variables

; --- the end of a game: the result for 3 s, then back to the lobby ----------------------
spy_over:
.ifndef DETTEST
        lda     spy_session
        beq     @again
        lda     #<300                   ; 3 s (two IRQs per frame; PAL)
        sta     spy_wait
        lda     #>300
        sta     spy_wait+1
        lda     #0
        sta     spy_due
@wait:  jsr     net_idle
        lda     spy_due
        beq     @wait
        dec     spy_due
        lda     spy_wait
        bne     :+
        dec     spy_wait+1
:       dec     spy_wait
        lda     spy_wait
        ora     spy_wait+1
        bne     @wait
        lda     #<END_GAMEOVER
        jmp     net_end
@again:
.endif
        lda     #$FF                    ; as the original: a new game
        sta     $7B
        sta     $7C
        jmp     $6627

; --- one tick: a pass of the main loop for one spy ($41 changes after this) ------------
spy_tick:
        stx     spy_x
        sty     spy_y
.ifdef DETTEST
        jsr     dt_step
.else
        lda     spy_session             ; a session: the inputs of a round (a
        beq     @inputs                 ; spy uses its input in its own pass
        lda     $41                     ; only): one network step per pair of
        beq     @inputs                 ; passes, before white's ($41 = 1: the
        jsr     net_step                ; pass after this is white's); slot 0
                                        ; plays white, slot 1 black
        lda     net_keys
        and     #$40                    ; Q (either player): the session ends
        beq     :+
        lda     #<END_QUIT
        jmp     net_end
:       lda     net_in0                 ; bits 0-4 as $DC00
        ora     #$E0
        sta     spy_in
        lda     net_in1
        ora     #$E0
        sta     spy_in+1
@inputs:
.endif
        lda     #0                      ; no keys (F5: restart, RUN/STOP: pause;
        sta     $0282                   ; bit 7 also ends the demo)
        lda     spy_in                  ; the joysticks (as $94A1 left them)
        sta     $0285
        lda     spy_in+1
        sta     $0286
        clc                             ; the clocks: SPY_VF_NUM virtual frames
        lda     spy_vf                  ; per SPY_VF_DEN ticks
        adc     #SPY_VF_NUM
@vf:    cmp     #SPY_VF_DEN
        bcc     @vfdone
        sbc     #SPY_VF_DEN
        pha
        ldx     #0                      ; as the IRQ: both halves, white and black
        jsr     $9362
        ldx     #1
        jsr     $9362
        cld
        pla
        jmp     @vf
@vfdone:
        sta     spy_vf
        inc     spy_ticks
        bne     :+
        inc     spy_ticks+1
:       ldx     spy_x
        ldy     spy_y
        lda     $41                     ; what $674E did
        sta     $42
        rts

; --- determinism test ----------------------------------------------------------------
.ifdef DETTEST
dt_n:           .byte   0
dt_rng:         .byte   $35, $A7
dt_dirs:        .byte   $0F, $0E, $0D, $0B, $07, $0A, $06, $09 ; none, up, down, left,
                                        ; right, up+left, up+right, down+left
dt_step:
.ifdef HALT_AT
        lda     spy_ticks
        cmp     #<HALT_AT
        bne     :+
        lda     spy_ticks+1
        cmp     #>HALT_AT
        bne     :+
spy_halt:
        jmp     spy_halt                ; tools/dettest.py saves the RAM here
:
.endif
        lda     spy_ticks+1             ; the bot, as a person (per spy: a tick
        lsr     a                       ; is one spy's pass): a direction for 12
        lda     spy_ticks               ; passes, nothing, then 6 passes the
        ror     a                       ; button (as $DC00: bits 0-3 directions,
        and     #63                     ; 4 fire, active low)
        cmp     #48
        bcs     @fire
        cmp     #12
        beq     @still
        cmp     #3
        bne     @keep
        lda     spy_ticks
        lsr     a
        bcs     @keep                   ; (once per pair of ticks)
        ldx     #1
@bot:   lda     dt_rng,x                ; LFSR per spy
        asl     a
        bcc     :+
        eor     #$1D
:       sta     dt_rng,x
        and     #7
        tay
        lda     dt_dirs,y
        ora     #$E0
        sta     spy_in,x
        dex
        bpl     @bot
        bmi     @keep
@still: ldx     #$FF                    ; (12-47: nothing)
        bne     @set
@fire:  ldx     #$EF                    ; the button, no direction (48-53),
        cmp     #54                     ; then nothing (54-63)
        bcc     @set
        ldx     #$FF
@set:   stx     spy_in
        stx     spy_in+1
@keep:
.ifdef JITTER                           ; wait 0-3 whole frames more, as a
        lda     $D012                   ; network would
        eor     spy_ticks
        and     #3
        beq     @nowait
        asl     a                       ; (two IRQs per frame)
        sta     dt_n
        lda     #0
        sta     spy_due
@frame: lda     spy_due
        cmp     dt_n
        bcc     @frame
@nowait:
.endif
        rts
.endif
.endif ; ONLINE
