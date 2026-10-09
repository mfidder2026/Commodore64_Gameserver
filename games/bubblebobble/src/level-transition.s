;===============================================================================
; bb-level-transition.s - Level Transition & Screen Initialization
;===============================================================================
; Address range: $2DD7-$2F67 (401 bytes)
;
; Purpose: Level transition effects, screen clearing, entity state
;          management, and special effect helper routines
;
; Key Features:
; - Screen clearing and initialization using indirect addressing
; - Player state reset for level transitions
; - Entity/enemy state cleanup (D_2E61, D_2E79)
; - Screen render coordination (D_2EC0)
; - Enemy state save/restore for bonus levels (D_2EEA)
; - Screen border/background color flash effects
; - Special effect helper routines (D_2F5F, D_2F62, D_2F65)
;
; Entry Points:
; - D_2DD7: Data bytes (level transition data)
; - D_2E61: Entity state cleanup loop
; - D_2E79: Entity reset routine (18 entities, $00-$11)
; - D_2EC0: Screen rendering coordination
; - D_2EEA: Enemy state save/restore
; - D_2F5F, D_2F62, D_2F65: Special effect helpers (called from item effects)
;
;===============================================================================

; Data at start of level transition routine
.segment "CODE_EFFECTS"

D_2DD7:
.byte   $e6, $37                ; Level transition data

; Main level transition initialization routine
; Sets up screen pointers and clears screen memory
    jsr  D_7BA6                 ; Call screen setup routine
    lda  #$c2                   ; Screen page high byte
    sta  MEMSIZ+1               ; Set screen pointer high
    sta  CURLIN+1               ; Set cursor line high
    lda  #$03                   ; Low byte offset
    ora  ARYTAB+1               ; Combine with array table
    sta  CURLIN                 ; Set cursor line low
    and  #$03                   ; Mask to page offset
    ora  #$d8                   ; Color RAM ($D800) base - hardware fixed
    sta  OLDLIN                 ; Set old line pointer
    jsr  D_2E79                 ; Reset all entity states
    dec  MEMSIZ                 ; Decrement memory pointer
    ldx  #$07                   ; Loop counter for 8 bytes
    lda  #$ff                   ; Fill value
    sta  $52                    ; Clear storage 1
    sta  FOUR6                  ; Clear special item type
    sta  D_58BF                 ; Clear global flag
L_2DFE:
    sta  D_47F8,x               ; Clear item table 1
    sta  D_4FF8,x               ; Clear item table 2
    dex                         ; Decrement counter
    bpl  L_2DFE                 ; Loop until done
    lda  #$19                   ; Screen row offset
    sta  STREND                 ; Set string end low
    lda  MEMSIZ+1               ; Get screen page
    sta  STREND+1               ; Set string end high
    lda  CURLIN                 ; Get cursor line
    eor  #ARYTAB_SCREEN_TOGGLE  ; Toggle screen page
    sta  FRETOP                 ; Set free space top

; Screen clearing loop - clears screen memory row by row
L_2E15:
    jsr  wait_one_frame                 ; Wait one frame
    jsr  wait_one_frame                 ; Wait another frame
    jsr  D_045C                 ; Screen update routine
    ldy  #$1b                   ; 28 bytes per row (0-27)
L_2E20:
    lda  (MEMSIZ+1),y           ; Get screen character
    cmp  #$20                   ; Compare with space
    bcs  L_2E2E                 ; Branch if >= space
    cmp  #$1f                   ; Compare with $1f
    beq  L_2E2E                 ; Branch if equal
    cmp  #$10                   ; Compare with $10
    bcs  L_2E34                 ; Branch if >= $10
L_2E2E:
    lda  #$ff                   ; Fill with $ff
    sta  (MEMSIZ+1),y           ; Clear screen position 1
    sta  (STREND+1),y           ; Clear screen position 2
L_2E34:
    lda  #$0b                   ; Color value
    sta  (CURLIN+1),y           ; Set color memory
    dey                         ; Next position
    bpl  L_2E20                 ; Loop for all 28 bytes
    lda  MEMSIZ+1               ; Get screen page
    sec                         ; Set carry for subtraction
    sbc  #$28                   ; Subtract 40 (one row)
    sta  STREND+1               ; Update string end
    sta  MEMSIZ+1               ; Update memory pointer
    sta  CURLIN+1               ; Update cursor line
    bcs  L_2E4E                 ; Branch if no borrow
    dec  CURLIN                 ; Decrement low byte
    dec  OLDLIN                 ; Decrement old line
    dec  FRETOP                 ; Decrement free top
