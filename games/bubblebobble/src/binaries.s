;===============================================================================
; binaries.s - Binary data file loader and data table symbols
;===============================================================================
; Loads all binary data files into their respective segments.
; Memory positions are defined in the linker config (c64-prg.cfg).
;
; This file also defines symbols (equates) for addresses within the memory
; regions covered by the binary files. Many of these addresses are used as
; RAM variables during gameplay, but fall within the initially-loaded binary
; data regions.
;
; To relocate a binary, change its segment offset in c64-prg.cfg.
;===============================================================================

;-------------------------------------------------------------------------------
; Character set - VIC-visible portion ($4000-$43FF, 1024 bytes = 128 characters)
; Source: data/charset.tga (first 128 of 140 hires 8x8 characters)
;
; NOTE: Region $4000-$47FF is used for charset + work buffers during gameplay.
; These 1024 bytes are backed up to charset B during init, allowing this region
; to be reused as work RAM while preserving the charset for double-buffering.
; Work buffer equates (D_4050, D_4080, etc.) are defined in master.s.
;-------------------------------------------------------------------------------
        .segment "VIC_CHARSET"
charset:
        .incbin "../build/charset.bin", 0, $400

;-------------------------------------------------------------------------------
; Character set - title screen extension (96 bytes = 12 characters)
; Characters 128-139: "BUBBLE BOBBLE" logo graphics, used only during title
; screen display. Not backed up to charset B (title screen uses single charset).
; At runtime this memory is reused as work RAM (enemy template data).
;-------------------------------------------------------------------------------
        .segment "TMP_CHARSET_EXT"
charset_ext:
        .incbin "../build/charset.bin", $400

;-------------------------------------------------------------------------------
; Early initialization code and title screen data ($4460-$47FF, 928 bytes)
; See game-init-early.s
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; Work RAM initialization - movable part ($4B00-$4FFF, 1280 bytes)
; See work-ram-init.s
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; Screen RAM initialization - VIC-fixed part ($5000-$57FF, 2048 bytes)
; See screen-ram-init.s
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; Game sprites ($5800-$703F, 6208 bytes = 97 sprites)
; Built from data/sprites-game.tga via convert-tga.py.
;
; Memory layout:
;   $5800-$5FFF: 32 sprites (pointers $160-$17F) - players, bubbles, EXTEND
;   $6000-$703F: 65 sprites (pointers $180-$1C0) - enemies, items, animations
;
; Note: Byte 63 of each sprite (the padding byte) is used as game state
; variables during gameplay. The initial values are set in the TGA file.
;-------------------------------------------------------------------------------
        .segment "VIC_SPRITES_GAME"
sprites_game:
        .incbin "../build/sprites-game.bin"               ; 97 sprites (6208 bytes)

;-------------------------------------------------------------------------------
; Music sequence data ($7040-$7304, 709 bytes)
; See music-sequence.s
;-------------------------------------------------------------------------------

; Symbols within sprite region ($5800-$5FFF)
; Game state flags stored in sprite padding bytes (byte 63 of each sprite)
; These addresses are used as RAM variables during gameplay.
D_5800      = sprites_game              ; Sprite data buffer base
D_58BF      = sprites_game + 2*64 + 63  ; Global level flag (sprite 2, byte 63)
D_58FF      = sprites_game + 3*64 + 63  ; Special timer (sprite 3, byte 63)
D_593F      = sprites_game + 4*64 + 63  ; Special rendering mode flag (sprite 4, byte 63)
D_597F      = sprites_game + 5*64 + 63  ; Frame counter (sprite 5, byte 63)
D_59BF      = sprites_game + 6*64 + 63  ; Game state flag (sprite 6, byte 63)
D_59FF      = sprites_game + 7*64 + 63  ; Game state flag (sprite 7, byte 63)
D_5A7F      = sprites_game + 9*64 + 63  ; Game mode flag (sprite 9, byte 63)
D_5ABF      = sprites_game + 10*64 + 63 ; Countdown timer 2 (sprite 10, byte 63)
D_5AFF      = sprites_game + 11*64 + 63 ; Sprites active flag (sprite 11, byte 63)
D_5B3F      = sprites_game + 12*64 + 63 ; Level progression counter (sprite 12, byte 63)
D_5B7F      = sprites_game + 13*64 + 63 ; Active sprite mask (sprite 13, byte 63)
D_5BBF      = sprites_game + 14*64 + 63 ; Special item countdown (sprite 14, byte 63)
D_5BFF      = sprites_game + 15*64 + 63 ; Enemy type seed (sprite 15, byte 63)
D_5C3F      = sprites_game + 16*64 + 63 ; Game state flag (sprite 16, byte 63)

