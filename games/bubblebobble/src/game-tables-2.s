;===============================================================================
; game-tables-2.s - Game Tables Part 2 (GT_ASM2 segment)
;===============================================================================
; Item/score/enemy state lookup tables, sprite graphics pointers,
; pathfinding tables, and screen layout data.
;===============================================================================

        .segment "GT_ASM2"

; --- Part 2a: Item/score/enemy state lookup tables (476 bytes) ---

        .byte   $20, $00, $33, $23, $30, $dd, $ed, $dc, $d5, $a9, $5c, $35, $a9
D_A885:
        .byte   $70
D_A886:
        .byte   $d6, $aa
        .byte   $5c, $da, $aa, $9c, $aa
D_A88D:
        .byte   $9a, $a8, $aa, $56, $aa
D_A892:                                        ; $A892 - Points item char block indices (47 bytes)
        .byte   $2c, $34, $2d, $1e, $2e, $29, $2b, $0b, $00, $1b, $31, $30, $02, $1c, $0b, $0e
        .byte   $26, $01, $11, $19, $20, $22, $21, $05, $24, $26, $0c, $08, $17, $25, $26, $36
        .byte   $0f, $23, $06, $15, $27, $2f, $04, $28, $04, $07, $04, $07, $07, $38, $32
D_A8C1:                                        ; $A8C1 - Powerup item char block indices (35 bytes)
        .byte   $09, $1d, $1d, $0d, $0d, $0d, $13, $13, $13, $14, $14, $14, $1f, $1f, $1f, $12
        .byte   $16, $16, $16, $1a, $0a, $1d, $0a, $1d, $37, $35, $35, $35, $14, $18, $1a, $33
        .byte   $39, $39, $2a
D_A8E4:                                        ; $A8E4 - Points item color indices (47 bytes, lower nibble only)
        .byte   $0c, $09, $09, $09, $0f, $0a, $0a, $0e, $0f, $0f, $0a, $0a, $0a, $0a, $0a, $0f
        .byte   $0b, $0f, $0a, $0c, $0d, $0f, $0f, $0a, $0d, $09, $0a, $0a
D_A900:
        .byte   $0f, $0f, $0f, $09
D_A904:
        .byte   $0f
D_A905:
        .byte   $0a, $0c, $0b, $0f, $0a
D_A90A:
        .byte   $0f
D_A90B:
        .byte   $0f, $0a, $0f, $0d, $0d, $0c, $0f, $0f
D_A913:                                        ; $A913 - Powerup item color indices (35 bytes, lower nibble only)
        .byte   $0a, $09, $0a, $0f, $0c, $0e, $0a, $0f, $0b, $0a
D_A91D:
        .byte   $0f
D_A91E:
        .byte   $0c, $0c, $0a
D_A921:
        .byte   $0e, $0d
D_A923:
        .byte   $0d, $0c, $0f, $0d
D_A927:
        .byte   $0e, $0f, $0c, $0b
D_A92B:
        .byte   $0a, $0f, $0e, $09, $0d, $0c
D_A931:
        .byte   $0c, $0a
        .byte   $0a, $09, $0d
D_A936:                                        ; $A936 - Enemy score value table
        .byte   $01, $04, $05, $05, $07, $07, $20, $35, $50, $50, $50, $70, $70, $75, $85, $01
        .byte   $01, $01, $01, $01, $01, $01
D_A94C:
        .byte   $02, $02, $02, $02, $02, $03, $03, $03, $03, $03
        .byte   $04, $04, $05, $05, $06, $06, $07, $07, $08, $08, $09, $09, $10, $10, $12
D_A965:                                        ; $A965 - Special item score value table
        .byte   $10, $50, $50, $10, $10, $10, $10, $10, $10, $10, $10, $10, $10, $10, $10, $20
        .byte   $20, $20, $20, $20, $01, $50, $01, $50, $01, $01, $01, $01, $03, $04, $05, $08
D_A985:
        .byte   $02, $02, $05
D_A988:                                        ; $A988 - Enemy state temporary storage
        .byte   $fc, $f3, $cf, $cf, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $cf, $cf, $f3, $fc
        .byte   $3f, $cf, $f3, $f3, $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc, $f3, $f3, $cf, $3f
D_A9A8:                                        ; $A9A8 - ROUND text indices
        .byte   $0a, $0b, $0c, $0d, $0e, $13
