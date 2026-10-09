;===============================================================================
; bb-extend-bonus.s - EXTEND Letter Collection Bonus Handler
;===============================================================================
; Address range: $32BF-$3489 (459 bytes)
;
; Purpose: Handles the EXTEND bonus triggered when a player collects all six
;          letters E-X-T-E-N-D. Awards an extra life, displays celebration
;          animation, and skips the current level.
;
; EXTEND Bonus Visual Sequence:
; 1. Player collects final letter -> completes vertical "EXTEND" text on border
; 2. Phase 1: Letters on screen change rapidly/randomly (celebration effect)
; 3. Phase 2: Screen fills with random collectible items (fruits, diamonds, etc.)
; 4. Phase 3: Large "EXTEND" text displays letter-by-letter in center of screen
; 5. Player receives +1 life and level is skipped
;
; Key Features:
; 1. D_32BF - Data table (2 bytes): player index offsets
; 2. D_32C1 - EXTEND trigger check
;    - Checks if either player collected item $3F (EXTEND completion trigger)
;    - If found, initiates EXTEND bonus sequence
; 3. EXTEND Bonus Sequence ($32CD-$341E):
;    - Phase 1 (L_32EE): Rapidly changes EXTEND letter components on screen
;      Creates visual "letter morphing" celebration effect
;    - Phase 2 (L_3389): Fills entire screen with collectible items from D_A892
;      Shows fruits, diamonds, and other pickups in grid pattern
;    - Phase 3 (L_33DA): Displays large centered "EXTEND" text over items
;    - Awards extra life to player who completed the collection
;    - Skips current level (level complete flag decremented)
; 4. D_3421 - Character position calculator
;    - Converts grid coordinates to pixel positions
;    - Updates position tables (D_4600, D_4700, D_4E00, D_4F00)
; 5. D_344A - Character block placement routine
;    - Places 2x2 character block for items/graphics
;    - Sets screen and color RAM values
;    - Used for both collectible items and "EXTEND" text display
;
; Technical Details:
; - Item $3F detection: scans $54 and $55 (player 1 and 2 item slots)
; - Phase 1: Uses D_E9EA (RNG) to rapidly cycle EXTEND letter components
;   Letter codes: $4A, $4E, $52, $56, $5A (matching D_A80D EXTEND letters)
;   Placed randomly across 20 rows, creating morphing animation
; - Phase 2: Fills 24 rows x 32 columns with collectible items
;   Uses D_A892 table (level data), values < $28, multiplied by 4, OR'd with $60
;   Generates character codes in $60-$9F range (collectible item graphics)
; - Phase 3: Uses D_A80D table containing 6 character codes for "EXTEND" text
;   Displays letter-by-letter in center: $4A, $4E, $52, $4A, $56, $5A
; - Character block: 4 chars arranged as 2x2 (top-left, top-right, bottom-left, bottom-right)
; - Color data from D_A8E4 based on DATPTR value
; - Screen memory layout: $C000/$0000/$E000 configurations supported
;
; Position Table Updates:
; - D_4600[x] = Y pixel position (row * 8 + $14)
; - D_4700[x] = X pixel position (col * 8 + $35)
; - D_4E00[x] = Screen address low byte
; - D_4F00[x] = Screen address high byte
; - CURLIN ($39) = character placement counter
;
; External Calls:
; - D_05AD: Unknown routine (Y=$2E parameter)
; - D_1844: Update player input
; - D_1847: Screen update routine
; - D_1853: Screen rendering routine
; - D_2E79: Entity reset routine (from bb-level-transition.s)
; - D_046C: Lives display update
; - D_311E: Screen area fill top (from bb-level-start.s)
; - D_312E: Screen area fill middle (from bb-level-start.s)
; - D_7B53: Unknown routine
; - D_7BC3: Wait for frame sync
; - D_7BC6: Wait routine variant
; - D_7BC8: Wait routine with delay parameter
; - D_E374: Unknown routine
; - D_E3A7: Update sprite data
; - D_E42A: Sprite/entity update routine
; - D_E49B: Game loop continuation
; - copy_and_mask_graphics: Copy and mask graphics routine
; - D_E9EA: Random number generator
; - L_A474: READY label
;
; Called From:
; - $0A57: jsr D_32C1 (main game loop - checks for bonus trigger)
; - $3308: jsr D_344A (internal - Phase 1: letter animation placement)
; - $33A6: jsr D_344A (internal - Phase 2: collectible item placement)
; - $33E8: jsr D_344A (internal - Phase 3: "EXTEND" text placement)
;
;===============================================================================

