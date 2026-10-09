;===============================================================================
; bb-bonus-round.s - Bonus Round and Special Stage Handler
;===============================================================================
; Address range: $348A-$35AF (294 bytes)
;
; Purpose: Handles bonus round initialization, special stage setup, and level
;          data processing for bonus/secret stages in Bubble Bobble.
;
; Key Routines:
; 1. Entry points at $348A, $3495, $34A0 - Initialize bonus stages with different parameters
; 2. Entry points at $34FA, $3502, $350A - Set up special stage configurations
; 3. L_34A2 - Process entity states during bonus round (6 entities, indexed 0-5)
; 4. L_34D3 - Handle player state during bonus transitions
; 5. D_350C/L_3510 - Store bonus stage parameters ($68/$69/$6A)
; 6. D_3517 - Main bonus stage data loader
;    - Copies level data from ROM tables (D_A815/D_A81A/D_A81F) to RAM ($7D00)
;    - Processes level layout data from $9AE0+ ROM region
;    - Converts compressed level data to screen format
;    - Stores processed data in D_4230 and D_40A8 tables
;
; Parameters:
; - $68: Bonus stage type/configuration byte
; - $69 (ARG): Y-coordinate or stage parameter
; - $6A: Stage index (0-4) used to select data tables
;
; External Calls:
; - D_05AD: Setup routine (called with Y=$19)
; - D_2AE9: Unknown routine (modified by bonus_sprite_colors table)
; - bonus_data_ptr_lo: Pointer table (low bytes) for level data sources
; - bonus_data_ptr_hi: Pointer table (high bytes) for level data sources  
; - bonus_sprite_colors: Color table for bonus stages
; - D_A892: Level layout compression table
; - bonus_stage1_pattern_a: Pattern data (8 bytes) copied to $7D37 for stage 1
; - bonus_stage1_pattern_b: Pattern data (8 bytes) copied to $7D76 for stage 1
;
; Called From:
; - $176F: jmp D_3517 (conditional on $68 != 0)
;
; Memory Usage:
; - $7D00-$7DFF: Temporary level data buffer (256 bytes)
; - D_4230 ($4230): Processed level row data (32 bytes)
; - D_40A8 ($40A8): Final level layout data
; - D_87A2, D_863A, D_85C2: Entity state tables
; - D_8728-D_8729: Saved to D_A813-D_A814
; - D_5A7F, D_5ABF: Countdown/state variables
;
;===============================================================================

.setcpu "6502"
.segment "CODE_BONUS"

;-------------------------------------------------------------------------------
; Bonus stage entry point 1 - Type $1B configuration
; Sets up bonus stage with Y=$10, A=$1B, X=$00
;-------------------------------------------------------------------------------
D_348A:
    ldy  #$10                   ; Y parameter = $10
D_348D = * + 1                  ; BIT trick: entry here reads A0 20 = LDY #$20
    bit  D_20A0                 ; Test bits (dummy instruction, affects flags)
    lda  #$1B                   ; Bonus type $1B
    ldx  #$00                   ; Stage index 0
    beq  L_3510                 ; Always branches - store parameters

;-------------------------------------------------------------------------------
; Bonus stage entry point 2 - Type $18 configuration
; Sets up bonus stage with Y=$20, A=$18, X=$01
;-------------------------------------------------------------------------------
D_3495:
    ldy  #$20                   ; Y parameter = $20
D_3498 = * + 1                  ; BIT trick: entry here reads A0 30 = LDY #$30
    bit  D_30A0                 ; Test bits (dummy instruction, affects flags)
    lda  #$18                   ; Bonus type $18
    ldx  #$01                   ; Stage index 1
    bne  L_3510                 ; Always branches - store parameters

;-------------------------------------------------------------------------------
; L_34A2 - Process entities during bonus round
; Loops through 6 entities (X=5 down to 0) and processes their states
; Entities with states $00-$0A get special handling
;-------------------------------------------------------------------------------
D_34A0:
    ldx  #$05                   ; Process 6 entities (indices 5-0)

L_34A2:
    lda  $B4,x                  ; Get entity state
    beq  L_34C2                 ; Skip if state = $00
    cmp  #$0B                   ; Check if state >= $0B
    bcs  L_34C2                 ; Skip if >= $0B (only process $01-$0A)
    cmp  #$0A                   ; Is state exactly $0A?
    bne  L_34B1                 ; No - skip special case
    lda  D_87A2,x               ; Yes - load from D_87A2 table

L_34B1:
    sta  D_87A2,x               ; Store entity data to D_87A2
    lda  #$16                   ; New state value
    sta  $B4,x                  ; Update entity state to $16
    lda  #$00                   ; Clear value
    sta  D_863A,x               ; Clear entity flag at D_863A
    lda  #$FF                   ; Marker value
    sta  D_85C2,x               ; Set entity marker at D_85C2

