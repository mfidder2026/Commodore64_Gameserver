;===============================================================================
; bb-bonus-stage-extended.s - Extended Bonus Stage Handler and Screen Setup
;===============================================================================
; Address range: $35B0-$37C6 (535 bytes)
;
; Purpose: Handles extended bonus stage setup, screen initialization, player
;          positioning, and various bonus stage related routines.
;
; Key Routines:
; 1. $35B0-$3620 - Bonus stage screen setup and initialization
;    - Copies data from D_A877 table to screen buffers ($7D00/$7E00)
;    - Sets up screen memory and initializes sprite positions
;    - Calls entity reset and screen rendering routines
;
; 2. $3621-$370B - Main bonus stage initialization (large routine)
;    - Sets up game state for bonus stage
;    - Initializes memory regions: D_4300, D_43B8, D_43B0, D_43C0
;    - Copies level data from D_A660 table
;    - Sets up level layout in D_8C00 and D_40A8
;    - Configures player positions and states
;
; 3. D_370C-$3771 - Bonus stage game loop setup
;    - Initializes game mode and counters
;    - Sets up screen display with D_344A (2x2 character blocks)
;    - Manages player spawn positions
;
; 4. $3771-$37C6 - Player position and animation handler
;    - Checks and updates player positions during bonus stage
;    - Handles special player Y-coordinate transitions ($9D -> $DD)
;    - Manages screen transitions and level completion
;
; External Dependencies:
; - L_069B: Screen clear/setup routine
; - D_2E79, D_2E61: Entity management routines  
; - D_2EEA: Unknown setup routine
; - L_2AAD: Sprite/entity handler
; - D_344A: 2x2 character block placement (from bb-extend-bonus.s)
; - D_1853: Screen rendering
; - clear_screen, copy_screen_buffers, decompress_level_data, setup_level_data_pointers, L_E2C3, display_text_string, fill_color_ram: Various engine routines
; - D_37C9, D_392A: Forward references to routines after this module
; - D_7BC3, D_7BC6, D_7BC8: Wait/timing routines
; - D_1805, D_05C5, D_05AD, D_1E2E, D_7B53: Setup/init routines
; - D_2BBD, D_2C32: Unknown routines
; - D_A428: Unknown routine
;
; Memory Areas Used:
; - $7D00-$7D7F: Screen buffer 1
; - $7E00-$7E7F: Screen buffer 2  
; - D_4300-D_43FF: Level data buffer
; - D_4050-D_407F: Entity/item data
; - D_8C00: Level layout data
; - D_52AA, D_52D2, D_52FA, D_5322, D_534A: Screen line pointers
; - D_4850-D_487F: Temporary item data storage
;
; Called From:
; - Various bonus stage trigger points in game loop
;
;===============================================================================

.setcpu "6502"
.segment "CODE_BONUS"

;-------------------------------------------------------------------------------
; Entry point at $35B0 - Bonus stage screen initialization
; Sets up screen buffers and prepares display for bonus stage
;-------------------------------------------------------------------------------
D_35B0:
    jsr  L_069B                 ; Clear/setup screen
    lda  #$2A                   ; Character code $2A
    sta  D_7D3E                 ; Store to screen buffer 1 offset $3E
    sta  D_7DC2                 ; Store to screen buffer 1 offset $C2
    lda  #$A0                   ; Character code $A0 (space)
    sta  D_7DBC                 ; Store to screen buffer 1 offset $BC

;-------------------------------------------------------------------------------
; D_35C0 - Copy data from D_A877 table to screen buffers
; Copies 27 bytes (indices $1A down to 0) to both $7D00 and $7E00 buffers
;-------------------------------------------------------------------------------
D_35C0:
    sta  D_7E40                 ; Store to screen buffer 2 offset $40
    
    ; Set up pointers for double-buffer copy
    lda  #<(sprite_data_7C40 + $13C) ; Pointer low byte (originally $7C)
    sta  DATLIN+1               ; $40 = low byte
    lda  #>(sprite_data_7C40 + $13C) ; Pointer high byte (originally $7D)
    sta  DATPTR                 ; $41 = high byte
    lda  #<(sprite_data_7C40 + $1C0) ; Second pointer low byte (originally $00)
    sta  DATPTR+1               ; $42 = low byte
    lda  #>(sprite_data_7C40 + $1C0) ; Second pointer high byte (originally $7E)
    sta  INPPTR                 ; $43 = high byte
    
    ldx  #$1A                   ; Copy 27 bytes (indices $1A-$00)