;-------------------------------------------------------------------------------
; Data table for player index offsets
;-------------------------------------------------------------------------------
.segment "CODE_PLATFORM"

D_32BF:
    .byte $00, $1E              ; Player index multipliers or screen offsets

;-------------------------------------------------------------------------------
; D_32C1 - EXTEND bonus trigger check
; Checks if either player has collected all EXTEND letters (item $3F completion)
; If found, initiates EXTEND bonus sequence with visual celebration
;-------------------------------------------------------------------------------
D_32C1:
    ldx  #$01                   ; Start with player 2
L_32C3:
    lda  $54,x                  ; Get player's current item
    cmp  #$3F                   ; Is it the EXTEND completion trigger ($3F)?
    beq  L_32CD                 ; Yes - start EXTEND bonus!
    dex                         ; Check next player
    bpl  L_32C3                 ; Continue for both players
    rts                         ; No EXTEND completion - exit

;-------------------------------------------------------------------------------
; L_32CD - EXTEND bonus sequence start
; Main routine that handles the EXTEND letter collection celebration
; Three-phase animation: letter morphing -> collectibles fill screen -> EXTEND text
; Awards extra life and skips the current level
;-------------------------------------------------------------------------------
L_32CD:
    txa                         ; Save player index (0 or 1)
    pha                         ; Push to stack for later use
    ldy  #(song_extend - music_song_table) ; EXTEND fanfare
    jsr  D_05AD                 ; Start EXTEND music
    inc  MEMSIZ                 ; Increment memory pointer
    jsr  L_A474                 ; READY - screen setup
    lda  ARYTAB+1               ; Get screen config byte
    eor  #ARYTAB_SCREEN_TOGGLE  ; Toggle screen configuration
    jsr  D_1853                 ; Apply screen rendering changes
    pla                         ; Restore player index
    pha                         ; Keep it on stack (needed again later)
    tax                         ; X = player index
    lda  D_32BF,x               ; Get player offset from table
    sta  MEMSIZ+1               ; Store as Y position offset
    lda  #$14                   ; Starting row = 20 ($14)
    sta  DATPTR                 ; Store in color pointer
    sta  CURLIN+1               ; Store as row counter (20 iterations)

;-------------------------------------------------------------------------------
; L_32EE - Phase 1: Letter morphing animation loop
; Rapidly changes EXTEND letter components across screen to create celebration effect
; This creates a "morphing letters" animation before the collectibles appear
;-------------------------------------------------------------------------------
L_32EE:
    jsr  D_7BC3                 ; Wait for frame sync
    lda  #$0A                   ; Start at column 10
    sta  CURLIN                 ; Store as character counter

;-------------------------------------------------------------------------------
; L_32F5 - Random letter component selection
; Selects random EXTEND letter components and places them across screen
; Generates codes: $4A, $4E, $52, $56, $5A (E-X-T-E-N-D letter graphics)
;-------------------------------------------------------------------------------
L_32F5:
    jsr  D_E9EA                 ; Get random number
    and  #$07                   ; Limit to 0-7
    cmp  #$05                   ; Is it >= 5?
    bcs  L_32F5                 ; Yes - try again (only want 0-4)
    asl                         ; Multiply by 4 (shift left twice)
    asl
D_3300:
    adc  #$4A                   ; Add base $4A -> results: $4A,$4E,$52,$56,$5A
    sta  DATLIN+1               ; Store EXTEND letter component code
    ldx  MEMSIZ+1               ; X = row position
    ldy  CURLIN                 ; Y = column position
    jsr  D_344A                 ; Place 2x2 character block
    lda  CURLIN                 ; Get current column
    clc
    adc  #$02                   ; Move 2 columns right
    sta  CURLIN                 ; Update column counter
    cmp  #$16                   ; Reached column 22?
    bne  L_32F5                 ; No - place more letter components
    dec  CURLIN+1               ; Decrement row counter
    bne  L_32EE                 ; More rows - continue morphing animation

