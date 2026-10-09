; ============================================================================
; BB-LAN - in-game network: handoff block, lockstep, one network driver
; ============================================================================
; The lobby (lobby/, a separate program) does everything that needs more
; code: hardware detection, finding the server, the lobby and the challenge.
; When the server starts a session, the lobby writes a handoff block to
; $03C0 and loads this game; the unpacker (tools/sfx.s) copies the block into
; bb_hb. Without a valid block the game runs locally (two joysticks).
;
; In a session both C64s run the complete game in lockstep (bblan.s makes it
; deterministic). Each tick (25 Hz) the local joystick for tick+delay goes
; to the server, which relays it to the other player; a tick only runs when
; the other player's input for it has arrived.
;
; INPUT ($80), 16 bytes:
;   $80, session, newest tick (16), checksum tick (16, $FFFF none),
;   checksum (16), 8 inputs for ticks newest-7..newest
; Input byte: bits 0-4 joystick (active low, as $DC00), bit 5 pause key (C=),
; bit 6 quit key (Q), both active high. Slot 0 plays Bub, slot 1 Bob.
;
; One driver is assembled in (a game file per hardware type):
;   NET_UCI   Ultimate 64 / C64 Ultimate: UDP through the Ultimate Command
;             Interface (socket opened by the lobby)
;   NET_WIC   WiC64: TCP to the server's port 6466 (connection opened by
;             the lobby), the stream carries [length][message]
;   NET_RR    RR-Net / CS8900a (VICE): raw Ethernet frames, EtherType $88B5,
;             to the server's pcap interface: server MAC, our MAC, $88B5,
;             message length, message. No IP, so no ARP or IP set-up.
; ============================================================================

.segment "BBLAN_CODE"

.export bb_hb

; --- Handoff block (written by the lobby, lobby/handoff.h) -------------------
HB_MAGIC        = 0                     ; "BL"
HB_DRIVER       = 2                     ; 0 local, 1 UCI, 2 RR-Net
HB_SLOT         = 3                     ; 0 = Bub, 1 = Bob
HB_SESSION      = 4
HB_SEED         = 5                     ; 2 bytes
HB_DELAY        = 7                     ; input delay in ticks (1-4)
HB_SOCKET       = 8                     ; UCI socket
HB_FLAGS        = 9                     ; bit 0: test bot plays
HB_DEVICE       = 10                    ; drive the lobby was loaded from
HB_DSTMAC       = 12                    ; RR-Net: server MAC
HB_MYMAC        = 18                    ; RR-Net: our MAC (directly after)
HB_SIZE         = 24

DRV_LOCAL       = 0
DRV_UCI         = 1
DRV_RR          = 2
DRV_WIC         = 3
HBF_BOT         = $01

; reasons, passed back to the lobby at $033C ("BR", reason, socket);
; 1-5 are the SESSION_END reasons of the server
END_GAMEOVER    = 1
END_TIMEOUT     = 3
END_LEFT        = 6                     ; OPPONENT_LEFT

MSG_INPUT       = $80
MSG_OPP_LEFT    = $0A
MSG_SESSION_END = $0B
MSG_BYE         = $0E

INPUT_LEN       = 16
WINDOW          = 8                     ; inputs per packet (delay <= 4)
RING            = 16                    ; ring size (power of 2)
IDLE_INPUT      = $1F                   ; no direction, no fire, no keys

; the rings live in the stack page; the game uses $0100 and $0107-$0126,
; the stack itself stays above $01A7
ls_lin          = $0128
ls_rin          = $0138

bb_hb:          .res    HB_SIZE

; --- Lockstep state -------------------------------------------------------
ls_on:          .byte   0               ; 1 while a session game runs
ls_got:         .byte   0               ; 1 once the other player was heard
ls_lnew:        .word   0               ; newest local tick sent   } tx_buf+2
ls_ckt:         .word   $FFFF           ; checksum tick            } +4
ls_ck:          .word   0               ; checksum                 } +6
ls_rnew:        .word   0               ; newest remote tick received
ls_wait:        .word   0               ; real frames waited for this tick
ls_rf:          .byte   0
ls_tmp:         .res    2
tx_buf:         .res    INPUT_LEN

; ============================================================================
; bb_net_start - called by bb_game_init when a session game starts
; ============================================================================
bb_net_start:
        lda     bb_hb+HB_SEED
        sta     bb_seed
        lda     bb_hb+HB_SEED+1
        sta     bb_seed+1
        ldx     #RING-1
        lda     #IDLE_INPUT
