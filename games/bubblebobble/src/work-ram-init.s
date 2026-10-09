;===============================================================================
; work-ram-init.s - Work RAM initialization data
;===============================================================================
; Original address range: $4C00-$4FFF (1024 bytes)
; Segment: TMP_WORK_BUFFERS (runtime temporary region)
;
; This region contains lookup tables and work buffers used during gameplay.
; All addresses are software-only (not read by VIC hardware) and can relocate.
;
; Note: The first 256 bytes of the original work RAM area ($4B00-$4BFF) are
; now part of the VIC_CHARSET_B segment (in loader.s), since they occupy VIC
; charset B hardware space and get overwritten during init.
;
; Memory layout:
;   $4C00-$4DFF: Character bitmap work buffers (HUD/item compositing)
;   $4E00-$4E47: Platform screen address low byte table (regenerated each level)
;   $4E48-$4EFF: Graphics output buffer + gradient masks
;   $4F00-$4FF7: Platform screen address high byte table (regenerated each level)
;   $4FF8-$4FFF: Item table 2 (cleared to $FF each level transition)
;
; Note: Most of this data is overwritten at runtime. The initial values here
; are the original game binary contents, preserved for hash verification.
;===============================================================================

.segment "TMP_WORK_BUFFERS"

; --- $4C00-$4DFF: Character bitmap work buffers ---
; Used for HUD and item graphics compositing during gameplay.
        .byte   $ef, $5f, $5e, $fc, $e0, $40, $40, $d4, $ff, $ff, $ff, $fc, $e0, $00, $00, $04
        .byte   $ff, $ff, $ff, $fe, $ff, $ff, $ff, $fe, $c0, $00, $00, $02, $c0, $00, $00, $02
        .byte   $c0, $00, $00, $02, $c0, $00, $00, $02, $c0, $00, $00, $02, $c0, $00, $00, $02
        .byte   $c0, $00, $00, $02, $c0, $00, $00, $02, $e6, $66, $66, $66, $e6, $66, $66, $66
        .byte   $c0, $00, $00, $00, $c3, $04, $12, $40, $c9, $24, $92, $4c, $c3, $24, $92, $40
        .byte   $c9, $24, $92, $70, $c3, $04, $90, $40, $ff, $ff, $ff, $fe, $c0, $00, $00, $02
        .byte   $c0, $00, $00, $02, $c0, $00, $00, $02, $c0, $00, $00, $02, $c0, $00, $00, $02
        .byte   $c0, $00, $00, $02, $c1, $e7, $e7, $82, $c1, $00, $00, $82, $e1, $00, $00, $86
        .byte   $c1, $00, $00, $82, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00
        .byte   $f9, $1f, $f8, $9c, $c1, $00, $00, $80, $c1, $00, $00, $80, $c1, $00, $00, $80
        .byte   $e1, $68, $5b, $56, $ed, $6b, $c3, $56, $ed, $6b, $db, $fe, $e1, $08, $5b, $56
        .byte   $ff, $ff, $ff, $fe, $c0, $00, $00, $02, $c0, $00, $00, $02, $c0, $00, $00, $02
        .byte   $c0, $00, $00, $02, $c0, $00, $00, $02, $c0, $00, $00, $02, $c0, $00, $00, $02
        .byte   $c0, $00, $00, $02, $c3, $c3, $c3, $c2, $c0, $00, $00, $02, $c0, $00, $00, $02
        .byte   $c0, $00, $00, $02, $c0, $00, $00, $02, $fc, $3c, $3c, $3e, $c0, $00, $00, $02
        .byte   $c0, $00, $00, $02, $c0, $00, $00, $02, $c0, $00, $00, $00, $00, $00, $00, $00
        .byte   $07, $e0, $00, $20, $00, $20, $07, $f0, $00, $20, $00, $20, $07, $e0, $00, $20
        .byte   $00, $20, $07, $e0, $00, $20, $00, $20, $07, $e0, $00, $20, $00, $20, $0f, $e0
        .byte   $00, $20, $00, $3f, $0f, $ff, $00, $07, $00, $07, $c0, $00, $00, $02, $c0, $00
        .byte   $00, $02, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $80, $00, $c0, $00
        .byte   $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $01
        .byte   $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00
        .byte   $00, $00, $c0, $00, $80, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00
        .byte   $00, $00, $c0, $00, $00, $00, $c0, $01, $00, $00, $c0, $00, $00, $00, $c0, $00
        .byte   $00, $00, $c0, $00, $00, $00, $80, $00, $80, $00, $80, $04, $04, $e2, $08, $10
        .byte   $08, $08, $08, $c4, $08, $22, $0c, $13, $08, $02, $08, $c2, $08, $03, $08, $02
        .byte   $08, $72, $04, $03, $04, $02, $08, $02, $08, $7f, $08, $82, $09, $02, $06, $01
        .byte   $00, $00, $00, $00, $40, $00, $40, $00, $00, $00, $00, $00, $33, $ff, $00, $18
        .byte   $00, $18, $00, $00, $00, $00, $0f, $ff, $03, $01, $03, $01, $00, $00, $00, $00
        .byte   $3f, $f9, $00, $01, $00, $00, $00, $00, $00, $00, $0f, $ff, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $30, $ff, $00, $84, $00, $84, $00, $84
        .byte   $33, $ff, $00, $00, $00, $00, $00, $00, $33, $31, $00, $00, $00, $00, $00, $00

