;===============================================================================
; bb-level-start.s - Level Start Sequence & Platform Generation
;===============================================================================
; Address range: $2F68-$3168 (513 bytes)
;
; Purpose: Level start sequence, platform/terrain generation from level data,
;          screen initialization, and player score display with bonus scoring
;
; Key Features:
; - Background color effect data ($2F68-$2F73)
; - Screen initialization with multiple entry points ($2F7D, $2F83, $2F89)
; - Platform generation from level data (D_2FAC)
; - Platform position table generation (D_4600, D_4700, D_4E00, D_4F00)
; - Screen area filling routines (D_311E, D_312E, D_3169)
; - Player score/lives display with bonus scoring (D_3080)
; - Level timer initialization (30 seconds initially, 50 seconds for gameplay)
;
; Technical Details:
; - Level Data Format: Bit 7 set (value >= $80) indicates solid/impassable tile
; - Modulo 10 Algorithm: Converts level number (1-100) to single digit (0-9)
;   using repeated subtraction in a loop
; - Indirect Addressing: Uses zero page pointers ($02, $04, $06) for efficient
;   screen memory access across different screen configurations
; - Screen Configurations: Supports three memory layouts ($C000, $0000, $E000)
; - Platform Limit: Maximum 85 platforms per level (checked at D_303C)
;
; Entry Points:
; - D_2F7D/D_2F83/D_2F89: Level initialization with different screen parameters
; - D_2FAC: Platform generation main loop
; - D_3000: Label within platform position calculation (self-modifying target)
; - D_3018: Label within loop decrement (self-modifying target)
; - D_3020: Screen pointer advancement
; - D_303C: Label for platform count check
; - D_3080: Main level start sequence (called from $6CFD)
; - D_30A0: Player display loop entry
; - D_30FC: Player data update entry
; - D_311E: Screen area fill (top section)
; - D_312E: Screen area fill (middle/bottom sections)
;
; External Calls:
; - D_A428: Level data setup
; - D_3169: Screen area fill subroutine (now in bb-remaining.s)
; - D_3193: Screen update routine (defined later)
; - D_3266: Display routine (defined later)
; - D_3293: Screen update routine (defined later)
; - D_E42A: Sprite/entity update
; - D_E49B: Game loop continuation
;
;===============================================================================

; Background color effect data - used by color cycling routines
; These bytes represent: LDA $1C, EOR #$07, STA $1C, LDA $1E, EOR #$07, STA $1E
.segment "CODE_EFFECTS"

D_2F68:
.byte   $A5,$1C,$49,$07,$85,$1C,$A5,$1E        ; $2F68
.byte   $49,$07,$85,$1E                        ; $2F70

; Small routine at $2F74 - animation/session setup
    lda  #$87                   ; Animation flag value
    sta  SESSION                ; Set animation active
    lda  #$ff                   ; Maximum value
    sta  TXTTAB                 ; Set frame sub-counter
    rts                         ; Return

;===============================================================================
; Level Initialization Routines - Three Entry Points
;===============================================================================
; These three entry points set up different screen memory configurations
; for level initialization. Each sets MEMSIZ+1 and CURLIN then continues
; to the common initialization code at L_2F8D.
;
; Entry 1 ($2F7D): Screen at $C000, index $0D
; Entry 2 ($2F83): Screen at $0000, index $0C  
; Entry 3 ($2F89): Screen at $E000, index $0F
;===============================================================================

; Entry point 1: Screen at $C000
D_2F7D:
    lda  #$c0                   ; Screen page high byte
    ldx  #$0d                   ; Screen index
    bne  L_2F8D                 ; Jump to common code

; Entry point 2: Screen at $0000
D_2F83:
    lda  #$00                   ; Screen page high byte
    ldx  #$0c                   ; Screen index
    bne  L_2F8D                 ; Jump to common code

; Entry point 3: Screen at $E000
D_2F89:
    lda  #$e0                   ; Screen page high byte
    ldx  #$0f                   ; Screen index

; Common initialization code
L_2F8D:
    sta  MEMSIZ+1               ; Set screen page
    stx  CURLIN                 ; Set screen index
    jsr  D_A428                 ; Load level data
    lda  #$04                   ; Game state value
    sta  $b0                    ; Set game state
    lda  #$2a                   ; Base value (42 decimal)
    eor  SUBFLG                 ; XOR with current level
    
