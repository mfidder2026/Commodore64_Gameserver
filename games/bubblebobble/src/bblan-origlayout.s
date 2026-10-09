; ============================================================================
; BB-LAN test build ORIGLAYOUT: the original game, byte for byte in the same
; place, with the DETTEST bot as joystick. Only the input reads are replaced
; by same-size patches; the bot lives in the space freed by the compressed
; level bitmaps. Used to check whether a crash also happens in the original.
;   python tools/build.py release -D ORIGLAYOUT=1 -D DETTEST=1 -o ol
; ============================================================================

.segment "BBLAN_CODE"

.export bb_tick, ol_passes, ol_hist

bb_in0:         .byte   $7F
bb_in1:         .byte   $FF
bb_key:         .byte   $F7             ; title: start a 2-player game
bb_tick:        .word   0
.ifndef BOT_SEED
BOT_SEED        = $ACE1
.endif
bot_rng:        .word   BOT_SEED
bot_dir:        .byte   0, 0

ol_joy:
        inc     bb_tick
        bne     @t
        inc     bb_tick+1
@t:     ldx     #$01
@pl:    lda     bb_tick
        and     #$07
        bne     @keep
        jsr     bot_rand
        and     #$07
        tay
        lda     bot_dirs,y
        sta     bot_dir,x
@keep:  jsr     bot_rand
        and     #$03
        bne     @nofire
        lda     #$10
        .byte   $2C
@nofire:
        lda     #$00
        ora     bot_dir,x
        eor     #$FF
        and     bot_idle,x
        sta     bb_in0,x
        dex
        bpl     @pl
        lda     bb_in0
        sta     D_85E8
        lda     bb_in1
        sta     D_85E9
        ldx     #$00
        rts

bot_rand:
        lsr     bot_rng+1
        ror     bot_rng
        bcc     @r
        lda     bot_rng+1
        eor     #$B4
        sta     bot_rng+1
@r:     lda     bot_rng
        rts

ol_passes:      .word   0
ol_last:        .byte   0
ol_hist:        .res    16              ; frames per pass (game running only)
ol_pass:
        inc     ol_passes
        bne     :+
        inc     ol_passes+1
:       lda     $08
        sec
        sbc     ol_last
        ldx     $08
        stx     ol_last
        ldx     MEMSIZ
        beq     :+
        and     #15
        tax
        inc     ol_hist,x
:       jmp     D_1844

bot_dirs:       .byte   $00, $04, $08, $01, $05, $09, $04, $08
bot_idle:       .byte   $7F, $FF