L_34C2:
    dex                         ; Next entity
    bpl  L_34A2                 ; Continue for all 6 entities

    ; Save D_8728-D_8729 to D_A813-D_A814
    lda  D_8728                 ; Get first save byte
    sta  D_A813                 ; Store to ROM/RAM area
    lda  D_8729                 ; Get second save byte
    sta  D_A814                 ; Store to ROM/RAM area

    ldx  #$01                   ; Process 2 players (indices 1-0)

;-------------------------------------------------------------------------------
; L_34D3 - Handle player state during bonus transition
; Checks player states and resets if not in special states $0E or $0F
;-------------------------------------------------------------------------------
L_34D3:
    lda  ENESSION,x             ; Get player state ($B2-$B3)
    beq  L_34E8                 ; Skip if state = $00
    cmp  #$0E                   ; Is state $0E?
    beq  L_34E8                 ; Yes - skip (special state)
    cmp  #$0F                   ; Is state $0F?
    beq  L_34E8                 ; Yes - skip (special state)
    lda  #$18                   ; Reset state value
    sta  ENESSION,x             ; Update player state to $18
    lda  #$00                   ; Clear value
    sta  D_8728,x               ; Clear player flag at D_8728

L_34E8:
    dex                         ; Next player
    bpl  L_34D3                 ; Continue for both players

    ; Set countdown timers
    ldy  #$18                   ; Timer value 24
    sty  D_5A7F                 ; Store countdown at D_5A7F
    lda  #$16                   ; Timer value 22
    sta  D_5ABF                 ; Store countdown at D_5ABF
    iny                         ; Y = $19 (song_bonus_round - music_song_table)
    jsr  D_05AD                 ; Start bonus round music
    rts                         ; Return

;-------------------------------------------------------------------------------
; Bonus stage entry point 3 - Type $29 configuration
; Sets up bonus stage with Y=$30, A=$29, X=$02
;-------------------------------------------------------------------------------
D_34FA:
    ldy  #$30                   ; Y parameter = $30
    lda  #$29                   ; Bonus type $29
    ldx  #$02                   ; Stage index 2
    bne  L_3510                 ; Always branches - store parameters

;-------------------------------------------------------------------------------
; Bonus stage entry point 4 - Type $2B configuration  
; Sets up bonus stage with Y=$40, A=$2B, X=$03
;-------------------------------------------------------------------------------
D_3502:
    ldy  #$40                   ; Y parameter = $40
    lda  #$2B                   ; Bonus type $2B
    ldx  #$03                   ; Stage index 3
    bne  L_3510                 ; Always branches - store parameters

;-------------------------------------------------------------------------------
; Bonus stage entry point 5 - Type $2C configuration
; Sets up bonus stage with Y=$50, A=$2C, X=$04
;-------------------------------------------------------------------------------
D_350A:
    ldy  #$50                   ; Y parameter = $50

D_350C:
    lda  #$2C                   ; Bonus type $2C
    ldx  #$04                   ; Stage index 4

;-------------------------------------------------------------------------------
; L_3510 - Store bonus stage parameters
; Saves A/Y/X to zero page variables for later use by D_3517
; Input: A = bonus type ($68), Y = parameter ($69/ARG), X = stage index ($6A)
;-------------------------------------------------------------------------------
L_3510:
    sta  $68                    ; Store bonus type
    sty  ARG                    ; Store Y parameter (ARG = $69)
    stx  $6A                    ; Store stage index
    rts                         ; Return

;-------------------------------------------------------------------------------
; D_3517 - Main bonus stage data loader
; Loads level data from ROM tables, processes it, and stores in RAM
; Uses $6A as index to select which data tables to use
; Returns early if $6A < 0 (negative index means no bonus stage)
;-------------------------------------------------------------------------------
D_3517:
    ldx  $6A                    ; Get stage index
    bmi  L_3554                 ; If negative, skip to level data processing

    ; Copy configuration byte from bonus_sprite_colors table
    lda  bonus_sprite_colors,x  ; Get color for this bonus stage
    sta  D_2AE9                 ; Store configuration

    ; Set up pointer to level data source ($40-$41)
    lda  bonus_data_ptr_lo,x    ; Get data pointer low byte
    sta  DATLIN+1               ; Store in $40
    lda  bonus_data_ptr_hi,x    ; Get data pointer high byte
    sta  DATPTR                 ; Store in $41

    ; Copy 256 bytes from (DATLIN+1) to $7D00
    ldy  #$00                   ; Start at byte 0

L_352D:
    lda  (DATLIN+1),y           ; Read byte from source
    sta  D_7D00,y               ; Write to $7D00 buffer
    iny                         ; Next byte
    bne  L_352D                 ; Continue for 256 bytes

    ; Check if we need to clear remaining buffer
    txa                         ; A = stage index
    beq  L_3554                 ; If index 0, skip to data processing

    ; Clear bytes $7D00-$7D7F (remaining 128 bytes with Y counter)
    tya                         ; A = $00 (Y wrapped to 0)

