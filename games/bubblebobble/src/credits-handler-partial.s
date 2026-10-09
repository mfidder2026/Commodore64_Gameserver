; ==============================================================================
; rebb64 - Credits Handler & Music Selection
; ==============================================================================
; Address range: $F1AC-$F23F (148 bytes)
;
; This module contains:
; - D_F1AC: Credit/score checking routine
; - D_F20B: Music index table (12 bytes of data)
; - D_F217: Level-specific initialization routine
;
; Arrays used:
;   RIDBS ($AC,x) - Credit/score index
;   RODBE ($AE,x) - Credit/score state
;   entry_0400 - Score data array
;   D_05B9,y - High score table
;   D_045A,x - Display flags
; ==============================================================================

; D_F1AC - Credit/score check routine
; Checks two player scores (X = 1 down to 0)
.segment "CODE_CREDITS"

D_F1AC:
    ldx  #$01                   ; Start with player 1

L_F1AE:
    ; Get player's score index
    ldy  RODBE,x                ; Load score state index
    dey                         ; Decrement
    bmi  L_F1BC                 ; If negative, skip to alt path
    cpy  #$02                   ; Check if index is 2
    beq  L_F1BC                 ; If 2, skip to alt path
    
    ; Check score value at index
    lda  entry_0400,y           ; Load score byte
    bne  L_F1C7                 ; If non-zero, increment counters

L_F1BC:
    ; Alternate path: check next score byte
    iny                         ; Next index
    lda  entry_0400,y           ; Load score byte
    ldy  RIDBS,x                ; Load player's credit index
    cmp  D_05B9,y               ; Compare with high score table
    bcc  L_F1D8                 ; If less, skip update

L_F1C7:
    ; Score is high enough - increment counters
    inc  RIDBS,x                ; Increment credit index
    inc  D_045A,x               ; Increment display flag
    lda  #$03                   ; Set status flag
    sta  $B0                    ; Store in temp variable
    
    ; Check if credit index is 1
    lda  RIDBS,x                ; Load credit index
    cmp  #$01                   ; Check if 1
    bne  L_F1D8                 ; If not, skip
    dec  RODBE,x                ; Decrement score state

L_F1D8:
    ; Continue to next player
    dex                         ; Decrement player index
    bpl  L_F1AE                 ; Loop for player 0
    
    ; Check status flag
    lda  $B0                    ; Load status flag
    cmp  #$03                   ; Check if set
    bne  L_F1E4                 ; If changed, skip sound
    jsr  D_046C                 ; Play sound effect or update display

L_F1E4:
    ; Check game state for music/mode selection
    lda  D_5C3F                 ; Load game state flag
    cmp  #$19                   ; Check if in range 25-38
    bcc  L_F1EF                 ; If less than 25, handle mode
    cmp  #$27                   ; Check if less than 39
    bne  L_F20A                 ; If >= 39, return (FORWARD REF)

L_F1EF:
    ; Handle mode/music selection
    lda  $B1                    ; Load mode flag
    beq  L_F1F9                 ; If zero, check alternate
    
    ; Clear mode flag
    ldx  #$00                   ; Set X to 0
    stx  $B1                    ; Clear mode flag
    beq  L_F201                 ; Always branch (FORWARD REF)

L_F1F9:
    ; Check alternate mode
    ldx  $B0                    ; Load status flag
    beq  L_F20A                 ; If zero, return (FORWARD REF)
    lda  #$00                   ; Clear value
    sta  $B0                    ; Clear status flag

    ; L_F201 - Music/mode selection handler (branch target from F1F7)
L_F201:
    lda  D_F20B,x               ; Load music index from table
    ldy  D_F211,x               ; Load music parameter from table
    jmp  sfx_start                 ; Jump to music handler

    ; L_F20A - Return point (branch target from F1DC and F1FB)
L_F20A:
    rts                         ; Return from subroutine

; ==============================================================================
; Music Index Tables ($F20B-$F216, 12 bytes)
; ==============================================================================
; These tables map mode indices to music/parameter values.
; Used by the L_F201 music selection code above.
; ==============================================================================

D_F20B:
    .byte <sfx_preset_0            ; -> sfx_preset_0 ($F976)
    .byte <sfx_preset_1            ; -> sfx_preset_1 ($F994)
    .byte <sfx_preset_2            ; -> sfx_preset_2 ($F9B2)
    .byte <sfx_preset_3            ; -> sfx_preset_3 ($F9D0)
    .byte <sfx_preset_4            ; -> sfx_preset_4 ($F9F5)
    .byte <sfx_preset_5            ; -> sfx_preset_5 ($FA13)
D_F211:
    .byte >sfx_preset_0            ; -> sfx_preset_0 ($F976)
    .byte >sfx_preset_1            ; -> sfx_preset_1 ($F994)
    .byte >sfx_preset_2            ; -> sfx_preset_2 ($F9B2)
    .byte >sfx_preset_3            ; -> sfx_preset_3 ($F9D0)
    .byte >sfx_preset_4            ; -> sfx_preset_4 ($F9F5)
    .byte >sfx_preset_5            ; -> sfx_preset_5 ($FA13)

; ==============================================================================
; Level-Specific Initialization ($F217-$F23F, 41 bytes)
; ==============================================================================
; Called from $066D during level setup.
; Handles special initialization for level 72 ($48) and sets up timing
; parameters based on level number.
;
; Entry: Level number in SUBFLG ($10)
; Exit: Y = timing parameter ($1E or $E6)
;       Value stored at $0DC7
; ==============================================================================

D_F217:
    lda  SUBFLG                 ; $F217: a5 10 - Get current level
    cmp  #$48                   ; $F219: c9 48 - Is it level 72?
    bne  L_F230                 ; $F21B: d0 13 - No, skip special init
    
    ; Level 72 special initialization
    ; Fill 4 arrays with value $02
    lda  #$02                   ; $F21D: a9 02 - Value to fill
    ldx  #$03                   ; $F21F: a2 03 - Loop counter (4 iterations)
L_F221:
    sta  D_88C9,x               ; $F221: 9d c9 88 - Array 1
    sta  D_88F1,x               ; $F224: 9d f1 88 - Array 2
    sta  D_8919,x               ; $F227: 9d 19 89 - Array 3
    sta  D_8941,x               ; $F22A: 9d 41 89 - Array 4
    dex                         ; $F22D: ca
    bpl  L_F221                 ; $F22E: 10 f1 - Loop until X < 0

L_F230:
    ; Set timing parameter based on level
    ldy  #$1E                   ; $F230: a0 1e - Default timing value
    cmp  #$22                   ; $F232: c9 22 - Level 34?
    beq  L_F23A                 ; $F234: f0 04 - Yes, use alternate
    cmp  #$60                   ; $F236: c9 60 - Level 96?
    bne  L_F23C                 ; $F238: d0 02 - No, keep default
L_F23A:
    ldy  #$E6                   ; $F23A: a0 e6 - Alternate timing value
L_F23C:
    sta  D_0DC7                 ; $F23C: 8d c7 0d - Store level number
    rts                         ; $F23F: 60 - Return