;-------------------------------------------------------------------------------
; L_331A - Cleanup after Phase 1 (letter morphing animation)
; Resets entities, clears memory, prepares for Phase 2 (collectibles display)
;-------------------------------------------------------------------------------
    jsr  D_2E79                 ; Reset entities
    jsr  clear_screen            ; Clear screen
    jsr  copy_screen_buffers    ; Game loop continuation
    lda  #$00                   ; Clear accumulator
    ldx  #$2F                   ; Clear 48 bytes

;-------------------------------------------------------------------------------
; L_3327 - Memory clearing loop
; Clears player/entity data at D_4080
;-------------------------------------------------------------------------------
L_3327:
    sta  D_4080,x               ; Clear byte at D_4080+X
    dex                         ; Next byte
    bpl  L_3327                 ; Continue until X < 0
    stx  FOUR6                  ; Set $53 to $FF
    stx  $52                    ; Set $52 to $FF
    ldx  #$1F                   ; 32 bytes to save/restore

;-------------------------------------------------------------------------------
; L_3333 - Save position data and clear sprite data
; Temporarily stores D_4700 data to D_A988, then clears D_4700
;-------------------------------------------------------------------------------
L_3333:
    lda  D_A988,x               ; Get saved data
    sta  D_4700,x               ; Restore to D_4700 (X positions)
    lda  #$FF                   ; Clear value
    sta  D_A988,x               ; Store $FF in save area
    dex                         ; Next byte
    bpl  L_3333                 ; Continue for 32 bytes
    jsr  copy_and_mask_graphics ; Copy and mask graphics
    lda  #$0F                   ; Wait parameter (15 frames)
    jsr  D_7BC8                 ; Wait with delay
    ldx  #$1F                   ; 32 bytes to restore

;-------------------------------------------------------------------------------
; L_334B - Restore position data
; Restores D_4700 data from temporary storage at D_A988
;-------------------------------------------------------------------------------
L_334B:
    lda  D_4700,x               ; Get D_4700 data
    sta  D_A988,x               ; Save to temporary area
    dex                         ; Next byte
    bpl  L_334B                 ; Continue for 32 bytes
    ldx  #$02                   ; Setup value
    stx  $1C                    ; Store in $1C
    dex                         ; X = 1
    stx  $1E                    ; Store in $1E
    jsr  D_7B53                 ; Unknown routine
    jsr  D_1847                 ; Screen update routine
    jsr  update_sprite_animations ; Update sprite data
    ldx  #$00                   ; Start at byte 0

;-------------------------------------------------------------------------------
; L_3366 - Copy ROM data to RAM for Phase 2
; Copies level/character data from ROM ($9AE0-$9EE0) to RAM ($4300-$4700)
; This prepares the data needed to fill screen with collectible items
;-------------------------------------------------------------------------------
L_3366:
    lda  sprites_rom+$0000,x    ; Get ROM data from $9AE0
    sta  D_4300,x               ; Store to RAM at $4300
    lda  sprites_rom+$0100,x    ; Get ROM data from $9BE0
    sta  D_4400,x               ; Store to RAM at $4400
    lda  sprites_rom+$0200,x    ; Get ROM data from $9CE0
    sta  D_4500,x               ; Store to RAM at $4500
    lda  sprites_rom+$0300,x    ; Get ROM data from $9DE0
    sta  D_4600,x               ; Store to RAM at $4600 (Y positions)
    lda  sprites_rom+$0400,x    ; Get ROM data from $9EE0
    sta  D_4700,x               ; Store to RAM at $4700 (X positions)
    inx                         ; Next byte
    bne  L_3366                 ; Continue for 256 bytes
    stx  CURLIN                 ; CURLIN = 0 (start at row 0)

;-------------------------------------------------------------------------------
; L_3389 - Phase 2: Fill screen with collectible items
; Places collectible items (fruits, diamonds, etc.) across grid (24 rows x 32 columns)
; This overwrites the letter morphing animation from Phase 1
;-------------------------------------------------------------------------------
L_3389:
    lda  #$00                   ; Start at column 0
    sta  MEMSIZ+1               ; Column counter