; Modulo 10 loop - converts level to single digit (0-9)
L_2F9C:
    cmp  #$0b                   ; Check if >= 11
    bcc  L_2FA4                 ; Branch if < 11
    sbc  #$0a                   ; Subtract 10 (carry already set from CMP)
    bne  L_2F9C                 ; Loop until < 10
L_2FA4:
    tax                         ; X = result (0-10)
    lda  #$00                   ; Zero accumulator
    sta  INDEX2                 ; Clear row counter
    sta  D_597F                 ; Clear platform counter

;===============================================================================
; D_2FAC - Platform Generation Main Loop
;===============================================================================
; Scans level data and generates platforms/terrain blocks where empty space
; exists. Checks 4 screen positions (2x2 grid) for valid platform placement.
;
; TECHNICAL: Level Data Format
; - Each byte represents terrain: bit 7 = 1 (value >= $80) means solid/impassable
; - Checks positions Y, Y+1, Y+$27, Y+$28 for empty space (bit 7 = 0)
; - If all 4 positions are empty (< $80), places platform tiles there
;
; Platform Tiles: Characters $42, $43, $44, $45 (2x2 block)
;   $42 = bottom-left    $43 = top-left
;   $44 = bottom-right   $45 = top-right
; Color: Value from CURLIN ($39) - platform color for this level
;
; TECHNICAL: Position Table Generation
; Generates four parallel arrays for platform tracking:
; - D_4600[n] = Y position * 8 + $14 (sprite Y coordinate in pixels)
; - D_4700[n] = X position * 8 + $35 (sprite X coordinate in pixels)  
; - D_4E00[n] = Screen address low byte (for collision detection)
; - D_4F00[n] = Screen address high byte (for collision detection)
;
; These tables allow fast lookup of platform positions for collision checking
; and entity interaction without scanning screen memory.
;===============================================================================
D_2FAC:
    ldy  #$1c                   ; Start at column 28 (rightmost)
    sty  $23                    ; Store column counter
    dey                         ; Y = 27
    dey                         ; Y = 26 (start checking from here)

; Check each column position for platform placement
; TECHNICAL: Scans right-to-left, top-to-bottom through level data
L_2FB2:
    sty  DATLIN+1               ; Save Y position
    lda  ($02),y                ; Check level data at position Y (via zero page pointer)
    bmi  L_3016                 ; Skip if bit 7 set (solid tile already here)
    iny                         ; Check Y+1
    lda  ($02),y                ; Check level data at position Y+1
    bmi  L_3016                 ; Skip if bit 7 set
    tya                         ; A = Y
    clc                         ; Clear carry
    adc  #$27                   ; A = Y + 39 (next row, offset -1)
    tay                         ; Y = Y + $27
    lda  ($02),y                ; Check level data at position Y+$27
    bmi  L_3016                 ; Skip if bit 7 set
    iny                         ; Check Y+$28
    lda  ($02),y                ; Check level data at position Y+$28
    bmi  L_3016                 ; Skip if bit 7 set

    ; All 4 positions valid (empty) - place platform tiles
    lda  #$45                   ; Platform tile (top right)
    sta  ($04),y                ; Place in screen memory
    dey                         ; Previous position
    lda  #$43                   ; Platform tile (top left)
    sta  ($04),y                ; Place in screen memory
    lda  CURLIN                 ; Get platform color for this level
    sta  ($06),y                ; Set color memory
    iny                         ; Next position
    sta  ($06),y                ; Set color memory
    ldy  DATLIN+1               ; Restore original Y position
    lda  #$42                   ; Platform tile (bottom left)
    sta  ($04),y                ; Place in screen memory
    iny                         ; Next position
    lda  #$44                   ; Platform tile (bottom right)
    sta  ($04),y                ; Place in screen memory
    lda  CURLIN                 ; Get platform color
    sta  ($06),y                ; Set color memory
    dey                         ; Previous position
    sta  ($06),y                ; Set color memory

    ; Generate platform position table entries
    ; TECHNICAL: Converts character grid positions to pixel coordinates
    ldy  D_597F                 ; Get platform index
    inc  D_597F                 ; Increment platform counter
    lda  $23                    ; Get row counter (character row)
    asl                         ; Multiply by 2
    asl                         ; Multiply by 4
    asl                         ; Multiply by 8 (convert to pixel Y)
    adc  #$14                   ; Add sprite offset (20 pixels)
    sta  D_4600,y               ; Store platform Y position
    lda  INDEX2                 ; Get column counter (character column)
    asl                         ; Multiply by 2