;-------------------------------------------------------------------------------
; L_35D5 - Outer loop: process each of 27 bytes from D_A877 table
;-------------------------------------------------------------------------------
L_35D5:
    ldy  #$02                   ; Copy to 3 positions (offsets 2, 1, 0)

;-------------------------------------------------------------------------------
; L_35D7 - Inner loop: write same byte to 3 consecutive positions
;-------------------------------------------------------------------------------
L_35D7:
    lda  D_A877,x               ; Get byte from source table
    sta  (DATLIN+1),y           ; Write to first buffer at ($40),Y
    sta  (DATPTR+1),y           ; Write to second buffer at ($42),Y
    dex                         ; Next source byte
    dey                         ; Previous offset
    bpl  L_35D7                 ; Continue for offsets 2, 1, 0

    ; Adjust pointers for next iteration
    lda  DATLIN+1               ; Get first buffer pointer low
    sec
    sbc  #$03                   ; Move back 3 bytes
    sta  DATLIN+1               ; Store updated pointer
    
    lda  DATPTR+1               ; Get second buffer pointer low
    clc
    adc  #$03                   ; Move forward 3 bytes
    sta  DATPTR+1               ; Store updated pointer
    
    txa                         ; Check if done (X counts down)
    bpl  L_35D5                 ; Continue if X >= 0

;-------------------------------------------------------------------------------
; Complete setup after screen buffer initialization
;-------------------------------------------------------------------------------
    inc  MEMSIZ                 ; Increment $37 (memory flag?)
    jsr  D_2E79                 ; Reset entities
    jsr  D_2E61                 ; Additional entity setup
    inc  $4A                    ; Increment some counter
    
    ; Call routine with parameters
    lda  #$14                   ; Parameter 1 = $14
    ldx  #$78                   ; Parameter 2 = $78  
    ldy  #$7C                   ; Parameter 3 = $7C
    jsr  D_2EEA                 ; Call setup routine
    
    ; Modify frame counter
    lda  ENDCHR                 ; Get frame counter ($08)
    and  #$03                   ; Keep only bits 0-1
    sta  ENDCHR                 ; Store back (reduces to 0-3 range)
    
    ; Call sprite handler
    ldx  #$05                   ; Parameter 1 = 5
    ldy  #$0E                   ; Parameter 2 = 14
    jsr  L_2AAD                 ; Handle sprites/entities
    
    ; Initialize sprite Y positions counting down from $F9
    ldx  #$04                   ; 5 sprites (indices 4-0)
    lda  #$F9                   ; Starting Y position
    sec                         ; Set carry for subtraction

L_3618:
    sta  D_859B,x               ; Store Y position for sprite X
    sbc  #$01                   ; Decrement by 1
    dex                         ; Next sprite
    bpl  L_3618                 ; Continue for all 5 sprites
    
D_3620:
    rts                         ; Return

;-------------------------------------------------------------------------------
; Entry point at $3621 - Main bonus stage initialization
; Large routine that sets up all game state for bonus stage
;-------------------------------------------------------------------------------
D_3621:
    jsr  D_A428                 ; Unknown initialization routine
    jsr  clear_screen             ; Engine routine
    jsr  copy_screen_buffers    ; Game loop related routine
    
    ; Save and modify SUBFLG
    lda  SUBFLG                 ; Get current value ($10)
    pha                         ; Save on stack
    lda  #$4C                   ; New value = $4C (JMP opcode!)

D_362F:
    sta  SUBFLG                 ; Store (self-modifying code?)
    jsr  decompress_level_data  ; Call engine routine
    pla                         ; Restore original SUBFLG
    sta  SUBFLG                 ; Restore value
    
    ; Copy 256 bytes from D_A660 to D_4300
    ldx  #$00                   ; Start at byte 0

