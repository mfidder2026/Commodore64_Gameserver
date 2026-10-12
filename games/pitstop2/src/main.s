; =============================================================================
; Pitstop II OME - patches to the original RAM image
; (orig/pitstop2-9403.bin: the RAM when the tape version's boot chain jumps
; into the game, JMP $9403). framework/tools/imagebuild.py places every
; segment P_xxxx at $xxxx; src/areas*.json list where patches may go.
;
; Without ONLINE: the original game as one PRG (only the entry below).
; With ONLINE (the game files the lobby loads for a session):
;   - no menu, no name entry, no "press your button": two drivers, the
;     session's options, driver 1 (slot 0) on port 2;
;   - a deterministic scheduler. In the original the race logic runs in the
;     raster IRQ, one car per frame, while the main loop draws; which of the
;     two gets how far depends on timing, so two C64s would drift apart.
;     Here the IRQ only does the display and counts frames ($E4); the main
;     loop runs a fixed number of logic slots (PIT_K, alternating cars) at
;     the start of every drawing pass ($41A0), and waits for the frames
;     first so the game is not faster than the original;
;   - the inputs: once per pass from the lockstep (or the test bot); the
;     track from the session's seed; Q (either player) ends the session;
;   - after the race: the finish stays on the screen for 3 s, then back to
;     the lobby.
; Without a handoff (the file started on its own) the same build is a local
; game: both joysticks, race after race on track 1. The lobby's key L loads
; the original game (lobby/game.h, LOCAL_GAME_FILE).
; DETTEST: ONLINE without a network, a bot drives both cars; HALT_AT=n
; stops before pass n (tools/dettest.py); JITTER waits 0-3 frames per pass.
; =============================================================================

        .import net_hb, net_start, net_step, net_idle, net_end, net_in0, net_in1, net_keys
        .import HB_SEED, END_GAMEOVER, END_QUIT
        .export game_entry

GAME_START = $9403      ; the game's own start: SEI, $01 = $25, stack, zero page ...

.if .defined(DETTEST) .or .defined(NET_UCI) .or .defined(NET_WIC) .or .defined(NET_RR)
ONLINE = 1
.endif
.ifndef PIT_K
PIT_K = 2               ; logic slots per drawing pass (one per car)
.endif

; zero page the game never uses (checked with VICE watchpoints in a race)
pit_due  = $E4          ; frames counted by the IRQ, not yet run as slots
pit_car  = $FB          ; the car of this slot (was $17)
pit_oth  = $FC          ; the other car (was $16)

; =============================================================================
; Entry, called by the framework's unpacker: low memory back as it was at the
; snapshot (the unpacker used $0200-$03BF), then the game. $E000-$E4FF is
; empty at the entry; the game's init fills it ($94FF).
; =============================================================================
        .segment "P_E000"
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
.ifdef ONLINE
        lda     #0
        sta     pit_due
        sta     pit_next
        sta     pit_passes
        sta     pit_passes+1
.endif
        jmp     GAME_START

        .segment "P_E100"
low:    .incbin "low.bin"               ; $0000-$03FF of the snapshot

.ifdef ONLINE
; =============================================================================
; Start-up: no menu screen, no menu IRQ, no names
; =============================================================================
        .segment "P_947D"
        bit     $953E                   ; was JSR $953E: the menu screen
        .segment "P_9484"
        bit     $96FC                   ; was JSR $96FC: the menu's lines
        .segment "P_948D"
        bit     $96AD                   ; was JSR $96AD
        .segment "P_9490"
        lda     #<$347C                 ; IRQ: only acknowledge (was the menu IRQ $99BC)
        .segment "P_9495"
        lda     #>$347C
        .segment "P_94AB"
        jsr     pit_menu                ; was LDA $09 / BEQ *-2: wait for "start the race"
        nop
        bit     $9A60                   ; was JSR $9A60: the drivers type their names

; race over: back to the lobby (was JMP $6D18: the menu)
        .segment "P_42B3"
        jmp     pit_over

; race start: no "press your button"; driver 1 = port 2 (X = 0 -> $7C)
        .segment "P_4FB6"
        jmp     $4FD4
        .segment "P_4FF9"
        jmp     $5010