D_3000:
    asl                         ; Multiply by 4
    asl                         ; Multiply by 8 (convert to pixel X)
    adc  #$35                   ; Add sprite offset (53 pixels)
    sta  D_4700,y               ; Store platform X position
    lda  DATLIN+1               ; Get screen position offset
    clc                         ; Clear carry
    adc  $04                    ; Add screen base low
    sta  D_4E00,y               ; Store screen address low
    lda  #$00                   ; Zero high byte
    adc  ADRAY2                 ; Add screen base high with carry
    sta  D_4F00,y               ; Store screen address high

L_3016:
    dec  $23                    ; Decrement column counter
D_3018:
    dec  $23                    ; Decrement column counter again (skip 2 columns)
    ldy  DATLIN+1               ; Get Y position
    dey                         ; Decrement Y
    dey                         ; Decrement Y again (move up 2 positions)
    bpl  L_2FB2                 ; Loop if Y >= 0

;===============================================================================
; D_3020 - Advance to Next Screen Row
;===============================================================================
; Advances screen pointers to the next row block.
; 
; TECHNICAL: Memory Layout
; - Adds $50 (80 bytes) = 2 character rows worth of screen memory
; - C64 screen has 40 columns, so 2 rows = 80 bytes
; - Must update all three pointer pairs ($02/$03, $04/$05, $06/$07)
; - Handles page boundary crossing by incrementing high bytes
;===============================================================================
D_3020:
    lda  $02                    ; Get screen pointer low
    clc                         ; Clear carry
    adc  #$50                   ; Add 80 bytes (2 char rows)
    sta  $02                    ; Update screen pointer low
    sta  $04                    ; Update alternate pointer 1 (screen data)
    sta  $06                    ; Update alternate pointer 2 (color RAM)
    bcc  L_3033                 ; Branch if no carry (no page boundary crossed)
    inc  ADRAY1                 ; Increment screen pointer high 1
    inc  ADRAY2                 ; Increment screen pointer high 2
    inc  CHARONE                ; Increment screen pointer high 3
L_3033:
    inc  INDEX2                 ; Increment row counter
    inc  INDEX2                 ; Increment row counter (2 rows processed)
    lda  D_597F                 ; Get platform count
    cmp  #$55                   ; Check if >= 85 platforms ($55 = 85 decimal)
D_303C:
    bcs  L_304D                 ; Branch if platform limit reached
    dex                         ; Decrement loop counter
    beq  L_3044                 ; Branch if counter = 0
    jmp  D_2FAC                 ; Continue platform generation

L_3044:
    lda  D_597F                 ; Get platform count
    bne  L_304D                 ; Branch if platforms found
    inx                         ; X = 1 (restart loop once if no platforms)
    jmp  D_2FAC                 ; Try platform generation again

; Platform generation complete - finalize level setup
L_304D:
    ldx  #$a2                   ; Default value
    lda  MEMSIZ+1               ; Check screen page
    bne  L_3054                 ; Branch if not zero
    inx                         ; X = $a3
L_3054:
    stx  CURLIN                 ; Store value
    stx  OLDLIN                 ; Store value (duplicate)
    clc                         ; Clear carry
    adc  #$10                   ; Add $10 to screen page
    sta  CURLIN+1               ; Store result
    dec  MEMSIZ                 ; Decrement memory flag
    jsr  D_3169                 ; Fill screen area
    inx                         ; X = $a3 or $a4
    stx  STREND                 ; Initialize string pointers
    stx  STREND+1               ; Initialize string pointers
    stx  $4a                    ; Clear enemy spawn counter
    lda  #$1e                   ; Level timer (30 seconds for display)
    sta  $2a                    ; Set level timer
    ldx  #$00                   ; Player 1
    ldy  #$50                   ; Screen offset
    jsr  D_3193                 ; Update player display
    lda  #$20                   ; Screen page $20
    sta  MEMSIZ+1               ; Set screen pointer
    sta  CURLIN+1               ; Set screen pointer
    lda  #$80                   ; Offset value
    sta  CURLIN                 ; Set offset
    sta  OLDLIN                 ; Set offset

