; ============================================================================
; BB-LAN - deterministic tick core
; ============================================================================
; Only assembled with -D BBLAN=1 (tools/build.py default build).
;
; The original game ran part of its logic inside the raster IRQ (frame
; counter, second timers, and every odd frame the player/sprite state machine
; D_1CBD). How often that ran relative to the 25 Hz main loop depended on
; CPU time, which makes lockstep play impossible.
;
; BB-LAN makes game time virtual:
;   - the IRQ only counts real frames (bb_rframe) and does display + sound
;   - every place that waited for the frame counter now calls vframe, which
;     advances ONE logical frame: timers, frame counter ($08) and on odd
;     frames the work the IRQ used to do (D_1805, D_1B40, D_1CBD)
;   - vframe is paced against real frames, so the game keeps its speed, but
;     the logic sequence no longer depends on how long anything takes
;
; All hooks into the original code are same-size patches (BB_PATCH_END in
; master.s): no byte of the original game may move.
;
; One "tick" = one odd logical frame (25 Hz). At every tick bb_sample
; fetches the input for both players into bb_in0/bb_in1/bb_key; all game
; code reads input from there, never from the CIA directly.
;
; Build options:
;   DETTEST=1   built-in bot drives both players, checksum logged every
;               64 ticks (tools/dettest.py)
;   JITTER=1    (with DETTEST) burn a random number of cycles every frame
;               and random title time, to prove timing does not matter
;   BOT_SEED=n  (with DETTEST) other bot behaviour
;   PREGAME=1   (with DETTEST) play and quit another game first, to prove
;               leftovers from an earlier game do not matter
; ============================================================================

.segment "BBLAN_CODE"

.export bb_rframe, bb_tick, bb_minsp

; --- State ---------------------------------------------------------------
bb_rframe:      .byte   0               ; real frames, incremented by the IRQ
bb_vseen:       .byte   0               ; real frames consumed by vframe
bb_depth:       .byte   0               ; >0 while vframe runs tick logic
bb_in0:         .byte   $7F             ; Bub joystick (as read from $DC00)
bb_in1:         .byte   $FF             ; Bob joystick (as read from $DC01)
bb_key:         .byte   $FF             ; keyboard row 7 (pause/quit/title)
bb_tick:        .word   0               ; ticks since game start
bb_seed:        .byte   $5A, $C3        ; PRNG seed applied at game start
bb_minsp:       .byte   $FF             ; DETTEST: lowest SP seen in vframe

.ifndef DETTEST
.include "bbnet.s"
.segment "BBLAN_CODE"
.endif

MAX_CATCHUP     = 4                     ; real frames we may run behind

; ============================================================================
; bb_irq - rest of irq_frame_update (irq-handlers.s jumps here)
; Counts a real frame. Keeps D_077C a JMP so the split IRQ never runs D_1CBD;
; the two other self-modified jumps are reset as before.
; ============================================================================
bb_irq:
        inc     bb_rframe
        lda     #$4C                    ; JMP opcode
        sta     D_077C
        sta     D_0768
        sta     D_0786
        jmp     L_06F0                  ; sound, colours, next raster IRQ

; ============================================================================
; bb_wait2 - main loop end (game-loop.s): advance logical frames until the
; frame counter is neither the snapshot D_0A5D nor D_0A61, then continue
; after the original wait loop.
; ============================================================================
bb_wait2:
        pla                             ; called with JSR; never return there
        pla
.ifdef DETTEST                          ; test: real frames per pass
        lda     bb_rframe
        sec
        sbc     det_rf
        ldx     bb_rframe
        stx     det_rf
        and     #15
        tax
        inc     det_hist,x
.endif
@loop:  lda     ENDCHR
        cmp     D_0A5D
        beq     @adv
        cmp     D_0A61
        bne     @done
@adv:   jsr     vframe
        jmp     @loop
@done:  jmp     bb_wf_after

; ============================================================================
; bb_sound_start - end of D_05AD (start song Y). The original relied on the
; frame wait to keep the IRQ's sound_update away; a logical frame is no real
; frame boundary, so hold the IRQ off explicitly.
; ============================================================================
bb_sound_start:
        php
        sei
        sty     D_5C3F
        jsr     music_start
        jsr     sound_update
        plp
        rts

; ============================================================================
; bb_boot_title - in place of the boot title's "jsr wait_one_frame": in a
; session (and in DETTEST) skip the title, which waits for fire.
; ============================================================================
bb_boot_title:
.ifndef DETTEST
        lda     bb_hb+HB_DRIVER
        bne     :+
        jmp     wait_one_frame
:
.endif
        pla                             ; leave the title loop
        pla
        jmp     L_45A1

; ============================================================================
; bb_title - in place of "jsr D_A5A0" at the title screen (D_F005). After a
; session game (game over or quit) the session ends here.
; ============================================================================
bb_title:
.ifndef DETTEST
        lda     ls_on
        beq     :+
        lda     #END_GAMEOVER
        jmp     bb_end