; =============================================================================
; The raster IRQ keeps only the display
; =============================================================================
        .segment "P_37A1"
        .res    5, $EA                  ; was LDA #0 / STA $61E4,X (now in pit_slot)
        .segment "P_37AB"
        .res    3, $EA                  ; was STA $0050,Y (the AND before sets the flags)
        .segment "P_3FC9"
        .res    3, $EA                  ; was STA $620B,X: the logic reads it (pit_slot)
        .segment "P_380A"
        inc     pit_due                 ; was LDA $621B / BEQ: the logic of this frame
        jmp     $3753                   ; is a slot for the main loop; restore, RTI

; the logic block ($3835 .. RTI $3EC9) reads our car numbers, not the IRQ's
        .segment "P_3835"
        ldx     pit_car
        .segment "P_38CB"
        ldx     pit_car
        .segment "P_38D0"
        ldx     pit_car
        .segment "P_3C8E"
        ldx     pit_car
        .segment "P_3CCA"
        ldx     pit_car
        .segment "P_3DA3"
        ldx     pit_car
        .segment "P_4A00"
        ldx     pit_car                 ; (in $498A, called from the logic)
        .segment "P_3D8E"
        ldy     pit_oth
        .segment "P_3DCB"
        ldx     pit_oth

; the joystick reads in the logic: the inputs of this pass
        .segment "P_387A"
        lda     pit_in                  ; was LDY $7C / LDA $DC00,Y / STA $03D2 /
        sta     $03D2                   ;     TYA / EOR #1 / TAY / LDA $DC00,Y / STA $03D3
        lda     pit_in+1
        sta     $03D3
        ldy     #1                      ; (as the original leaves it: $7C ^ 1)
        .res    4, $EA

; the main loop: every drawing pass starts with the logic slots
        .segment "P_41A0"
        jsr     pit_pass                ; was LDA $61E3 (pit_pass does it at the end)