:       sta     ls_lin,x
        sta     ls_rin,x
        dex
        bpl     :-
        lda     bb_hb+HB_DELAY          ; ticks 1..delay are idle on both sides
        sta     ls_lnew
        sta     ls_rnew
        ldx     #0
        stx     ls_lnew+1
        stx     ls_rnew+1
        stx     ls_got
        dex
        stx     ls_ckt
        stx     ls_ckt+1
        lda     #1
        sta     ls_on
        jmp     drv_init

; ============================================================================
; net_tick - bb_sample in a session: exchange the input for this tick
; ============================================================================
net_tick:
        lda     bb_tick                 ; lnew = tick + delay
        clc
        adc     bb_hb+HB_DELAY
        sta     ls_lnew
        lda     bb_tick+1
        adc     #0
        sta     ls_lnew+1
        jsr     read_local
        ldx     ls_lnew
        jsr     ring_x
        sta     ls_lin,x

        lda     bb_tick                 ; checksum every 64 ticks
        and     #63
        bne     :+
        jsr     net_checksum
:
.ifdef NET_WIC                          ; WiC64: send every other tick (each
        lda     bb_tick                 ; packet carries 8 inputs anyway)
        lsr     a
        bcs     @sent
.endif
.ifdef HALT_AT                          ; debug: stop before this tick
        lda     bb_tick
        cmp     #<HALT_AT
        bne     :+
        lda     bb_tick+1
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
.if .not (.defined(HALT_AT) .or .defined(NETBOT))
        lda     VIC_BORDER
        pha
.endif
@wait:  lda     bb_rframe
        sta     ls_rf
@poll:  lda     ls_rnew                 ; the other's input for this tick?
        cmp     bb_tick                 ; (only poll when it is missing:
        lda     ls_rnew+1               ; a WiC64 poll costs frames)
        sbc     bb_tick+1
        bcs     @ready
        jsr     net_poll                ; may end the session (no return)
        lda     bb_rframe
        cmp     ls_rf
        beq     @poll
        jsr     send_input              ; resend every real frame
        inc     ls_wait
        bne     :+
        inc     ls_wait+1
:
.if .not (.defined(HALT_AT) .or .defined(NETBOT)) ; (no room in test builds)
        lda     ls_wait+1               ; after 5 s: flash the border
        beq     :+
        inc     VIC_BORDER
:
.endif
        ldx     #>500                   ; give up after 10 s ...
        lda     ls_got
        bne     :+
        ldx     #>6000                  ; ... or 120 s while the other loads
:       cpx     ls_wait+1
        bcs     @wait
        lda     #END_TIMEOUT
        jmp     bb_end

@ready:
.if .not (.defined(HALT_AT) .or .defined(NETBOT))
        pla
        sta     VIC_BORDER
.endif
        ldx     bb_tick
        jsr     ring_x
        lda     ls_lin,x                ; ls_tmp = mine, theirs
        sta     ls_tmp
        lda     ls_rin,x
        sta     ls_tmp+1
        ldy     bb_hb+HB_SLOT           ; slot 0 plays Bub
        lda     ls_tmp,y
        and     #$1F
        ora     #$60                    ; as $DC00 reads with keyboard row 7
        sta     bb_in0
        tya
        eor     #1
        tay
        lda     ls_tmp,y
        and     #$1F
        ora     #$E0                    ; as $DC01 reads
        sta     bb_in1
        lda     ls_tmp                  ; keys of both players
        ora     ls_tmp+1
        and     #$60
        ldx     #$BF                    ; Q (quit) wins over C= (pause)
        cmp     #$40
        bcs     :+
        ldx     #$DF
        cmp     #$20
        beq     :+
        ldx     #$FF
:       stx     bb_key
        rts

ring_x:                                 ; X = X & (RING-1), keeps A
        pha
        txa
        and     #RING-1
        tax
        pla
        rts

; --- local input: joystick port 2, C= pauses, Q quits ---------------------
read_local:
.ifdef NETBOT
        lda     bb_hb+HB_FLAGS
        lsr     a
        bcc     :+
        jmp     netbot
:
.endif
        lda     #$7F
        sta     CIA1_PRA
        lda     CIA1_PRB                ; keyboard row 7
        eor     #$FF
        and     #$60                    ; bit 5 C=, bit 6 Q (active high now)
        sta     ls_tmp
        lda     CIA1_PRA
        and     #$1F
        ora     ls_tmp
        rts

