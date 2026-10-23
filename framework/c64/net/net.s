; ============================================================================
; Framework: in-game network for lockstep games (ca65)
; ============================================================================
; The standard lobby (framework/c64/lobby) finds the hardware, connects to the
; server and runs the lobby. When the server starts a session it writes a
; handoff block to $03C0 and loads the game; the framework's unpacker copies
; the block into net_hb (pack.py's hb_addr). Without a valid block the game
; runs locally.
;
; In a session both C64s run the complete game in lockstep. The game calls
; net_step once per tick; it sends the local input for tick+delay to the
; server, which relays it to the other player, and returns when the other
; player's input for this tick is there. net_in0/net_in1 then hold the
; inputs of slot 0 and slot 1.
;
; INPUT ($80), 16 bytes:
;   $80, session, newest tick (16), checksum tick (16, $FFFF none),
;   checksum (16), 8 inputs for ticks newest-7..newest
; Input byte: bits 0-4 joystick (active low, as $DC00), bit 5 pause key (C=),
; bit 6 quit key (Q), both active high.
;
; The game supplies "netgame.inc" (assemble with -I games/<game>/src):
;   .define NET_LOBBY "NAME"        file name of the lobby on the disk
;   NET_WIC_SEND_EVERY = 2/4          optional: a WiC64 sends every n-th tick
;   NET_TAIL = $xxxx                 128 bytes of RAM for net_end's last part
;                                    (outside $A000-$BFFF and $D000-$FFFF,
;                                    not needed by the game after a session)
;   .define NET_CK_START a, b, ...   areas for the state checksum
;   .define NET_CK_LEN   n, m, ...   (lengths 1-256; 256 = 0)
;   NET_PLAYERS = 4                  optional: up to 4 players (default 2).
;                                    The session's players are slots 0 ..
;                                    n-1 (handoff: HB_PLAYERS); net_in0 ..
;                                    net_in3 follow each other, slots that
;                                    are not in the session stay idle. The
;                                    server relays a player's INPUT with the
;                                    type $80+slot (games with more than two
;                                    seats), so the receiver knows the sender
;   NET_BOT_PERSON = 1               optional: the test bot (NETBOT) moves like a
;                                    person: a direction, a pause, the button
;   NET_SPLIT = 1                    optional: four segments instead of one
;                                    NET, for games without 1.3 KB in one
;                                    piece: NET (the lockstep, net_hb),
;                                    NETRX (receiving, net_end), NETDRV (the
;                                    driver), NETBSS (state and buffers, never
;                                    loaded: may lie below $0400)
; and calls:
;   net_start   when a session game starts (C=1: no handoff, a local game)
;   net_step    once per tick (session only)
;   net_idle    often while the game waits without ticks (between rounds):
;               repeats the last INPUT about every 0.3 s, so the server does
;               not drop the player, and handles the end of the session
;   net_end     A = reason: back to the lobby (never returns)
;
; One driver is assembled in (a game file per hardware type):
;   NET_UCI   Ultimate 64 / C64 Ultimate: UDP through the Ultimate Command
;             Interface (socket opened by the lobby)
;   NET_WIC   WiC64: TCP to the server's port 6466 (opened by the lobby),
;             the stream carries [length][message]
;   NET_RR    RR-Net / CS8900a (VICE): raw Ethernet frames, EtherType $88B5
;
; Test options: NETBOT (a bot plays when the handoff's flag bit 0 is set),
; HALT_AT=tick (stop there, for memory comparisons).
;
; First used by The Way of the Exploding Fist; Bubble Bobble has the same
; code in games/bubblebobble/src/bbnet.s (not yet moved here).
; ============================================================================

.include "netgame.inc"

.ifndef NET_WIC_SEND_EVERY
NET_WIC_SEND_EVERY = 2                  ; 1, 2 or 4; delay + this must be <= 8
.endif
.ifndef NET_PLAYERS
NET_PLAYERS = 2
.endif

.export net_hb, net_start, net_step, net_idle, net_end
.export net_in0, net_in1, net_keys, net_tick, net_flag2, net_waited

.segment "NET"

; --- Handoff block (framework/c64/lobby/README.md) ------------------------
HB_MAGIC        = 0                     ; "BL"
HB_DRIVER       = 2                     ; 0 local, 1 UCI, 2 RR-Net, 3 WiC64
HB_SLOT         = 3
HB_SESSION      = 4
HB_SEED         = 5                     ; 2 bytes
HB_DELAY        = 7                     ; input delay in ticks (1-4)
HB_SOCKET       = 8                     ; UCI socket
HB_FLAGS        = 9                     ; bit 0: test bot plays
HB_DEVICE       = 10                    ; drive the lobby was loaded from
HB_PLAYERS      = 11                    ; bits 0-3: players in the session (START;
                                        ; 0 = 2), 4-7: a table's option
HB_DSTMAC       = 12                    ; RR-Net: server MAC
HB_MYMAC        = 18                    ; RR-Net: our MAC
HB_SIZE         = 24
.export HB_SEED, HB_SLOT, HB_PLAYERS

END_GAMEOVER    = 1
END_TIMEOUT     = 3
END_QUIT        = 5
END_LEFT        = 6                     ; OPPONENT_LEFT
.export END_GAMEOVER, END_QUIT

MSG_INPUT       = $80
MSG_OPP_LEFT    = $0A
MSG_SESSION_END = $0B
MSG_BYE         = $0E

INPUT_LEN       = 16
WINDOW          = 8                     ; inputs per packet (delay <= 4)
RING            = 16                    ; ring size (power of 2)
IDLE_INPUT      = $1F                   ; no direction, no fire, no keys

net_hb:         .res    HB_SIZE

.ifdef NET_SPLIT
.segment "NETBSS"
.endif
; --- Lockstep state -------------------------------------------------------
net_state:
net_tick:       .word   0               ; ticks played in this session
net_in0:        .byte   IDLE_INPUT      ; input of slot 0 for this tick
net_in1:        .byte   IDLE_INPUT      ; input of slot 1
.if NET_PLAYERS > 2
                .res    NET_PLAYERS-2, IDLE_INPUT ; slot 2, 3
.endif
net_keys:       .byte   0               ; key bits (5 pause, 6 quit) of all
net_flag2:      .byte   0               ; a game's NMI handler ORs $DD0D here (WiC64)
net_waited:     .word   0               ; raster wraps (2 per frame) spent waiting for the other C64
ls_lin:         .res    RING
.if NET_PLAYERS > 2
ls_rin:         .res    RING*NET_PLAYERS ; slot n at n*RING (our own unused)
ls_rnlo:        .res    NET_PLAYERS     ; newest tick received per slot
ls_rnhi:        .res    NET_PLAYERS
ls_np:          .byte   2               ; players in the session
ls_slot:        .byte   0               ; rx_input: the sender
ls_base:        .byte   0               ; rx_input: its ring
ls_diff:        .byte   0
.else
ls_rin:         .res    RING
.endif
ls_got:         .byte   0               ; 1 once the other player was heard
ls_lnew:        .word   0               ; newest local tick sent   } tx_buf+2
ls_ckt:         .word   $FFFF           ; checksum tick            } +4
ls_ck:          .word   0               ; checksum                 } +6
.if NET_PLAYERS <= 2
ls_rnew:        .word   0               ; newest remote tick received
.endif
ls_wait:        .word   0               ; raster wraps waited (2 per frame)
ls_line:        .byte   0
ls_idle:        .byte   0
ls_tmp:         .res    2
tx_buf:         .res    INPUT_LEN
NET_STATE_LEN   = * - net_state
.assert NET_STATE_LEN <= 255, lderror, "the lockstep state is too long"
.ifdef NET_SPLIT
.segment "NET"
.endif