L_3639:
    lda  D_A660,x               ; Get byte from source
    sta  D_4300,x               ; Store to destination
    dex                         ; Next byte (wraps to $FF)
    bne  L_3639                 ; Continue until wrap to 0
    
    ; Initialize D_43B8, D_43B0, D_43C0 tables (8 bytes each)
    ldx  #$07                   ; 8 bytes (indices 7-0)

L_3644:
    lda  #$55                   ; Pattern %01010101
    sta  D_43B8,x               ; Store pattern to D_43B8
    and  #$C0                   ; Mask to %11000000
    sta  D_43B0,x               ; Store masked to D_43B0
    eor  #$D5                   ; XOR to flip: %11010101
    sta  D_43C0,x               ; Store to D_43C0
    dex                         ; Next byte
    bpl  L_3644                 ; Continue for all 8
    
    ; Set up screen parameters
    lda  #$06                   ; Value 6
    sta  $1D                    ; Store in $1D
    lda  #$0E                   ; Value 14
    sta  $1F                    ; Store in $1F
    
    ; Initialize level data arrays
    ldx  #$31                   ; 50 bytes (indices $31-0)

L_3660:
    lda  #$00                   ; Clear value
    sta  D_8C00,x               ; Clear D_8C00 array
    sta  D_4050,x               ; Clear D_4050 array
    lda  D_A660,x               ; Get from source table
    sta  D_40A8,x               ; Store to D_40A8 array
    dex                         ; Next byte
    bpl  L_3660                 ; Continue until done
    
    ; Copy specific bytes from D_F192/D_F19F tables
    ldx  #$0C                   ; 13 bytes (indices $0C-0)

L_3673:
    ldy  credit_index_table,x    ; Get index from credit_index_table
    lda  credit_timing_table,x  ; Get value from credit_timing_table
    sta  D_8C00,y               ; Store to D_8C00 at index Y
    dex                         ; Next byte
    bpl  L_3673                 ; Continue for all 13
    
    ; Set up pointer to D_8C00 (screen backup buffer page 1)
    lda  #<D_8C00               ; Low byte
    sta  DATLIN+1               ; $40 = $00
    lda  #>D_8C00               ; High byte
    sta  DATPTR                 ; $41 = $8C (pointer = $8C00)
    
    ldx  #$00                   ; Parameter = 0
    jsr  L_E2C3                 ; Engine routine with pointer
    jsr  setup_level_data_pointers ; Another engine routine
    
    inc  SUBFLG                 ; Increment game mode flag ($10)
    jsr  D_37C9                 ; Call routine at $37C9 (later in this file)
    jsr  D_392A                 ; Call routine at $392A (after this module)
    
    ; Set up sprite/entity parameters
    ldx  #<gameover_text_data    ; Parameter low byte
    ldy  #>gameover_text_data   ; Parameter high byte ($7EE1)
    jsr  display_text_string    ; Sprite/entity routine
    
    ; Initialize screen line pointer arrays
    ; Fill 5 arrays with $77, then set first byte of each to $78
    ldx  #$1B                   ; 28 bytes (indices $1B-0)
    lda  #$77                   ; Fill value

L_36A2:
    sta  D_52AA,x               ; Fill D_52AA array
    sta  D_52D2,x               ; Fill D_52D2 array
    sta  D_52FA,x               ; Fill D_52FA array
    sta  D_5322,x               ; Fill D_5322 array
    sta  D_534A,x               ; Fill D_534A array
    dex                         ; Next byte
    bne  L_36A2                 ; Continue (stops at X=0, leaves byte 0)
    
    ; Set first byte of each array to $78
    lda  #$78                   ; First byte value
    sta  D_52AA                 ; D_52AA[0] = $78
    sta  D_52D2                 ; D_52D2[0] = $78
    sta  D_52FA                 ; D_52FA[0] = $78
    sta  D_5322                 ; D_5322[0] = $78
    sta  D_534A                 ; D_534A[0] = $78
    
    ; Additional setup calls
    jsr  D_1E2E                 ; Setup routine
    ldy  #(song_super_bonus - music_song_table)
    jsr  D_05AD                 ; Start super bonus music
    lda  #$14                   ; Wait time = 20 frames
    jsr  D_7BC8                 ; Wait routine
    lda  #$09                   ; Parameter = 9
    jsr  fill_color_ram         ; Fill color RAM
    jsr  D_7B53                 ; Another setup routine
    
    ; Process player states for both players
    ldx  #$01                   ; Start with player 2 (index 1)

