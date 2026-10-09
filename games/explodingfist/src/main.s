; =============================================================================
; The Way of the Exploding Fist OME - patches to the original RAM image
; (orig/fist-1158.bin, the RAM the original loader leaves at JMP $1158).
; Every segment P_xxxx is placed at $xxxx by tools/build.py; other segments
; get their address from src/areas.json, which also lists every area a patch
; may touch.
;
; Online: the lobby (framework/c64/lobby) loads this game with a handoff
; block; the session runs the original two-player match ($161D: four bouts)
; with both joysticks fed by the lockstep (framework/c64/net/net.s), then
; goes back to the lobby. Without a handoff the original game runs
; (attract mode, one or two players on one C64).
;
; Build options: NET_UCI / NET_RR / NET_WIC (the network driver), DETTEST
; (no network: a bot plays both fighters, for tools/dettest.py), HALT_AT=n
; (stop before tick n), JITTER (random waits per tick, DETTEST only).
; =============================================================================

        .import net_hb, net_start, net_step, net_idle, net_end
        .import net_in0, net_in1, net_keys, net_tick, net_flag2
        .export fist_entry

HB_SEED   = 5           ; offset in the handoff block (net.s)

SNAP_SP   = $F6         ; stack pointer at the snapshot ($01 was $36)