.ifdef NETBOT
; test bot: a fixed walk that differs per slot, fire every 4th tick
netbot:
        lda     bb_tick
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     bb_hb+HB_SLOT
        and     #7
        tax
        lda     bb_tick
        and     #3
        bne     :+
        lda     nb_dirs,x
        and     #$0F                    ; fire
        rts
:       lda     nb_dirs,x
        rts
nb_dirs:        .byte   $1F, $1B, $17, $1E, $1A, $16, $1B, $17
.endif

; --- INPUT packet -----------------------------------------------------------
send_input:
        lda     #MSG_INPUT
        sta     tx_buf
        lda     bb_hb+HB_SESSION
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

; Fletcher-16 over the state both machines must agree on
net_checksum:
        lda     bb_tick
        sta     ls_ckt
        lda     bb_tick+1
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

.define CK_START $0010, $0026, $002A, $005D, $00B2, $0400
.define CK_LEN   1,     2,     4,     2,     $46,   $5C
ck_lo:          .lobytes CK_START
ck_hi:          .hibytes CK_START
ck_len:         .byte    CK_LEN
CK_RANGES       = * - ck_len

; ============================================================================
; net_poll - let the driver work; handle one received message, if any
; ============================================================================
net_poll:
        jsr     drv_poll                ; C=0: message at RX_DATA, A = length
        bcs     rx_done
net_msg:                                ; (the WiC64 driver calls this itself)
        ldx     RX_DATA                 ; (PINGs are not answered in a game:
        ldy     RX_DATA+1               ; the server only uses them to show
                                        ; the ping time)
        cpy     bb_hb+HB_SESSION
        beq     :+
rx_done:
        rts
:       cpx     #MSG_INPUT
        beq     rx_input
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
        jmp     bb_end
.endif

rx_input:
        cmp     #INPUT_LEN
        bcc     rx_done
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
@in:    lda     ls_tmp                  ; only ticks 1-255 newer than rnew
        sec                             ; (the first packets also carry
        sbc     ls_rnew                 ; "ticks" below 0)
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
@next:  inc     ls_tmp
        bne     :+
        inc     ls_tmp+1
:       iny
        cpy     #8+WINDOW
        bne     @in
        rts

; ============================================================================
; bb_end - the session is over (A = reason): load the lobby again
; ============================================================================
bb_end:
        pha
        lda     #MSG_BYE
        sta     tx_buf
        lda     #1
        ldx     #<tx_buf
        ldy     #>tx_buf
        jsr     drv_send
        jsr     drv_flush
        sei                             ; (the reason stays on the stack)
        ldx     #$37                    ; KERNAL, BASIC and I/O back
        stx     R6510
        lda     #0
        sta     $D01A                   ; no raster IRQ (the lobby hides the sprites)
        jsr     $FF84                   ; IOINIT    as a KERNAL reset does it
        jsr     $FF87                   ; RAMTAS    (clears pages 0, 2 and 3)
        jsr     $FF8A                   ; RESTOR
        jsr     $FF81                   ; CINT
        pla
        sta     $033E                   ; result for the lobby: "BR", reason, socket
        lda     #'B'
        sta     $033C
        lda     #'R'
        sta     $033D
        lda     bb_hb+HB_SOCKET
        sta     $033F
        cli
        lda     #1
        ldx     bb_hb+HB_DEVICE
        tay                             ; load to the address in the file
        jsr     $FFBA                   ; SETLFS
        lda     #5
        ldx     #<lobby_name
        ldy     #>lobby_name
        jsr     $FFBD                   ; SETNAM
        lda     #0
        jsr     $FFD5                   ; LOAD
        bcs     :+
        jmp     $080D                   ; the lobby's SYS 2061
:       jmp     $FCE2                   ; no lobby: reset

lobby_name:     .byte   "BBLAN"

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
uci_rx:         .res    UCI_RXMAX+2
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
        lda     bb_hb+HB_SOCKET
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

rr_rx:          .res    RR_RXMAX
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
:       lda     bb_hb+HB_DSTMAC,x
        sta     RR_DATA
        lda     bb_hb+HB_DSTMAC+1,x
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
        cmp     bb_hb+HB_MYMAC,x
        bne     :+
        lda     rr_rx+6,x
        cmp     bb_hb+HB_DSTMAC,x
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
; ----------------------------------------------------------------------------
WIC_TCP_READ    = $22
WIC_TCP_WRITE   = $23
MB_MAX          = INPUT_LEN

wic_mbuf:       .res    MB_MAX          ; the message being received
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
        lda     #$10
:       bit     $DD0D
        beq     :-
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
        jmp     bb_end
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