D_A9AE:                                        ; $A9AE - Level tens digit storage
        .byte   $01
D_A9AF:                                        ; $A9AF - Level ones digit storage
        .byte   $00
D_A9B0:                                        ; $A9B0 - Graphics mode flag
        .byte   $00
D_A9B1:                                        ; $A9B1 - Hurry-up timer
        .byte   $ff
D_A9B2:                                        ; $A9B2 - Enemy state flags (18 bytes)
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $00, $00, $00, $00, $07
        .byte   $00, $00
D_A9C4:                                        ; $A9C4 - Enemy X sub-position (18 bytes)
        .byte   $00, $00
D_A9C6:                                        ; $A9C6 - Projectile state array 1
        .byte   $02, $01, $00, $00, $03, $02, $00, $02, $01, $00
D_A9D0:
        .byte   $03, $03, $00, $00, $00, $00
D_A9D6:                                        ; $A9D6 - Enemy direction flags (18 bytes)
        .byte   $00, $00
D_A9D8:                                        ; $A9D8 - Projectile state array 2
        .byte   $00, $06, $00, $00
D_A9DC:
        .byte   $02
D_A9DD:
        .byte   $00, $00, $00, $00, $00, $00, $00, $06, $00, $02, $04
D_A9E8:                                        ; $A9E8 - Enemy AI routine indices (18 bytes)
        .byte   $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d
        .byte   $7d, $7d
D_A9FA:                                        ; $A9FA - Enemy special flags (18 bytes)
        .byte   $16, $12
D_A9FC:                                        ; $A9FC - Projectile state array 3
        .byte   $22, $0e, $0a
D_A9FF:
        .byte   $06, $01, $cf, $a1, $1b, $be, $6e, $57, $4c, $2b, $08, $00, $f6
D_AA0C:                                        ; $AA0C - Enemy X positions (18 bytes)
        .byte   $da, $e2
D_AA0E:                                        ; $AA0E - Enemy X positions (offset by 2)
        .byte   $d8, $de, $d4, $dc, $d2, $50, $3c, $68, $56, $24, $72, $72, $24, $2c, $24, $24
D_AA1E:                                        ; $AA1E - Enemy Y positions (18 bytes)
        .byte   $4b, $47
D_AA20:                                        ; $AA20 - Enemy Y positions (offset by 2)
        .byte   $45, $4b, $4d, $55, $47, $dd, $dd, $dd, $dd, $0d, $0d, $0d, $db, $dd, $cf, $b9
D_AA30:                                        ; $AA30 - Bubble type storage
        .byte   $02, $00, $ff, $ff, $ff, $ff, $ff, $02, $04, $04, $04, $04, $04, $04, $04, $04
        .byte   $04, $04
D_AA42:                                        ; $AA42 - Saved enemy type during capture
        .byte   $3a, $00
D_AA44:                                        ; $AA44 - Enemy data
        .byte   $04, $04, $04, $04, $04, $18, $04, $04, $00, $04, $04, $04, $0a, $04, $0a, $04