;===============================================================================
; D_3080 - Main Level Start Sequence
;===============================================================================
; Primary entry point for level start. Called from $6CFD.
; Initializes screen areas, displays player info, handles bonus scoring,
; and starts the game timer.
;
; TECHNICAL: Timer Values
; - Initial timer at $306B: $1E (30 seconds) - used during display sequence
; - Final timer at $3117: $32 (50 seconds) - actual gameplay time limit
;
; TECHNICAL: Bonus Scoring System
; - Only triggers on levels with D_597F = 0 (no platforms generated)
; - Compares both players' scores (stored in $31/$32)
; - Awards 1 point to higher score player (shows chars $21/$20)
; - Awards 50 points to lower score player (shows chars $40/$25)
; - Uses D_7C26 to add score, which handles BCD arithmetic and display
;===============================================================================
D_3080:
    jsr  D_3169                 ; Fill screen area
    jsr  D_3293                 ; Update screen
    jsr  D_312E                 ; Fill middle/bottom screen areas
    ldx  #<D_A7C8               ; Data pointer low
    ldy  #>D_A7C8               ; Data pointer high
    jsr  display_text_string    ; Update sprites/entities
    ldx  #$01                   ; Start with player 2
    stx  MEMSIZ+1               ; Set player index
    lda  #$51                   ; Screen position
    sta  DATPTR                 ; Set screen position
    dex                         ; X = 0
    stx  VARNAM                 ; Clear variable

; Player info display loop - processes both players
L_309B:
    ldy  MEMSIZ+1               ; Get player index (0 or 1)
    ldx  D_8570,y               ; Get player sprite data

;===============================================================================
; D_30A0 - Player Display Loop Entry
;===============================================================================
D_30A0:
    lda  a:STREND,y             ; Get player score value
    pha                         ; Save on stack
    lda  D_A7F7,y               ; Get player display offset
    clc                         ; Clear carry
    adc  #$4c                   ; Add base offset
    tay                         ; Y = display position
    pla                         ; Restore score value
    jsr  D_3266                 ; Display score
    ldx  MEMSIZ+1               ; Get player index
    lda  #$08                   ; Offset value
    clc                         ; Clear carry
    adc  D_A7F7,x               ; Add player display offset
    sta  EVAL                   ; Store in sprite data pointer
    sta  D_A7EE                 ; Store in alternate pointer
    ldy  #$00                   ; Y = 0 (default, no display)
    lda  D_597F                 ; Check platform counter
    bne  L_30F9                 ; Skip bonus if platforms exist
    ldy  ENESSION,x             ; Get player state
    beq  L_30F9                 ; Skip if player not active
    
    ; Player is active and no platforms - bonus scoring!
    ; TECHNICAL: Bonus levels have D_597F = 0 (no platforms generated)
    txa                         ; A = player index
    eor  #$01                   ; Toggle player (0<->1)
    tay                         ; Y = other player index
    lda  STREND,x               ; Get current player score
    cmp  a:STREND,y             ; Compare with other player score
    bcc  L_30E3                 ; Branch if current < other
    
    ; Current player has higher score - award small bonus
    ldy  D_AB51,x               ; Get player score offset
    dey                         ; Adjust offset
    dey                         ; Adjust offset
    lda  #$01                   ; 1 point bonus
    jsr  D_7C26                 ; Add score
    lda  #$21                   ; Bonus display character 1
    ldy  #$20                   ; Bonus display character 2
    bne  L_30F0                 ; Jump to display
    
L_30E3:
    ; Other player has higher score - award large bonus
    ldy  D_AB51,x               ; Get player score offset
    dey                         ; Adjust offset
    lda  #$50                   ; 50 point bonus
    jsr  D_7C26                 ; Add score
    lda  #$40                   ; Bonus display character 1
    ldy  #$25                   ; Bonus display character 2
    
