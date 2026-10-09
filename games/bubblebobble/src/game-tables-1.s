;===============================================================================
; game-tables-1.s - Game Tables Part 1 (GT_ASM1 segment)
;===============================================================================
; Sprite/position/spawn lookup tables, bonus data pointers,
; entity state tables, and digit graphics pointers.
;===============================================================================

        .segment "GT_ASM1"

; --- Part 1a: Sprite/position/spawn lookup tables (483 bytes) ---

D_A632:                                        ; $A632 - Sprite Y position table
        .byte   $65, $7d
D_A634:                                        ; $A634 - Pointer table (high bytes)
        .byte   $5a, $d2, $4a
D_A637:                                        ; $A637 - Pointer table (low bytes)
        .byte   $51, $51, $52
D_A63A:                                        ; $A63A - Text string: game init display
        .byte   $1f, $0f
D_A63C:                                        ; $A63C - Temp storage (Y register)
        .byte   $00
D_A63D:                                        ; $A63D - Temp storage (X register)
        .byte   $00, $40, $40, $40, $40, $40, $20, $20, $40, $40, $40, $40, $40, $40, $40, $10
D_A64D:                                        ; $A64D - Special item effect routine 1
        lda     #$12
        sta     D_A783,x
        rts
D_A653:                                        ; $A653 - Special item effect routine 2
        jsr     D_E9EA              ; Random number generator
        and     #$03
        clc
        adc     #$02
        sta     D_58FF              ; Store to sprite region
        rts
        .byte   $ff                 ; Padding/terminator
D_A660:                                        ; $A660 - Level data source table
        .byte   $aa, $95, $91, $95, $85, $95, $95, $94, $aa, $95, $91, $95, $95, $95, $94, $91
        .byte   $aa, $55, $45, $55, $55, $14, $55, $55, $91, $95, $95, $95, $85, $95, $95, $95
        .byte   $55, $15, $55, $51, $45, $55, $14, $55, $00, $0a, $0a, $2a, $2a, $29, $aa, $a9
        .byte   $00, $95, $65, $95, $55, $95, $55, $55, $00, $55, $55, $55, $55, $55, $55, $55
        .byte   $00, $50, $50, $54, $54, $54
D_A6A6:
        .byte   $55, $55, $00, $10, $10, $04, $04, $04, $01, $01
        .byte   $02, $02, $02, $02, $02, $02, $02, $02, $a6, $a9, $a6, $a9, $a6, $a9, $a6, $a9
        .byte   $50, $45, $55, $55, $65, $65, $65, $65, $25, $e5, $e5, $e5, $e5, $e5, $e5, $00
        .byte   $05, $51, $55, $55, $59, $59, $59, $59, $58, $5b, $1b, $9b, $5b, $5b, $5b, $00
        .byte   $fe, $55, $fe, $55, $d5, $f5, $fd, $f9, $fe, $fa, $fe, $fa, $fe, $fa, $55, $fa
        .byte   $03, $33, $f3, $f0, $c0, $05, $c1, $d5, $01, $dd, $c9, $15, $c1, $d5, $01, $d5
        .byte   $c0, $cc, $cf, $0f, $03, $90, $83, $97, $80, $b7, $b3, $84, $83, $97, $80, $97
D_A710:                                        ; $A710 - Position table 1
        .byte   $06, $08, $06, $08, $02, $04, $06, $08, $02, $04, $06, $08, $02, $04, $06, $08
        .byte   $0a, $0c
D_A722:                                        ; $A722 - Position table 2
        .byte   $02, $02, $05, $05, $08, $08, $08, $08, $0b, $0b, $0b, $0b, $16, $16, $16, $16
        .byte   $16, $16, $bf
D_A735:                                        ; $A735 - Respawn X positions
        .byte   $2c, $ec
D_A737:                                        ; $A737 - Death animation frames
        .byte   $00, $04
D_A739:                                        ; $A739 - Y position offset table
        .byte   $07, $0e
D_A73B:                                        ; $A73B - Text string: game over display
        .byte   $1f, $23
D_A73D:                                        ; $A73D - Game over Y position
        .byte   $07, $01, $47, $41, $4d, $45, $1f, $23
D_A745:                                        ; $A745 - Game over Y position +1
        .byte   $08, $4f, $56, $45, $52, $10
D_A74B:                                        ; $A74B - Item X positions (11 bytes)
        .byte   $13
D_A74C:                                        ; $A74C - Item X positions (offset by 1)
        .byte   $13, $13, $13, $13, $13, $13, $13, $13
D_A754:                                        ; $A754 - Item position data
        .byte   $13
D_A755:                                        ; $A755 - Item movement direction
        .byte   $13
D_A756:                                        ; $A756 - Item Y positions (11 bytes)
        .byte   $1d
D_A757:                                        ; $A757 - Item Y positions (offset by 1)
        .byte   $1d, $1d, $1d, $1d, $1d, $1d, $1d, $1d
D_A75F:                                        ; $A75F - Item data
        .byte   $1d
D_A760:                                        ; $A760 - Item data
        .byte   $1d