; --- Sprite graphics pointer table - low bytes (58 bytes) ---
; Combined with sprite_gfx_ptr_hi to form full addresses for sprite graphics
; Entries 0-11: bubble masks ($8000-$8210)
; Entries 12-43: software sprites ($9080-$9810)
; Entries 44-47: null ($0000)
; Entries 48-57: software sprites ($8F00-$9870)
sprite_gfx_ptr_lo:
        .byte   <bubble_mask_0x000                        ; Entry 0
        .byte   <bubble_mask_0x030                        ; Entry 1
        .byte   <bubble_mask_0x060                        ; Entry 2
        .byte   <bubble_mask_0x090                        ; Entry 3
        .byte   <bubble_mask_0x0c0                        ; Entry 4
        .byte   <bubble_mask_0x0f0                        ; Entry 5
        .byte   <bubble_mask_0x120                        ; Entry 6
        .byte   <bubble_mask_0x150                        ; Entry 7
        .byte   <bubble_mask_0x180                        ; Entry 8
        .byte   <bubble_mask_0x1b0                        ; Entry 9
        .byte   <bubble_mask_0x1e0                        ; Entry 10
        .byte   <bubble_mask_0x210                        ; Entry 11
        .byte   <soft_spr_0x180                           ; Entry 12
        .byte   <(soft_spr_0x180 + $30)                   ; Entry 13
        .byte   <(soft_spr_0x180 + $60)                   ; Entry 14
        .byte   <(soft_spr_0x240 - $30)                   ; Entry 15
        .byte   <soft_spr_0x240                           ; Entry 16
        .byte   <(soft_spr_0x240 + $30)                   ; Entry 17
        .byte   <(soft_spr_0x240 + $60)                   ; Entry 18
        .byte   <(soft_spr_0x240 + $90)                   ; Entry 19
        .byte   <soft_spr_0x300                           ; Entry 20 (lightning bubble)
        .byte   <(soft_spr_0x300 + $30)                   ; Entry 21 (lightning bubble)
        .byte   <(soft_spr_0x300 + $60)                   ; Entry 22 (lightning bubble)
        .byte   <(soft_spr_0x300 + $90)                   ; Entry 23 (lightning bubble)
        .byte   <soft_spr_0x580                           ; Entry 24
        .byte   <(soft_spr_0x580 + $30)                   ; Entry 25
        .byte   <(soft_spr_0x580 + $60)                   ; Entry 26
        .byte   <soft_spr_0x610                           ; Entry 27
        .byte   <(soft_spr_0x610 + $30)                   ; Entry 28
        .byte   <(soft_spr_0x610 + $60)                   ; Entry 29
        .byte   <(soft_spr_0x610 + $90)                   ; Entry 30
        .byte   <(soft_spr_0x610 + $C0)                   ; Entry 31
        .byte   <soft_spr_0x700                           ; Entry 32
        .byte   <(soft_spr_0x700 + $30)                   ; Entry 33
        .byte   <(soft_spr_0x700 + $60)                   ; Entry 34
        .byte   <(soft_spr_0x700 + $90)                   ; Entry 35
        .byte   <(soft_spr_0x700 + $C0)                   ; Entry 36
        .byte   <(soft_spr_0x700 + $F0)                   ; Entry 37
        .byte   <soft_spr_0x820                           ; Entry 38
        .byte   <(soft_spr_0x820 + $30)                   ; Entry 39
        .byte   <(soft_spr_0x820 + $60)                   ; Entry 40
        .byte   <(soft_spr_0x820 + $90)                   ; Entry 41
        .byte   <(soft_spr_0x820 + $C0)                   ; Entry 42
        .byte   <soft_spr_0x910                           ; Entry 43
        .byte   $00, $00, $00, $00                        ; Entries 44-47: null
        .byte   <soft_spr_0x000                           ; Entry 48
        .byte   <(soft_spr_0x000 + $30)                   ; Entry 49
        .byte   <(soft_spr_0x000 + $60)                   ; Entry 50
        .byte   <(soft_spr_0x000 + $90)                   ; Entry 51
        .byte   <soft_spr_0x400                           ; Entry 52
        .byte   <(soft_spr_0x400 + $30)                   ; Entry 53
        .byte   <(soft_spr_0x400 + $60)                   ; Entry 54
        .byte   <(soft_spr_0x400 + $90)                   ; Entry 55
        .byte   <soft_spr_0x940                           ; Entry 56
        .byte   <(soft_spr_0x940 + $30)                   ; Entry 57