L_2E4E:
    dec  STREND                 ; Decrement row counter
    bne  L_2E15                 ; Loop until all rows cleared
    
    ; Reset player states if in special mode
    ldx  #$01                   ; Check 2 players
L_2E54:
    lda  ENESSION,x             ; Get player state
    cmp  #$0d                   ; Check if in special mode
    bne  L_2E5E                 ; Branch if not
    lda  #$01                   ; Reset to active state
    sta  ENESSION,x             ; Update player state
L_2E5E:
    dex                         ; Next player
    bpl  L_2E54                 ; Loop for both players

;===============================================================================
; D_2E61 - Entity State Cleanup
;===============================================================================
; Cleans up entity states for level transitions
; Checks entities $00-$05 and clears any in transitional states
;
; Called from: $2EDF (level setup), $35F8, and multiple locations
;===============================================================================
D_2E61:
    ldx  #$05                   ; Check 6 entity slots
L_2E63:
    lda  $b4,x                  ; Get entity state
    beq  L_2E72                 ; Skip if empty
    cmp  #$0d                   ; Check for state $0d
    beq  L_2E6F                 ; Branch if match
    cmp  #$0b                   ; Check for state $0b
    bcs  L_2E72                 ; Skip if >= $0b
L_2E6F:
    jsr  D_1A6F                 ; Clear entity
L_2E72:
    dex                         ; Next entity
    bpl  L_2E63                 ; Loop for all entities
    inx                         ; X = 0
    stx  $4a                    ; Clear flag
L_2E78:
    rts                         ; Return

;===============================================================================
; D_2E79 - Entity Reset Routine
;===============================================================================
; Resets all entity states (18 entities, $00-$11)
; Handles entity spawning from death/despawn states
;
; Called from: $0A78, $2DEE, $2EDC, $331A, $35F5, $7FCE, $A42D
;
; Process:
; - For entities in spawn range ($18-$23), spawns them as active entities
; - Resets entity positions, states, and sprite flags
; - Clears movement, animation, and collision data
; - Calls screen rendering after all entities processed
;===============================================================================
D_2E79:
    ldx  #$11                   ; Loop through 18 entities ($00-$11)
    lda  D_58BF                 ; Check global flag
    bmi  L_2E78                 ; Return if flag set (< 0)
L_2E80:
    lda  PESSION,x              ; Get entity spawn state
    cmp  #$24                   ; Check if in despawn range
    bcs  L_2EA4                 ; Skip if >= $24
    cmp  #$18                   ; Check if in spawn range
    bcc  L_2EA4                 ; Skip if < $18
    sbc  #$18                   ; Convert to entity type (0-11)
    lsr                         ; Divide by 2 to get slot
    stx  DATLIN+1               ; Save X register
    ldy  D_AA30,x               ; Get entity spawn type
    tax                         ; X = slot number
    tya                         ; A = spawn type
    sta  $b4,x                  ; Set entity active state
    lda  VIC_SPR_ENA            ; Get sprite enable register
    ora  D_AB55,x               ; Enable sprite for this entity
    sta  VIC_SPR_ENA            ; Update sprite enable
    jsr  D_1A6F                 ; Initialize entity
    ldx  DATLIN+1               ; Restore X register
L_2EA4:
    lda  #$4a                   ; Reset state value
    sta  PESSION,x              ; Reset entity spawn state
    lda  #$00                   ; Zero value
    sta  D_014B,x               ; Clear entity data 1
    sta  D_016F,x               ; Clear entity data 2
    sta  D_015D,x               ; Clear entity data 3
    sta  D_0181,x               ; Clear entity data 4
    sta  $dc,x                  ; Clear entity position X
    sta  $ee,x                  ; Clear entity position Y
    dex                         ; Next entity
    bpl  L_2E80                 ; Loop for all 18 entities
    jsr  D_2EC0                 ; Screen render coordination
    
;===============================================================================
; D_2EC0 - Screen Rendering Coordination
;===============================================================================
; Calls screen rendering routines twice for double-buffering
;
; Called from: $2EBD (after entity reset)
;===============================================================================
D_2EC0:
    jsr  L_1B19                 ; Render routine 1
    jsr  D_1844                 ; Render routine 2
    jsr  L_1B19                 ; Render routine 1 again
    jmp  D_1844                 ; Render routine 2 again and return

; Level transition continuation - copies data and manages entity states
D_2ECC:
    jsr  L_069B                 ; Level data load routine
    ldx  #$22                   ; Copy 35 bytes