;-------------------------------------------------------------------------------
; Music command handlers inserted here ($7305-$743F, 315 bytes)
; See music-command-handlers.s
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; Level data part 2 - Sprite block 1 ($7440-$7ABF, 1664 bytes)
; Bubble dragon in bubble + Grumple Gromit (left & bubble) sprites.
; 26 multicolor sprites = 1664 bytes
; Source: data/bubble-dragon-in-bubble.tga (8 sprites, 512 bytes)
;         data/grumple-gromit.tga left+bubble (18 sprites, 1152 bytes)
;-------------------------------------------------------------------------------
        .segment "VIC_LEVELS2_SPR1"
sprite_data_7440:
        .incbin "../build/bubble-dragon-in-bubble.bin"
        .incbin "../build/grumple-gromit.bin", 0, 1152

;-------------------------------------------------------------------------------
; Level data part 2 - Code block 1 ($7AC0-$7C3F)
; See level-data-part2.s for disassembled routines
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; Level data part 2 - Sprite block 2 ($7C40-$7E7F, 576 bytes)
; Grumple Gromit facing right sprites.
; 9 multicolor sprites = 576 bytes
; Source: data/grumple-gromit.tga right (9 sprites at offset 1152)
;-------------------------------------------------------------------------------
        .segment "VIC_LEVELS2_SPR2"
sprite_data_7C40:
        .incbin "../build/grumple-gromit.bin", 1152, 576

;-------------------------------------------------------------------------------
; Level data part 2 - Code block 2 ($7E80-$7FFF)
; See level-data-part2.s for disassembled routines
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; Sprite data 2 & 3 ($8000-$A427, 9256 bytes)
; This large region contains sprite graphics and is heavily used as RAM
; for entity data, collision flags, and animation arrays during gameplay
;
; Layout:
;   - $8000-$847F: Bubble masks (1152 bytes, from bubble-masks.tga)
;   - $8480-$8EFF: Entity/table data (2688 bytes, used as RAM during gameplay)
;   - $8F00-$A31F: Software sprites (5152 bytes, from software-sprites.tga)
;   - $A340-$A427: Sprite ROM data (232 bytes, from sprites-rom.tga)
;-------------------------------------------------------------------------------

; Bubble mask tables ($8000-$847F, 1152 bytes)
; 72 x 16-byte mask patterns for bubble rendering
        .segment "BUBBLE_MASKS"
bubble_masks:
        .incbin "../build/bubble-masks.bin"

; Entity/table data ($8480-$8EFF, 2688 bytes)
; Used as RAM for entity state during gameplay
; Contains entity state arrays, bubble animation masks, and title screen music.
; See sprites2-tables.s for detailed documentation.

; Software sprites ($8F00-$A31F, 5152 bytes)
; 48-byte column-major multicolor sprites for software rendering
        .segment "SOFTWARE_SPRITES"
software_sprites_base:
        .incbin "../build/software-sprites.bin"             ; 5152 bytes

; Legacy symbol for code that references the old SPRITES_ROM location
; This points to offset $BE0 within SOFTWARE_SPRITES ($8F00 + $BE0 = $9AE0)
sprites_rom = software_sprites_base + $BE0