; --- Sprite graphics pointer table - high bytes (58 bytes) ---
; Combined with sprite_gfx_ptr_lo to form full addresses for sprite graphics
sprite_gfx_ptr_hi:
        .byte   >bubble_mask_0x000                        ; Entry 0
        .byte   >bubble_mask_0x030                        ; Entry 1
        .byte   >bubble_mask_0x060                        ; Entry 2
        .byte   >bubble_mask_0x090                        ; Entry 3
        .byte   >bubble_mask_0x0c0                        ; Entry 4
        .byte   >bubble_mask_0x0f0                        ; Entry 5
        .byte   >bubble_mask_0x120                        ; Entry 6
        .byte   >bubble_mask_0x150                        ; Entry 7
        .byte   >bubble_mask_0x180                        ; Entry 8
        .byte   >bubble_mask_0x1b0                        ; Entry 9
        .byte   >bubble_mask_0x1e0                        ; Entry 10
        .byte   >bubble_mask_0x210                        ; Entry 11
        .byte   >soft_spr_0x180                           ; Entry 12
        .byte   >(soft_spr_0x180 + $30)                   ; Entry 13
        .byte   >(soft_spr_0x180 + $60)                   ; Entry 14
        .byte   >(soft_spr_0x240 - $30)                   ; Entry 15
        .byte   >soft_spr_0x240                           ; Entry 16
        .byte   >(soft_spr_0x240 + $30)                   ; Entry 17
        .byte   >(soft_spr_0x240 + $60)                   ; Entry 18
        .byte   >(soft_spr_0x240 + $90)                   ; Entry 19
        .byte   >soft_spr_0x300                           ; Entry 20 (lightning bubble)
        .byte   >(soft_spr_0x300 + $30)                   ; Entry 21 (lightning bubble)
        .byte   >(soft_spr_0x300 + $60)                   ; Entry 22 (lightning bubble)
        .byte   >(soft_spr_0x300 + $90)                   ; Entry 23 (lightning bubble)
        .byte   >soft_spr_0x580                           ; Entry 24
        .byte   >(soft_spr_0x580 + $30)                   ; Entry 25
        .byte   >(soft_spr_0x580 + $60)                   ; Entry 26
        .byte   >soft_spr_0x610                           ; Entry 27
        .byte   >(soft_spr_0x610 + $30)                   ; Entry 28
        .byte   >(soft_spr_0x610 + $60)                   ; Entry 29
        .byte   >(soft_spr_0x610 + $90)                   ; Entry 30
        .byte   >(soft_spr_0x610 + $C0)                   ; Entry 31
        .byte   >soft_spr_0x700                           ; Entry 32
        .byte   >(soft_spr_0x700 + $30)                   ; Entry 33
        .byte   >(soft_spr_0x700 + $60)                   ; Entry 34
        .byte   >(soft_spr_0x700 + $90)                   ; Entry 35
        .byte   >(soft_spr_0x700 + $C0)                   ; Entry 36
        .byte   >(soft_spr_0x700 + $F0)                   ; Entry 37
        .byte   >soft_spr_0x820                           ; Entry 38
        .byte   >(soft_spr_0x820 + $30)                   ; Entry 39
        .byte   >(soft_spr_0x820 + $60)                   ; Entry 40
        .byte   >(soft_spr_0x820 + $90)                   ; Entry 41
        .byte   >(soft_spr_0x820 + $C0)                   ; Entry 42
        .byte   >soft_spr_0x910                           ; Entry 43
        .byte   $00, $00, $00, $00                        ; Entries 44-47: null
        .byte   >soft_spr_0x000                           ; Entry 48
        .byte   >(soft_spr_0x000 + $30)                   ; Entry 49
        .byte   >(soft_spr_0x000 + $60)                   ; Entry 50
        .byte   >(soft_spr_0x000 + $90)                   ; Entry 51
        .byte   >soft_spr_0x400                           ; Entry 52
        .byte   >(soft_spr_0x400 + $30)                   ; Entry 53
        .byte   >(soft_spr_0x400 + $60)                   ; Entry 54
        .byte   >(soft_spr_0x400 + $90)                   ; Entry 55
        .byte   >soft_spr_0x940                           ; Entry 56
        .byte   >(soft_spr_0x940 + $30)                   ; Entry 57

; --- Part 2b: Sprite/pathfinding/screen layout tables (685 bytes) ---