; ============================================================================
; net_start - C=1: no handoff (a local game); else the session starts
; ============================================================================
net_start:
        lda     net_hb+HB_MAGIC
        cmp     #$42                    ; "B" "L" (ASCII)
        bne     @local
        lda     net_hb+HB_MAGIC+1
        cmp     #$4C
        bne     @local
        lda     net_hb+HB_DRIVER
        bne     :+
@local: sec
        rts
.ifdef NET_SPLIT
:       ldx     #0                      ; the state was never loaded: from 0
        txa
@zero:  sta     net_state,x
        inx
        cpx     #NET_STATE_LEN
        bne     @zero
        ldx     #NET_PLAYERS-1
        lda     #IDLE_INPUT
@idle:  sta     net_in0,x
        dex
        bpl     @idle
.endif
.if NET_PLAYERS > 2
:       ldx     #RING*NET_PLAYERS-1
        lda     #IDLE_INPUT
:       sta     ls_rin,x
        dex
        bpl     :-
        ldx     #RING-1
:       sta     ls_lin,x
        dex
        bpl     :-
        lda     net_hb+HB_PLAYERS       ; 1..NET_PLAYERS (an old lobby: 0 = 2)
        and     #15
        tax
        bne     :+
        ldx     #2
:       cpx     #NET_PLAYERS+1
        bcc     :+
        ldx     #NET_PLAYERS
:       stx     ls_np
        lda     net_hb+HB_DELAY         ; ticks 0..delay-1 are idle everywhere:
        sec                             ; tick delay-1 counts as received (the
        sbc     #1                      ; first input, net_tick 0's, is for
        sta     ls_lnew                 ; tick delay)
        lda     #0
        sbc     #0
        sta     ls_lnew+1
        ldx     #NET_PLAYERS-1
:       lda     ls_lnew
        sta     ls_rnlo,x
        lda     ls_lnew+1
        sta     ls_rnhi,x
        dex
        bpl     :-
.else
:       ldx     #RING-1
        lda     #IDLE_INPUT