:
.endif
        jmp     D_A5A0

bb_sound_init:
        php
        sei
        jsr     sound_init
        plp
        rts

; ============================================================================
; vframe - advance one logical frame (replaces wait_one_frame)
; Preserves A, X, Y and $01.
; ============================================================================
vframe:
.ifdef DETTEST
        php                             ; test: track deepest stack use
        pha
        txa
        tsx
        cpx     bb_minsp
        bcs     @sp
        stx     bb_minsp
@sp:    tax
        pla
        plp
.endif
        pha
        txa
        pha
        tya
        pha
        lda     R6510
        pha
        lda     #$35
        sta     R6510
        cld

.ifdef JITTER
        lda     CIA1_TALO               ; real time: differs per run
        and     #$7F
        tax
@jit:   dex
        bne     @jit
  .if JITTER = 2
        ; like a network wait: now and then stall 1-7 real frames
        lda     CIA1_TALO
        and     #$0F
        bne     @nost
        lda     CIA1_TALO
        and     #$07
        tax
        beq     @nost
@stall: lda     bb_rframe
:       cmp     bb_rframe
        beq     :-
        dex
        bne     @stall
@nost:
  .endif
.endif

        ; --- pacing: one real frame per logical frame, catch up if behind
@wait:  lda     bb_rframe
        sec
        sbc     bb_vseen
        beq     @wait
        cmp     #MAX_CATCHUP + 1
        bcc     @paced
        ldx     bb_rframe               ; too far behind: drop real frames
        dex
        stx     bb_vseen
@paced: inc     bb_vseen

        ; --- per-frame timers (was irq_frame_update)
        lda     TXTTAB
        bmi     @frame
        dec     TXTTAB
        bne     @frame
        lda     #$32                    ; 50 frames = 1 second
        sta     TXTTAB
        dec     ZP_2A
        lda     D_A9B1
        beq     @hurry
        bmi     @hurry
        dec     D_A9B1
@hurry: dec     ZP_5D
        dec     ZP_5E
@frame: inc     ENDCHR

        ; --- odd frame = tick
        lda     ENDCHR
        and     #$01
        beq     @done
        lda     bb_depth                ; nested call from tick logic:
        bne     @done                   ; time only, no second tick
        inc     bb_depth
        jsr     bb_sample
        lda     MEMSIZ                  ; game running?
        beq     @untick
        jsr     D_1805                  ; sprite positions/pointers
        lda     OPMASK
        beq     @noitem
        jsr     D_1B40
@noitem:
        lda     ZP_20                   ; split screen: IRQ skipped D_1CBD
        bne     @untick
        jsr     D_1CBD                  ; player/sprite state machine
@untick:
        dec     bb_depth
@done:
        pla
        sta     R6510
        pla
        tay
        pla
        tax
        pla
        rts

; ============================================================================
; bb_sample - fetch this tick's input for both players
; ============================================================================
bb_sample:
        inc     bb_tick
        bne     @t
        inc     bb_tick+1
@t:
.ifdef DETTEST
        jmp     bot_input
.else
.ifndef NETBOT
        lda     bb_hb+HB_DRIVER
        beq     @local
.endif
        lda     ls_on
        beq     @title
        jmp     net_tick                ; in a session: lockstep
@title: lda     #$7F                    ; session not started yet: the title
        sta     bb_in0                  ; starts a 2-player game at once
        lda     #$FF
        sta     bb_in1
        lda     #$F7                    ; key "2"
        sta     bb_key
        rts
.ifndef NETBOT                          ; (test builds only play sessions)
@local: lda     #$7F                    ; same reads as the original D_1CBD
        sta     CIA1_PRA
        ldx     #$FF
        stx     CIA1_PRB
        lda     CIA1_PRA
        sta     bb_in0
        lda     CIA1_PRB                ; port 1 + keyboard row 7
        sta     bb_in1
        sta     bb_key
        rts
.endif
.endif

; ============================================================================
; bb_game_start - called when a game starts from the title screen, in place
; of the original "inc SUBFLG / inc D_5AFF". Gives both machines the same
; starting state.
; ============================================================================
bb_game_start:
        jsr     bb_game_init
        inc     SUBFLG                  ; the two original instructions
        inc     D_5AFF
        rts

bb_game_init:
.ifdef JITTER
        lda     CIA1_TALO               ; random title time
        and     #$1F
        tax
@title: jsr     vframe
        dex
        bne     @title
.endif
.ifdef START_LEVEL
        lda     #START_LEVEL - 2        ; test: title code increments it
        sta     SUBFLG
.endif
.ifndef DETTEST
        lda     bb_hb+HB_DRIVER         ; session: seed etc. from the server
        beq     :+
        jsr     bb_net_start
:
.endif
        lda     bb_seed
        sta     RESHO
        lda     bb_seed+1
        sta     $27
        lda     #$00
        sta     ENDCHR
        sta     bb_tick
        sta     bb_tick+1