; Symbols for bubble mask offsets ($8000-$8210)
; These are used by sprite_gfx_ptr table entries 0-11
; Each entry is 48 bytes ($30) apart, same spacing as software sprites
bubble_mask_0x000 = bubble_masks + $000         ; $8000 - Entry 0
bubble_mask_0x030 = bubble_masks + $030         ; $8030 - Entry 1
bubble_mask_0x060 = bubble_masks + $060         ; $8060 - Entry 2
bubble_mask_0x090 = bubble_masks + $090         ; $8090 - Entry 3
bubble_mask_0x0c0 = bubble_masks + $0C0         ; $80C0 - Entry 4
bubble_mask_0x0f0 = bubble_masks + $0F0         ; $80F0 - Entry 5
bubble_mask_0x120 = bubble_masks + $120         ; $8120 - Entry 6
bubble_mask_0x150 = bubble_masks + $150         ; $8150 - Entry 7
bubble_mask_0x180 = bubble_masks + $180         ; $8180 - Entry 8
bubble_mask_0x1b0 = bubble_masks + $1B0         ; $81B0 - Entry 9
bubble_mask_0x1e0 = bubble_masks + $1E0         ; $81E0 - Entry 10
bubble_mask_0x210 = bubble_masks + $210         ; $8210 - Entry 11

; Symbols for bubble AND mask offsets ($8240-$8450)
; These are used by D_AAC8/D_AB02 (AND mask pointer table) entries 0-42
; Each entry is 48 bytes ($30) apart, same as OR mask table
bubble_and_mask_0x240 = bubble_masks + $240     ; $8240 - AND mask entry 0
bubble_and_mask_0x270 = bubble_masks + $270     ; $8270 - AND mask entry 1
bubble_and_mask_0x2a0 = bubble_masks + $2A0     ; $82A0 - AND mask entry 2
bubble_and_mask_0x2d0 = bubble_masks + $2D0     ; $82D0 - AND mask entry 3
bubble_and_mask_0x300 = bubble_masks + $300     ; $8300 - AND mask entry 4
bubble_and_mask_0x330 = bubble_masks + $330     ; $8330 - AND mask entry 5
bubble_and_mask_0x360 = bubble_masks + $360     ; $8360 - AND mask entry 6
bubble_and_mask_0x390 = bubble_masks + $390     ; $8390 - AND mask entry 7
bubble_and_mask_0x3c0 = bubble_masks + $3C0     ; $83C0 - AND mask entries 8,12+
bubble_and_mask_0x3f0 = bubble_masks + $3F0     ; $83F0 - AND mask entries 9,13+
bubble_and_mask_0x420 = bubble_masks + $420     ; $8420 - AND mask entries 10,14+
bubble_and_mask_0x450 = bubble_masks + $450     ; $8450 - AND mask entries 11,15+

; Symbols for sprite graphics within software sprites region
; These are used by sprite_gfx_ptr table entries 12-57
; Named by offset within software-sprites.tga for easy cross-reference
soft_spr_0x000 = software_sprites_base + $000   ; $8F00 - Entries 48-51
soft_spr_0x180 = software_sprites_base + $180   ; $9080 - Entries 12-14
soft_spr_0x240 = software_sprites_base + $240   ; $9140 - Entries 15-19
soft_spr_0x300 = software_sprites_base + $300   ; $9200 - Entries 20-23 (lightning bubble)
soft_spr_0x400 = software_sprites_base + $400   ; $9300 - Entries 52-55
soft_spr_0x580 = software_sprites_base + $580   ; $9480 - Entries 24-26
soft_spr_0x610 = software_sprites_base + $610   ; $9510 - Entries 27-31
soft_spr_0x700 = software_sprites_base + $700   ; $9600 - Entries 32-37
soft_spr_0x820 = software_sprites_base + $820   ; $9720 - Entries 38-42
soft_spr_0x910 = software_sprites_base + $910   ; $9810 - Entry 43
soft_spr_0x940 = software_sprites_base + $940   ; $9840 - Entries 56-57