; --- AND mask pointer table - low bytes (58 bytes) ---
; Combined with D_AB02 to form full addresses for AND mask data
; Entries 0-11: Bubble AND masks (bubble_masks + $240..$450)
; Entries 12-42: Repeat bubble AND masks 8-11 pattern
; Entries 44-47: null
; Entries 48-57: Software sprite AND masks
D_AAC8:
        .byte   <bubble_and_mask_0x240                   ; Entry 0
        .byte   <bubble_and_mask_0x270                   ; Entry 1
        .byte   <bubble_and_mask_0x2a0                   ; Entry 2
        .byte   <bubble_and_mask_0x2d0                   ; Entry 3
        .byte   <bubble_and_mask_0x300                   ; Entry 4
        .byte   <bubble_and_mask_0x330                   ; Entry 5
        .byte   <bubble_and_mask_0x360                   ; Entry 6
        .byte   <bubble_and_mask_0x390                   ; Entry 7
        .byte   <bubble_and_mask_0x3c0                   ; Entry 8
        .byte   <bubble_and_mask_0x3f0                   ; Entry 9
        .byte   <bubble_and_mask_0x420                   ; Entry 10
        .byte   <bubble_and_mask_0x450                   ; Entry 11
        .byte   <bubble_and_mask_0x3c0                   ; Entry 12
        .byte   <bubble_and_mask_0x3f0                   ; Entry 13
        .byte   <bubble_and_mask_0x420                   ; Entry 14
        .byte   <bubble_and_mask_0x450                   ; Entry 15
        .byte   <bubble_and_mask_0x3c0                   ; Entry 16
        .byte   <bubble_and_mask_0x3f0                   ; Entry 17
        .byte   <bubble_and_mask_0x420                   ; Entry 18
        .byte   <bubble_and_mask_0x450                   ; Entry 19
        .byte   <bubble_and_mask_0x3c0                   ; Entry 20 (lightning bubble)
        .byte   <bubble_and_mask_0x3f0                   ; Entry 21 (lightning bubble)
        .byte   <bubble_and_mask_0x420                   ; Entry 22 (lightning bubble)
        .byte   <bubble_and_mask_0x450                   ; Entry 23 (lightning bubble)
        .byte   <bubble_and_mask_0x3c0                   ; Entry 24
        .byte   <bubble_and_mask_0x3f0                   ; Entry 25
        .byte   <bubble_and_mask_0x420                   ; Entry 26
        .byte   <bubble_and_mask_0x450                   ; Entry 27
        .byte   <bubble_and_mask_0x3c0                   ; Entry 28
        .byte   <bubble_and_mask_0x3f0                   ; Entry 29
        .byte   <bubble_and_mask_0x420                   ; Entry 30
        .byte   <bubble_and_mask_0x450                   ; Entry 31
        .byte   <bubble_and_mask_0x3c0                   ; Entry 32
        .byte   <bubble_and_mask_0x3f0                   ; Entry 33
        .byte   <bubble_and_mask_0x420                   ; Entry 34
        .byte   <bubble_and_mask_0x450                   ; Entry 35
        .byte   <bubble_and_mask_0x3c0                   ; Entry 36
        .byte   <bubble_and_mask_0x3f0                   ; Entry 37
        .byte   <bubble_and_mask_0x420                   ; Entry 38
        .byte   <bubble_and_mask_0x450                   ; Entry 39
        .byte   <bubble_and_mask_0x3c0                   ; Entry 40
        .byte   <bubble_and_mask_0x3f0                   ; Entry 41
        .byte   <bubble_and_mask_0x420                   ; Entry 42
        .byte   <bubble_and_mask_0x450                   ; Entry 43
        .byte   $00, $00, $00, $00                       ; Entries 44-47: null
        .byte   <(soft_spr_0x000 + $C0)                  ; Entry 48
        .byte   <(soft_spr_0x000 + $F0)                  ; Entry 49
        .byte   <(soft_spr_0x000 + $120)                 ; Entry 50
        .byte   <(soft_spr_0x000 + $150)                 ; Entry 51
        .byte   <(soft_spr_0x400 + $C0)                  ; Entry 52
        .byte   <(soft_spr_0x400 + $F0)                  ; Entry 53
        .byte   <(soft_spr_0x400 + $120)                 ; Entry 54
        .byte   <(soft_spr_0x400 + $150)                 ; Entry 55
        .byte   <(soft_spr_0x400 + $C0)                  ; Entry 56
        .byte   <(soft_spr_0x400 + $120)                 ; Entry 57

