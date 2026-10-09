; ============================================================================
; BB-LAN lobby: Ultimate Command Interface (Ultimate 64 / C64 Ultimate),
; cc65 C callable. One synchronous command at a time; uci.c builds them.
; ============================================================================
; Registers (only when "Command Interface" is enabled in the Ultimate menu):
;   $DF1C read: status, write: control      $DF1D read: id $C9, write: command
;   $DF1E response data                     $DF1F status data
; Never read-modify-write $DF1C (reading it returns the status).
; ============================================================================

        .export _uci_detect, _uci_exec
        .export _uci_cmd, _uci_cmdlen, _uci_resp, _uci_resplen, _uci_stat, _uci_statlen

UCI_CTRL        = $DF1C
UCI_CMD         = $DF1D
UCI_RESP        = $DF1E
UCI_STAT        = $DF1F
PUSH            = $01
ACC             = $02
ABORT           = $04
CLR_ERR         = $08
STATE           = $30
BUSY            = $10
MORE            = $30
RESP_MAX        = 300

        .bss
_uci_cmd:       .res    300
_uci_cmdlen:    .res    2
_uci_resp:      .res    RESP_MAX
_uci_resplen:   .res    2
_uci_stat:      .res    40
_uci_statlen:   .res    1
wait:           .res    2

        .code

; unsigned char uci_detect(void): 1 = interface present
_uci_detect:
        lda     UCI_CMD
        ldx     #0
        cmp     #$C9
        beq     :+
        cmp     #$49                    ; same, with an IRQ pending
        beq     :+
        txa
        rts
:       lda     #1
        rts

; unsigned char uci_exec(void): send _uci_cmd, wait, collect the answer.
; Returns 0 when the command finished, 1 on timeout (interface reset).
_uci_exec:
        jsr     idle
        bcs     @fail
        lda     #<_uci_cmd
        sta     @src+1
        lda     #>_uci_cmd
        sta     @src+2
        ldx     _uci_cmdlen             ; up to 300 bytes
        ldy     _uci_cmdlen+1
@put:   txa
        bne     :+
        tya
        beq     @push
        dey
:       dex
@src:   lda     $FFFF
        sta     UCI_CMD
        inc     @src+1
        bne     @put
        inc     @src+2
        bne     @put
@push:  lda     #PUSH
        sta     UCI_CTRL
        lda     #0
        sta     _uci_resplen
        sta     _uci_resplen+1
        sta     _uci_statlen
        sta     wait
        sta     wait+1
@busy:  lda     UCI_CTRL                ; wait while busy (~6 s max)
        and     #STATE
        cmp     #BUSY
        bne     @data
        inc     wait
        bne     @busy
        inc     wait+1
        lda     wait+1
        cmp     #$C0
        bne     @busy
        jsr     reset
@fail:  lda     #1
        ldx     #0
        rts
@data:  ldy     #0
@r:     lda     UCI_CTRL
        bpl     @s                      ; response data available?
        lda     UCI_RESP
        ldx     _uci_resplen+1          ; keep at most RESP_MAX bytes
        cpx     #>RESP_MAX
        bcc     :+
        ldx     _uci_resplen
        cpx     #<RESP_MAX
        bcs     :++
:       pha
        lda     #<_uci_resp
        clc
        adc     _uci_resplen
        sta     @rd+1
        lda     #>_uci_resp
        adc     _uci_resplen+1
        sta     @rd+2
        pla
@rd:    sta     $FFFF
        inc     _uci_resplen
        bne     :+
        inc     _uci_resplen+1
:       iny                             ; bounded (queues can saturate)
        bne     @r
@s:     ldy     #40
:       bit     UCI_CTRL
        bvc     :+                      ; status data available?
        lda     UCI_STAT
        ldx     _uci_statlen
        sta     _uci_stat,x
        inc     _uci_statlen
        dey
        bne     :-
:       lda     UCI_CTRL
        and     #STATE
        beq     :+                      ; idle: nothing to acknowledge
        tay
        lda     #ACC
        sta     UCI_CTRL
        cpy     #MORE
        bne     :+
        jmp     @busy                   ; another block follows
:       lda     #0
        tax
        rts

; wait until the interface is idle; C=1 if it does not get there
idle:   ldx     #0
        ldy     #0
:       lda     UCI_CTRL
        and     #STATE
        beq     @ok
        cmp     #$20                    ; data left over: acknowledge
        bcc     :+
        lda     #ACC
        sta     UCI_CTRL
:       dex
        bne     :--
        dey
        bne     :--
        jsr     reset
        lda     UCI_CTRL
        and     #STATE
        beq     @ok
        sec
        rts
@ok:    clc
        rts

reset:  lda     #ABORT
        sta     UCI_CTRL
        ldx     #0
:       lda     UCI_CTRL
        and     #(STATE | ABORT)
        beq     :+
        dex
        bne     :-
:       lda     #CLR_ERR
        sta     UCI_CTRL
        rts