; --- $4E00-$4E47: Platform screen address low bytes ---
; Regenerated at each level start from level layout data.
D_4E00:
        .byte   $3c, $f9, $04, $00, $00, $00, $00, $00, $3c, $fe, $04, $00, $00, $00, $00, $00
        .byte   $40, $00, $00, $00, $00, $00, $3f, $ff, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $3f, $ff, $00, $00, $00, $00, $00, $00, $00, $00, $3f, $ff, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $3f, $ff, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $04, $09, $24

; --- $4E48-$4EFF: Graphics output buffer + gradient masks ---
; D_4E48 is used as output buffer for character compositing (72 bytes).
; Remainder contains gradient mask data and character bitmaps.
D_4E48:
        .byte   $09, $24, $09, $24, $09, $24, $09, $24
        .byte   $09, $24, $09, $24, $09, $24, $09, $24, $09, $24, $09, $24, $09, $24, $09, $24
        .byte   $09, $24, $09, $24, $09, $24, $09, $24, $00, $00, $00, $00, $40, $00, $00, $00
        .byte   $00, $01, $00, $10, $00, $19, $00, $7c, $00, $3c, $00, $1c, $00, $01, $00, $06
        .byte   $1f, $f4, $1f, $f4, $00, $06, $00, $01, $00, $1c, $00, $3c, $00, $7c, $00, $1c
        .byte   $00, $10, $00, $01, $00, $00, $00, $00, $00, $00, $40, $00, $40, $00, $00, $00
        .byte   $3f, $07, $00, $00, $00, $00, $00, $00, $00, $00, $3c, $1f, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $30, $7f, $00, $00, $00, $00, $00, $00, $00, $00, $21, $ff
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00
        .byte   $c0, $00, $00, $00, $c0, $07, $80, $00, $c0, $1f, $e0, $00, $c0, $3f, $10, $00
        .byte   $c0, $3e, $18, $00, $c0, $7e, $44, $00, $c0, $7e, $44, $00, $c0, $7f, $04, $00
        .byte   $c0, $6d, $8e, $00, $c0, $41, $fe, $80, $c0, $00, $b7, $80, $c0, $2c, $37, $80

; --- $4F00-$4FF7: Platform screen address high bytes ---
; Regenerated at each level start from level layout data.
D_4F00:
        .byte   $c0, $3d, $8f, $00, $c0, $1f, $bf, $00, $c0, $0f, $fc, $00, $c0, $06, $18, $00
        .byte   $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00
        .byte   $c0, $00, $00, $00, $40, $07, $c0, $01, $00, $39, $00, $00, $00, $00, $00, $73
        .byte   $00, $00, $00, $00, $00, $e6, $00, $00, $00, $00, $01, $cc, $00, $00, $00, $00
        .byte   $03, $99, $00, $00, $00, $00, $07, $32, $00, $00, $00, $00, $0e, $64, $40, $00
        .byte   $40, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $01
        .byte   $99, $98, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00
        .byte   $00, $00, $c0, $0c, $cc, $cc, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00
        .byte   $00, $00, $c0, $00, $00, $00, $c0, $66, $66, $64, $c0, $00, $00, $00, $c0, $00
        .byte   $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c3, $33, $33, $30, $c0, $00
        .byte   $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00
        .byte   $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00, $00, $00, $c0, $00
        .byte   $00, $00, $cf, $ff, $ff, $f0, $cf, $ff, $ff, $f0, $cc, $30, $cc, $70, $cd, $d7
        .byte   $6b, $b0, $cd, $d7, $6b, $30, $cc, $30, $ea, $b0, $cd, $d7, $69, $b0, $cd, $d7
        .byte   $6b, $b0, $cc, $37, $6c, $70, $cf, $ff, $ff, $f0, $cf, $ff, $ff, $f0, $c0, $00
        .byte   $00, $00, $c0, $00, $00, $00, $c0, $00

; --- $4FF8-$4FFF: Item table 2 ---
; Cleared to $FF during level transitions. Tracks special item state.
D_4FF8:
        .byte   $00, $00, $c0, $00, $00, $00, $c0, $00