; --- the original game ---------------------------------------------------------
GAME_INIT   = $1601     ; start: JSR $1414 (hardware), JMP $19A7 (outer loop)
HW_INIT     = $1414     ; vectors, raster IRQ, VIC, CIA set-up; seeds RNG $8E
SHOW_MODE1  = $1BC3     ; mode texts from $A3 (0 one player, 1 two players)
SHOW_MODE2  = $1C34
MATCH_2P    = $161D     ; two-player match, 4 bouts; N=1 when it was aborted
KEYS        = $1948     ; F1/F3/F5/F7 (F5 aborts a game), fire starts one
JOY_DONE    = $227F     ; input routine after the joystick read: AND #$1F ...
NMI_EFFECT  = $28AA     ; NMI: PHA, $D021 = yellow (the floor), PLA, RTI
MODE        = $A3       ; 0 one player, 1 two players
RNG         = $8E       ; LFSR (shift left, EOR #$1D), stepped once a tick

; =============================================================================
; Entry, called by the framework's unpacker. The unpacker lives in
; $0200-$03BF and the lobby left its own zero page, so first the low memory
; ($0002-$03FF) comes back as it was at the snapshot: every machine starts
; from exactly the same state. $C000-$C03E is cleared by the game's init
; ($1608), $C100-$C4FF belongs to the fighter build buffers that the game
; writes before it reads them, so both may be used until the game starts.
; =============================================================================
        .segment "P_C000"
fist_entry:
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
        ldx     #SNAP_SP
        txs
        lda     #$35                    ; RAM at $E000: our code is under the KERNAL
        sta     $01
        jmp     fist_start

        .segment "P_C100"
low:    .incbin "low.bin"               ; $0000-$03FF of the snapshot (tools/build.py)

; =============================================================================
; Patches in the original code (same size)
; =============================================================================

; bout loop: the raster wait at the start of every pass becomes the tick
        .segment "P_15AA"
        jsr     fist_tick               ; was LDA $D012 / CMP #$FD / BCC *-5
        nop
        nop
        nop
        nop

; bout loop: the keyboard (F5 aborts) becomes the network's quit key online
        .segment "P_15C4"
        jsr     fist_keys               ; was JSR $1948

; input routine: the joystick read becomes the tick's input of this fighter
        .segment "P_2270"
        lda     fist_joy,x              ; was LDA #0 / STA $DC02 / LDA $DC00,X /
        jmp     JOY_DONE                ;     PHA / LDA #$FF / STA $DC02 / PLA
        .res    9, $EA

; waits without ticks between bouts (fighters walk back, the judge): online,
; the network is kept alive meanwhile
        .segment "P_191C"
        jsr     fist_wait_fe            ; was LDA $D012 / CMP #$FE / BCC *-5
        nop
        nop
        nop
        nop
        .segment "P_193C"
        jsr     fist_wait_fe            ; was LDA $D012 / CMP #$FE / BCC *-5
        nop
        nop
        nop
        nop
        .segment "P_1C79"
        jsr     fist_frame              ; was: wait for raster $FE, then wait
        .res    11, $EA                 ; until it has passed (one frame)

; NMI (CIA2 timer B, the floor colour): keep the WiC64's handshake bit
        .segment "P_28A5"
        jmp     fist_nmi                ; was BIT $DD0D / BPL rti

; =============================================================================
; New code, in the floor rows of the bitmap ($F540-$FF3F): they are yellow on
; yellow (screen and colour RAM $77, $1445), so their bytes are never seen,
; and the game does not read or write them (checked with VICE watchpoints).
; =============================================================================
        .segment "FIST"

fist_online:    .byte   0               ; 1 in a session (or a DETTEST run)
fist_joy:       .byte   $1F, $1F        ; joystick bits of fighter 0 and 1 for this tick
fist_icr:       .byte   0

; --- after the entry: a session, or the original game ----------------------
fist_start:
.ifndef DETTEST
        jsr     net_start
        bcc     :+
        jmp     GAME_INIT               ; no handoff: the original game (it sets $01
:                                       ; itself; $36 here would switch the KERNAL
                                        ; in under this code)
.endif
        jsr     HW_INIT
.ifdef DETTEST
        lda     #$53                    ; the original seed
.else
        lda     net_hb+HB_SEED          ; the session's seed (both machines)
        bne     :+
        lda     #$53                    ; an LFSR state of 0 would stay 0
:
.endif
        sta     RNG
        lda     #1
        sta     MODE                    ; two players
        sta     fist_online
        jsr     SHOW_MODE1
        jsr     SHOW_MODE2
        jsr     MATCH_2P                ; four bouts
.ifdef DETTEST
dt_done:
        jmp     dt_done                 ; the match is over (tools/dettest.py)
.else
        bmi     :+
        lda     #1                      ; END_GAMEOVER
        jmp     net_end
:       lda     #5                      ; END_QUIT: a player pressed Q
        jmp     net_end
.endif

; --- once per pass of the bout loop -----------------------------------------
; First the original wait for raster line $FD (the pace of the game), then the
; inputs: a short wait for the network then costs a few lines of the vertical
; blank, not a whole frame.
fist_tick:
:       lda     $D012
        cmp     #$FD
        bcc     :-
        lda     fist_online
        beq     @local
.ifdef DETTEST
        jmp     dt_step
.else
        jsr     net_step                ; slot 0 plays fighter 0 (white, left)
        lda     net_in0
        and     #$1F
        sta     fist_joy
        lda     net_in1
        and     #$1F
        sta     fist_joy+1
        rts
.endif
@local: lda     #0                      ; the original read, both ports
        sta     $DC02
        lda     $DC00
        and     #$1F
        sta     fist_joy
        lda     $DC01
        and     #$1F
        sta     fist_joy+1
        lda     #$FF
        sta     $DC02
        rts

; --- waits without ticks ------------------------------------------------------
fist_wait_fe:                           ; until raster line $FE or below the screen
        jsr     fist_idle
        lda     $D012
        cmp     #$FE
        bcc     fist_wait_fe
        rts

fist_frame:                             ; until line $FE, then until it has passed
:       jsr     fist_idle
        lda     $D012
        cmp     #$FE
        bne     :-
:       jsr     fist_idle
        lda     $D012
        cmp     #$FE
        beq     :-
        rts

fist_idle:
.ifndef DETTEST
        lda     fist_online
        beq     :+
        jmp     net_idle
:
.endif
        rts

; --- the keyboard in the bout loop -------------------------------------------
fist_keys:
        lda     fist_online
        bne     :+
        jmp     KEYS                    ; the original (F5 aborts the game)
:
.ifndef DETTEST
        lda     net_keys                ; Q of either player ends the match
        and     #$40
        beq     :+
        lda     #$80                    ; N=1: as F5 in the original
        rts
:
.endif
        lda     #0
        rts

; --- NMI ---------------------------------------------------------------------
fist_nmi:
        pha
        lda     $DD0D                   ; (reading it clears the WiC64's FLAG2 bit:
        sta     fist_icr                ; keep that for the driver)
        and     #$10
        ora     net_flag2
        sta     net_flag2
        lda     fist_icr
        bmi     :+
        pla
        rti
:       pla
        jmp     NMI_EFFECT

; --- determinism test: a bot plays both fighters --------------------------
.ifdef DETTEST
dt_tick:        .word   0
dt_rng:         .byte   $35, $A7

dt_step:
.ifdef HALT_AT
        lda     dt_tick
        cmp     #<HALT_AT
        bne     :+
        lda     dt_tick+1
        cmp     #>HALT_AT
        bne     :+
dt_halt:
        jmp     dt_halt                 ; tools/dettest.py saves the RAM here
:
.endif
        lda     dt_tick                 ; new joystick positions every 8 ticks
        and     #7
        bne     @keep
        ldx     #1
@bot:   lda     dt_rng,x                ; LFSR per fighter
        asl     a
        bcc     :+
        eor     #$1D
:       sta     dt_rng,x
        and     #$1F
        sta     fist_joy,x
        dex
        bpl     @bot
@keep:
.ifdef JITTER                           ; wait 0-3 whole frames every tick, as a
        lda     $D012                   ; network would (and differently on each
        eor     dt_tick                 ; machine)
        and     #3
        tax
        beq     @nowait
@frame: lda     $D012                   ; one frame: to line $10, then past it
        cmp     #$10
        bne     @frame
:       lda     $D012
        cmp     #$10
        beq     :-
        dex
        bne     @frame
@nowait:
.endif
        inc     dt_tick
        bne     :+
        inc     dt_tick+1
:       rts
.endif