; --- AND mask pointer table - high bytes (58 bytes) ---
; Combined with D_AAC8 to form full addresses for AND mask data
D_AB02:
        .byte   >bubble_and_mask_0x240                   ; Entry 0
        .byte   >bubble_and_mask_0x270                   ; Entry 1
        .byte   >bubble_and_mask_0x2a0                   ; Entry 2
        .byte   >bubble_and_mask_0x2d0                   ; Entry 3
        .byte   >bubble_and_mask_0x300                   ; Entry 4
        .byte   >bubble_and_mask_0x330                   ; Entry 5
        .byte   >bubble_and_mask_0x360                   ; Entry 6
        .byte   >bubble_and_mask_0x390                   ; Entry 7
        .byte   >bubble_and_mask_0x3c0                   ; Entry 8
        .byte   >bubble_and_mask_0x3f0                   ; Entry 9
        .byte   >bubble_and_mask_0x420                   ; Entry 10
        .byte   >bubble_and_mask_0x450                   ; Entry 11
        .byte   >bubble_and_mask_0x3c0                   ; Entry 12
        .byte   >bubble_and_mask_0x3f0                   ; Entry 13
        .byte   >bubble_and_mask_0x420                   ; Entry 14
        .byte   >bubble_and_mask_0x450                   ; Entry 15
        .byte   >bubble_and_mask_0x3c0                   ; Entry 16
        .byte   >bubble_and_mask_0x3f0                   ; Entry 17
        .byte   >bubble_and_mask_0x420                   ; Entry 18
        .byte   >bubble_and_mask_0x450                   ; Entry 19
        .byte   >bubble_and_mask_0x3c0                   ; Entry 20 (lightning bubble)
        .byte   >bubble_and_mask_0x3f0                   ; Entry 21 (lightning bubble)
        .byte   >bubble_and_mask_0x420                   ; Entry 22 (lightning bubble)
        .byte   >bubble_and_mask_0x450                   ; Entry 23 (lightning bubble)
        .byte   >bubble_and_mask_0x3c0                   ; Entry 24
        .byte   >bubble_and_mask_0x3f0                   ; Entry 25
        .byte   >bubble_and_mask_0x420                   ; Entry 26
        .byte   >bubble_and_mask_0x450                   ; Entry 27
        .byte   >bubble_and_mask_0x3c0                   ; Entry 28
        .byte   >bubble_and_mask_0x3f0                   ; Entry 29
        .byte   >bubble_and_mask_0x420                   ; Entry 30
        .byte   >bubble_and_mask_0x450                   ; Entry 31
        .byte   >bubble_and_mask_0x3c0                   ; Entry 32
        .byte   >bubble_and_mask_0x3f0                   ; Entry 33
        .byte   >bubble_and_mask_0x420                   ; Entry 34
        .byte   >bubble_and_mask_0x450                   ; Entry 35
        .byte   >bubble_and_mask_0x3c0                   ; Entry 36
        .byte   >bubble_and_mask_0x3f0                   ; Entry 37
        .byte   >bubble_and_mask_0x420                   ; Entry 38
        .byte   >bubble_and_mask_0x450                   ; Entry 39
        .byte   >bubble_and_mask_0x3c0                   ; Entry 40
        .byte   >bubble_and_mask_0x3f0                   ; Entry 41
        .byte   >bubble_and_mask_0x420                   ; Entry 42
        .byte   >bubble_and_mask_0x450                   ; Entry 43
        .byte   $00, $00, $00, $00                       ; Entries 44-47: null
        .byte   >(soft_spr_0x000 + $C0)                  ; Entry 48
        .byte   >(soft_spr_0x000 + $F0)                  ; Entry 49
        .byte   >(soft_spr_0x000 + $120)                 ; Entry 50
        .byte   >(soft_spr_0x000 + $150)                 ; Entry 51
        .byte   >(soft_spr_0x400 + $C0)                  ; Entry 52
        .byte   >(soft_spr_0x400 + $F0)                  ; Entry 53
        .byte   >(soft_spr_0x400 + $120)                 ; Entry 54
        .byte   >(soft_spr_0x400 + $150)                 ; Entry 55
        .byte   >(soft_spr_0x400 + $C0)                  ; Entry 56
        .byte   >(soft_spr_0x400 + $120)                 ; Entry 57
        .byte   $00, $01, $02, $01, $00                  ; Trailing data ($AB3C-$AB40)
D_AB41:                                        ; $AB41 - Bubble anim mask ptr low bytes
        .byte   <(bubble_anim_masks + $20)
        .byte   <(bubble_anim_masks + $50)
        .byte   <(bubble_anim_masks + $80)
        .byte   <(bubble_anim_masks + $B0)
        .byte   <(bubble_anim_masks + $E0)
        .byte   <(bubble_anim_masks + $110)
        .byte   <(bubble_anim_masks + $140)
        .byte   <(bubble_anim_masks + $170)