;-------------------------------------------------------------------------------
; L_338D - Random collectible item selection and placement
; Selects random collectible items from D_A892 table (level data) and places on screen
; Generates item graphics in $60-$9F character code range
;-------------------------------------------------------------------------------
L_338D:
    jsr  D_E9EA                 ; Get random number
    and  #$1F                   ; Limit to 0-31
    tax                         ; Use as index into D_A892
    lda  D_A892,x               ; Get item data from level table
    cmp  #$28                   ; Is it >= $28 (40)?
    bcs  L_338D                 ; Yes - try again (invalid item)
    asl                         ; Multiply by 4
    asl
    ora  #$60                   ; OR with $60 -> generates $60-$9F range
    sta  DATLIN+1               ; Store collectible item character code
    stx  DATPTR                 ; Store table index for color lookup
    ldx  MEMSIZ+1               ; X = column position
    ldy  CURLIN                 ; Y = row position
    jsr  D_344A                 ; Place 2x2 collectible item block
    inc  MEMSIZ+1               ; Advance column by 2
    inc  MEMSIZ+1
    lda  MEMSIZ+1               ; Get column counter
    cmp  #$20                   ; Reached column 32?
    bne  L_338D                 ; No - continue placing items
    inc  CURLIN                 ; Next row
    inc  CURLIN                 ; Rows advance by 2
    lda  CURLIN                 ; Get row counter
    cmp  #$18                   ; Reached row 24?
    bne  L_3389                 ; No - continue filling screen

;-------------------------------------------------------------------------------
; L_33BD - Prepare for Phase 3: "EXTEND" text display
; Clears specific screen areas and sets up for centered text animation
;-------------------------------------------------------------------------------
    jsr  D_312E                 ; Clear middle screen area
    pla                         ; Get player index from stack
    pha                         ; Keep it on stack (needed once more)
    clc
    adc  #$21                   ; Add $21 to player index
    sta  D_A804                 ; Store result
    jsr  D_311E                 ; Clear top screen area
    ldx  #<D_A7F9               ; Low byte of address
    ldy  #>D_A7F9               ; High byte of address ($A7F9)
    jsr  display_text_string    ; Sprite/entity update routine
    lda  #$14                   ; Color value (20)
    sta  DATPTR                 ; Store color pointer
    lda  #$05                   ; 6 letters (counting down from 5)
    sta  MEMSIZ+1               ; Letter counter

;-------------------------------------------------------------------------------
; L_33DA - Phase 3: Display "EXTEND" text letter by letter
; Shows large centered "EXTEND" text over collectible items background
; Uses D_A80D table: $4A, $4E, $52, $4A, $56, $5A (6 letters)
;-------------------------------------------------------------------------------
L_33DA:
    ldx  MEMSIZ+1               ; X = letter index (5 down to 0)
    lda  D_A80D,x               ; Get letter from "EXTEND" table
    sta  DATLIN+1               ; Store as character to display
    txa                         ; A = letter index
    asl                         ; Multiply by 2 for spacing
    adc  #$0A                   ; Add 10 for X position offset
    tax                         ; X = column position
    ldy  #$0B                   ; Y = row 11 (center of screen)
    jsr  D_344A                 ; Place 2x2 character block
    dec  MEMSIZ+1               ; Decrement letter counter
    bpl  L_33DA                 ; More letters - continue
    jsr  D_1847                 ; Update screen
    lda  #$C8                   ; Wait for 200 frames
    jsr  D_7BC8                 ; Wait with delay
    lda  #$0B                   ; Countdown value (11)
    sta  D_597F                 ; Store countdown timer

;-------------------------------------------------------------------------------
; L_33FC - Animation countdown loop
; Waits for 11 frames with screen updates
;-------------------------------------------------------------------------------
L_33FC:
    jsr  D_1844                 ; Update player input
    jsr  D_7BC6                 ; Wait for frame
    dec  D_597F                 ; Decrement countdown
    bne  L_33FC                 ; Not zero - continue waiting

;-------------------------------------------------------------------------------
; Award extra life and clean up
; Gives +1 life to the player who completed EXTEND, clears item flag,
; updates lives display, and decrements level completion counter
;-------------------------------------------------------------------------------
    jsr  clear_screen            ; Clear screen
    jsr  D_7BC6                 ; Wait for frame
    pla                         ; Get player index from stack (final use)
    pha                         ; Push back for one more use
    tax                         ; X = player index
    inc  D_045A,x               ; Increment player's lives
    lda  #$00                   ; Clear value
    sta  $54,x                  ; Clear player's item slot (remove $3F flag)
    jsr  D_046C                 ; Update lives display on screen
    dec  $21                    ; Decrement level complete counter (skips level)
    pla                         ; Get player index from stack (final cleanup)
    tax                         ; X = player index
    jmp  L_32C3                 ; Jump back to check other player