:       sta     ls_lin,x
        sta     ls_rin,x
        dex
        bpl     :-
        lda     net_hb+HB_DELAY         ; ticks 0..delay-1 are idle on both sides:
        sec                             ; tick delay-1 counts as received (the
        sbc     #1                      ; first input, net_tick 0's, is for
        sta     ls_lnew                 ; tick delay)
        sta     ls_rnew
        lda     #0
        sbc     #0
        sta     ls_lnew+1
        sta     ls_rnew+1
        lda     net_hb+HB_PLAYERS       ; alone in the session (a table started
        and     #15                     ; by its host alone): never wait for
        cmp     #1                      ; the other slot, its input stays idle
        bne     :+
        lda     #$FF
        sta     ls_rnew
        sta     ls_rnew+1
:
.endif
        ldx     #0
        stx     ls_got
        stx     net_tick
        stx     net_tick+1
        stx     net_keys
        dex
        stx     ls_ckt
        stx     ls_ckt+1
        jsr     drv_init
        clc
        rts

; ============================================================================
; net_step - exchange the input for this tick (net_tick), then net_tick+1
; ============================================================================
net_step:
        lda     net_tick                ; lnew = tick + delay
        clc
        adc     net_hb+HB_DELAY
        sta     ls_lnew
        lda     net_tick+1
        adc     #0
        sta     ls_lnew+1
        jsr     read_local
        ldx     ls_lnew
        jsr     ring_x
        sta     ls_lin,x

        lda     net_tick                ; checksum every 64 ticks
        and     #63
        bne     :+
        jsr     net_checksum
:
.ifdef NET_WIC                          ; WiC64: send every NET_WIC_SEND_EVERY
        lda     net_tick                ; ticks (each transfer costs the C64
        and     #NET_WIC_SEND_EVERY-1   ; time; a packet carries 8 inputs)
        bne     @sent
.endif
.ifdef HALT_AT                          ; debug: stop before this tick
        lda     net_tick
        cmp     #<HALT_AT
        bne     :+
        lda     net_tick+1
        cmp     #>HALT_AT
        bne     :+
        jmp     *
:
.endif
        jsr     send_input
@sent:
        lda     #0
        sta     ls_wait
        sta     ls_wait+1
        lda     $D012
        sta     ls_line
@poll:
.ifdef NET_UCI                          ; Ultimate: our input waits while a
        lda     uci_pend                ; command runs; poll until it is out,
        bne     @net                    ; or it leaves a tick late
.endif
.if NET_PLAYERS > 2
        jsr     all_ready               ; all others' inputs for this tick?
        bcs     @ready                  ; (only poll when one is missing)
.else
        lda     ls_rnew                 ; the other's input for this tick?
        cmp     net_tick                ; (only poll when it is missing:
        lda     ls_rnew+1               ; a WiC64 poll costs frames)
        sbc     net_tick+1
        bcs     @ready
.endif
@net:   jsr     net_poll                ; may end the session (no return)
        lda     $D012                   ; a raster wrap (twice a frame)?
        cmp     ls_line
        sta     ls_line
        bcs     @poll
        lda     ls_wait                 ; resend every 8 wraps (4 frames): more
        and     #7                      ; only fills the network's queues (VICE's
        cmp     #7                      ; RR-Net is slow enough already)
        bne     :+
        jsr     send_input
:       inc     net_waited              ; (statistics: total raster wraps waited)
        bne     :+
        inc     net_waited+1
:       inc     ls_wait
        bne     :+
        inc     ls_wait+1
:       ldx     #>1000                  ; give up after 10 s ...
        lda     ls_got
        bne     :+
        ldx     #>12000                 ; ... or 120 s while the other loads
:       cpx     ls_wait+1
        bcs     @poll
        lda     #END_TIMEOUT
        jmp     net_end

@ready:
.if NET_PLAYERS > 2
        ldx     net_tick                ; this tick's place in the rings
        jsr     ring_x
        stx     ls_tmp
        lda     #0
        sta     net_keys
        ldy     #NET_PLAYERS-1
@slot:  lda     #IDLE_INPUT             ; not in the session: idle
        cpy     ls_np
        bcs     @set
        ldx     ls_tmp
        lda     ls_lin,x                ; ours
        cpy     net_hb+HB_SLOT
        beq     @set
        tya                             ; another's: ring y*RING
        asl     a
        asl     a
        asl     a
        asl     a
        ora     ls_tmp
        tax
        lda     ls_rin,x
@set:   sta     net_in0,y
        and     #$60                    ; the keys of all players
        ora     net_keys
        sta     net_keys
        dey
        bpl     @slot
        inc     net_tick
        bne     :+
        inc     net_tick+1
:       rts

; C=1 when every other player of the session has sent this tick's input
all_ready:
        ldx     ls_np
        dex
@s:     cpx     net_hb+HB_SLOT
        beq     @n
        lda     ls_rnlo,x
        cmp     net_tick
        lda     ls_rnhi,x
        sbc     net_tick+1
        bcc     @no
@n:     dex
        bpl     @s
        sec
@no:    rts
.else
        ldx     net_tick
        jsr     ring_x
        lda     ls_lin,x                ; ls_tmp = mine, theirs
        sta     ls_tmp
        lda     ls_rin,x
        sta     ls_tmp+1
        ldy     net_hb+HB_SLOT          ; net_in0 = slot 0's input
        lda     ls_tmp,y
        sta     net_in0
        tya
        eor     #1
        tay
        lda     ls_tmp,y
        sta     net_in1
        lda     ls_tmp                  ; keys of both players
        ora     ls_tmp+1
        and     #$60
        sta     net_keys
        inc     net_tick
        bne     :+
        inc     net_tick+1
:       rts
.endif

; ============================================================================
; net_idle - while the game waits without ticks: keep the session alive
; ============================================================================
net_idle:
        lda     $D012                   ; a raster wrap (twice a frame)?
        cmp     ls_line
        sta     ls_line
        bcs     :+
        inc     ls_idle
        lda     ls_idle
        and     #31                     ; every 32 wraps, about 0.3 s
        bne     :+
        jsr     send_input              ; (the last input again: the other
        jmp     net_poll                ; C64 ignores what it already has)
:       rts

ring_x:                                 ; X = X & (RING-1), keeps A
        pha
        txa
        and     #RING-1
        tax
        pla
        rts

; --- local input: joystick port 2, C= pause, Q quit --------------------------
read_local:
.ifdef NETBOT
        lda     net_hb+HB_FLAGS
        lsr     a
        bcc     :+
        jmp     netbot
:
.endif
        lda     $DC02                   ; (a game may have made port A an input)
        pha
        lda     #$FF
        sta     $DC02
        lda     #$7F
        sta     $DC00
        lda     $DC01                   ; keyboard row 7
        eor     #$FF
        and     #$60                    ; bit 5 C=, bit 6 Q (active high now)
        sta     ls_tmp
        lda     #$FF
        sta     $DC00
        pla
        sta     $DC02
        lda     $DC00                   ; joystick port 2
        and     #$1F
        ora     ls_tmp
        rts

.ifdef NETBOT
; test bot: a walk that differs per slot, fire every 4th tick
netbot:
.ifdef NET_BOT_PERSON
        lda     net_tick                ; like a person: a direction for 6 ticks,
        and     #31                     ; nothing, the button for 4 ticks (24-27)
        cmp     #24
        bcs     @button
        cmp     #6
        bcs     @none
        lda     net_tick                ; the direction of this period:
        lsr     a                       ; (period + 3 * tick high + slot) & 7
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        pha
        lda     net_tick+1
        asl     a
        adc     net_tick+1
        adc     net_hb+HB_SLOT
        tsx
        adc     $0101,x
        and     #7
        tax
        pla
        lda     nb_pdirs,x
        rts
@button:
        cmp     #28
        bcs     @none
        lda     #$0F                    ; the button, no direction
        rts
@none:  lda     #$1F
        rts
nb_pdirs:       .byte   $1E, $1D, $1B, $17, $1A, $16, $19, $15 ; all eight
.else
        lda     net_tick
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     net_hb+HB_SLOT
        and     #7
        tax
        lda     net_tick
        and     #3
        bne     :+
        lda     nb_dirs,x
        and     #$0F                    ; fire
        rts
:       lda     nb_dirs,x
        rts
.endif
nb_dirs:        .byte   $1F, $1B, $17, $1E, $1A, $16, $1B, $17
.endif

; --- INPUT packet -----------------------------------------------------------
send_input:
        lda     #MSG_INPUT
        sta     tx_buf
        lda     net_hb+HB_SESSION
        sta     tx_buf+1
        ldx     #5
:       lda     ls_lnew,x               ; lnew, ckt, ck
        sta     tx_buf+2,x
        dex
        bpl     :-
        ldy     #WINDOW-1               ; inputs lnew-7 .. lnew
        lda     ls_lnew
:       tax
        jsr     ring_x
        pha
        lda     ls_lin,x
        sta     tx_buf+8,y
        pla
        sec
        sbc     #1
        dey
        bpl     :-
        lda     #INPUT_LEN
        ldx     #<tx_buf
        ldy     #>tx_buf
        jmp     drv_send

; Fletcher-16 over the state both machines must agree on (netgame.inc)
net_checksum:
        lda     net_tick
        sta     ls_ckt
        lda     net_tick+1
        sta     ls_ckt+1
        lda     #0
        sta     ls_ck
        sta     ls_ck+1
        ldy     #CK_RANGES-1
@r:     lda     ck_lo,y
        sta     @ld+1
        lda     ck_hi,y
        sta     @ld+2
        ldx     ck_len,y
@ld:    lda     $FFFF
        clc
        adc     ls_ck
        sta     ls_ck
        clc
        adc     ls_ck+1
        sta     ls_ck+1
        inc     @ld+1
        bne     :+
        inc     @ld+2
:       dex
        bne     @ld
        dey
        bpl     @r
        rts

ck_lo:          .lobytes NET_CK_START
ck_hi:          .hibytes NET_CK_START
ck_len:         .lobytes NET_CK_LEN
CK_RANGES       = * - ck_len

.ifdef NET_SPLIT
.segment "NETRX"
.endif
; ============================================================================
; net_poll - let the driver work; handle one received message, if any
; ============================================================================
net_poll:
        jsr     drv_poll                ; C=0: message at RX_DATA, A = length
        bcs     rx_done
net_msg:                                ; (the WiC64 driver calls this itself)
        ldx     RX_DATA
        ldy     RX_DATA+1
        cpy     net_hb+HB_SESSION
        beq     :+
rx_done:
        rts
:
.if NET_PLAYERS > 2
        cpx     #MSG_INPUT              ; INPUT from slot 0-3: $80-$83 (A is
        bcc     :+                      ; the length)
        cpx     #MSG_INPUT+NET_PLAYERS
        bcc     rx_input
:
.else
        cpx     #MSG_INPUT
        beq     rx_input
.endif
        ldy     #END_LEFT
        cpx     #MSG_OPP_LEFT
        beq     :+
        ldy     RX_DATA+2               ; SESSION_END reason
        cpx     #MSG_SESSION_END
        bne     rx_done
:       tya
.ifdef NET_WIC
        sta     wic_end                 ; not in the middle of a WiC64 transfer
        rts
.else
        jmp     net_end
.endif

rx_input:
        cmp     #INPUT_LEN
        bcc     rx_done
.if NET_PLAYERS > 2
        txa                             ; the sender: a player of the session,
        and     #3                      ; not us
        tax
        cpx     ls_np
        bcs     rx_done
        cpx     net_hb+HB_SLOT
        beq     rx_done
        stx     ls_slot
        asl     a
        asl     a
        asl     a
        asl     a
        sta     ls_base
.endif
        lda     #1
        sta     ls_got
        lda     RX_DATA+2               ; t = newest - 7
        sec
        sbc     #WINDOW-1
        sta     ls_tmp
        lda     RX_DATA+3
        sbc     #0
        sta     ls_tmp+1
        ldy     #8
@in:
.if NET_PLAYERS > 2
        ldx     ls_slot                 ; only ticks 1-255 newer than rnew
        lda     ls_tmp
        sec
        sbc     ls_rnlo,x
        sta     ls_diff
        lda     ls_tmp+1
        sbc     ls_rnhi,x
        bne     @next
        lda     ls_diff
        beq     @next
        lda     ls_tmp
        sta     ls_rnlo,x
        lda     ls_tmp+1
        sta     ls_rnhi,x
        lda     ls_tmp
        and     #RING-1
        ora     ls_base
        tax
        lda     RX_DATA,y
        sta     ls_rin,x
.else
        lda     ls_tmp                  ; only ticks 1-255 newer than rnew
        sec
        sbc     ls_rnew
        tax
        lda     ls_tmp+1
        sbc     ls_rnew+1
        bne     @next
        txa
        beq     @next
        ldx     ls_tmp
        jsr     ring_x
        lda     RX_DATA,y
        sta     ls_rin,x
        lda     ls_tmp
        sta     ls_rnew
        lda     ls_tmp+1
        sta     ls_rnew+1
.endif
@next:  inc     ls_tmp
        bne     :+
        inc     ls_tmp+1
:       iny
        cpy     #8+WINDOW
        bne     @in
        rts

; ============================================================================
; net_end - the session is over (A = reason): load the lobby again
; ============================================================================
net_end:
        pha
        cmp     #END_GAMEOVER           ; the game ended it (game over, quit):
        beq     @why                    ; tell the server why
        cmp     #END_QUIT
        bne     :+
@why:   sta     tx_buf+2
        lda     #MSG_SESSION_END
        sta     tx_buf
        lda     net_hb+HB_SESSION
        sta     tx_buf+1
        lda     #3
        ldx     #<tx_buf
        ldy     #>tx_buf
        jsr     drv_send
        jsr     drv_flush
:       lda     #MSG_BYE
        sta     tx_buf
        lda     #1
        ldx     #<tx_buf
        ldy     #>tx_buf
        jsr     drv_send
        jsr     drv_flush
        sei
        lda     #$7F                    ; no CIA interrupts, no raster IRQ
        sta     $DC0D
        sta     $DD0D
        lda     #0
        sta     $D01A
        sta     $D015                   ; (the lobby does not hide sprites)
        ldx     #TAIL_LEN-1             ; the rest runs from NET_TAIL: this code
:       lda     tail_src,x              ; may lie under a ROM that comes back
        sta     NET_TAIL,x
        dex
        bpl     :-
        pla
        sta     tail_reason
        lda     net_hb+HB_SOCKET
        sta     tail_socket
        lda     net_hb+HB_DEVICE
        sta     tail_device
        jmp     NET_TAIL

; assembled for NET_TAIL (netgame.inc: RAM outside $A000-$BFFF and $D000-$FFFF,
; that the game no longer needs)
tail_src:
.org NET_TAIL
        ldx     #$37                    ; KERNAL, BASIC and I/O back
        stx     $01
        jsr     $FF84                   ; IOINIT    as a KERNAL reset does it
        jsr     $FF87                   ; RAMTAS    (clears pages 0, 2 and 3)
        jsr     $FF8A                   ; RESTOR
        jsr     $FF81                   ; CINT
        lda     tail_reason             ; result for the lobby: "BR", reason, socket
        sta     $033E
        lda     #$42                    ; "B"
        sta     $033C
        lda     #$52                    ; "R"
        sta     $033D
        lda     tail_socket
        sta     $033F
        cli
        lda     #1
        ldx     tail_device
        tay                             ; load to the address in the file
        jsr     $FFBA                   ; SETLFS
        lda     #lobby_name_end-lobby_name
        ldx     #<lobby_name
        ldy     #>lobby_name
        jsr     $FFBD                   ; SETNAM
        lda     #0
        jsr     $FFD5                   ; LOAD
        bcs     :+
        jmp     $080D                   ; the lobby's SYS 2061
:       jmp     $FCE2                   ; no lobby: reset
tail_reason:    .byte   0
tail_socket:    .byte   0
tail_device:    .byte   8
lobby_name:     .byte   NET_LOBBY
lobby_name_end:
tail_end:
.reloc
TAIL_LEN        = tail_end - NET_TAIL
.assert TAIL_LEN <= 128, error, "net_end's tail is too long"

.ifdef NET_SPLIT
.segment "NETDRV"
.endif
; ============================================================================
; Drivers:
;   drv_init            once per session
;   drv_send            A = length, X/Y = data (lo/hi)
;   drv_poll            C=0: a message at RX_DATA, A = length
;   drv_flush           finish sending before the machine is reset
; ============================================================================

.ifdef NET_UCI
; ----------------------------------------------------------------------------
; Ultimate Command Interface. One command at a time: a read is pending
; whenever nothing is sent; a send while a read runs waits for it.
; ----------------------------------------------------------------------------
UCI_CTRL        = $DF1C                 ; write: control, read: status
UCI_CMD         = $DF1D
UCI_RESP        = $DF1E
UCI_STAT        = $DF1F
UCI_PUSH        = $01
UCI_ACC         = $02
UCI_STATE       = $30
UCI_BUSY        = $10
UCI_MORE        = $30
UCI_TARGET      = $03
UCI_READ        = $10
UCI_WRITE       = $11
UCI_RXMAX       = 48

uci_state:      .byte   0               ; 0 idle, 1 read, 2 write
uci_pend:       .byte   0               ; length of a waiting send, 0 none
.ifdef NET_SPLIT
.segment "NETBSS"
.endif
uci_rx:         .res    UCI_RXMAX+2
.ifdef NET_SPLIT
.segment "NETDRV"
.endif
RX_DATA         = uci_rx + 2

drv_init:
        lda     #0
        sta     uci_state
        sta     uci_pend
        rts

drv_send:
        sta     uci_pend
        stx     uci_src+1
        sty     uci_src+2
        lda     uci_state
        beq     uci_write
        rts

drv_flush:
        jsr     drv_poll                ; until the send is out
        lda     uci_state
        ora     uci_pend
        bne     drv_flush
        rts

uci_cmd:                                ; wait for idle, send target, A, socket
        pha
        ldx     #0
:       lda     UCI_CTRL
        and     #UCI_STATE
        beq     :+
        dex
        bne     :-
:       lda     #UCI_TARGET
        sta     UCI_CMD
        pla
        sta     UCI_CMD
        lda     net_hb+HB_SOCKET
        sta     UCI_CMD
        rts

uci_write:
        lda     #UCI_WRITE
        jsr     uci_cmd
        ldx     #0
uci_src:
        lda     $FFFF,x
        sta     UCI_CMD
        inx
        cpx     uci_pend
        bne     uci_src
        lda     #0
        sta     uci_pend
        lda     #2
        bne     uci_push

uci_read:
        lda     #UCI_READ
        jsr     uci_cmd
        lda     #UCI_RXMAX
        sta     UCI_CMD
        lda     #0
        sta     UCI_CMD
        lda     #1
uci_push:
        sta     uci_state
        lda     #UCI_PUSH
        sta     UCI_CTRL
        sec
        rts

drv_poll:
        lda     uci_state
        bne     @busy
        lda     uci_pend                ; idle: send if waiting, else read
        beq     uci_read
        bne     uci_write
@busy:  lda     UCI_CTRL
        and     #UCI_STATE
        cmp     #UCI_BUSY
        bne     :+
        sec                             ; still running
        rts
:       ldx     #0                      ; collect the response (bounded)
@data:  ldy     #0
@resp:  lda     UCI_CTRL
        bpl     @stat                   ; bit 7: response data available
        lda     UCI_RESP
        cpx     #UCI_RXMAX+2
        bcs     :+
        sta     uci_rx,x
        inx
:       dey
        bne     @resp
@stat:  ldy     #40
:       bit     UCI_CTRL
        bvc     :+                      ; bit 6: status data available
        lda     UCI_STAT
        dey
        bne     :-
:       lda     UCI_CTRL
        and     #UCI_STATE
        beq     :+                      ; idle: nothing to acknowledge
        tay
        lda     #UCI_ACC
        sta     UCI_CTRL
        cpy     #UCI_MORE
        beq     @data
:
        lda     uci_state
        ldy     #0
        sty     uci_state
        lsr     a                       ; 1 = read
        bcc     @none
        cpx     #3                      ; count (2) + data
        bcc     @none
        lda     uci_rx+1
        bne     @none                   ; $FFFF = nothing
        lda     uci_rx
        beq     @none                   ; 0 bytes
        clc
        rts
@none:  sec
        rts
.endif ; NET_UCI

.ifdef NET_RR
; ----------------------------------------------------------------------------
; RR-Net (CS8900a), raw Ethernet. The lobby initialised the chip and found
; the server's MAC. Frame: server MAC, our MAC, $88 $B5, message.
; ----------------------------------------------------------------------------
RR_PP           = $DE02
RR_PPDATA       = $DE04
RR_DATA         = $DE08
RR_TXCMD        = $DE0C
RR_TXLEN        = $DE0E
RR_RXMAX        = 15 + 47
ETHERTYPE_HI    = $88
ETHERTYPE_LO    = $B5

.ifdef NET_SPLIT
.segment "NETBSS"
.endif
rr_rx:          .res    RR_RXMAX
.ifdef NET_SPLIT
.segment "NETDRV"
.endif
RX_DATA         = rr_rx + 15
rr_len:         .byte   0, 0

drv_init:
drv_flush:
        rts                             ; RR-Net sends synchronously

drv_send:                               ; A = length, X/Y = data
        stx     @src+1
        sty     @src+2
        pha
        clc
        adc     #15
        ldx     #$C9                    ; TxCMD: start after all bytes (padded)
        stx     RR_TXCMD
        ldx     #0
        stx     RR_TXCMD+1
        sta     RR_TXLEN
        stx     RR_TXLEN+1
        ldy     #8
:       lda     #$38                    ; BusST: Rdy4TxNOW?
        jsr     rr_pp
        lda     RR_PPDATA+1
        lsr     a
        bcs     :+
        dey
        bne     :-
        pla                             ; no buffer space: drop it
        rts
:       ldx     #0                      ; header: both MACs, then the type
:       lda     net_hb+HB_DSTMAC,x
        sta     RR_DATA
        lda     net_hb+HB_DSTMAC+1,x
        sta     RR_DATA+1
        inx
        inx
        cpx     #12
        bne     :-
        lda     #ETHERTYPE_HI
        sta     RR_DATA
        lda     #ETHERTYPE_LO
        sta     RR_DATA+1
        pla
        sta     rr_len
        sta     RR_DATA                 ; message length, then the message
        ldx     #0
        ldy     #1
@src:   lda     $FFFF,x                 ; data in words (odd: one extra byte)
        sta     RR_DATA,y               ; Y = 0 / 1 alternately
        inx
        tya
        eor     #1
        tay
        cpx     rr_len
        bne     @src
        tya                             ; odd length: complete the last word
        beq     :+
        sta     RR_DATA+1
:       rts

rr_pp:                                  ; PacketPage pointer = $01xx (A)
        sta     RR_PP
        lda     #$01
        sta     RR_PP+1
        rts

drv_poll:
        lda     #$24                    ; RxEvent
        jsr     rr_pp
        lda     RR_PPDATA+1
        and     #$0D
        bne     :+
        sec
        rts
:       ldx     RR_DATA+1               ; status (ignored; same order as ip65)
        lda     RR_DATA
        ldx     RR_DATA+1               ; frame length
        lda     RR_DATA
        sta     rr_len
        stx     rr_len+1
        ldx     #0
@word:  cpx     #RR_RXMAX
        bcs     @skip                   ; longer than we keep
        lda     rr_len+1
        bne     @read
        cpx     rr_len
        bcs     @done                   ; whole frame read
@read:  lda     RR_DATA
        sta     rr_rx,x
        lda     RR_DATA+1
        sta     rr_rx+1,x
        inx
        inx
        bne     @word
@skip:  lda     #$02                    ; RxCFG: skip the rest of the frame
        jsr     rr_pp
        lda     RR_PPDATA
        ora     #$40
        sta     RR_PPDATA
@done:  lda     rr_rx+12                ; ours?
        cmp     #ETHERTYPE_HI
        bne     :++
        lda     rr_rx+13
        cmp     #ETHERTYPE_LO
        bne     :++
        ldx     #5                      ; to us, from the server? (VICE's
:       lda     rr_rx,x                 ; CS8900a lets other frames through)
        cmp     net_hb+HB_MYMAC,x
        bne     :+
        lda     rr_rx+6,x
        cmp     net_hb+HB_DSTMAC,x
        bne     :+
        dex
        bpl     :-
        lda     rr_rx+14                ; message length
        clc
        rts