D_A761:                                        ; $A761 - Player sprite column positions (5 bytes)
        .byte   $11, $0c, $05, $05, $04
D_A766:                                        ; $A766 - Player sprite row positions (5 bytes)
        .byte   $1b, $0f, $0f, $0f, $08
D_A76B:                                        ; $A76B - Player sprite data indices (5 bytes)
        .byte   $01, $0d, $0e, $0f
D_A76F:                                        ; $A76F - Entity state array
        .byte   $01
D_A770:                                        ; $A770 - Player sprite active flags (5 bytes)
        .byte   $ff, $ff, $ff, $ff, $ff
D_A775:                                        ; $A775 - Animation timer array
        .byte   $16, $00
D_A777:                                        ; $A777 - Entity spawn X position table
        .byte   $02, $1b
D_A779:                                        ; $A779 - Entity spawn Y position table
        .byte   $05, $19
D_A77B:                                        ; $A77B - Entity attribute table
        .byte   $08
D_A77C:                                        ; $A77C - Entity attribute table +1
        .byte   $08
D_A77D:                                        ; $A77D - Entity attribute table +2
        .byte   $88, $88
D_A77F:                                        ; $A77F - Entity attribute table +4
        .byte   $04, $04
D_A781:                                        ; $A781 - Entity attribute table +6
        .byte   $04, $04
D_A783:                                        ; $A783 - Entity attribute table +8
        .byte   $ff
D_A784:                                        ; $A784 - Entity attribute table +9
        .byte   $ff                                            ; Entity 1: lo=$FF (player - unused by score_display)
        .byte   <(sprite_data_7C40+$0C0)                      ; Entity 2: lo byte of screen buffer addr
        .byte   <(sprite_data_7C40+$100)                      ; Entity 3: lo byte
        .byte   <(sprite_data_7C40+$140)                      ; Entity 4: lo byte
        .byte   <(sprite_data_7C40+$180)                      ; Entity 5: lo byte
D_A789:                                        ; $A789 - Entity attribute table +14 (screen address high)
        ; NOTE: First 2 bytes overlap with lo bytes for entities 6-7 via D_A783,x.
        ; Entities 0-1 are players and never reach score_display, so hi[0]/hi[1]
        ; are don't-cares and we use the lo-byte value for entities 6-7.
        .byte   <(sprite_data_7C40+$1C0)                      ; Entity 6: lo byte (also hi[0] - unused)
        .byte   <(sprite_data_7C40+$200)                      ; Entity 7: lo byte (also hi[1] - unused)
        .byte   >(sprite_data_7C40+$0C0)                      ; Entity 2: hi byte of screen buffer addr
        .byte   >(sprite_data_7C40+$100)                      ; Entity 3: hi byte
        .byte   >(sprite_data_7C40+$140)                      ; Entity 4: hi byte
        .byte   >(sprite_data_7C40+$180)                      ; Entity 5: hi byte
        .byte   >(sprite_data_7C40+$1C0)                      ; Entity 6: hi byte
D_A790:                                        ; $A790 - Enemy death bonus item indices
        .byte   >(sprite_data_7C40+$200)                      ; Entity 7: hi byte (also first bonus index)
        .byte   $08, $11, $02, $18, $0a, $1d, $29, $2b, $2c
D_A79A:                                        ; $A79A - Item score value table
        .byte   $22, $50, $01, $02, $03, $04, $05, $08, $09
D_A7A3:
        .byte   $0a, $03, $00, $04, $04
D_A7A8:
        .byte   $00, $fc
        .byte   $fc, $fe, $02, $04, $02, $fe
D_A7B0:                                        ; $A7B0 - Super bonus X positions (normal)
        .byte   $54, $84, $b4, $54, $84, $b4
D_A7B6:                                        ; $A7B6 - Super bonus Y positions (normal)
        .byte   $67, $67, $67, $91, $91, $91
D_A7BC:                                        ; $A7BC - Super bonus X positions (expanded)
        .byte   $78, $90, $a8, $78, $90, $a8
D_A7C2:                                        ; $A7C2 - Super bonus Y positions (expanded)
        .byte   $7c, $7c, $7c, $91, $91, $91
D_A7C8:                                        ; $A7C8 - Text string: level start display
        .byte   $01, $1f, $0d, $07, $42, $4f, $4e, $55, $53, $05
        .byte   $1f, $08, $08, $25, $20, $20, $58, $03, $1f, $11, $08, $25, $20, $20, $58, $10
D_A7E2:                                        ; $A7E2 - Sprite data storage
        .byte   $05, $1f
D_A7E4:                                        ; $A7E4 - Sprite data pointer (EVAL)
        .byte   $08, $0a, $50, $45, $52, $46, $45, $43, $54, $1f
D_A7EE:                                        ; $A7EE - Sprite data pointer
        .byte   $08, $0c
D_A7F0:                                        ; $A7F0 - Bonus display character 1
        .byte   $21
D_A7F1:                                        ; $A7F1 - Bonus display character 2
        .byte   $20, $20, $20, $20, $20, $10
D_A7F7:                                        ; $A7F7 - Player display offset table
        .byte   $00, $09