; Symbols for software sprite addresses used by sprite-init.s
; These form the ORA data and AND mask pointers written into self-modifying code
; at D_E84C/D_E84D (ORA col1), D_E856/D_E857 (ORA col2),
; D_E849/D_E84A (AND col1), D_E853/D_E854 (AND col2)
;
; Routine 2 (D_3E94): bubble entity sprites
soft_spr_0x3c0 = software_sprites_base + $3C0   ; $92C0 - ORA col1
soft_spr_0x3d0 = software_sprites_base + $3D0   ; $92D0 - ORA col2
soft_spr_0x3e0 = software_sprites_base + $3E0   ; $92E0 - AND col1
soft_spr_0x3f0 = software_sprites_base + $3F0   ; $92F0 - AND col2
;
; Routine 3 (D_3ED5): table-driven sprites (4 ORA + 2 AND entries)
soft_spr_0x9a0 = software_sprites_base + $9A0   ; $98A0 - ORA entry 0
soft_spr_0x9c0 = software_sprites_base + $9C0   ; $98C0 - ORA entry 1
soft_spr_0x9e0 = software_sprites_base + $9E0   ; $98E0 - ORA entry 2
soft_spr_0xa00 = software_sprites_base + $A00   ; $9900 - ORA entry 3 (page cross)
soft_spr_0xa40 = software_sprites_base + $A40   ; $9940 - AND entry 0
soft_spr_0xa60 = software_sprites_base + $A60   ; $9960 - AND entry 1
;
; Routine 1 (routine_3E79): sprites (2 ORA + 2 AND)
soft_spr_0xa20 = software_sprites_base + $A20   ; $9920 - ORA col1
soft_spr_0xa30 = software_sprites_base + $A30   ; $9930 - ORA col2
soft_spr_0xac0 = software_sprites_base + $AC0   ; $99C0 - AND col1
soft_spr_0xad0 = software_sprites_base + $AD0   ; $99D0 - AND col2
;
; Routine 4 (routine_3EFD): table-driven sprites (4 ORA + 4 AND entries)
soft_spr_0xae0 = software_sprites_base + $AE0   ; $99E0 - ORA entry 0
soft_spr_0xb00 = software_sprites_base + $B00   ; $9A00 - ORA entry 1 (page cross)
soft_spr_0xb20 = software_sprites_base + $B20   ; $9A20 - ORA entry 2
soft_spr_0xb40 = software_sprites_base + $B40   ; $9A40 - ORA entry 3
soft_spr_0xb60 = software_sprites_base + $B60   ; $9A60 - AND entry 0
soft_spr_0xb80 = software_sprites_base + $B80   ; $9A80 - AND entry 1
soft_spr_0xba0 = software_sprites_base + $BA0   ; $9AA0 - AND entry 2
soft_spr_0xbc0 = software_sprites_base + $BC0   ; $9AC0 - AND entry 3
;
; Block copy (L_3F2E_do_copy): compositing source and mask
soft_spr_0x1320 = software_sprites_base + $1320 ; $A220 - Block copy source
soft_spr_0x1370 = software_sprites_base + $1370 ; $A270 - Block copy mask

; Bonus cake sprites + unused data ($A320-$A427, 264 bytes)
; Layout:
;   $A320-$A41F: 256 bytes - 4 cake sprites from bonus-sprites.tga
;   $A420-$A427: 8 bytes - bonus stage 1 pattern data (patch B)
        .segment "BONUS_CAKE"
bonus_cake_sprites:
        .incbin "../build/bonus-sprites.bin", 0, 256        ; 256 bytes - cake
; Bonus stage 1 pattern B - 8 bytes copied to $7D76 during stage 1 init
; Creates a small decorative element (pillar/stripe pattern) in the level buffer
; Used alongside bonus_stage1_pattern_a which is copied to $7D37
; This data is the top left of the melon sprite from bonus-sprites.tga
bonus_stage1_pattern_b:
        .incbin "../build/bonus-sprites.bin", 256, 8        ; 8 bytes - melon top left

; Symbols within SPRITES2 region ($8000-$9FFF)
; Entity data arrays, collision flags, animation data
; NOTE: Much of this region is overwritten and used as RAM during gameplay