:       sec
        rts
.endif ; NET_RR

.ifdef NET_WIC
; ----------------------------------------------------------------------------
; WiC64 (firmware 2.x) on the userport. Request: "R", command, length (16),
; payload; answer: status, length (16), payload. Every byte is confirmed with
; FLAG2 ($DD0D bit 4); PA2 high = C64 sends, low = C64 receives. The TCP
; connection was opened by the lobby. Messages in the stream are handed to
; net_msg as they complete (several can arrive at once).
; A game whose NMI handler reads $DD0D must OR that value into net_flag2,
; or the handshake bit it clears is lost.
; ----------------------------------------------------------------------------
WIC_TCP_READ    = $22
WIC_TCP_WRITE   = $23
MB_MAX          = INPUT_LEN

.ifdef NET_SPLIT
.segment "NETBSS"
.endif
wic_mbuf:       .res    MB_MAX          ; the message being received
.ifdef NET_SPLIT
.segment "NETDRV"
.endif
RX_DATA         = wic_mbuf
wic_need:       .byte   0               ; bytes still missing of it
wic_pos:        .byte   0
wic_len:        .byte   0
wic_left:       .word   0
wic_end:        .byte   0               ; a session end, handled after the read

drv_init:
        lda     $DD02                   ; PA2 is an output
        ora     #$04
        sta     $DD02
        lda     #0
        sta     wic_need
        sta     wic_end