.ifdef DETTEST
        lda     #<BOT_SEED
        sta     bot_rng
        lda     #>BOT_SEED
        sta     bot_rng+1
  .ifdef PREGAME
        ; First game: other seed, quit (RUN/STOP) after a random time.
        ; The measured game is the one after it, so it starts from a
        ; machine that has already played - like in a real LAN session.
        lda     det_games
        bne     @real
        inc     det_games
        lda     RESHO
        eor     #$FF
        sta     RESHO
        lda     CIA1_TALO
        and     #$03
        ora     #$02
        sta     det_quit_hi             ; quit after 512..1279 ticks
        jmp     bb_game_inited
@real:  inc     det_games
  .endif
        lda     det_on                  ; log from the measured game on
        bne     @logging
        sta     det_n
        inc     det_on
@logging:
.endif
bb_game_inited:                         ; tools/startdiff.py breaks here
        rts

; ============================================================================
; DETTEST: bot input + checksum log
; ============================================================================
.ifdef DETTEST

.export det_n, det_lo, det_hi, det_hist

.ifndef BOT_SEED
BOT_SEED        = $ACE1
.endif
DET_EVERY       = 64                    ; ticks between checksums
DET_MAX         = 200                   ; log entries (tools/dettest.py)

bot_rng:        .word   BOT_SEED
bot_dir:        .byte   0, 0            ; current direction mask per player
det_n:          .byte   0
det_lo:         .res    DET_MAX
det_hi:         .res    DET_MAX
det_s1:         .byte   0
det_rf:         .byte   0
det_hist:       .res    16              ; real frames per main loop pass
det_games:      .byte   0               ; PREGAME: games started
det_on:         .byte   0               ; logging started
det_quit_hi:    .byte   0               ; PREGAME: quit at this tick/256
det_s2:         .byte   0

; 16-bit Galois LFSR, advanced only by the bot -> depends on tick count only
bot_rand:
        lsr     bot_rng+1
        ror     bot_rng
        bcc     @r
        lda     bot_rng+1
        eor     #$B4
        sta     bot_rng+1
@r:     lda     bot_rng
        rts

; Directions (active high here): up=1 down=2 left=4 right=8 fire=$10
bot_dirs:
        .byte   $00, $04, $08, $01, $05, $09, $04, $08

bot_input:
        ldx     #$01
@pl:    lda     bb_tick
        and     #$07                    ; new direction every 8 ticks
        bne     @keep
        jsr     bot_rand
        and     #$07
        tay
        lda     bot_dirs,y
        sta     bot_dir,x
@keep:  jsr     bot_rand
        and     #$03                    ; fire 1 tick in 4
        bne     @nofire
        lda     #$10
        .byte   $2C                     ; BIT abs: skip next
@nofire:
        lda     #$00
        ora     bot_dir,x
        eor     #$FF                    ; joystick bits are active low
        and     bot_idle,x
        sta     bb_in0,x
        dex
        bpl     @pl
        lda     #$F7                    ; title: start a 2-player game
.ifdef PREGAME
        ldx     det_games
        dex
        bne     @play                   ; only during the first game
        ldx     bb_tick+1
        cpx     det_quit_hi
        bcc     @play
        ldx     #$FF                    ; quit once
        stx     det_quit_hi
        lda     #$BF                    ; RUN/STOP
@play:
.endif
        sta     bb_key

        lda     det_on
        beq     @nolog
        lda     bb_tick
        and     #DET_EVERY - 1
        bne     @nolog
        ldx     det_n
        cpx     #DET_MAX
        bcs     @nolog
        jsr     det_checksum
        ldx     det_n
        lda     det_s1
        sta     det_lo,x
        lda     det_s2
        sta     det_hi,x
        inc     det_n
@nolog: rts

bot_idle:
        .byte   $7F, $FF                ; idle values of D_85E8 / D_85E9

; Fletcher-16 over the game state
det_checksum:
        lda     #$00
        sta     det_s1
        sta     det_s2
        ldy     #$00
@range: lda     det_rng_lo,y
        sta     @ld+1
        lda     det_rng_hi,y
        sta     @ld+2
        ldx     det_rng_len,y
@ld:    lda     $FFFF
        clc
        adc     det_s1
        sta     det_s1
        clc
        adc     det_s2
        sta     det_s2
        inc     @ld+1
        bne     @nc
        inc     @ld+2
@nc:    dex
        bne     @ld
        iny
        cpy     #DET_RANGES
        bne     @range
        rts

; start, length (0 = 256)
.define DET_START $0010, $0026, $002A, $005D, $00B2, $014B, $0400, $8480, $8580, $8680, $8780, $8880, $A824, $A9B1
.define DET_LEN   1,     2,     4,     2,     $46,   $5C,   $5C,   0,     0,     0,     0,     $80,   2,     1
det_rng_lo:     .lobytes DET_START
det_rng_hi:     .hibytes DET_START
det_rng_len:    .byte    DET_LEN
DET_RANGES      = * - det_rng_len

.endif ; DETTEST
