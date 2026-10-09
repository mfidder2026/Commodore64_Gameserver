; =============================================================================
; BB-LAN self-extracting loader (used by tools/pack.py)
; =============================================================================
; PRG layout (load $0801):
;   BASIC "10 SYS2061" -> stub: copy unpacker (+raw tail) to $0200, jump there
;   unpacker ($0200-$03BF): with all RAM banked in ($01=$34)
;     1. move compressed blob up so it ends at BLOB_END
;     2. LZ-decompress forward to $0400 (in place, pack.py checks overlap)
;     3. copy the raw tail bytes (if any) behind the output
;     4. handoff: if the lobby left a block at $03C0 ("BL"), copy it to
;        HB_ADDR in the game and consume it
;     5. $01=$35, jump to ENTRY
; $03C0-$03FF is never touched before step 4 (the handoff lives there).
;
; Stream format: see tools/pack.py.
; Constants passed with -D: ENTRY, BLOB_END, OUT_END, CLEN, TAIL_LEN, HB_ADDR
; =============================================================================

src     = $02
dst     = $04
mptr    = $06
cnt     = $08

OUT_START = $0400
HANDOFF   = $03C0
HB_SIZE   = 24

.segment "LOADADDR"
        .word   $0801

.segment "STUB"
        .word   basic_end
        .word   10
        .byte   $9E, "2061", 0
basic_end:
        .word   0

        sei
        lda     #$0B                    ; blank screen while unpacking
        sta     $D011
        ldx     #0
@copy:  lda     __UNPACK_LOAD__,x
        sta     __UNPACK_RUN__,x
        inx
        bne     @copy
        ldx     #UNPACK_REST
@copy2: lda     __UNPACK_LOAD__+$FF,x   ; second page up to $03BF only
        sta     __UNPACK_RUN__+$FF,x
        dex
        bne     @copy2
        jmp     unpack

.import __UNPACK_LOAD__, __UNPACK_RUN__, __UNPACK_SIZE__, __BLOB_LOAD__
UNPACK_REST = $C0                       ; bytes copied to $0300-$03BF

.segment "UNPACK"
unpack:
        lda     #$34
        sta     $01

        ; --- 1. move blob up: [BLOB_LOAD, +CLEN) -> [BLOB_END-CLEN, BLOB_END)
        lda     #<(__BLOB_LOAD__ + CLEN - $100)
        sta     src
        lda     #>(__BLOB_LOAD__ + CLEN - $100)
        sta     src+1
        lda     #<(BLOB_END - $100)
        sta     dst
        lda     #>(BLOB_END - $100)
        sta     dst+1
        ldx     #>CLEN
        beq     @rest
@page:  ldy     #$FF
@pb:    lda     (src),y
        sta     (dst),y
        dey
        cpy     #$FF
        bne     @pb
        dec     src+1
        dec     dst+1
        dex
        bne     @page
@rest:
.if <CLEN <> 0
        lda     #<__BLOB_LOAD__
        sta     src
        lda     #>__BLOB_LOAD__
        sta     src+1
        lda     #<(BLOB_END - CLEN)
        sta     dst
        lda     #>(BLOB_END - CLEN)
        sta     dst+1
        ldy     #<CLEN - 1
@rb:    lda     (src),y
        sta     (dst),y
        dey
        cpy     #$FF
        bne     @rb
.endif

        ; --- 2. decompress
        lda     #<(BLOB_END - CLEN)
        sta     src
        lda     #>(BLOB_END - CLEN)
        sta     src+1
        lda     #<OUT_START
        sta     dst
        lda     #>OUT_START
        sta     dst+1
loop:
        lda     dst+1
        cmp     #>OUT_END
        bne     @go
        lda     dst
        cmp     #<OUT_END
        bne     @go
        jmp     done
@go:    ldy     #0
        lda     (src),y
        bmi     match

        sta     cnt                     ; literal: cnt = len-1
        inc     src                     ; skip the token
        bne     :+
        inc     src+1
:       ldy     #0
@lit:   lda     (src),y
        sta     (dst),y
        iny
        cpy     cnt
        bcc     @lit
        beq     @lit
        tya                             ; src += len, dst += len
        tax
        clc
        adc     src
        sta     src
        bcc     :+
        inc     src+1
:       txa
        jmp     advance

match:
        iny
        cmp     #$C0
        bcs     @long
        and     #$3F                    ; short: len L+2, dist o+1
        adc     #1                      ; (C=0) cnt = len-1 = L+1
        sta     cnt
        lda     dst
        clc
        sbc     (src),y                 ; dst - o - 1
        sta     mptr
        lda     dst+1
        sbc     #0
        sta     mptr+1
        lda     #2
        bne     @adv
@long:  and     #$3F
        cmp     #$3F
        beq     @ext
        adc     #2                      ; (C=0) cnt = len-1 = L+2
        sta     cnt
        lda     #3
        bne     @dist
@ext:   ldy     #3
        lda     (src),y                 ; len = e+66: cnt = e+65
        clc
        adc     #65
        sta     cnt
        ldy     #1
        lda     #4
@dist:  pha
        sec
        lda     dst
        sbc     (src),y
        sta     mptr
        iny
        lda     dst+1
        sbc     (src),y
        sta     mptr+1
        pla
@adv:   clc                             ; src += token size
        adc     src
        sta     src
        bcc     :+
        inc     src+1
:       ldy     #0
@mc:    lda     (mptr),y
        sta     (dst),y
        iny
        cpy     cnt
        bcc     @mc
        beq     @mc
        tya                             ; dst += len

advance:                                ; dst += A
        clc
        adc     dst
        sta     dst
        bcc     :+
        inc     dst+1
:       jmp     loop

done:
        ; --- 3. raw tail
.if TAIL_LEN > 0
        ldy     #0
@t:     lda     tail,y
        sta     OUT_END,y
        iny
        cpy     #TAIL_LEN
        bne     @t
.endif
        ; --- 4. handoff from the lobby
.if HB_ADDR <> 0
        lda     HANDOFF
        cmp     #'B'
        bne     @nohb
        lda     HANDOFF+1
        cmp     #'L'
        bne     @nohb
        ldx     #HB_SIZE-1
@hb:    lda     HANDOFF,x
        sta     HB_ADDR,x
        dex
        bpl     @hb
        inx
        stx     HANDOFF                 ; consumed
@nohb:
.endif
        ; --- 5. same start on every machine: clear the stack page below the
        ;        stack (the game keeps tables at $014B-$01A6 and does not
        ;        clear them; what the previous program left there differs)
        lda     #0
        ldx     #$DF
@clr:   sta     $0100,x
        dex
        bne     @clr
        sta     $0100
        ; --- 6. start the game
        lda     #$35
        sta     $01
        jmp     ENTRY

tail:
        .incbin "sfx-tail.bin"

.segment "BLOB"
        .incbin "sfx-blob.bin"