L_3539:
    sta  D_7D00,y               ; Clear byte at $7D00+Y
    iny                         ; Next byte
    bpl  L_3539                 ; Continue while Y < $80 (0-127)

    ; Special handling for stage index 1
    ; After clearing first 128 bytes, patch in two 8-byte patterns
    ; that create small decorative elements in the level buffer
    cpx  #$01                   ; Is stage index 1?
    bne  L_3554                 ; No - skip to data processing

    ; Copy pattern data tables for stage 1
    ldy  #$07                   ; Copy 8 bytes (indices 7-0)

L_3545:
    lda  bonus_stage1_pattern_a,y ; Get pattern A byte
    sta  D_7D37,y               ; Store to $7D37
    lda  bonus_stage1_pattern_b,y ; Get pattern B byte
    sta  D_7D76,y               ; Store to $7D76
    dey                         ; Next byte
    bpl  L_3545                 ; Continue for 8 bytes

;-------------------------------------------------------------------------------
; L_3554 - Process level layout data
; Reads level data from $9AE0+ ROM area (indexed by D_A892 table)
; Decompresses/processes 32 bytes of level data into D_4230 and D_40A8
;-------------------------------------------------------------------------------
L_3554:
    lda  #$00                   ; Clear high byte
    sta  INPPTR                 ; Initialize $43 = 0

    ; Calculate source address: $9AE0 + (D_A892[X] * 32)
    ldx  $68                    ; Get bonus type as index
    lda  D_A892,x               ; Get level data index from table
    
    ; Multiply by 32 (shift left 5 times, with ROL for high byte)
    asl                         ; *2
    asl                         ; *4
    rol  INPPTR                 ; Rotate carry into high byte
    asl                         ; *8
    rol  INPPTR
    asl                         ; *16
    rol  INPPTR
    asl                         ; *32
    rol  INPPTR
    
    ; Add sprites_rom base address
    adc  #<sprites_rom          ; Add low byte of base
    sta  DATPTR+1               ; Store pointer low at $42
    lda  INPPTR                 ; Get high byte (with carries)
    adc  #>sprites_rom          ; Add high byte of base
    sta  INPPTR                 ; Store pointer high at $43

    ; Process 32 bytes of level data
    ldy  #$1F                   ; Start with byte 31 (count down)

;-------------------------------------------------------------------------------
; L_3576 - Process each level data byte
; Converts each byte into nibbles and stores processed result
;-------------------------------------------------------------------------------
L_3576:
    lda  (DATPTR+1),y           ; Read level data byte
    sta  D_4230,y               ; Store raw byte to D_4230
    
    ; Save Y index for later
    sty  DATLIN+1               ; Save Y in $40
    
    ; Initialize processing
    ldx  #$00                   ; Clear result byte
    stx  DATPTR                 ; Initialize $41 = 0
    
    ldx  #$04                   ; Process 4 bit-pairs (2 bits each)

;-------------------------------------------------------------------------------
; L_3583 - Convert bit-pairs to nibbles
; Extracts 2-bit pairs from input byte and converts to 2-bit patterns
; Pattern: %11 -> %00, %10 -> %00, %01 -> %11, %00 -> %11
;-------------------------------------------------------------------------------
L_3583:
    asl  DATPTR                 ; Shift result left by 2
    asl  DATPTR
    
    ldy  #$03                   ; Default pattern = %11
    asl                         ; Shift bit 7 into carry
    bcc  L_358E                 ; If bit 7 = 0, use %11
    ldy  #$00                   ; If bit 7 = 1, pattern = %00

L_358E:
    asl                         ; Shift bit 6 into carry
    bcc  L_3593                 ; If bit 6 = 0, use current pattern
    ldy  #$00                   ; If bit 6 = 1, force %00

L_3593:
    pha                         ; Save accumulator
    tya                         ; Get pattern (%00 or %11)
    ora  DATPTR                 ; OR with existing result
    sta  DATPTR                 ; Store back to result
    pla                         ; Restore accumulator
    dex                         ; Next bit-pair
    bne  L_3583                 ; Process all 4 bit-pairs

    ; Store final result
    lda  DATPTR                 ; Get processed byte
    ldy  DATLIN+1               ; Restore Y index
    sta  D_40A8,y               ; Store to D_40A8 table
    dey                         ; Next byte (counting down)
    bpl  L_3576                 ; Continue for all 32 bytes
    
D_35A7:
    rts                         ; Return

;-------------------------------------------------------------------------------
; Bonus stage 1 pattern A - 8 bytes copied to $7D37 during stage 1 init
; Creates a small decorative element (pillar/stripe pattern) in the level buffer
; Used alongside bonus_stage1_pattern_b which is copied to $7D76
;-------------------------------------------------------------------------------
bonus_stage1_pattern_a:
    .byte $BF, $FF, $00, $95, $55, $00, $95, $45

;-------------------------------------------------------------------------------
; End of bb-bonus-round.s
;===============================================================================