drv_flush:
        rts

wic_out:                                ; send A, wait for the handshake
        sta     $DD01
wic_wait:
:       lda     $DD0D
        ora     net_flag2
        and     #$10
        beq     :-
        lda     #0
        sta     net_flag2
        rts

wic_in:
        jsr     wic_wait
        lda     $DD01
        rts

wic_head:                               ; A = command, X = payload length
        pha
        lda     $DD00                   ; PA2 high: we send
        ora     #$04
        sta     $DD00
        lda     #$FF
        sta     $DD03
        lda     #$52                    ; "R"
        jsr     wic_out
        pla
        jsr     wic_out
        txa
        jsr     wic_out
        lda     #0
        jmp     wic_out

wic_turn:                               ; to receiving; wic_left = answer length
        lda     #0
        sta     $DD03
        lda     $DD00
        and     #$FB
        sta     $DD00
        jsr     wic_wait
        lda     $DD01
        jsr     wic_in                  ; status (not needed: a closed
        jsr     wic_in                  ; connection just brings nothing)
        sta     wic_left
        jsr     wic_in
        sta     wic_left+1
        rts

drv_send:                               ; A = length, X/Y = data
        stx     @src+1
        sty     @src+2
        sta     wic_len
        tax
        inx                             ; [length][message]
        lda     #WIC_TCP_WRITE
        jsr     wic_head
        lda     wic_len
        jsr     wic_out
        ldx     #0
