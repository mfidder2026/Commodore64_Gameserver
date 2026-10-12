; =============================================================================
; Pitstop II OME - patches to the original RAM image
; (orig/pitstop2-9403.bin: the RAM when the tape version's boot chain jumps
; into the game, JMP $9403). framework/tools/imagebuild.py places every
; segment P_xxxx at $xxxx; src/areas.json lists where patches may go.
; =============================================================================

        .import net_hb
        .export game_entry

GAME_START = $9403      ; the game's own start: SEI, $01 = $25, stack, zero page ...

; Entry, called by the framework's unpacker: low memory back as it was at the
; snapshot (the unpacker used $0200-$03BF), then the game.
        .segment "P_E000"               ; (rewritten by the game's init, $94FF)
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
        jmp     GAME_START

.ifdef DETTEST
; ---- test build only (tools/dettest.py): a race starts at once, a bot drives ----
; menu: the main program waits here (LDA $09 / BEQ *-2) until the menu IRQ
; sets $09 ("start the race"); online, the session's options are set instead
        .segment "P_94AB"
        jsr     pit_menu
        nop
        bit     $9A60                   ; was JSR $9A60: the drivers type their names

; the start of the race: whoever presses the button first becomes driver 1
; (top half, $7C = his port). Online: slot 0 = port 2 = driver 1, no waiting.
        .segment "P_4FB6"
        jmp     $4FD4                   ; (X = 0: driver 1 is port 2)
        .segment "P_4FF9"
        jmp     $5010                   ; driver 2 does not have to press either

; the race logic (raster IRQ, every other frame): the joystick reads become
; the tick. Original: $03D2 = port $7C, $03D3 = the other port; Y = $7C ^ 1.
        .segment "P_387A"
        jsr     pit_tick                ; was LDY $7C / LDA $DC00,Y / STA $03D2 /
        jmp     $388C                   ;     TYA / EOR #1 / TAY / LDA $DC00,Y / STA $03D3
        .res    12, $EA

; test code in the name entry routine ($9AB9-), which this flow never runs
        .segment "P_9AB9"
pit_tick:
        php
        sei
.ifdef HALT_AT
        lda     dt_tick
        cmp     #<HALT_AT
        bne     :+
        lda     dt_tick+1
        cmp     #>HALT_AT
        bne     :+
pit_halt:
        jmp     pit_halt                ; tools/dettest.py saves the RAM here
:
.endif
        lda     dt_tick                 ; new joystick positions every 8 ticks
        and     #7
        bne     @keep
        ldx     #1
@bot:   lda     dt_rng,x                ; LFSR per driver
        asl     a
        bcc     :+
        eor     #$1D
:       sta     dt_rng,x
        and     #$1F
        ora     #$10                    ; (fire rarely: it is the gear shift)
        sta     dt_in,x
        dex
        bpl     @bot
        lda     dt_rng
        and     #$60
        bne     @keep
        lda     dt_in                   ; now and then fire on driver 1
        and     #$0F
        sta     dt_in
@keep:
.ifdef JITTER                           ; wait 0-2 whole frames plus some lines,
        lda     $D012                   ; as a network would (with interrupts
        eor     dt_tick                 ; off, as net_step will)
        and     #$27
        tax
        beq     @nowait
@line:  lda     $D012
:       cmp     $D012
        beq     :-
        dex
        bne     @line
@nowait:
.endif
        inc     dt_tick
        bne     :+
        inc     dt_tick+1
:       lda     dt_in                   ; driver 1 (slot 0, port 2) = $03D2
        sta     $03D2
        lda     dt_in+1
        sta     $03D3
        ldy     #1                      ; (as the original leaves it: $7C ^ 1)
        plp
        rts
dt_tick:        .word   0
dt_rng:         .byte   $35, $A7
dt_in:          .byte   $7F, $7F
.endif

.ifdef DETTEST
        .segment "NET"
pit_menu:
        lda     #1
        sta     $039E                   ; two drivers
        lda     #0
        sta     $039F                   ; track: Brands Hatch
        sta     $03A0                   ; three laps
        sta     $03A1                   ; rookie
        lda     #1
        sta     $09                     ; "start the race"
        rts
.endif

        .segment "P_E100"
low:    .incbin "low.bin"               ; $0000-$03FF of the snapshot