; --- Sprite mask tables ($8000-$82FF) ---
D_8000      = bubble_masks + $000   ; Sprite mask background bits 1
D_8010      = bubble_masks + $010   ; Sprite mask background bits 2
D_8020      = bubble_masks + $020   ; Sprite mask background bits 3
D_8240      = bubble_masks + $240   ; Sprite mask table 1
D_8250      = bubble_masks + $250   ; Sprite mask table 2
D_8260      = bubble_masks + $260   ; Sprite mask table 3

; All symbols for the SPRITES2_TABLES region ($8480-$8EFF) are now
; defined as labels in sprites2-tables.s.



;-------------------------------------------------------------------------------
; Bonus melon sprites + padding ($A47E-$A51F, 162 bytes)
; Layout:
;   $A47E-$A495: 24 bytes - zero padding
;   $A496-$A49F: 10 bytes - melon top right (from bonus-sprites.tga)
;   $A4A0-$A51F: 128 bytes - 2 melon sprites from bonus-sprites.tga
;-------------------------------------------------------------------------------
        .segment "BONUS_MELON"
bonus_melon_padding:
        .byte   $00, $00, $00, $00, $00, $00, $00, $00      ; 24 bytes - zero padding
        .byte   $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00
        .incbin "../build/bonus-sprites.bin", 264, 10       ; 10 bytes - melon top right
bonus_melon_sprites:
        .incbin "../build/bonus-sprites.bin", 274, 128      ; 128 bytes - melon sprites 4 & 5

;-------------------------------------------------------------------------------
; Bonus diamond sprites ($A520-$A59F, 128 bytes)
; 2 diamond sprites from bonus-sprites.tga
;-------------------------------------------------------------------------------
        .segment "BONUS_DIAMOND"
bonus_diamond_sprites:
        .incbin "../build/bonus-sprites.bin", 402, 128      ; 128 bytes - diamond



;-------------------------------------------------------------------------------
; Game tables ($A632-$AE50, 2079 bytes)
; Lookup tables for sprites, positions, items, etc.
; Assembly portions are in game-tables.s; binary data portions below.
;-------------------------------------------------------------------------------

; --- diamond-sprite.bin (36 bytes, within game tables) ---
        .segment "GT_BIN1"
D_A854:                                             ; Level data source
        .incbin "../build/diamond-sprite.bin", 0, 35
D_A877:                                             ; Screen data source table
        .incbin "../build/diamond-sprite.bin", 35, 1

; --- digit-font.bin (60 bytes, within game tables) ---
; 12 glyphs x 5 bytes each: digits 0-9, space, colon
        .segment "GT_BIN2"
digit_font:
        .incbin "../build/digit-font.bin", 0, 16
D_AD85:
        .incbin "../build/digit-font.bin", 16, 44

;-------------------------------------------------------------------------------
; Enemy Spawn Data ($AE51-$B568, 1816 bytes)
; Position and type data for enemy spawns on all 100 levels
; Generated from data/levels.txt by build/convert-levels.py
;-------------------------------------------------------------------------------
        .segment "ENEMY_SPAWNS"
enemy_spawns:
        .incbin "../build/enemy-spawns.bin"

;-------------------------------------------------------------------------------
; Item Spawn Positions ($B569-$B694, 300 bytes)
; Three 100-byte tables at offsets +0, +100, +200
; Generated from data/levels.txt by build/convert-levels.py
;-------------------------------------------------------------------------------
        .segment "ITEM_POSITIONS"
item_positions:
        .incbin "../build/item-positions.bin"

;-------------------------------------------------------------------------------
; Game data - Zone regions ($B695-$BC0D, variable size, original 1145 bytes)
; Generated from data/zone-data.txt by tools/zone-data-tool.py
;-------------------------------------------------------------------------------
        .segment "GAMEDATA_WIND"
zone_data:
        .incbin "../build/zone-data.bin"

;-------------------------------------------------------------------------------
; Sidebars ($BC0E-$C2CD, 1888 bytes)
; 59 sidebar designs × 4 characters × 8 bytes per character
; Multi-color character data for level sidebars
; Generated from data/sidebars.tga by build/convert-tga.py
;-------------------------------------------------------------------------------
        .segment "SIDEBARS"
sidebars:
        .incbin "../build/sidebars.bin"