D_AB49:                                        ; $AB49 - Bubble anim mask ptr high bytes
        .byte   >(bubble_anim_masks + $20)
        .byte   >(bubble_anim_masks + $50)
        .byte   >(bubble_anim_masks + $80)
        .byte   >(bubble_anim_masks + $B0)
        .byte   >(bubble_anim_masks + $E0)
        .byte   >(bubble_anim_masks + $110)
        .byte   >(bubble_anim_masks + $140)
        .byte   >(bubble_anim_masks + $170)
D_AB51:                                        ; $AB51 - Player score offset table
        .byte   $02
D_AB52:                                        ; $AB52 - Score value table for pickups
        .byte   $05
D_AB53:                                        ; $AB53 - Player sprite mask table
        .byte   $01, $02
D_AB55:                                        ; $AB55 - Sprite enable masks
        .byte   $04, $08, $10, $20, $40, $80
D_AB5B:                                        ; $AB5B - ORA col1 low bytes (Routine 3)
        .byte   <soft_spr_0x9a0, <soft_spr_0x9c0, <soft_spr_0x9e0, <soft_spr_0xa00
D_AB5F:                                        ; $AB5F - AND col1 low bytes (Routine 3)
        .byte   <soft_spr_0xa40, <soft_spr_0xa60
D_AB61:                                        ; $AB61 - Entity animation frame table
        .byte   $80, $a0, $0c, $0f, $05, $0d, $04, $05
D_AB69:                                        ; $AB69 - Entity sprite data table
        .byte   $03, $0f, $73, $7f, $8b, $97, $9f, $ab
D_AB71:                                        ; $AB71 - Entity animation offset table
        .byte   $b3, $bb, $1e, $19, $00, $0f, $14, $14
D_AB79:                                        ; $AB79 - Entity sprite index table
        .byte   $0a, $14, $04, $04, $04, $04, $04, $02
D_AB81:                                        ; $AB81 - Score value table
        .byte   $02, $00, $0b, $0b, $0b, $07, $0b, $07
D_AB89:                                        ; $AB89 - Animation offset table
        .byte   $07, $05, $07, $07, $07, $03, $07, $03, $03, $01
D_AB93:                                        ; $AB93 - Text string: credits display
        .byte   $1f, $21, $02, $02, $3e, $3e
        .byte   $3e, $3e, $3e, $3e, $3e, $1f, $22, $09, $3e, $3e, $3e, $3e
D_ABA5:                                        ; $ABA5 - Loader completion check
        .byte   $3e, $1f, $22, $10, $3e, $3e, $3e, $3e, $3e, $1f, $21, $16, $3e, $3e, $3e, $3e
        .byte   $3e, $3e, $3e, $1f, $23, $04, $07, $21, $55, $50, $1f, $23, $0b, $22, $55, $50
        .byte   $1f, $23, $12, $54, $4f, $50, $05, $1f, $21, $05, $40
D_ABD0:
        .byte   $40, $40, $40, $40, $20
        .byte   $20, $1f, $21, $07, $40, $40, $40, $40, $3d, $3d, $3d, $03, $1f, $21, $0c, $40
        .byte   $40, $40, $40, $40, $20, $20, $1f, $21, $0e, $40, $40, $40, $40, $3d, $3d, $3d
        .byte   $1f, $21, $14, $01, $40, $40, $40, $40, $40, $40, $20, $10
D_AC01:                                        ; $AC01 - Flying enemy pathfinding table (low)
        .byte   $60
D_AC02:                                        ; $AC02 - Flying enemy pathfinding table (high)
        .byte   $ff
D_AC03:                                        ; $AC03 - Screen position table (low bytes)
        .byte   $88
D_AC04:                                        ; $AC04 - Screen position table (high bytes)
        .byte   $ff, $b0, $ff, $d8, $ff
D_AC09:                                        ; $AC09 - Data pointer table low
        .byte   $00
D_AC0A:                                        ; $AC0A - Data pointer table high
        .byte   $00, $28, $00, $50, $00, $78, $00, $a0, $00, $c8, $00, $f0, $00, $18, $01, $40
        .byte   $01, $68, $01, $90, $01, $b8, $01, $e0, $01, $08, $02, $30, $02, $58, $02, $80
        .byte   $02, $a8, $02, $d0, $02, $f8, $02, $20, $03, $48, $03, $70, $03, $98, $03, $c0
        .byte   $03, $e8, $03, $10, $04, $38, $04