@src:   lda     $FFFF,x
        jsr     wic_out
        inx
        cpx     wic_len
        bne     @src
        jsr     wic_turn                ; the answer has no payload
        lda     $DD0D
        rts

drv_poll:
        lda     #WIC_TCP_READ
        ldx     #0
        jsr     wic_head
        jsr     wic_turn
@byte:  lda     wic_left                ; all of it, a message at a time
        ora     wic_left+1
        beq     @done
        lda     wic_left
        bne     :+
        dec     wic_left+1
:       dec     wic_left
        jsr     wic_in
        ldx     wic_need
        bne     @data
        sta     wic_need                ; a length byte starts a message
        sta     wic_len
        stx     wic_pos
        beq     @byte
@data:  ldx     wic_pos
        cpx     #MB_MAX
        bcs     :+                      ; (longer messages are not for the game)
        sta     wic_mbuf,x
:       inc     wic_pos
        dec     wic_need
        bne     @byte
        lda     wic_len
        cmp     #MB_MAX+1
        bcs     @byte
        jsr     net_msg
        jmp     @byte
@done:  lda     $DD0D
        lda     wic_end
        beq     :+
        jmp     net_end
:       sec
        rts
.endif ; NET_WIC

.if .not (.defined(NET_UCI) .or .defined(NET_RR) .or .defined(NET_WIC))
RX_DATA         = tx_buf
drv_init:
drv_flush:
drv_send:
        rts
drv_poll:
        sec
        rts
.endif