;-------------------------------------------------------------------------------
; Level Tiles ($C2CE-$C58D, 800 bytes)
; Multi-color 4x8 tiles for levels 12-99
; Generated from data/level-tiles.tga by build/convert-tga.py
;-------------------------------------------------------------------------------
        .segment "LEVEL_TILES"
level_tiles:
        .incbin "../build/level-tiles.bin"

;-------------------------------------------------------------------------------
; Physics Flags ($C58E-$C5F1, 100 bytes)
; Level hole/bubble current metadata
; Generated from data/levels.txt by build/convert-levels.py
;-------------------------------------------------------------------------------
        .segment "PHYSICS_FLAGS"
physics_flags:
        .incbin "../build/physics-flags.bin"

.ifdef COMPRESS_LEVELS
;-------------------------------------------------------------------------------
; Level Bitmap Deltas + Compressed Bitmaps (split across PRG_MID/IO_SHADOW)
;-------------------------------------------------------------------------------
; Per-level compressed sizes.  The decompressor accumulates a running sum
; of deltas[0..level-1] to find the offset into level_bitmaps_compressed.
;
; Split at I/O shadow boundary ($D000):
;   IO_LEVEL_BITMAPS:    deltas (100 bytes) + first part of compressed bitmaps
;   IO_LEVEL_BITMAPS_HI: remaining compressed bitmaps
;
; COMPRESSED_SPLIT is calculated to ensure IO_LEVEL_BITMAPS ends exactly at $D000,
; making the two segments contiguous. The decompressor reads across both segments
; sequentially, so they MUST be contiguous in memory.
;
; IO_LEVEL_BITMAPS starts at LEVEL_BM_START (passed by tools/build.py to both
; ca65 and ld65). build.py picks it so that the high part just fits in the
; I/O shadow, which leaves free PRG_MID space for BBLAN_CODE.
; See c64-prg.cfg for segment layout.
; Generated from data/levels.txt by build/convert-levels.py
;-------------------------------------------------------------------------------
.ifndef LEVEL_BM_START
LEVEL_BM_START = $C5F2
.endif
COMPRESSED_SPLIT = $D000 - LEVEL_BM_START - 100  ; bytes of compressed data before I/O shadow

        .segment "IO_LEVEL_BITMAPS"
level_bitmap_deltas:
        .incbin "../build/level-bitmap-offsets.bin"
level_bitmaps_compressed:
        .incbin "../build/level-bitmaps-compressed.bin", 0, COMPRESSED_SPLIT
level_bitmaps_compressed_end:

        .segment "IO_LEVEL_BITMAPS_HI"
level_bitmaps_compressed_hi:
        .incbin "../build/level-bitmaps-compressed.bin", COMPRESSED_SPLIT

; Verify the two bitmap segments are contiguous (decompressor expects this)
.assert level_bitmaps_compressed_end = level_bitmaps_compressed_hi, error, "IO_LEVEL_BITMAPS and IO_LEVEL_BITMAPS_HI must be contiguous"

;-------------------------------------------------------------------------------
; Bitmap Decode Table (256 bytes)
;-------------------------------------------------------------------------------
; Lookup table for the level bitmap decompressor.
; For each byte value 0-255:
;   $00          = literal (copy source byte to output as-is)
;   $01          = zero-run escape (next byte = run length - 2)
;   $02..THR-1   = 2-byte dictionary pair (index = value - 2)
;   THR+         = 3-byte dictionary triple (index = value - THR)
; THR (threshold) is stored as the last byte of bitmap-dict-pairs.bin.
; Generated from data/levels.txt by build/convert-levels.py
;-------------------------------------------------------------------------------
        .segment "IO_BITMAP_DECODE_TABLE"
bitmap_decode_table:
        .incbin "../build/bitmap-decode-table.bin"