;-------------------------------------------------------------------------------
; D_3421 - Character position calculator
; Converts grid coordinates (row, column) to pixel positions and screen addresses
; Input: A = row, Y = column, CURLIN = entity index
; Updates: D_4600[x] = Y pixel, D_4700[x] = X pixel
;          D_4E00[x] = screen address low, D_4F00[x] = screen address high
;-------------------------------------------------------------------------------
D_3421:
    sta  MEMSIZ+1               ; Save row value
    ldx  CURLIN                 ; X = entity index
    inc  CURLIN                 ; Increment for next entity
    asl                         ; Row * 8 (multiply by 8 pixels per row)
    asl
    asl
    adc  #$14                   ; Add Y offset ($14 = 20 pixels)
    sta  D_4600,x               ; Store Y pixel position
    tya                         ; A = column
    asl                         ; Column * 8 (multiply by 8 pixels per column)
    asl
    asl
    adc  #$35                   ; Add X offset ($35 = 53 pixels)
    sta  D_4700,x               ; Store X pixel position
    lda  MEMSIZ+1               ; Get row value
    adc  D_AD22,y               ; Add screen row base address (low byte)
    sta  D_4E00,x               ; Store screen address low byte
    lda  #$00                   ; Clear high byte
    adc  D_AD41,y               ; Add screen column offset (high byte)
    sta  D_4F00,x               ; Store screen address high byte
    ldx  MEMSIZ+1               ; Restore row value to X
    ; Falls through to D_344A

;-------------------------------------------------------------------------------
; D_344A - Place 2x2 character block on screen
; Places a 2x2 block of characters with color data
; Used for: Phase 1 (letter animation), Phase 2 (collectible items), Phase 3 (EXTEND text)
; Input: X = row offset, Y = column, DATLIN+1 = base character code
;        DATPTR = color index
; Output: 4 consecutive characters placed on screen with color
; Screen layout: [char] [char+1]
;                [char+2] [char+3]
;-------------------------------------------------------------------------------
D_344A:
    txa                         ; A = X position
    clc
    adc  D_AD22,y               ; Add screen row base address (low byte)
    sta  DATPTR+1               ; Store screen pointer low byte
    sta  $44                    ; Also store in $44 (color RAM pointer low)
    lda  D_AD41,y               ; Get screen column offset (high byte)
    adc  #$00                   ; Add carry
    sta  INPPTR                 ; Store screen pointer high byte
    adc  #(>$D800 - >__VIC_SCREEN_A__) ; Add offset for color RAM ($D800) page
    sta  VARNAM                 ; Store color RAM pointer high byte

    ; Place top-left character
    lda  DATLIN+1               ; Get base character code
    ldy  #$00                   ; Offset 0 (top-left)
    sta  (DATPTR+1),y           ; Write to screen memory

    ; Place bottom-left character
    ldy  #$28                   ; Offset 40 (next row, same column)
    adc  #$01                   ; Character code + 1
    sta  (DATPTR+1),y           ; Write to screen memory

    ; Place top-right character
    ldy  #$01                   ; Offset 1 (same row, next column)
    adc  #$01                   ; Character code + 2
    sta  (DATPTR+1),y           ; Write to screen memory

    ; Place bottom-right character
    ldy  #$29                   ; Offset 41 (next row, next column)
    adc  #$01                   ; Character code + 3
    sta  (DATPTR+1),y           ; Write to screen memory

    ; Set color data for all 4 characters
    ldx  DATPTR                 ; X = color index
    lda  D_A8E4,x               ; Get color value from table
    ldy  #$00                   ; Top-left color
    sta  ($44),y                ; Write to color RAM
    iny                         ; Top-right color
    sta  ($44),y                ; Write to color RAM
    ldy  #$28                   ; Bottom-left color (offset 40)
    sta  ($44),y                ; Write to color RAM
    iny                         ; Bottom-right color
    sta  ($44),y                ; Write to color RAM
    rts                         ; Return

;-------------------------------------------------------------------------------
; End of bb-extend-bonus.s
;===============================================================================