D_AC41:                                        ; $AC41 - Text string: game start text
        .byte   $1f, $05, $00, $07, $4e, $4f, $57, $5e, $40
        .byte   $49, $54, $40, $49, $53, $40, $54, $48, $45, $40, $42, $45, $47, $49, $4e, $4e
        .byte   $49, $4e, $47, $40, $4f, $46, $40, $41, $1f, $05, $02, $46, $41, $4e, $54, $41
        .byte   $53, $49, $43, $40, $53, $54, $4f, $52, $59, $5c, $5c, $40, $4c, $45, $54, $5f
        .byte   $53, $40, $4d, $41, $4b, $45, $40, $41, $1f, $04, $04, $4a, $4f, $55, $52, $4e
        .byte   $45, $59, $40, $54, $4f, $40, $54, $48, $45, $40, $43, $41, $56, $45, $40, $4f
        .byte   $46, $40, $4d, $4f, $4e, $53, $54, $45, $52, $53, $5c, $1f, $0d, $06, $5c, $40
        .byte   $47, $4f, $4f, $44, $40, $40, $4c, $55, $43, $4b, $40, $5c
D_ACB6:                                        ; $ACB6 - Enemy animation direction table
        .byte   $10, $04, $04, $02, $02, $02, $00
D_ACBD:                                        ; $ACBD - Sprite character data table
        .byte   $00, $00, $1c, $40, $41, $40, $1c
D_ACC4:                                        ; $ACC4 - Direction table
        .byte   $00, $08, $08, $09, $09, $08, $08
D_ACCB:                                        ; $ACCB - Direction storage
        .byte   $02, $02
D_ACCD:                                        ; $ACCD - Fall speed table
        .byte   $00, $01, $01, $02, $02, $02, $03, $03, $03, $03, $03, $04, $04, $04, $04, $04
D_ACDD:                                        ; $ACDD - Movement table
        .byte   $00, $01, $01, $01, $02, $02, $02, $03, $03, $03, $03, $04, $04, $04, $04, $04
D_ACED:                                        ; $ACED - Jump table
        .byte   $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
D_ACFD:                                        ; $ACFD - Text string: story text display
        .byte   $09, $1f, $0c, $0a, $e0, $e1, $e2, $e3, $e4, $e5, $e6, $e7, $e8, $1f
D_AD0B:
        .byte   $0c, $0c
        .byte   $e9, $ea, $eb, $ec, $ed, $ee, $ef, $10
D_AD15:                                        ; $AD15 - READY! text indices
        .byte   $0a, $0f, $10, $0e, $11, $13, $12, $13, $13
D_AD1E:                                        ; $AD1E - Screen row pointer table (low bytes)
        .byte   $00
D_AD1F:                                        ; $AD1F - Screen row pointer table (low, +1)
        .byte   $00
D_AD20:                                        ; $AD20 - Screen row pointer (offset by 2)
        .byte   $00, $00
D_AD22:                                        ; $AD22 - Screen row pointer table (low, +4)
        .byte   $00, $28, $50, $78, $a0, $c8, $f0, $18, $40, $68, $90, $b8, $e0
D_AD2F:
        .byte   $08, $30, $58
        .byte   $80, $a8, $d0, $f8, $20, $48, $70, $98, $c0, $00, $00
D_AD3D:                                        ; $AD3D - Screen row pointer table (high bytes)
        .byte   $01
D_AD3E:                                        ; $AD3E - Screen row pointer table (high, +1)
        .byte   $01
D_AD3F:                                        ; $AD3F - Screen row pointer (offset by 2)
        .byte   $01, $01
D_AD41:                                        ; $AD41 - Screen column data
        .byte   $50, $50, $50, $50, $50, $50, $50, $51, $51, $51, $51, $51, $51, $52, $52, $52
        .byte   $52, $52
D_AD53:
        .byte   $52, $52, $53, $53, $53, $53, $53, $01, $01
D_AD5C:                                        ; $AD5C - Screen column source
        .byte   $00, $00, $00, $00
D_AD60:
        .byte   $00, $00, $00, $01, $00, $00, $00, $00, $00, $01, $00, $00
        .byte   $00, $00, $00, $00, $01, $00, $00, $00, $00

; Aliases for source-defined labels
D_AA54      = sprite_gfx_ptr_lo   ; Sprite graphics pointer table (low)
D_AA8E      = sprite_gfx_ptr_hi   ; Sprite graphics pointer table (high)