;-------------------------------------------------------------------------------
; Bitmap Dictionary Entries + Threshold
;-------------------------------------------------------------------------------
; [N_PAIRS x 2 bytes] [N_TRIPLES x 3 bytes] [threshold byte]
; Pairs are indexed by (action - 2) * 2.
; Triples are indexed by pairs_size + (action - threshold) * 3.
; The threshold byte at the end encodes the pair/triple boundary.
; Generated from data/levels.txt by build/convert-levels.py
;-------------------------------------------------------------------------------
        .segment "IO_BITMAP_DICT_PAIRS"
bitmap_dict_entries:
        .incbin "../build/bitmap-dict-pairs.bin"
bitmap_dict_entries_end:

.else
;-------------------------------------------------------------------------------
; Level Bitmaps ($C5F2-$DFFF, 6670 bytes)
;-------------------------------------------------------------------------------
; Platform layout bitmaps for all 100 levels (uncompressed)
; Each level uses 46 bytes (symmetric) or 92 bytes (asymmetric)
; Generated from data/levels.txt by build/convert-levels.py
;
; Split at I/O shadow boundary ($D000):
;   IO_LEVEL_BITMAPS:    $C5F2-$CFFF (2574 bytes) - in PRG_MID
;   IO_LEVEL_BITMAPS_HI: $D000-$DFFF (4096 bytes) - in IO_SHADOW
;-------------------------------------------------------------------------------
LEVEL_BITMAPS_SPLIT = $D000 - $C5F2     ; 2574 bytes before I/O shadow

        .segment "IO_LEVEL_BITMAPS"
level_bitmaps:
        .incbin "../build/level-bitmaps.bin", 0, LEVEL_BITMAPS_SPLIT
level_bitmaps_end:

        .segment "IO_LEVEL_BITMAPS_HI"
level_bitmaps_hi:
        .incbin "../build/level-bitmaps.bin", LEVEL_BITMAPS_SPLIT

; Verify the two bitmap segments are contiguous
.assert level_bitmaps_end = level_bitmaps_hi, error, "IO_LEVEL_BITMAPS and IO_LEVEL_BITMAPS_HI must be contiguous"

; Empty segment declarations to satisfy the linker config.
; These segments only contain data in the compressed build.
        .segment "IO_BITMAP_DECODE_TABLE"
        .segment "IO_BITMAP_DICT_PAIRS"
.endif

;-------------------------------------------------------------------------------
; HUD Font ($FE90-$FF2F, 160 bytes)
;-------------------------------------------------------------------------------
; 4x8 multicolor font containing 20 characters (160 bytes total)
; Each character is 8 bytes (one byte per row, 8 rows)
; Bit pattern: 2 bits per pixel (4 pixels per byte)
;
; Character set contents:
;   Index $00-$09: Digits 0-9 (for score display, level numbers)
;   Index $0A-$13: R O U N D E A Y ! (space) - for "ROUND" and "READY!" text
;
; Usage:
;   1. Copied to $4300 during init - accessed via screen codes $60-$73
;   2. Accessed directly at $FE90 for graphics compositing (ROUND/READY text)
;
; Source: data/hud-font.tga (converted by build/convert-tga.py --format multicolor-chars)
;-------------------------------------------------------------------------------
        .segment "HUDFONT"
hud_font:
        .incbin "../build/hud-font.bin"

;-------------------------------------------------------------------------------
; Level Colors ($FF30-$FF93, 100 bytes)
;-------------------------------------------------------------------------------
; Background/platform color theme for each level (1 byte per level)
; High nibble and low nibble each encode a C64 color value
; Generated from data/levels.txt by build/convert-levels.py
;-------------------------------------------------------------------------------
        .segment "LEVEL_COLORS"
level_colors:
        .incbin "../build/level-colors.bin"

;-------------------------------------------------------------------------------
; Level Flags ($FF94-$FFF7, 100 bytes)
;-------------------------------------------------------------------------------
; Symmetry flag + sidebar character set index for each level
; Bit 7 = symmetry (1=symmetric/46 bytes, 0=asymmetric/92 bytes)
; Bits 0-6 = sidebar character set index
; Generated from data/levels.txt by build/convert-levels.py
;-------------------------------------------------------------------------------
        .segment "LEVEL_FLAGS"
level_flags:
        .incbin "../build/level-flags.bin"