L_30F0:
    sta  D_A7F0                 ; Store bonus display character 1
    sty  D_A7F1                 ; Store bonus display character 2
    ldy  D_8570,x               ; Get player sprite data
    
L_30F9:
    sty  D_A7E2                 ; Store sprite data

;===============================================================================
; D_30FC - Player Data Update Entry
;===============================================================================
D_30FC:
    ldx  #<D_A7E2               ; Data pointer low
    ldy  #>D_A7E2               ; Data pointer high
    jsr  display_text_string    ; Update sprites
    dec  MEMSIZ+1               ; Next player (1 -> 0)
    bpl  L_309B                 ; Loop for player 1

    ; Both players processed - finalize level start
    lda  #$c8                   ; Delay value (200 frames)
    jsr  D_7BC8                 ; Wait
    jsr  update_sprite_animations ; Update sprite data
    jsr  D_311E                 ; Fill top screen area
    jsr  D_3293                 ; Update screen
    lda  #$32                   ; Timer value (50 seconds for gameplay)
    sta  $2a                    ; Set level timer
    sta  TXTTAB                 ; Set frame sub-counter
    jmp  copy_screen_buffers    ; Jump to game loop

;===============================================================================
; D_311E - Fill Top Screen Area
;===============================================================================
; Fills the top section of the screen with specified character and color.
; Used for clearing the score/status display area.
;
; Parameters set before call:
;   DATLIN+1 = $20 (screen page)
;   DATPTR = $D9 (screen position)
;   A = $0D (fill character)
;   X = $06 (row count)
;   Y = $0F (column count)
;===============================================================================
D_311E:
    lda  #$20                   ; Screen page
    sta  DATLIN+1               ; Set screen pointer high
    lda  #$d9                   ; Screen position
    sta  DATPTR                 ; Set screen pointer low
    lda  #$0d                   ; Fill character
    ldx  #$06                   ; 6 rows
    ldy  #$0f                   ; 15 columns
    bne  L_314D                 ; Jump to fill routine

;===============================================================================
; D_312E - Fill Middle and Bottom Screen Areas
;===============================================================================
; Fills two sections of the screen:
; 1. Middle section starting at $CE50
; 2. Bottom section starting at $F750
;
; Used for clearing game play area borders.
;===============================================================================
D_312E:
    ; Fill middle section
    lda  #$ce                   ; Screen page high
    sta  DATLIN+1               ; Set screen pointer
    lda  #$50                   ; Screen position low
    sta  DATPTR                 ; Set screen pointer
    lda  #$10                   ; Fill character
    ldx  #$0a                   ; 10 rows
    ldy  #$13                   ; 19 columns
    jsr  L_314D                 ; Fill area
    
    ; Fill bottom section
    lda  #$f7                   ; Screen page high
    sta  DATLIN+1               ; Set screen pointer
    lda  #$50                   ; Screen position low
    sta  DATPTR                 ; Set screen pointer
    lda  #$20                   ; Fill character (space)
    ldx  #$08                   ; 8 rows
    ldy  #$11                   ; 17 columns

;===============================================================================
; L_314D - Screen Fill Subroutine
;===============================================================================
; Fills a rectangular area of screen memory with a specified character.
;
; Parameters:
;   A = fill character
;   X = number of rows
;   Y = number of columns - 1 (0-based)
;   DATLIN+1 = screen pointer high byte
;   DATPTR is used as screen pointer low byte
;===============================================================================
L_314D:
    sta  MEMSIZ+1               ; Store fill character
    sty  CURLIN                 ; Store column count
L_3151:
    lda  MEMSIZ+1               ; Get fill character
    ldy  CURLIN                 ; Get column count
L_3155:
    sta  (DATLIN+1),y           ; Write character to screen
    dey                         ; Next column
    bpl  L_3155                 ; Loop for all columns
    lda  DATLIN+1               ; Get screen pointer low
    clc                         ; Clear carry
    adc  #$28                   ; Add 40 (next row)
    sta  DATLIN+1               ; Update screen pointer
    bcc  L_3165                 ; Branch if no carry
    inc  DATPTR                 ; Increment screen page
L_3165:
    dex                         ; Next row
    bne  L_3151                 ; Loop for all rows
    rts                         ; Return
