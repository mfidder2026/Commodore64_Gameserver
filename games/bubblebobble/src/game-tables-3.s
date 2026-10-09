;===============================================================================
; game-tables-3.s - Game Tables Part 3 (GT_ASM3 segment)
;===============================================================================
; Character mask tables and sprite/charset data.
;
; D_ADB1 (72 bytes): OR mask table used during screen scrolling.
;   Indexed by X in an 8-byte inner loop across 9 characters (9*8 = 72).
;   Each group of 8 bytes corresponds to one character row being scrolled.
;   The value is ORed into character data before storing to output buffer.
;
; D_ADF9 (72 bytes): AND mask table used during screen scrolling.
;   Same indexing as D_ADB1. Character data is ANDed with this mask after
;   the first OR, then ORed with D_ADB1 again, to produce the second buffer.
;
; D_AE41 (16 bytes): Sprite/charset source data copied to $47F0 at init.
;===============================================================================

        .segment "GT_ASM3"

; --- Character OR mask table (72 bytes) ---
; 9 groups of 8 bytes, one per character row in the scroll region
D_ADB1:                                        ; $ADB1
        .byte   $00, $33, $33, $3f, $33, $33, $00, $00 ; Row 0
        .byte   $00, $00, $00, $33, $33, $3f, $00, $00 ; Row 1
        .byte   $00, $00, $00, $3f, $30, $30, $00, $00 ; Row 2
        .byte   $00, $00, $00, $3f, $30, $30, $00, $00 ; Row 3
        .byte   $00, $00, $00, $33, $3f, $03, $3f, $00 ; Row 4
        .byte   $00, $00, $00                           ; Row 5 (partial)
D_ADDC:                                        ; $ADDC
        .byte   $00
D_ADDD:                                        ; $ADDD
        .byte   $00, $00, $00, $00                      ; Row 5 (continued)
        .byte   $00, $33, $33, $33, $33, $3f, $00, $00 ; Row 6
        .byte   $00, $00, $3f, $33, $3f, $30, $30, $00 ; Row 7
        .byte   $00, $3c, $3c, $3c, $00, $3c, $00, $00 ; Row 8

; --- Character AND mask table (72 bytes) ---
; 9 groups of 8 bytes, matching the OR mask structure above
D_ADF9:                                        ; $ADF9
        .byte   $00, $00, $00, $00, $00                 ; Row 0 (partial)
D_ADFE:                                        ; $ADFE
        .byte   $00, $00, $ff                           ; Row 0 (continued)
        .byte   $3f, $3f, $00, $00, $00, $00, $00, $ff ; Row 1
        .byte   $ff, $ff, $00, $00, $00, $03, $03, $ff ; Row 2
        .byte   $ff, $ff, $00, $00, $00, $03, $03, $ff ; Row 3
        .byte   $ff, $ff, $00, $00, $00, $00, $00, $00 ; Row 4
        .byte   $ff, $ff, $3f, $3f, $3f, $3f, $3f, $3f ; Row 5
        .byte   $00, $00, $00, $00, $00, $00, $00, $ff ; Row 6
        .byte   $3f, $00, $00, $00, $00, $00, $03, $03 ; Row 7
        .byte   $00, $00, $00, $00, $00, $00, $00, $ff ; Row 8

; --- Sprite/charset source data (16 bytes) ---
; Copied to $47F0 during sprite/charset initialization
D_AE41:                                        ; $AE41
        .byte   $00, $00, $00, $10, $00, $00, $00, $00
        .byte   $00, $00, $00, $20, $20, $00, $00, $00
