; ============================================================================
; BB-LAN lobby: WiC64 (userport WiFi, firmware 2.x), cc65 C callable
; ============================================================================
; Request:  "R", command, length (16 bit), payload       (C64 -> WiC64)
; Response: status, length (16 bit), payload             (WiC64 -> C64)
; Byte transfer over the userport: $DD01 data, the WiC64 confirms every byte
; with FLAG2 ($DD0D bit 4). PA2 ($DD00 bit 2) high: C64 sends, low: C64
; receives. Protocol as in the WiC64 team's library (wic64-library).
; ============================================================================

        .export _wic_exec
        .export _wic_cmd, _wic_out, _wic_outlen, _wic_in, _wic_inlen

IN_MAX  = 512

        .bss
_wic_cmd:       .res    1
_wic_outlen:    .res    1
_wic_out:       .res    255
_wic_inlen:     .res    2               ; bytes in _wic_in (the rest is skipped)
_wic_in:        .res    IN_MAX
status:         .res    1
left:           .res    2
savesp:         .res    1

        .code

; wait for the WiC64's handshake; after about 1 s without one the whole
; request fails (back to wic_exec's caller with $FF)
wait:   ldx     #0
        ldy     #0
:       lda     $DD0D
        and     #$10
        bne     :+
        dey
        bne     :-
        dex
        bne     :-
        ldx     savesp
        txs
        jmp     fail
:       rts

out:    sta     $DD01
        jmp     wait

in:     jsr     wait
        lda     $DD01
        rts

; unsigned char wic_exec(void): sends _wic_cmd with _wic_out[_wic_outlen],
; receives the answer into _wic_in. Returns the status (0 = ok), $FF if no
; WiC64 answered.
_wic_exec:
        tsx
        stx     savesp
        lda     $DD0D                   ; clear FLAG2
        lda     $DD02                   ; PA2 is an output
        ora     #$04
        sta     $DD02
        lda     $DD00                   ; PA2 high: we send
        ora     #$04
        sta     $DD00
        lda     #$FF
        sta     $DD03
        lda     #$52                    ; "R" in ASCII (not PETSCII)
        jsr     out
        lda     _wic_cmd
        jsr     out
        lda     _wic_outlen
        jsr     out
        lda     #0
        jsr     out
        lda     #0
        sta     status
:       ldx     status                  ; (status used as index here)
        cpx     _wic_outlen
        beq     :+
        lda     _wic_out,x
        jsr     out
        inc     status
        bne     :-
:       lda     #$00                    ; now receive
        sta     $DD03
        lda     $DD00
        and     #$FB                    ; PA2 low
        sta     $DD00
        jsr     wait                    ; the WiC64 confirms the turn around
        lda     $DD01                   ; and expects a handshake
        jsr     in
        sta     status
        jsr     in
        sta     left
        jsr     in
        sta     left+1
        lda     #0
        sta     _wic_inlen
        sta     _wic_inlen+1
@data:  lda     left
        ora     left+1
        beq     @done
        jsr     in
        ldx     _wic_inlen+1            ; keep at most IN_MAX bytes
        cpx     #>IN_MAX
        bcs     @skip
        pha
        lda     #<_wic_in
        clc
        adc     _wic_inlen
        sta     @st+1
        lda     #>_wic_in
        adc     _wic_inlen+1
        sta     @st+2
        pla
@st:    sta     $FFFF
        inc     _wic_inlen
        bne     @skip
        inc     _wic_inlen+1
@skip:  lda     left
        bne     :+
        dec     left+1
:       dec     left
        jmp     @data
@done:  lda     $DD0D
        lda     status
        ldx     #0
        rts
fail:   lda     #$00
        sta     $DD03
        lda     $DD0D
        lda     #$FF
        ldx     #0
        rts
