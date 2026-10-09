; ============================================================================
; BB-LAN lobby: load and start the game. The game file loads over the lobby
; ($0801-...), so a small stub runs from the cassette buffer at $033C.
; The handoff block at $03C0 (written by C) is not touched by LOAD; the
; game's unpacker copies it into the game.
; ============================================================================

        .export _start_game

STUB    = $033C
SETLFS  = $FFBA
SETNAM  = $FFBD
LOAD    = $FFD5

        .code

; void __fastcall__ start_game(const char *name): never returns
_start_game:
        sta     $FB
        stx     $FC
        ldx     #stub_end - stub - 1    ; the stub to $033C
:       lda     stub,x
        sta     STUB,x
        dex
        bpl     :-
        ldy     #0                      ; then the name behind it
:       lda     ($FB),y
        beq     :+
        sta     STUB + name - stub,y
        iny
        cpy     #16
        bne     :-
:       sty     STUB + namelen - stub + 1
        jmp     STUB

; position independent: runs at $033C
stub:
        sei
        lda     #$37                    ; BASIC, KERNAL, I/O
        sta     $01
        cli
        lda     #1
        ldx     $BA                     ; the drive we were loaded from
        bne     :+
        ldx     #8
:       ldy     #1                      ; load to the address in the file
        jsr     SETLFS
namelen:
        lda     #0                      ; patched: length of the name
        ldx     #<(STUB + name - stub)
        ldy     #>(STUB + name - stub)
        jsr     SETNAM
        lda     #0
        jsr     LOAD
        bcs     :+
        jmp     $080D                   ; the game's SYS 2061
:       jmp     $FCE2                   ; load failed: reset
name:   .res    16
stub_end:

        .assert stub_end - stub <= $84, error, "loader stub too large for $033C-$03BF"