; main code that waits for the logic counter $04 (incremented in car 0's slot)
; now runs the slots itself
        .segment "P_5077"
        jsr     pit_while04             ; was CMP $04 / BEQ *-2 (start countdown)
        nop
        .segment "P_7C74"
        jsr     pit_until04             ; was CMP $04 / BNE *-2 (pit stop: one tick)
        nop

; =============================================================================
; New code, in the menu and title code ($9C87-$9FFF), which online never runs
; =============================================================================
        .segment "PIT"

pit_next:       .byte   0               ; car of the next slot
pit_passes:     .word   0               ; car 0 slots (the ticks of the lockstep)
pit_tmp:        .byte   0
pit_in:         .byte   $7F, $7F        ; joystick of driver 1 (port 2) and driver 2
pit_local:      .byte   1               ; 1: no session (both joysticks here)

; --- set the session's options instead of the menu --------------------------
; (here, after the game's own init: it sets up the CIAs, which the WiC64 uses)
pit_menu:
        lda     #1
        sta     $039E                   ; two drivers
        lda     #0
        sta     $03A0                   ; three laps
        sta     $03A1                   ; rookie
.ifdef DETTEST
        sta     $039F                   ; track 1
        sta     pit_local
.else
        jsr     net_start               ; C=1: no handoff, a local game
        lda     #0
        rol     a
        sta     pit_local
        lda     #0
        bcs     @track                  ; local: track 1
        lda     net_hb+HB_SEED          ; the session's track, 0-6: seed mod 7
:       cmp     #7
        bcc     @track
        sbc     #7
        jmp     :-
@track: sta     $039F
.endif
        rts

; --- once per drawing pass (main loop, $41A0) ----------------------------------
; The frame handler runs once per screen half (twice a frame): pit_due counts
; those, as the original ran one logic slot (one car) per half.
pit_pass:
:       lda     pit_due                 ; not faster than the original: one
        cmp     #PIT_K                  ; slot per screen half
        bcc     :-
        lda     #0                      ; (slower: no catching up, the same on
        sta     pit_due                 ; every machine)
        ldx     #PIT_K
@slots: txa
        pha
        jsr     pit_next_slot
        pla
        tax
        dex
        bne     @slots
        lda     $61E3                   ; the instruction this replaced
        rts

; --- one slot, paced (one per frame) -------------------------------------------
pit_run1:
:       lda     pit_due
        beq     :-
        dec     pit_due
pit_next_slot:
        lda     pit_next
        jsr     pit_slot
        lda     pit_next
        eor     #1
        sta     pit_next
        rts

; --- waits on the logic counter $04 ----------------------------------------------
pit_while04:                            ; A = $04 before: slots while it is unchanged
        sta     pit_tmp                 ; (X and Y are the caller's counters)
        txa
        pha
        tya
        pha
:       jsr     pit_run1
        lda     $04
        cmp     pit_tmp
        beq     :-
        jmp     pit_xy

pit_until04:                            ; A = the value $04 must reach
        sta     pit_tmp
        txa
        pha
        tya
        pha
:       lda     $04
        cmp     pit_tmp
        beq     pit_xy
        jsr     pit_run1
        jmp     :-
pit_xy: pla
        tay
        pla
        tax
        rts

; --- one logic slot for car A, as the IRQ ran it -----------------------------
pit_slot:
        sta     pit_car
        eor     #1
        sta     pit_oth
        lda     pit_car                 ; car 0: the joysticks are read in this
        bne     @no_tick                ; slot ($387A): the tick of the lockstep
.ifdef DETTEST
        jsr     dt_step
.else
        lda     pit_local
        beq     @net
        lda     $DC00                   ; local: as the original, driver 1 on
        sta     pit_in                  ; port 2, driver 2 on port 1
        lda     $DC01
        sta     pit_in+1
        jmp     @tick
@net:   jsr     net_step                ; slot 0 drives car 1 (top half)
        lda     net_keys
        and     #$40                    ; Q: the session ends
        beq     :+
        lda     #<END_QUIT
        jmp     net_end
:       lda     net_in0                 ; joystick bits 0-4 (active low), the
        ora     #$E0                    ; rest as $DC00 reads them
        sta     pit_in
        lda     net_in1
        ora     #$E0
        sta     pit_in+1
@tick:
.endif
        inc     pit_passes
        bne     @no_tick
        inc     pit_passes+1
@no_tick:
        ldx     #1                      ; $620B,X from $70,X, as the display IRQ
@steer: lda     #0                      ; did it ($3FB4); the logic reads it
        ldy     $70,x
        cpy     #2
        bmi     :+
        lda     #1
:       cpy     #$FD
        bpl     :+
        lda     #2
:       sta     $620B,x
        dex
        bpl     @steer
        ldx     pit_car                 ; moved from the IRQ ($37A1, $37AB)
        lda     #0
        sta     $61E4,x
        ldy     pit_oth
        lda     $0050,y
        and     #$7F
        sta     $0050,y
        lda     #>@back                 ; the logic block ends with RTI: a frame
        pha                             ; as an interrupt would leave it
        lda     #<@back
        pha
        php
        jmp     $3835
@back:  rts

; --- the race is over (interrupts are off: the screen stays) ----------------------
pit_over:
.ifndef DETTEST
        lda     pit_local
        beq     :+
.endif
        jmp     $6D18                   ; local: the start-up again, a new race
.ifndef DETTEST
:       ldx     #150                    ; 3 s (PAL; NTSC 2.5 s)
@frame: jsr     net_idle
        lda     $D012
        cmp     #$F8
        bne     @frame
:       lda     $D012
        cmp     #$F8
        beq     :-
        dex
        bne     @frame
        lda     #<END_GAMEOVER
        jmp     net_end
.endif

; --- test bot (DETTEST) ---------------------------------------------------------
.ifdef DETTEST
dt_rng:         .byte   $35, $A7

dt_step:
.ifdef HALT_AT
        lda     pit_passes
        cmp     #<HALT_AT
        bne     :+
        lda     pit_passes+1
        cmp     #>HALT_AT
        bne     :+
pit_halt:
        jmp     pit_halt                ; tools/dettest.py saves the RAM here
:
.endif
        lda     pit_passes              ; new joystick positions every 4 passes
        and     #3
        bne     @keep
        ldx     #1
@bot:   lda     dt_rng,x                ; LFSR per driver
        asl     a
        bcc     :+
        eor     #$1D
:       sta     dt_rng,x
        and     #$0F                    ; directions; fire (the gear) now and then
        ora     #$70
        cmp     #$7C                    ; (no left+right / up+down: as $7F)
        bcs     :+
        ora     #$10
:       sta     pit_in,x
        dex
        bpl     @bot
@keep:
.ifdef JITTER                           ; wait 0-3 whole frames, as a network
        lda     $D012                   ; would (with interrupts on: we are in
        eor     pit_passes              ; the main loop now)
        and     #3
        tax
        beq     @nowait
@frame: lda     $D012
        cmp     #$10
        bne     @frame
:       lda     $D012
        cmp     #$10
        beq     :-
        dex
        bne     @frame
@nowait:
.endif
        rts
.endif
.endif ; ONLINE