;-------------------------------------------------------------------------------
; L_36DC - Set up player positions based on state
; Checks ENESSION (player state) and sets FA (X pos) and $C2 (Y pos)
;-------------------------------------------------------------------------------
L_36DC:
    ldy  #$00                   ; Default Y position offset = 0
    lda  ENESSION,x             ; Get player state ($B2+X)
    beq  L_36EB                 ; If 0, skip to position setup
    
    ; Player is active
    lda  #$01                   ; Set state to 1
    sta  ENESSION,x             ; Update player state
    lda  D_A735,x               ; Get X position from table
    ldy  #$9D                   ; Y position = $9D

L_36EB:
    sta  FA,x                   ; Set player X position ($BA+X)
    tya                         ; A = Y position
    sta  $C2,x                  ; Set player Y position ($C2+X)
    dex                         ; Next player (player 1, index 0)
    bpl  L_36DC                 ; Continue for both players
    
    ; Update screens and initialize game state
    jsr  D_1805                 ; Screen update
    jsr  D_05C5                 ; Setup routine
    jsr  D_1805                 ; Screen update again
    
    ; Set up game mode variables
    lda  #$00                   ; Game mode = 0
    sta  $20                    ; Store game mode
    lda  #$74                   ; Value $74
    sta  $BC                    ; Store in $BC
    lda  #$35                   ; Value $35
    sta  ROESSION               ; Store in ROESSION ($BD)
    lda  #$06                   ; Value 6
    sta  $C0                    ; Store in $C0

;-------------------------------------------------------------------------------
; D_370C - Bonus stage game loop initialization entry point
; Prepares screen display and player spawn
;-------------------------------------------------------------------------------
D_370C:
    ldx  #$00                   ; Value = 0
    stx  FSESSION               ; Clear FSESSION ($BE)
    dex                         ; X = $FF
    stx  D_5AFF                 ; Store $FF at D_5AFF
    stx  TXTTAB                 ; Store $FF in TXTTAB ($2B)
    
    ; Call setup routines
    lda  #$29                   ; Parameter = $29
    jsr  D_2BBD                 ; Setup routine
    lda  #$22                   ; Parameter = $22
    jsr  D_2C32                 ; Setup routine
    
    ; Set up character display parameters
    lda  #$46                   ; Character code $46
    sta  DATLIN+1               ; Store in $40
    lda  #$24                   ; Color/attribute $24
    sta  DATPTR                 ; Store in $41
    lda  #>__VIC_SCREEN_A__         ; Screen config
    jsr  D_1853                 ; Screen rendering
    
    ; Place character blocks using D_344A routine
    ldx  #$02                   ; X position = 2
    ldy  #$02                   ; Y position = 2
    jsr  D_344A                 ; Place 2x2 character block
    
    ldx  #$1C                   ; X position = $1C (28)
    ldy  #$02                   ; Y position = 2
    jsr  D_344A                 ; Place 2x2 character block
    
    jsr  copy_screen_buffers    ; Game loop routine
    
    ; Update character and position for next blocks
    lda  #$42                   ; Character code $42
    sta  DATLIN+1               ; Store in $40
    dec  DATPTR                 ; Decrement color ($41)
    
    ; Set up loop counter
    lda  #$11                   ; 18 iterations (counting down from $11)
    sta  $02                    ; Store counter in $02

