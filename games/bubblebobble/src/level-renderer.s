; ============================================================================
; rebb64 - Level Renderer and Screen Setup ($E000-$E3A6)
; ============================================================================
; This file contains level rendering, decompression, and screen setup code
; Originally from remaining-chunk1.bin, addresses $E000-$E3A6
;
; Main routines:
;   $E000 - setup_level_screen: Level/screen initialization and rendering
;   $E18B - decompress_level_data: Level data decompression (RLE format)
;   $E28C - advance_screen_row: Helper to advance screen pointer
;   $E299 - init_level_renderer: Initialize rendering system
;   $E374 - clear_screen: Clear screen memory and sprites
;   $E393 - clear_color_ram: Clear color RAM
; ============================================================================
; NOTE: All symbol definitions are in bb-master.s
; This file is included, not assembled separately
; ============================================================================
; ROUTINE: setup_level_screen ($E000)
; ============================================================================
; Sets up the screen and level data for the current level
; 
; INPUT:
;   $10 (SUBFLG) - Current level number (1-100)
;
; USES:
;   $2F,$30 - Pointer to screen memory ($5448)
;   $18,$19 - Pointer to level header data
;   $1A,$1B - Pointer to level tileset data
;   $1D,$1F - Color values (high/low nibbles)
;   $2A,$2C - Timer values (#$1E)
;   $04,$05 - Screen pointer ($5400)
;   $11,$12,$13,$14 - Level data pointers
;   $0A - Row counter (25 rows)
;   $31 - Bit counter (8 bits per byte)
;   $07 - Current byte being processed
; ============================================================================
.segment "CODE_LEVEL_RENDERER"

setup_level_screen:
        ; Initialize screen pointer
        lda     #>__VIC_CHARSET_B__
        sta     $2F
        lda     #>__VIC_SCREEN_B__
        sta     $30
        
        ; Call helper routines
        jsr     wait_one_frame              ; Wait one frame / prepare screen
        jsr     clear_color_ram      ; Setup screen memory
        
        ; Get current level number
        ldx     SUBFLG              ; $10 = current level (1-100)
        
        ; Calculate pointer to level tiles: level_tiles + level * 8
        lda     D_0200,x
        clc
        adc     #<level_tiles
        sta     $18                 ; Store low byte of header pointer
        lda     D_0300,x
        adc     #>level_tiles
        sta     $19                 ; Store high byte of header pointer
        
        ; Copy 8 bytes from level header to $40A8 and $48A8
        ldy     #$07
L_E021:
        lda     ($18),y
        sta     D_40A8,y
        sta     CHARSETB_A8,y
        dey
        bpl     L_E021
        
        ; Check level number (level >= 100 branches)
        lda     level_flags,x       ; Get symmetry (bit 7) + sidebarCharsIndex (bits 0-6)
        and     #$7F
        cmp     #$64                ; Compare with 100
        bcs     L_E05E              ; Branch if >= 100
        
        ; For levels < 100: Calculate sidebar chars pointer
        ; Multiply level by 32 (shift left 5 times) and add sidebars base
        iny                         ; Y = 0
        sty     $1B                 ; Clear high byte
        asl     a                   ; Level * 2
        asl     a                   ; Level * 4
        rol     $1B
        asl     a                   ; Level * 8
        rol     $1B
        asl     a                   ; Level * 16
        rol     $1B
        asl     a                   ; Level * 32
        rol     $1B
        adc     #<sidebars          ; Add low byte of sidebars base
        sta     $1A
        lda     $1B
        adc     #>sidebars          ; Add high byte of sidebars base
        sta     $1B                 ; Pointer is now at sidebars + (level * 32)
        
        ; Copy 32 bytes from sidebar chars data to $40B0 and $48B0
        ldy     #$1F
L_E051:
        lda     ($1A),y
        sta     D_40B0,y
        sta     CHARSETB_B0,y
        dey
        bpl     L_E051
        bmi     L_E07E              ; Always branches
        
L_E05E:
        ; For levels >= 100: Duplicate existing data
        ldy     #$07
L_E060:
        lda     D_40A8,y            ; Source data
        sta     D_40B0,y            ; Copy to 4 locations
        sta     D_40B8,y
        sta     D_40C0,y
        sta     D_40C8,y
        sta     CHARSETB_B0,y       ; Mirror locations
        sta     CHARSETB_B8,y
        sta     CHARSETB_C0,y
        sta     CHARSETB_C8,y
        dey
        bpl     L_E060

L_E07E:
        ; Initialize frame counters
        sty     TXTTAB              ; $2B = $FF (Y is $FF from previous loop)
        iny                         ; Y = 0
        sty     VARTAB              ; $2D = 0
        
        ; Extract color information from level flags
        lda     level_colors,x      ; Get background color byte (bgColors metadata)
        tay
        lsr     a                   ; High nibble -> $1D
        lsr     a
        lsr     a
        lsr     a
        sta     $1D
        tya
        and     #$0F                ; Low nibble -> $1F
        sta     $1F
        
        ; Set timer values
        lda     #$1E                ; 30 frames
        sta     $2A
        sta     $2C
        
        ; Setup for level rendering
        jsr     init_level_renderer ; Initialize level renderer ($E299)
        
        ; Clear level data pointers
setup_level_data_pointers:
        lda     #$00
        sta     $11
        sta     $13
        sta     $04
        lda     #>__SCREEN_BACKUP__
        sta     $12
        sta     $14
        lda     #>__VIC_SCREEN_B__
        sta     $05
        
        ; Process 25 rows of screen data
        ldx     #$19                ; 25 rows (0-24)
        stx     $0A

; ============================================================================
; Inner loop: Process screen rows
; For each row, process 32 columns using bit-packed data
; Each bit in the source data determines whether to place a tile
; ============================================================================
L_E0B1:
        ldx     #$00                ; Column counter
        
L_E0B3:
        ; Get next byte of level data
        ldy     #$00
        lda     ($13),y
        sta     $07                 ; Store in $07 for bit processing
        
        ; Process 8 bits
        lda     #$08
        sta     $31                 ; Bit counter

L_E0BD:
        asl     $07                 ; Shift bit into carry
        bcc     L_E0F8              ; Skip if bit is 0
        
        ; Bit is 1: Place tiles
        txa
        tay                         ; Y = current column
        
        ; Write tile #$15 at current position
        lda     #$15
        sta     ($04),y
        
        ; Check and update next tile
        iny
        lda     ($04),y
        cmp     #$20                ; Space?
        beq     L_E0DD
        cmp     #$0A                ; Special tile?
        beq     L_E0DA
        cmp     #$0D                ; Another special tile?
        beq     L_E0DA
        lda     #$0E
        bne     L_E0DF
        
L_E0DA:
        lda     #$0F
        .byte   $2C                 ; BIT instruction to skip next 2 bytes
        
L_E0DD:
        lda     #$0C
        
L_E0DF:
        sta     ($04),y
        
        ; Update tile in row below (offset +$28 = 40 chars)
        txa
        clc
        adc     #$28
        tay
        
        lda     ($04),y
        cmp     #$20                ; Space?
        bne     L_E0EF
        lda     #$0A
        .byte   $2C                 ; BIT instruction to skip next 2 bytes
        
L_E0EF:
        lda     #$0D
        sta     ($04),y
        iny
        lda     #$0B
        sta     ($04),y

L_E0F8:
        inx                         ; Next column
        dec     $31                 ; Decrement bit counter
        bne     L_E0BD              ; Process next bit
        
        ; Move to next byte of level data
        inc     $13
        bne     L_E103
        inc     $14
        
L_E103:
        cpx     #$20                ; Processed 32 columns?
        bne     L_E0B3              ; No, continue with next byte
        
        ; Next row
        jsr     advance_screen_row  ; Move screen pointer down one row ($E28C)
        dec     $0A                 ; Decrement row counter
        bne     L_E0B1              ; Process next row

; ============================================================================
; Draw border around playfield
; Places decorative border tiles around the edges
; ============================================================================
draw_border:
        lda     #$00
        sta     $02
        lda     #$1E
        sta     $04
        lda     #>__VIC_SCREEN_B__
        sta     $03
        sta     $05
        
        ldx     #$0C                ; 12 rows to process

L_E11E:
        ; Top-left corner tiles
        lda     #$16
        ldy     #$00
        sta     ($02),y
        sta     ($04),y
        lda     #$17
        iny
        sta     ($02),y
        sta     ($04),y
        
        ; Top-right area
        lda     #$18
        ldy     #$28
        sta     ($02),y
        sta     ($04),y
        lda     #$19
        iny
        sta     ($02),y
        sta     ($04),y
        
        ; Fill middle and far right
        lda     #$20                ; Space character
        tay
        sta     ($02),y
        ldy     #$48
        sta     ($02),y
        
        ; Move to next row (add $50 = 80 bytes)
        lda     $02
        clc
        adc     #$50
        sta     $02
        bcc     L_E150
        inc     $03
        
L_E150:
        jsr     advance_screen_row              ; Advance screen pointers
        inx
        jsr     advance_screen_row              ; Advance again
        bne     L_E11E              ; Always branches (X never 0)

; ============================================================================
; Final border decoration
; ============================================================================
        ldy     #$00
        lda     #$16
        sta     ($02),y
        sta     ($04),y
        iny
        lda     #$17
        sta     ($02),y
        sta     ($04),y
        ldy     #$20
        tya                         ; A = $20 (space)
        sta     ($02),y

; ============================================================================
; Clean up screen character data
; Replace tile $0C with $0E in color RAM area
; ============================================================================
        ldx     #$1F
L_E16F:
        lda     D_5400,x
        cmp     #$0C
        bne     L_E17B
        lda     #$0E
        sta     D_5400,x
        
L_E17B:
        dex
        bpl     L_E16F
        
        ; Clear 9 bytes at $5800
        ldx     #$08
        lda     #$00
L_E182:
        sta     D_5800,x
        dex
        bpl     L_E182

L_E188:
        rts

; ============================================================================
; ROUTINE: decompress_level_data ($E18B)
; ============================================================================
; Decompresses and renders level/screen data
; Uses run-length encoding and tile patterns
;
; INPUT:
;   $10 (SUBFLG) - Current level number
;
; USES:
;   $02,$03 - Source data pointer ($B695 - wind currents/level data)
;   $11 - Level counter
;   $13,$14 - Decompression buffer pointer ($8B00)
;   $04,$05 - Screen destination pointer ($8500)
;   $0A - Fill pattern byte
;   $0B - Y register save
; ============================================================================
decompress_level_data:
        lda     SUBFLG              ; $10 = current level
        
L_E18B:
        sta     $11                 ; Save level number
        
        ; Set up source pointer to zone data (wind currents/level data)
        lda     #<zone_data
        sta     $02
        lda     #>zone_data
        sta     $03
        
        ; Set up decompression buffer pointer to $8B00
        lda     #$00
        sta     $13
        lda     #>__SCREEN_BACKUP__
        sta     $14
        
        ; Initialize renderer
        ldx     $11
        jsr     init_level_renderer
        
        ; Skip forward in source data based on level number
        ldy     #$00
        ldx     $11
        beq     L_E1BC              ; If level 0, skip ahead
        
L_E1A8:
        ; Read offset byte and advance pointer
        lda     ($02),y
        bpl     L_E1AE
        
L_E1AC:
        lda     #$01                ; Default offset = 1
        
L_E1AE:
        beq     L_E1AC              ; If 0, use 1
        clc
        adc     $02                 ; Add offset to pointer
        sta     $02
        bcc     L_E1B9
        inc     $03
        
L_E1B9:
        dex
        bne     L_E1A8              ; Repeat for each level
        
L_E1BC:
        ; Check for continuation marker
        lda     ($02),y
        bpl     L_E1C5              ; Positive = normal data
        and     #$7F                ; Strip high bit
        jmp     L_E18B              ; Recursive call
        
L_E1C5:
        sta     $11                 ; Save command byte
        
        ; Clear screen data ($8500-$8600, 24 rows x 32 columns)
        ldx     #$18                ; 24 rows
        lda     #$00
        sta     $04
        lda     #>D_8500
        sta     $05
        
L_E1D1:
        ; Get fill pattern from buffer
        ldy     #$03
        tya
        and     ($13),y             ; Mask with data at ($13+3)
        
        ; Fill 32 bytes (one row)
        ldy     #$1F
L_E1D8:
        sta     ($04),y
        dey
        bpl     L_E1D8
        
        ; Advance buffer pointer by 4
        lda     $13
        clc
        adc     #$04
        sta     $13
        bcc     L_E1E8
        inc     $14
        
L_E1E8:
        jsr     advance_screen_row              ; Advance screen pointer
        bpl     L_E1D1              ; Continue for all rows
        
        ; Process compressed data commands
        iny                         ; Y = 0
        lda     ($02),y
        beq     L_E188              ; If 0, done
        iny                         ; Y = 1

; ============================================================================
; Decode compressed tile commands
; Format 1 (high bit set): Rectangle fill
;   Byte 1: 1YYYXXXX (Y=row bits 6-5, X=column 0-4)
;   Byte 2: YYYYYCCC (Y=row bits 4-0, C=color 0-7)
;   Byte 3: HHHHHWWW (H=height 0-31, W=width 0-7)
; Format 2 (high bit clear): Horizontal mirror operation
; ============================================================================
L_E1F3:
        lda     ($02),y
        bpl     L_E24C              ; Branch if format 2
        
        ; Format 1: Rectangle fill
        tax
        and     #$60                ; Extract Y bits 6-5
        asl     a                   ; Shift to high nibble
        asl     a
        rol     a
        rol     a
        sta     $0A                 ; Save fill pattern

level_decompress_data:
        txa
        and     #$1F                ; Extract X coordinate (0-31)
        sta     $04
        
        iny
        lda     ($02),y             ; Get second byte
        tax
        lsr     a                   ; Extract color/row info
        lsr     a
        and     #$FE
        sta     $05
        
        txa
        and     #$07                ; Extract width (0-7)
        sta     $06
        
        iny
        lda     ($02),y             ; Get third byte (height/width)
        tax
        iny
        sty     $0B                 ; Save Y
        
        ; Calculate height
        asl     a
        rol     $06
        asl     a
        rol     $06
        txa
        and     #$1F                ; Height = 0-31
        sta     $07
        
        ; Calculate screen address using lookup table
        ldx     $05
        lda     D_AC09,x            ; Row address table (low)
        clc
        adc     $04                 ; Add column offset
        sta     $04
        lda     D_AC0A,x            ; Row address table (high)
        adc     #>D_8500
        sta     $05
        
        ; Fill rectangle
        ldx     $07                 ; Height counter
L_E239:
        ldy     $06                 ; Width counter
        lda     $0A                 ; Fill pattern
L_E23D:
        sta     ($04),y
        dey
        bpl     L_E23D
        
        jsr     advance_screen_row              ; Next row
        bpl     L_E239
        
        ldy     $0B                 ; Restore Y
        jmp     L_E282              ; Continue processing

; ============================================================================
; Format 2: Horizontal mirror/flip operation
; Mirrors the left half of the screen to the right half
; ============================================================================
L_E24C:
        iny
        sty     $0B                 ; Save Y
        
        ; Initialize screen pointer
        lda     #$00
        sta     $04
        lda     #>D_8500
        sta     $05
        
        ldx     #$18                ; 24 rows
        
L_E259:
        lda     #$00
        sta     $06                 ; Source column = 0
        lda     #$1F
        sta     $07                 ; Dest column = 31 (rightmost)
        
L_E261:
        ldy     $06
        lda     ($04),y             ; Read from left side
        and     #$01                ; Check bit 0
        beq     L_E26F
        lda     ($04),y
        eor     #$02                ; Flip bit 1
        bne     L_E271
        
L_E26F:
        lda     ($04),y             ; Copy unchanged
        
L_E271:
        ldy     $07
        sta     ($04),y             ; Write to right side
        dec     $07                 ; Move dest left
        inc     $06                 ; Move source right
        cpy     #$10                ; Processed 16 columns?
        bne     L_E261
        
        jsr     advance_screen_row              ; Next row
        bpl     L_E259
        
L_E282:
        ldy     $0B                 ; Restore Y
        cpy     $11                 ; More commands?
        beq     L_E28B
        jmp     L_E1F3              ; Process next command
        
L_E28B:
        rts

; ============================================================================
; ROUTINE: advance_screen_row ($E28C)
; ============================================================================
; Advances screen pointer to next row (+40 bytes)
;
; MODIFIES:
;   $04,$05 - Screen pointer (advanced by $28 = 40)
;   X - Decremented
; ============================================================================
D_E28C:
advance_screen_row:
        lda     $04
        clc
        adc     #$28                ; Add 40 (screen row width)
        sta     $04
        bcc     L_E297
        inc     $05
L_E297:
        dex
        rts

; ============================================================================
; ROUTINE: init_level_renderer
; ============================================================================
; Initializes the level rendering system.
; Reads the current level's bitmap data, sets up symmetry mirroring,
; physics flags, and border walls.
;
; INPUT:
;   X - Level index (0-99)
;
; USES:
;   $01 - Memory banking ($30 = RAM under I/O)
;   $3C - Level counter save
;   $3D,$3E - Bit manipulation temporaries
;   $40,$41 - Data pointer (source bitmap or decompressed scratch buffer)
; ============================================================================
D_E299:
init_level_renderer:
        stx     $3C                 ; Save level index

.ifdef COMPRESS_LEVELS
        ; --- Compressed path ---
        ; Bank in all-RAM ($01=$30) for the entire routine.  Needed because:
        ;   - The decompressor + data live in the I/O shadow ($D000-$DFFF)
        ;   - The decompression buffer is in the I/O shadow gap (DECOMP_BUFFER)
        ;   - The copy/mirror loop reads the buffer via ($40),y
        ; $01=$30 is kept until the routine's shared exit, matching the
        ; original path which also runs entirely with $01=$30.
        ; The IRQ handler saves/restores $01, so no SEI is needed.
        lda     #$30
        sta     R6510               ; $01 = all RAM visible

        ; Decompress level bitmap into the I/O shadow gap.
        jsr     decompress_level_bitmap

        ; Reset $40/$41 to start of decompressed data.
        ; The decompressor advanced $40; the copy/mirror code
        ; below reads from ($40),y and expects it at the buffer start.
        ; ($41 is unchanged — the buffer never crosses a page boundary.)
        lda     #<DECOMP_BUFFER
        sta     $40
        lda     #>DECOMP_BUFFER
        sta     $41

        ldx     $3C                 ; Restore level index
.else
        ; --- Original uncompressed path ---
        ; Bank in RAM under I/O to access level bitmaps at $C5F2+
        lda     #$30
        sta     R6510               ; $01 = CPU port

        ; Set up data pointer to level bitmaps
        lda     #<level_bitmaps
        sta     $40
        lda     #>level_bitmaps
        sta     $41

        cpx     #$00
        beq     L_E2C3              ; Skip if level 0

        ; Calculate offset based on previous levels
        ldx     #$00
L_E2AD:
        lda     #$2E                ; Base offset = 46 bytes
        ldy     level_flags,x       ; Get symmetry flag (bit 7)
        bmi     L_E2B5              ; Branch if asymmetric level (bit 7 set)
        asl     a                   ; Double offset (92 bytes)
L_E2B5:
        clc
        adc     $40                 ; Add to pointer
        sta     $40
        bcc     L_E2BE
        inc     $41
L_E2BE:
        inx
        cpx     $3C                 ; Reached target level?
        bne     L_E2AD
.endif

L_E2C3:
        ldy     #$00
        lda     level_flags,x       ; Get symmetry flag (bit 7)
        bpl     L_E2CB              ; Branch if symmetric (bit 7 clear)
        iny                         ; Y = 1 for asymmetric levels

L_E2CB:
        ; Set up self-modifying code addresses for copy/mirror
        lda     D_E36A,y            ; Get low byte of routine
        sta     D_E30C              ; Store in JSR target
        lda     D_E36C,y            ; Get high byte
        sta     D_E30D

        ; --- Physics flags processing ---
        lda     physics_flags,x
        sta     $3D

        ; Process two chunks (at X=0 and X=96)
        ldx     #$00
        jsr     L_E34E
        ldx     #$60
        jsr     L_E34E

        ; Extract and store color bits
        lda     $3D
        and     #$03                ; Low 2 bits
        sta     $3E
        lsr     $3D                 ; Shift down
        lsr     $3D

        ; Update hole bits at $8B03
        lda     D_8B03
        and     #$FC                ; Clear low 2 bits
        ora     $3E                 ; Set new bits
        sta     D_8B03

        ; Update hole bits at $8B63
        lda     D_8B63
        and     #$FC
        ora     $3D
        sta     D_8B63

        ; --- Copy/mirror decompressed bitmap to $8B04 ---
        ldx     #$00
        ldy     #$00
L_E308:
        jsr     L_E31F

        ; Self-modifying JSR target (set at L_E2CB)
D_E30C  = * + 1                     ; Low byte of JSR operand
D_E30D  = * + 2                     ; High byte of JSR operand
        jsr     L_E32A              ; Default target (modified at runtime)

        ; Set border wall bits (high bits of first byte in each row)
        lda     D_8B00,x
        ora     #$C0                ; Set bits 7 and 6
        sta     D_8B00,x
        cpx     #$5C                ; 92 bytes processed?
        bne     L_E308

        ; Restore normal memory banking. Both paths run with $01=$30:
        ; - Original path: reads level bitmaps from I/O shadow ($D000+)
        ; - Compressed path: reads decompressed data from I/O gap (DECOMP_BUFFER)
        lda     #$35
        sta     R6510
        rts

; ============================================================================
; Helper routines for data copying
; ============================================================================
L_E31F:
D_E31F:
        jsr     L_E322
        
L_E322:
D_E322:
        lda     ($40),y             ; Read from source
        sta     D_8B04,x            ; Write to destination+4
        iny
        inx
        rts

; Additional helper routine (13 bytes)
L_E32A:
        jsr     D_E337
        sta     D_8B04,x
        jsr     D_E337
        sta     D_8B02,x
        rts

D_E337:
        lda     D_8B02,x
        sta     $3D
        lda     #$01
        sta     $3E
        lda     #$00
L_E342:
        asl     $3D                 ; Shift bit
        bcc     L_E348
        ora     $3E                 ; Set bit if carry
L_E348:
        asl     $3E
        bcc     L_E342
        inx
        rts

L_E34E:
D_E34E:
        ldy     #$01
        jsr     L_E355
        ldy     #$02
        
L_E355:
D_E355:
        lsr     $3D                 ; Shift bit from $3D
        bcs     L_E35B              ; Branch if bit was 1
        ldy     #$00                ; Use index 0
L_E35B:
        lda     D_E36E,y            ; Get data byte 1
        sta     D_8B00,x
        inx
        lda     D_E371,y            ; Get data byte 2
        sta     D_8B00,x
        inx
        rts

; ============================================================================
; Data tables
; ============================================================================
D_E36A:
        .byte   <D_E31F             ; Low byte of L_E31F routine address
        .byte   <L_E32A             ; Low byte of L_E32A routine address

D_E36C:
        .byte   >D_E31F,>L_E32A     ; High bytes of routine addresses

D_E36E:
        .byte   $FF,$FF,$E1         ; Data table 1

D_E371:
        .byte   $FF,$87,$FF         ; Data table 2

; ============================================================================
; ROUTINE: clear_screen ($E374)
; Clears screen memory, sprites, and color RAM
; ============================================================================
clear_screen:
        lda     #$00
        sta     VIC_BORDER          ; $D020 = black border
        sta     VIC_BG0             ; $D021 = black background
        sta     VIC_SPR_ENA         ; $D015 = disable all sprites
        
        jsr     fill_color_ram      ; Additional cleanup
        
        ; Clear screen RAM $5000-$53FF (1024 bytes)
        lda     #$20                ; Space character
L_E384:
        sta     D_5000,x
        sta     D_5100,x
        sta     D_5200,x
        sta     D_5300,x
        inx
        bne     L_E384

; ============================================================================
; ROUTINE: clear_color_ram ($E393)
; ============================================================================
; Clears color RAM $5400-$57FF
; ============================================================================
D_E393:
clear_color_ram:
        ldx     #$00
        lda     #$20                ; White color
L_E397:
        sta     D_5400,x
        sta     D_5500,x
        sta     D_5600,x
        sta     D_5700,x
        inx
        bne     L_E397
        rts

.ifdef COMPRESS_LEVELS
; ============================================================================
; Level Bitmap Decompressor (in CODE_DECOMPRESSOR segment)
; ============================================================================
; Custom dictionary + zero-run decompressor for level bitmap data.
; Lives in CODE_DECOMPRESSOR, in the gap between bitmap tables and $E000.
; This address range ($D000-$DFFF) overlaps C64 I/O registers, so the
; decompressor is only callable with $01=$30 (all-RAM banking).
; init_level_renderer sets this before JSR decompress_level_bitmap.
;
; Compression format (see build/convert-levels.py for encoder):
;   Uses 36 byte values that never appear in uncompressed bitmap data.
;   A 256-byte decode table maps each source byte to an action code:
;     $00          = literal byte (copy source byte to output)
;     $01          = zero-run escape (next byte = run_length - 2)
;     $02..THR-1   = 2-byte dictionary pair (index = action - 2)
;     THR+         = 3-byte dictionary triple (index = action - THR)
;   THR is stored as the last byte of the dict entries blob.
;
; Dict entries blob layout:
;   [N_PAIRS x 2 bytes] [N_TRIPLES x 3 bytes] [threshold byte]
;
; Offset table: 100 x 1-byte deltas (each = compressed size of that level).
;   The source pointer is found by summing deltas[0..level-1].
; ============================================================================

.segment "IO_CODE_DECOMPRESSOR"

; --- Decompress level bitmap ---
; INPUT:  $3C = level index
; OUTPUT: $40 advanced past decompressed data (caller must reset)
;         $41 unchanged (high byte of DECOMP_BUFFER)
;
; Zero-page usage (preserves $3C; does NOT preserve $02):
;   $3D/$3E = source pointer (compressed data)
;   $3F = bytes remaining to decompress
;   $40/$41 = destination pointer (DECOMP_BUFFER; high byte never changes)
;   Y = always 0 (for indirect indexed addressing)
;
; Size-optimized vs. original:
;   - Uses SMC for triple index*3 (avoids ZP_02 scratch + save/restore)
;   - Omits $41 page-cross check in @store_out (asserted at build time)
decompress_level_bitmap:
        ; --- Patch threshold constants via SMC ---
        ; The threshold byte (pair/triple boundary) is the last byte of
        ; the dict entries blob.  Load it once and patch the CMP and SBC
        ; immediate operands in the decompression loop.
        lda     bitmap_dict_entries_end - 1  ; threshold
        sta     @smc_cmp_thr + 1    ; patch CMP #threshold
        sta     @smc_sbc_thr + 1    ; patch SBC #threshold
        ; pairs_size = (threshold - 2) * 2
        sec
        sbc     #$02                ; A = n_pairs
        asl     a                   ; A = n_pairs * 2 = pairs_size
        sta     @smc_adc_psz + 1    ; patch ADC #pairs_size

        ; --- Accumulate 1-byte deltas to find compressed data offset ---
        ; source_ptr = level_bitmaps_compressed + sum(deltas[0..level-1])
        lda     #<level_bitmaps_compressed
        sta     $3D
        lda     #>level_bitmaps_compressed
        sta     $3E
        ldx     $3C                 ; Level index
        beq     @offset_done        ; Level 0: offset = 0
        ldy     #$00                ; Delta table index
        clc
@offset_loop:
        lda     level_bitmap_deltas,y
        adc     $3D
        sta     $3D
        bcc     :+
        inc     $3E
        clc
:       iny
        dex
        bne     @offset_loop

@offset_done:
        ; Set destination pointer to I/O shadow gap buffer.
        ; Only the low byte changes during decompression; the high byte
        ; is constant because the 92-byte buffer never crosses a page
        ; (verified by .assert below).
        lda     #<DECOMP_BUFFER
        sta     $40
        lda     #>DECOMP_BUFFER
        sta     $41

        ; Determine decompressed size from level flags
        ldx     $3C
        lda     level_flags,x
        and     #$80                ; Bit 7: 1=symmetric (46 bytes), 0=asymmetric (92 bytes)
        bne     @symmetric
        lda     #92                 ; Asymmetric: full 92 bytes
        bne     @have_size          ; always taken
@symmetric:
        lda     #46                 ; Symmetric: left half only
@have_size:
        sta     $3F                 ; $3F = bytes remaining
        ldy     #$00                ; Y stays 0 throughout

        ; --- Main decompression loop ---
@loop:
        lda     ($3D),y             ; Read compressed byte
        tax                         ; X = raw byte (preserve for literal)
        inc     $3D                 ; Advance source pointer
        bne     :+
        inc     $3E
:
        ; Look up action in decode table
        lda     bitmap_decode_table,x   ; A = action code
        beq     @literal            ; $00 = literal (raw byte still in X)
        cmp     #$02
        bcc     @zero_run           ; $01 = zero-run escape
                                    ; $02+ = dictionary entry (fall through)

        ; --- Dictionary entry: pair ($02..THR-1) or triple (THR+) ---
@smc_cmp_thr:
        cmp     #$00                ; SMC: patched to threshold
        bcs     @dict_triple

        ; --- 2-byte pair: index = (action - 2), byte offset = index * 2 ---
        sec
        sbc     #$02                ; A = pair index
        asl     a                   ; A = index * 2
        tax
        lda     bitmap_dict_entries,x
        jsr     @store_out
        lda     bitmap_dict_entries + 1,x
        jsr     @store_out
        bne     @loop
        beq     @done               ; always taken ($3F = 0)

        ; --- 3-byte triple: index = (action - THR) ---
        ; byte offset = pairs_size + index * 3
        ; index * 3 computed via SMC to avoid needing ZP scratch
@dict_triple:
@smc_sbc_thr:
        sbc     #$00                ; SMC: patched to threshold (C=1 from BCS)
        sta     @smc_idx + 1        ; SMC: stash triple index for *3 calc
        asl     a                   ; A = index * 2
        clc
@smc_idx:
        adc     #$00                ; SMC: + index = index * 3
@smc_adc_psz:
        adc     #$00                ; SMC: + pairs_size (C=0: idx*3 < 128)
        tax
        lda     bitmap_dict_entries,x
        jsr     @store_out
        lda     bitmap_dict_entries + 1,x
        jsr     @store_out
        lda     bitmap_dict_entries + 2,x
        jsr     @store_out
        bne     @loop
        beq     @done               ; always taken ($3F = 0)

        ; --- Zero-run: next source byte = count - 2 ---
@zero_run:
        lda     ($3D),y             ; Read count - 2
        inc     $3D                 ; Advance source pointer
        bne     :+
        inc     $3E
:       clc
        adc     #$02
        tax                         ; X = zero count
        lda     #$00                ; Fill value = 0
@fill_loop:
        jsr     @store_out
        dex
        bne     @fill_loop
        lda     $3F                 ; DEX clobbers Z, must re-check
        bne     @loop
        beq     @done               ; always taken ($3F = 0)

        ; --- Literal: raw byte is in X ---
@literal:
        txa                         ; A = raw source byte
        jsr     @store_out
        bne     @loop

        ; --- Decompression complete ---
@done:
        rts

        ; --- Helper: write A to ($40),y and advance dest pointer ---
        ; Note: $41 (high byte) is never incremented — the 92-byte buffer
        ; is asserted not to cross a page boundary (see .assert below).
@store_out:
        sta     ($40),y
        inc     $40
        dec     $3F
        rts

; --- Temporary decompression buffer (92 bytes) ---
; Sits in the I/O shadow gap after the decompressor code.
; Only accessible with $01=$30 (all-RAM banking).
; Previously used the cassette buffer at $033C, but that overlaps the
; D_0300 multiplication lookup table which the game needs intact.
DECOMP_BUFFER:
        .res    92, $00

; Build-time safety check: the 92-byte decompression buffer must not
; cross a 256-byte page boundary, because @store_out omits inc $41.
.assert (>DECOMP_BUFFER) = (>(DECOMP_BUFFER + 91)), error, "DECOMP_BUFFER crosses a page boundary — @store_out needs inc $41"

.else
; Empty segment declaration to satisfy the linker config.
; CODE_DECOMPRESSOR only contains code in the compressed build.
        .segment "IO_CODE_DECOMPRESSOR"
.endif ; COMPRESS_LEVELS

; ============================================================================
; End of bb-level-renderer.s
; Forward references (wait_one_frame, fill_color_ram, D_AC09, D_AC0A) defined in bb-master.s
; ============================================================================