L_2ED1:
    lda  D_A854,x               ; Get source data
    sta  D_7D00,x               ; Copy to destination
    dex                         ; Next byte
    bpl  L_2ED1                 ; Loop until done
    inc  MEMSIZ                 ; Increment memory pointer
    jsr  D_2E79                 ; Reset entity states
    jsr  D_2E61                 ; Clean up entity states
    inc  $4a                    ; Increment flag
    lda  #$13                   ; Parameter A
    ldx  #$88                   ; Parameter X
    ldy  #$91                   ; Parameter Y

;===============================================================================
; D_2EEA - Enemy State Save/Restore
;===============================================================================
; Saves or restores enemy states, positions, and attributes
; Used for bonus level transitions where enemies need to be preserved
;
; Called from: $2EE4 (with A=#$13, X=#$88, Y=#$91)
;
; Parameters stored in zero page:
;   MEMSIZ+1 ($38) = A value
;   CURLIN ($39) = X value  
;   CURLIN+1 ($3A) = Y value
;
; Process:
; - Saves 6 entities' states to $4700-$4737
; - Clears current entity states
; - Flashes screen border/background 6 times
; - Restores entity positions from saved parameters
;===============================================================================
D_2EEA:
    sta  MEMSIZ+1               ; Store A parameter
    stx  CURLIN                 ; Store X parameter
    sty  CURLIN+1               ; Store Y parameter
    ldx  #$05                   ; Loop for 6 entities
L_2EF2:
    lda  $b4,x                  ; Get entity state
    sta  D_4700,x               ; Save state
    lda  $bc,x                  ; Get entity X position low
    sta  D_4710,x               ; Save X position low
    lda  $c4,x                  ; Get entity X position high
    sta  D_4720,x               ; Save X position high
    lda  D_859A,x               ; Get entity Y position
    sta  D_4730,x               ; Save Y position
    lda  #$f4                   ; Off-screen Y value
    sta  D_859A,x               ; Move entity off-screen
    lda  #$00                   ; Zero value
    sta  D_8522,x               ; Clear sprite direction
    sta  $bc,x                  ; Clear X position low
    sta  $c4,x                  ; Clear X position high
    sta  D_872A,x               ; Clear entity data 1
    sta  D_863A,x               ; Clear entity data 2
    lda  MEMSIZ+1               ; Get saved parameter
    sta  $b4,x                  ; Restore entity state
    lda  #$ff                   ; Initial value
    sta  D_85C2,x               ; Set entity flag
    lda  #$07                   ; Color value
    sta  D_854A,x               ; Set entity color
    dex                         ; Next entity
    bpl  L_2EF2                 ; Loop for all 6 entities
    stx  $2a                    ; X = -1, store flag
    sta  VIC_BORDER             ; Set border color = 7
    sta  VIC_BG0                ; Set background color = 7
    ldx  #$06                   ; Flash 6 times
L_2F36:
    lda  VIC_BORDER             ; Get current border color
    eor  #$02                   ; Toggle bit 1 (flip between 5 and 7)
    sta  VIC_BORDER             ; Set new border color
    sta  VIC_BG0                ; Set new background color
    lda  #$03                   ; Delay value
    jsr  D_7BC8                 ; Wait routine
    dex                         ; Decrement counter
    bne  L_2F36                 ; Loop for all flashes
    stx  VIC_BORDER             ; X = 0, set border to black
    stx  VIC_BG0                ; Set background to black
    ldx  #$05                   ; Loop for 6 entities
L_2F51:
    lda  CURLIN                 ; Get saved X parameter
    sta  $bc,x                  ; Restore X position low
    lda  CURLIN+1               ; Get saved Y parameter
    sta  $c4,x                  ; Restore X position high
    dex                         ; Next entity
    bpl  L_2F51                 ; Loop for all entities
    dec  MEMSIZ                 ; Decrement memory pointer
    rts                         ; Return

;===============================================================================
; Special Effect Helper Routines
;===============================================================================
; These routines are called from special item effects (bb-special-item-effects.s)
; at $2DBE-$2DC7. They modify specific zero page locations.
;
; D_2F5F: Decrements FAC,x ($61,x) - used for special effect 1
; D_2F62: Decrements $63,x - used for special effect 2  
; D_2F65: Decrements $65,x - used for special effect 3
;===============================================================================
D_2F5F:
    dec  FAC,x                  ; Decrement $61,x
    rts                         ; Return

D_2F62:
    dec  $63,x                  ; Decrement $63,x
    rts                         ; Return

D_2F65:
    dec  $65,x                  ; Decrement $65,x
    rts                         ; Return