D_A7F9:                                        ; $A7F9 - Text string: player gets display
        .byte   $1f, $0c, $07, $07, $50, $4c, $41, $59, $45, $52, $40
D_A804:                                        ; $A804 - Player bonus data location
        .byte   $21, $1f, $0e, $09, $47, $45
D_A80A:
        .byte   $54, $53, $10
D_A80D:                                        ; $A80D - EXTEND character table
        .byte   $4a, $4e, $52, $4a, $56, $5a
D_A813:                                        ; $A813 - Spawn data table
        .byte   $00
D_A814:                                        ; $A814 - Spawn data table + 1
        .byte   $00

; --- Bonus stage data pointer tables (15 bytes) ---
; These point to data areas used during bonus round initialization
; 256 bytes are copied from the pointed address to buffer $7D00
; Index 0: Cake bonus - copies cake sprite data directly
; Index 1: Special stage - copies from $A420, then clears first 128 bytes,
;          then patches in bonus_stage1_pattern_a at $7D37 and
;          bonus_stage1_pattern_b at $7D76
; Index 2-4: Melon bonus - copies melon sprite data directly
bonus_data_ptr_lo:
        .byte   <bonus_cake_sprites         ; Index 0: $A320
        .byte   <bonus_stage1_pattern_b     ; Index 1: $A420
        .byte   <bonus_melon_sprites        ; Index 2: $A4A0
        .byte   <bonus_melon_sprites        ; Index 3: $A4A0
        .byte   <bonus_melon_sprites        ; Index 4: $A4A0
bonus_data_ptr_hi:
        .byte   >bonus_cake_sprites         ; Index 0: $A320
        .byte   >bonus_stage1_pattern_b     ; Index 1: $A420
        .byte   >bonus_melon_sprites        ; Index 2: $A4A0
        .byte   >bonus_melon_sprites        ; Index 3: $A4A0
        .byte   >bonus_melon_sprites        ; Index 4: $A4A0
bonus_sprite_colors:
        .byte   $07                         ; Index 0: Yellow (cake)
        .byte   $05                         ; Index 1: Green
        .byte   $07                         ; Index 2: Yellow (melon)
        .byte   $0E                         ; Index 3: Light blue (diamond)
        .byte   $04                         ; Index 4: Purple (diamond)

; --- Part 1b: Entity state and sprite data tables (24 bytes) ---

D_A824:                                        ; $A824 - Entity state table
        .byte   $07
D_A825:                                        ; $A825 - Player 2 invincibility timer
        .byte   $00
D_A826:                                        ; $A826 - ORA col1 low bytes (Routine 4)
        .byte   <soft_spr_0xae0, <soft_spr_0xb00, <soft_spr_0xb20, <soft_spr_0xb40
D_A82A:                                        ; $A82A - AND col1 low bytes (Routine 4)
        .byte   <soft_spr_0xb60, <soft_spr_0xb80, <soft_spr_0xba0, <soft_spr_0xbc0
D_A82E:                                        ; $A82E - Item offsets table
        .byte   $79, $78, $53, $52, $51, $2a, $29, $28, $03, $02, $a0, $d0, $00, $30

; --- Digit graphics pointer tables (24 bytes) ---
D_A83C:                                             ; Digit graphics pointer table (low bytes)
        .byte   <(digit_font + 0)                   ; Digit 0
        .byte   <(digit_font + 5)                   ; Digit 1
        .byte   <(digit_font + 10)                  ; Digit 2
        .byte   <(digit_font + 15)                  ; Digit 3
        .byte   <(digit_font + 20)                  ; Digit 4
        .byte   <(digit_font + 25)                  ; Digit 5
        .byte   <(digit_font + 30)                  ; Digit 6
        .byte   <(digit_font + 35)                  ; Digit 7
        .byte   <(digit_font + 40)                  ; Digit 8
        .byte   <(digit_font + 45)                  ; Digit 9
        .byte   <(digit_font + 50)                  ; Space
        .byte   <(digit_font + 55)                  ; Colon
D_A848:                                             ; Digit graphics pointer table (high bytes)
        .byte   >(digit_font + 0)                   ; Digit 0
        .byte   >(digit_font + 5)                   ; Digit 1
        .byte   >(digit_font + 10)                  ; Digit 2
        .byte   >(digit_font + 15)                  ; Digit 3
        .byte   >(digit_font + 20)                  ; Digit 4
        .byte   >(digit_font + 25)                  ; Digit 5
        .byte   >(digit_font + 30)                  ; Digit 6
        .byte   >(digit_font + 35)                  ; Digit 7
        .byte   >(digit_font + 40)                  ; Digit 8
        .byte   >(digit_font + 45)                  ; Digit 9
        .byte   >(digit_font + 50)                  ; Space
        .byte   >(digit_font + 55)                  ; Colon

; Aliases for source-defined labels
D_A815      = bonus_data_ptr_lo   ; Level data pointer table (low bytes)
D_A81A      = bonus_data_ptr_hi   ; Level data pointer table (high bytes)
D_A81F      = bonus_sprite_colors ; Large bonus sprite colors
