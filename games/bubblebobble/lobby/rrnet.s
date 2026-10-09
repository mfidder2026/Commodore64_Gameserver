; ============================================================================
; BB-LAN lobby: RR-Net (CS8900a) raw Ethernet driver, cc65 C callable
; ============================================================================
; Frames: destination MAC, source MAC, EtherType $88B5, length, message.
; The game server talks this on its pcap interface (server.json
; "pcapInterface"); in VICE: RR-Net cartridge on that host interface.
; Chip set-up as in ip65's cs8900a driver (MPL 1.1, see third_party/).
; ============================================================================

        .export _rr_init, _rr_send, _rr_poll
        .export _rr_mymac, _rr_dst, _rr_from, _rr_txbuf, _rr_txlen, _rr_rxbuf, _rr_rxlen

RR_ISQ          = $DE00
RR_PP           = $DE02
RR_PPDATA       = $DE04
RR_DATA         = $DE08
RR_TXCMD        = $DE0C
RR_TXLEN        = $DE0E
RXMAX           = 15 + 255

        .bss
_rr_mymac:      .res    6               ; set by C before rr_init
_rr_dst:        .res    6               ; destination of rr_send
_rr_from:       .res    6               ; source of the last received frame
_rr_txbuf:      .res    255
_rr_txlen:      .res    1
_rr_rxbuf:      .res    255             ; message only
_rr_rxlen:      .res    1
frame:          .res    RXMAX + 1
flen:           .res    2

        .code

pp_a1:  ldx     #$01                    ; PacketPage pointer = X:A
pp_ax:  sta     RR_PP
        stx     RR_PP+1
        rts

; unsigned char rr_init(void): 0 = ok, 1 = no CS8900a
_rr_init:
        lda     RR_ISQ+1
        ora     #$01                    ; RR-Net: clockport on
        sta     RR_ISQ+1
        lda     #$00
        tax
        jsr     pp_ax
        lda     #$63^$0E                ; product id $630E
        eor     RR_PPDATA
        eor     RR_PPDATA+1
        beq     :+
        lda     #1
        ldx     #0
        rts
:       lda     #$14                    ; SelfCTL: reset
        jsr     pp_a1
        lda     #$40
        sta     RR_PPDATA
        ldy     #0
:       dey                             ; give it time
        bne     :-
        lda     #$04                    ; RxCTL: individual, broadcast, RxOK
        jsr     pp_a1
        lda     #$05
        sta     RR_PPDATA
        lda     #$0D
        sta     RR_PPDATA+1
        ldy     #0                      ; MAC address: PP $0158-$015D
:       tya
        clc
        adc     #$58
        jsr     pp_a1
        lda     _rr_mymac,y
        sta     RR_PPDATA
        lda     _rr_mymac+1,y
        sta     RR_PPDATA+1
        iny
        iny
        cpy     #6
        bne     :-
        lda     #$12                    ; LineCTL: receiver and transmitter on
        jsr     pp_a1
        lda     #$D3
        sta     RR_PPDATA
        lda     #$00
        sta     RR_PPDATA+1
        lda     #0
        tax
        rts

; unsigned char rr_send(void): _rr_txbuf/_rr_txlen to _rr_dst; 0 = sent
_rr_send:
        lda     _rr_txlen
        clc
        adc     #15
        ldx     #$C9
        stx     RR_TXCMD
        ldx     #0
        stx     RR_TXCMD+1
        sta     RR_TXLEN
        bcc     :+
        inx
:       stx     RR_TXLEN+1
        ldy     #0
:       lda     #$38                    ; BusST: Rdy4TxNOW
        jsr     pp_a1
        lda     RR_PPDATA+1
        lsr     a
        bcs     :+
        dey
        bne     :-
        lda     #1
        ldx     #0
        rts
:       ldx     #0
:       lda     _rr_dst,x
        sta     RR_DATA
        lda     _rr_dst+1,x
        sta     RR_DATA+1
        inx
        inx
        cpx     #6
        bne     :-
        ldx     #0
:       lda     _rr_mymac,x
        sta     RR_DATA
        lda     _rr_mymac+1,x
        sta     RR_DATA+1
        inx
        inx
        cpx     #6
        bne     :-
        lda     #$88
        sta     RR_DATA
        lda     #$B5
        sta     RR_DATA+1
        lda     _rr_txlen
        sta     RR_DATA
        ldx     #0
        ldy     #1
        cpx     _rr_txlen
        beq     @end
@b:     lda     _rr_txbuf,x
        sta     RR_DATA,y
        tya
        eor     #1
        tay
        inx
        cpx     _rr_txlen
        bne     @b
@end:   tya
        beq     :+
        sta     RR_DATA+1               ; complete the last word
:       lda     #0
        tax
        rts

; unsigned char rr_poll(void): 1 = a message for us arrived (_rr_rxbuf, _rr_rxlen, _rr_from)
_rr_poll:
        lda     #$24                    ; RxEvent
        jsr     pp_a1
        lda     RR_PPDATA+1
        and     #$0D
        bne     :+
        lda     #0
        tax
        rts
:       ldx     RR_DATA+1               ; status, then length (order as ip65)
        lda     RR_DATA
        ldx     RR_DATA+1
        lda     RR_DATA
        sta     flen
        stx     flen+1
        lda     #<frame
        sta     @st+1
        lda     #>frame
        sta     @st+2
        ldy     #0                      ; words read (counts bytes / 2)
@w:     lda     flen+1                  ; bytes left?
        ora     flen
        beq     @done
        lda     @st+1                   ; buffer full?
        cmp     #<(frame+RXMAX-1)
        lda     @st+2
        sbc     #>(frame+RXMAX-1)
        bcs     @skip
        lda     RR_DATA
        jsr     @st
        lda     RR_DATA+1
        jsr     @st
        lda     flen                    ; flen -= 2 (stop at 0)
        sec
        sbc     #2
        sta     flen
        lda     flen+1
        sbc     #0
        sta     flen+1
        bcs     @w
        lda     #0
        sta     flen
        sta     flen+1
        beq     @w
@st:    sta     $FFFF
        inc     @st+1
        bne     :+
        inc     @st+2
:       rts
@skip:  lda     #$02                    ; RxCFG: skip the rest
        jsr     pp_a1
        lda     RR_PPDATA
        ora     #$40
        sta     RR_PPDATA
@done:  lda     frame+12
        cmp     #$88
        bne     @no
        lda     frame+13
        cmp     #$B5
        bne     @no
        ldx     #5
:       lda     frame+6,x
        sta     _rr_from,x
        dex
        bpl     :-
        ldx     #0
        lda     frame+14
        sta     _rr_rxlen
        beq     @no
:       lda     frame+15,x
        sta     _rr_rxbuf,x
        inx
        cpx     _rr_rxlen
        bne     :-
        lda     #1
        ldx     #0
        rts
@no:    lda     #0
        tax
        rts