;-------------------------------------------------------------------------------
; L_3748 - Place character blocks in a pattern
; Uses D_3421 position calculator twice per iteration
;-------------------------------------------------------------------------------
L_3748:
    ldx  $02                    ; Get current counter
    ldy  D_A722,x               ; Get Y position from table
    sty  ADRAY1                 ; Save Y in ADRAY1 ($03)
    lda  D_A710,x               ; Get first value from table
    jsr  D_3421                 ; Calculate position and update tables
    
    ldy  ADRAY1                 ; Restore Y position
    lda  #$1E                   ; Value = 30
    sec
    sbc  MEMSIZ+1               ; Subtract value from $38
    jsr  D_3421                 ; Calculate position again
    
    dec  $02                    ; Decrement counter
    bpl  L_3748                 ; Continue if >= 0
    
    dec  MEMSIZ                 ; Decrement $37
    
    ; Set up countdown timer
    lda  #$25                   ; Timer value = 37
    sta  D_597F                 ; Store countdown timer
    
    ; Set up final parameters and jump to routine
    ldx  #$02                   ; X parameter = 2
    ldy  #$12                   ; Y parameter = $12 (18)
    jmp  D_3193                 ; Jump to routine in bb-platform-collision.s

;-------------------------------------------------------------------------------
; Entry at $3771 - Player position checker during bonus stage
; Monitors player positions and handles special transitions
;-------------------------------------------------------------------------------
D_3771:
    ldx  #$01                   ; Start with player 2

L_3773:
    ldy  $C2,x                  ; Get player Y position
    lda  FA,x                   ; Get player X position
    cmp  #$8C                   ; Is X position = $8C?
    bne  L_378E                 ; No - skip to next player
    
    ; Player X is at $8C - check timer and Y position
    lda  D_597F                 ; Get countdown timer
    cmp  #$01                   ; Is timer = 1?
    beq  L_3792                 ; Yes - handle transition
    cmp  #$0E                   ; Is timer >= 14?
    bcs  L_378E                 ; Yes - skip (too early)
    
    ; Timer is 2-13, check Y position
    cpy  #$9D                   ; Is Y position = $9D?
    bne  L_378E                 ; No - skip
    
    ; Update Y position to $DD
    lda  #$DD                   ; New Y position
    sta  $C2,x                  ; Update player Y position

L_378E:
    dex                         ; Next player
    bpl  L_3773                 ; Continue for both players
    rts                         ; Return

;-------------------------------------------------------------------------------
; L_3792 - Handle player transition when timer reaches 1
; Triggers level completion sequence
;-------------------------------------------------------------------------------
L_3792:
    cpy  #$DD                   ; Is Y position = $DD?

D_3794:
    bne  L_378E                 ; No - skip
    
    ; Player reached $DD at timer=1 - trigger completion
    inc  MEMSIZ                 ; Increment $37
    ldx  #$10                   ; 16 frames for transition effect

L_379A:
    jsr  D_7BC3                 ; Wait for frame
    lda  $1C                    ; Get value from $1C
    eor  #$04                   ; Toggle bit 2
    sta  $1C                    ; Store back
    ora  #$08                   ; Set bit 3
    sta  $1E                    ; Store in $1E
    dex                         ; Decrement frame counter
    bne  L_379A                 ; Continue for 16 frames
    
    ; Complete transition
    jsr  clear_screen             ; Engine routine
    jsr  D_7BC6                 ; Wait routine
    
    ; Copy data from D_4850 to D_4050 (48 bytes)
    ldx  #$2F                   ; 48 bytes (indices $2F-0)

L_37B2:
    lda  D_4850,x               ; Get byte from source
    sta  D_4050,x               ; Store to destination
    dex                         ; Next byte
    bpl  L_37B2                 ; Continue for all bytes
    
    ; Clean up stack (4 return addresses)
    pla                         ; Pop return address low
    pla                         ; Pop return address high
    pla                         ; Pop another return address low
    pla                         ; Pop another return address high
    
    ; Finalize level completion
    dec  $21                    ; Decrement level completion flag
    ldy  #(song_level_resume - music_song_table)
    jsr  D_05AD                 ; Resume level music
    rts                         ; Return

;-------------------------------------------------------------------------------
; End of bb-bonus-stage-extended.s
;===============================================================================
