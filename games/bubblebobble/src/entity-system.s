;===============================================================================
; Bubble Bobble - Entity System
; Address Range: $E9FD-$F0ED (1777 bytes)
;===============================================================================
; This module combines entity bubble physics, movement, AI, and physics
; continuation into a single file because they share cross-references via
; short branch instructions that require a single contiguous segment.
;
; Subsystems:
;   1. Entity Bubble Physics & Climbing Handler ($E9FD-$EC0B)
;      - Bubble movement, platform collision, directional velocity
;      - Self-modifying code for jump targets at $EB94, $EBB5/$EBB6
;
;   2. Entity Movement & Direction Handler ($EC0C-$EDC6)
;      - Platform climbing continuation, horizontal movement
;      - Entity direction changes, spawn new entities/projectiles
;
;   3. Entity AI & Attack Logic ($EDC7-$EFBB)
;      - Attack decisions, entity position updates (D_EDCD)
;      - Animation toggle, player Y-position comparison
;      - Horizontal/vertical movement with platform collision
;
;   4. Entity Physics Continuation & Title Screen Init ($EFBC-$F0ED)
;      - Platform collision check, movement handler with state-based logic
;      - Title screen initialization (D_F005)
;===============================================================================

.segment "CODE_ENTITY"

; ===========================================================================
; Part 1: Entity Bubble Physics & Climbing Handler ($E9FD-$EC0B)
; ===========================================================================

; Entry point at $E9FD - Main bubble entity handler
; X register holds entity index

D_E9FD:
    jsr  D_EDCD                 ; Update entity position
    lda  D_8818,x               ; Load animation frame data
    bmi  L_EA08                 ; If negative, process bubble physics
    jmp  D_ED3B                 ; Otherwise, handle normal entity

; Bubble physics handler
L_EA08:
    jsr  D_EE62                 ; Jump state handler
    lda  D_85E8,x               ; Load entity state flags
    sta  $02                    ; Store in temp (bit flags for behavior)
    lda  D_87F0,x               ; Load vertical collision flags
    bmi  L_EA18                 ; If negative, check climbing state
    jmp  D_EB3F                 ; Handle bubble ascent

; Check if entity is on platform
L_EA18:
    lda  D_87A0,x               ; Load platform collision state
    bmi  L_EA20                 ; If negative, check bubble trapped state
    jmp  D_EBD9                 ; Handle platform physics

; Check if entity is bubble-trapped
L_EA20:
    lda  D_8700,x               ; Load movement state
    beq  L_EA6B                 ; If zero, skip collision checks
    
    ; Calculate adjacent cell pointer (subtract $A0 from current cell)
    lda  INPFLG                 ; $11 - Cell pointer low
    sec
    sbc  #$A0                   ; Subtract one row (40 cols * 4 bytes)
    sta  $04                    ; Store in temp pointer
    lda  $12                    ; Cell pointer high
    sbc  #$00
    sta  $05                    ; Complete temp pointer
    
    ; Check 5 platform cells for open space (detect if trapped by platforms)
    ; This checks: cell+$02, +$2A, +$52, +$7A, +$A2 (vertical column)
    ldy  #$02                   ; Check cell offset +$02
    lda  ($04),y
    bmi  L_EA3E                 ; If solid, continue checking
    ldy  #$2A                   ; Check cell offset +$2A
    lda  ($04),y
    bmi  L_EA62                 ; If solid, set "trapped" flag
    
L_EA3E:
    ldy  #$2A                   ; Check cell offset +$2A
    lda  ($04),y
    bmi  L_EA4A                 ; If solid, continue checking
    ldy  #$52                   ; Check cell offset +$52
    lda  ($04),y
    bmi  L_EA62                 ; If solid, set "trapped" flag
    
L_EA4A:
    ldy  #$52                   ; Check cell offset +$52
    lda  ($04),y
    bmi  L_EA56                 ; If solid, continue checking
    ldy  #$7A                   ; Check cell offset +$7A
    lda  ($04),y
    bmi  L_EA62                 ; If solid, set "trapped" flag
    
L_EA56:
    ldy  #$7A                   ; Check cell offset +$7A
    lda  ($04),y
    bmi  L_EA6B                 ; If solid, skip flag setting
    ldy  #$A2                   ; Check cell offset +$A2
    lda  ($04),y
    bpl  L_EA6B                 ; If not solid, skip flag setting
    
L_EA62:
    ; Entity is trapped between platforms
    lda  $02                    ; Load state flags
    ora  #$04                   ; Set "trapped" bit
    sta  D_85E8,x               ; Store back to entity state
    sta  $02                    ; Update temp copy

; Check if entity can climb platform
L_EA6B:
    lda  ZP_C2,x                ; Load Y position
    cmp  #$1F                   ; Below screen top?
    bcc  L_EA8C                 ; Yes, skip climb check
    
    lda  INDEX2                 ; $24 - Terrain index
    beq  L_EA78                 ; If zero, check platform above
    jmp  D_EAFA                 ; Otherwise, handle standard movement

; Check platform cells above entity (3 cells at +$51, +$52, +$53)
L_EA78:
    ldy  #$51                   ; Cell offset +$51
    lda  (INPFLG),y             ; Check cell
    bmi  L_EA92                 ; If solid, can't climb
    iny                         ; Next cell (+$52)
    lda  (INPFLG),y
    bmi  L_EA92                 ; If solid, can't climb
    lda  $23                    ; Level/world index
    beq  L_EA8C                 ; If zero, allow climb
    iny                         ; Next cell (+$53)
    lda  (INPFLG),y
    bmi  L_EA92                 ; If solid, can't climb
    
L_EA8C:
    ; Entity can climb - advance vertical state
    inc  D_87F0,x               ; Increment vertical collision state
    jmp  D_EB3F                 ; Handle bubble ascent

; Entity colliding with platform above
L_EA92:
    lda  D_86D8,x               ; Load collision data
    ora  D_8700,x               ; OR with movement state
    beq  D_EAFA                 ; If both zero, use standard movement
    
    lda  ENESSION,x             ; Load entity state ($B2,x)
    cmp  #$03                   ; State 3?
    beq  D_EAFA                 ; Yes, use standard movement
    
    ; Check if entity should move down vs up
    lda  $25                    ; Player Y position / level index
    cmp  D_8750,x               ; Compare to target direction
    bcs  L_EABE                 ; If >=, move down
    
    ; Move up - check cell at +$53
    ldy  #$53                   ; Cell offset
    lda  $23                    ; Level/world index
    cmp  #$06                   ; World 6?
    bne  D_EAFA                 ; No, use standard movement
    
    ; Calculate pointer offset +$08
    lda  INPFLG                 ; $11
    adc  #$08                   ; Add 8
    sta  $04
    lda  $12
    adc  #$00
    sta  $05
    jmp  D_EAD1                 ; Check platform cell

; Move down path
L_EABE:
    ldy  #$50                   ; Cell offset +$50
    lda  $23                    ; Level/world index
    bne  D_EAFA                 ; If not zero, use standard movement
    
    ; Calculate pointer offset -$09
    lda  INPFLG                 ; $11
    sec
    sbc  #$09                   ; Subtract 9
    sta  $04
    lda  $12
    sbc  #$00
    sta  $05

; Check if platform cell allows passage
D_EAD1:
    lda  (INPFLG),y             ; Check current cell
    bmi  D_EAFA                 ; If solid, use standard movement
    ldy  #$50                   ; Check offset cell
    lda  ($04),y
    bpl  D_EAFA                 ; If not solid, use standard movement
    
    ; Set directional velocity
    lda  #$00
    sta  D_8840,x               ; Clear horizontal velocity
    sta  D_8868,x               ; Clear secondary velocity
    
    lda  $25                    ; Player Y / level index
    cmp  D_8750,x               ; Compare to target
    bcc  L_EAEF                 ; If less, move left
    
    dec  D_8840,x               ; Move right (set to $FF)
    bne  L_EAF2                 ; Always taken
    
L_EAEF:
    dec  D_8868,x               ; Move left (set to $FF)
    
L_EAF2:
    lda  #$0F                   ; Platform climb state
    sta  D_87A0,x               ; Set collision state
    jmp  D_EBD9                 ; Handle platform physics

; Standard movement handler - processes state bit flags
D_EAFA:
    lsr  $02                    ; Shift state flags right
    bcc  L_EB01                 ; If bit 0 clear, skip
    jsr  D_ECDF                 ; Handle movement bit 0
    
L_EB01:
    lsr  $02                    ; Shift state flags right
    bcc  L_EB08                 ; If bit 1 clear, skip
    jsr  D_ED1E                 ; Handle movement bit 1
    
L_EB08:
    lsr  $02                    ; Shift state flags right
    bcc  L_EB0F                 ; If bit 2 clear, skip
    jmp  D_EBC4                 ; Handle movement bit 2 (reset velocities)

; Animation frame update at $EB0F
L_EB0F:
    inc  D_8610,x               ; Increment animation counter
    lda  D_8610,x
    cmp  #$02                   ; Every 2 frames?
    bcc  L_EB33                 ; No, return
    
    ; Reset counter and update animation frame
    lda  #$00
    sta  D_8610,x               ; Reset counter
    inc  D_8520,x               ; Increment animation frame
    lda  D_8520,x
    and  D_8778,x               ; Mask with animation limit
    bne  L_EB33                 ; If not zero, return
    
    ; Wrap animation frame
    lda  D_8520,x
    sec
    sbc  D_8750,x               ; Subtract frame count
    sta  D_8520,x               ; Store wrapped frame
    
L_EB33:
    rts

; Self-modifying code setup routines
; These modify jump targets at runtime

; Setup for downward movement (called from elsewhere) - D_EB34
D_EB34:
    lda  #$2C                   ; Opcode for BIT absolute
    sta  D_EB94                 ; Modify instruction at $EB94
    lda  #<D_EE4A               ; Low byte of target
    ldy  #>D_EE4A               ; High byte of target
    bne  L_EB48                 ; Always taken

; Setup for bubble ascent - D_EB3F
D_EB3F:
    lda  #$4C                   ; Opcode for JMP absolute
    sta  D_EB94                 ; Modify instruction at $EB94
    
    ; D_EB44
    lda  #<L_EB0F               ; Low byte of target
    ldy  #>L_EB0F               ; High byte of target

; Store modified jump target address
L_EB48:
    sta  D_EBB5                 ; Store low byte at $EBB5
    sty  D_EBB6                 ; Store high byte at $EBB6
    
    ; Update Y position (bubble rises)
    lda  ZP_C2,x                ; Load Y position
    clc
    adc  #$02                   ; Move up 2 pixels
    sta  ZP_C2,x                ; Store new position
    cmp  #$F5                   ; Reached top wrap point?
    bne  L_EB5F
    
    ; Wrap to bottom of screen
    lda  #$15                   ; Bottom Y position
    sta  ZP_C2,x
    bne  L_EBB4                 ; Jump to exit (always taken)

; Check if on platform boundary
L_EB5F:
    cmp  #$1F                   ; Below screen top?
    bcc  L_EBB4                 ; Yes, exit
    sbc  #$2D                   ; Subtract platform base
    and  #$07                   ; Check if on 8-pixel boundary
    bne  L_EBB4                 ; Not on boundary, exit
    
    ; Check platform cells (3 cells at +$51, +$52, +$53)
    ldy  #$51
    lda  (INPFLG),y
    bmi  L_EBB4                 ; Solid platform, exit
    iny
    lda  (INPFLG),y
    bmi  L_EBB4                 ; Solid platform, exit
    lda  $23                    ; Level index
    beq  L_EB7D                 ; If zero, check next set
    iny
    lda  (INPFLG),y
    bmi  L_EBB4                 ; Solid platform, exit

; Check second platform row (cells at +$79, +$7A, +$7B)
L_EB7D:
    ldy  #$79
    lda  (INPFLG),y
    bmi  L_EB91                 ; Solid platform, decrease state
    iny
    lda  (INPFLG),y
    bmi  L_EB91                 ; Solid platform, decrease state
    lda  $23                    ; Level index
    beq  L_EBB4                 ; If zero, exit
    iny
    lda  (INPFLG),y
    bpl  L_EBB4                 ; Not solid, exit

; Decrease vertical collision state (descending)
L_EB91:
    dec  D_87F0,x               ; Decrement vertical collision state
    
; Self-modified instruction at D_EB94 - either JMP or BIT depending on setup
D_EB94:
    jmp  L_EB0F                 ; Modified at runtime (may become BIT)

; Horizontal position check for player interaction
    lda  D_85E8,x               ; Load entity state
    and  #$04                   ; Check "trapped" bit
    sta  $04                    ; Store in temp
    lda  FA,x                   ; Load entity X position
    ldy  OPPTR                  ; $4B - Player index pointer
    cmp  FA,y                   ; Compare with player X
    bcs  L_EBAA                 ; If entity >= player, go right
    
    lda  #$02                   ; Direction = left
    .byte $2C                   ; BIT absolute - skip next 2-byte instruction
    
L_EBAA:
    lda  #$01                   ; Direction = right
    ora  $04                    ; Combine with state flags
    sta  D_85E8,x               ; Store updated state
    jmp  D_EE4A                 ; Continue with state handler

; Self-modified jump target (3-byte instruction modified at runtime)
L_EBB4:
    .byte $4C                   ; JMP opcode - D_EBB5 points here (= * - 1)
D_EBB5:
    .byte <L_EB0F               ; Target address low (modified) - D_EBB5
D_EBB6:
    .byte >L_EB0F               ; Target address high (modified) - D_EBB6
L_EBB7:
    rts

; Alternative bubble physics setup - D_EBB8
D_EBB8:
    lda  #$4C                   ; JMP opcode
    sta  D_EB94                 ; Modify instruction
    lda  #<L_EBB7               ; Target low
    ldy  #>L_EBB7               ; Target high
    jmp  L_EB48                 ; Store target address

; Reset horizontal velocities - D_EBC4
D_EBC4:
    lda  #$00
    sta  D_8840,x               ; Clear horizontal velocity
    sta  D_8868,x               ; Clear secondary velocity
    lda  D_85E8,x               ; Load entity state
    and  #$FB                   ; Clear bit 2 (trapped flag)
    sta  D_85E8,x               ; Store back
    lda  #$1F                   ; Platform state value
    sta  D_87A0,x               ; Set collision state

; Platform climbing physics handler - D_EBD9
D_EBD9:
    beq  L_EC0C                 ; If zero, exit
    cmp  #$10                   ; State >= $10?
    bcs  L_EBFB                 ; Yes, handle fast descent
    
    ; Slow descent (state 0-15)
    dec  D_87A0,x               ; Decrement platform state
    tay                         ; Transfer to Y
    lda  D_8840,x               ; Check horizontal velocity
    ora  D_8868,x               ; OR with secondary velocity
    beq  L_EBF0                 ; If both zero, use table
    
    ; Manual descent with velocity
    dec  ZP_C2,x                ; Move down 1 pixel
    jmp  D_EC87                 ; Continue processing
    
L_EBF0:
    ; Table-driven descent
    lda  ZP_C2,x                ; Load Y position
    sec
    sbc  D_ACDD,y               ; Subtract offset from table
    sta  ZP_C2,x                ; Store new position
    jmp  L_EB0F                 ; Update animation

; Fast descent (state >= $10)
L_EBFB:
    dec  D_87A0,x               ; Decrement platform state
    and  #$03                   ; Check if multiple of 4
    bne  L_EC0B                 ; Not multiple, exit
    
    ; Toggle animation frame every 4th frame
    lda  D_8520,x               ; Load animation frame
    eor  D_8750,x               ; XOR with frame limit
    sta  D_8520,x               ; Store toggled frame
    
L_EC0B:
    rts

; $EC0C marks the end of this routine section

; ===========================================================================
; Part 2: Entity Movement & Direction Handler ($EC0C-$EDC6)
; ===========================================================================

; Continuation from platform climbing handler (jumped to from D_EBD9 via beq)
; This handles the climbing state counter and Y position updates
; Entry at L_EC0C

L_EC0C:
    ldy  D_87C8,x               ; Load secondary collision state
    bpl  L_EC17                 ; If positive, use as-is
    lda  #$00                   ; Reset to zero if negative
    sta  D_87C8,x
    tay                         ; Transfer to Y
    
L_EC17:
    cpy  #$10                   ; Check if counter reached 16
    bne  L_EC1E                 ; If not, continue movement
    jmp  D_EC7C                 ; If 16, exit climbing state

; Increment climbing counter and update Y position
L_EC1E:
    inc  D_87C8,x               ; Increment climbing state counter
    lda  D_8840,x               ; Load horizontal velocity
    ora  D_8868,x               ; OR with secondary velocity
    beq  L_EC34                 ; If both zero, use standard table
    
    ; Use alternate movement table (D_ACED) when velocity present
    lda  ZP_C2,x                ; Load Y position
    clc
    ; D_EC2C
    adc  D_ACED,y               ; Add offset from alternate table
    sta  ZP_C2,x                ; Store new Y position
    jmp  D_EC3C                 ; Continue to collision check
    
L_EC34:
    ; Use standard movement table (D_ACDD) when no velocity
    lda  ZP_C2,x                ; Load Y position
    clc
    adc  D_ACDD,y               ; Add offset from standard table
    sta  ZP_C2,x                ; Store new Y position

; Check if entity reached platform level during climb - D_EC3C
D_EC3C:
    cmp  #$1F                   ; Y position >= $1F (on-screen)?
    bcc  D_EC87                 ; If below, continue to horizontal movement
    sbc  #$15                   ; Subtract base offset
    and  #$07                   ; Check if on 8-pixel boundary
    cmp  INDEX2                 ; Compare with terrain index
    bcs  D_EC87                 ; If >=, continue to horizontal movement
    
    ; Check platform cells above (3 cells at +$51, +$52, +$53)
    ldy  #$51
    lda  (INPFLG),y             ; Check cell +$51
    bmi  D_EC87                 ; If solid, continue horizontal movement
    iny
    lda  (INPFLG),y             ; Check cell +$52
    bmi  D_EC87                 ; If solid, continue horizontal movement
    lda  ZP_23                  ; Check level index
    beq  L_EC5C                 ; If zero, check next row
    iny
    lda  (INPFLG),y             ; Check cell +$53
    bmi  D_EC87                 ; If solid, continue horizontal movement
    
; Check second row of platform cells (at +$79, +$7A, +$7B)
L_EC5C:
    ldy  #$79
    lda  (INPFLG),y             ; Check cell +$79
    bmi  L_EC70                 ; If solid, snap to platform
    iny
    lda  (INPFLG),y             ; Check cell +$7A
    bmi  L_EC70                 ; If solid, snap to platform
    lda  ZP_23                  ; Check level index
    beq  D_EC87                 ; If zero, continue horizontal movement
    iny
    lda  (INPFLG),y             ; Check cell +$7B
    bpl  D_EC87                 ; If not solid, continue horizontal movement
    
; Snap entity Y position to platform boundary
L_EC70:
    lda  ZP_C2,x                ; Load Y position
    sec
    sbc  #$2D                   ; Subtract platform base
    and  #$F8                   ; Round down to 8-pixel boundary
    clc
    adc  #$2D                   ; Add platform base back
    sta  ZP_C2,x                ; Store aligned Y position
    
; Exit climbing state - set flags to exit platform mode - D_EC7C
D_EC7C:
    lda  #$FF
    sta  D_87A0,x               ; Set primary collision flag
    sta  D_87C8,x               ; Set secondary collision flag
    jmp  L_EB0F                 ; Jump to animation update

; Horizontal movement handler - processes left/right velocity - D_EC87
D_EC87:
    lda  D_8840,x               ; Load horizontal velocity
    bpl  L_ECB0                 ; If positive/zero, check right movement
    
    ; Moving left (negative velocity)
    ldy  #$28                   ; Default cell offset
    lda  INDEX2                 ; Check terrain index
    beq  L_EC94                 ; If zero, use default
    ldy  #$50                   ; Alternate cell offset
    
L_EC94:
    lda  ZP_23                  ; Check level index
    bne  L_ECA9                 ; If non-zero, move left unconditionally
    
    ; Check if wall to the left
    lda  (INPFLG),y             ; Check left cell
    bpl  L_ECA9                 ; If not solid, move left
    iny                         ; Check adjacent cell
    lda  (INPFLG),y
    bmi  L_ECA9                 ; If solid, reverse direction
    
    ; Hit wall - reverse horizontal velocity
    lda  #$01
    sta  D_8840,x               ; Change to positive (move right)
    jmp  L_EB0F                 ; Update animation
    
L_ECA9:
    ; Move left 2 pixels
    dec  FA,x                   ; Decrement X position
    dec  FA,x                   ; Decrement X position again
    jmp  L_EB0F                 ; Update animation

; Check right movement (positive velocity in D_8868,x)
L_ECB0:
    lda  D_8868,x               ; Load secondary velocity
    bpl  L_ECDC                 ; If positive/zero, done with movement
    
    ; Moving right (negative secondary velocity indicates rightward)
    lda  FA,x                   ; Load X position
    cmp  #$F4                   ; At right edge?
    beq  L_ECD0                 ; If yes, reverse direction
    
    ldy  #$2B                   ; Default cell offset
    lda  INDEX2                 ; Check terrain index
    beq  L_ECC3                 ; If zero, use default
    ldy  #$53                   ; Alternate cell offset
    
L_ECC3:
    lda  ZP_23                  ; Check level index
    bne  L_ECD8                 ; If non-zero, move right unconditionally
    
    ; Check if wall to the right
    lda  (INPFLG),y             ; Check right cell
    bpl  L_ECD8                 ; If not solid, move right
    dey                         ; Check adjacent cell
    lda  (INPFLG),y
    bmi  L_ECD8                 ; If solid, reverse direction
    
L_ECD0:
    ; Hit wall or edge - reverse secondary velocity
    lda  #$01
    sta  D_8868,x               ; Change to positive
    jmp  L_EB0F                 ; Update animation
    
L_ECD8:
    ; Move right 2 pixels
    inc  FA,x                   ; Increment X position
    inc  FA,x                   ; Increment X position again
    
L_ECDC:
    jmp  L_EB0F                 ; Update animation

; D_ECDF: Movement handler for state bit flag 0 (called from D_EAFA)
; Handles directional decision based on player/target position
D_ECDF:
    lda  ZP_25                  ; Load player Y / level index
    cmp  D_8750,x               ; Compare with target direction
    bcs  L_ECED                 ; If >=, skip direction change
    
    ; Store target direction to entity direction array
    lda  D_8750,x               ; Load target direction
    sta  D_8520,x               ; Store to direction array
    rts                         ; Return

; Check platform cell and potentially reverse entity direction
L_ECED:
    ldy  #$28                   ; Default cell offset
    lda  INDEX2                 ; Check terrain index
    beq  L_ECF5                 ; If zero, use default
    ldy  #$50                   ; Alternate cell offset
    
L_ECF5:
    lda  #$FE                   ; Direction value (-2 for leftward)
    
; Common direction change routine (used by multiple entry points)
L_ECF7:
    sta  $04                    ; Store direction in temp
    lda  ZP_23                  ; Check level index
    bne  L_ED0A                 ; If non-zero, change direction
    
    ; Check if platform allows direction change
    lda  (INPFLG),y             ; Check cell
    bpl  L_ED0A                 ; If not solid, change direction
    
    ; Platform is solid - toggle entity state bits 0 and 1
    lda  D_85E8,x               ; Load entity state flags
    eor  #$03                   ; XOR bits 0 and 1
    sta  D_85E8,x               ; Store updated flags
    rts
    
L_ED0A:
    ; Apply direction change to X position
    lda  FA,x                   ; Load X position
    clc
    adc  $04                    ; Add direction offset
    sta  FA,x                   ; Store new X position
    rts

; D_ED12: Handle right direction input (entry point for external calls)
D_ED12:
    ldy  #$28                   ; Cell offset
    lda  #$FC                   ; Direction value (-4 for rightward)
    bmi  L_ECF7                 ; Always taken - jump to common handler

; D_ED18: Handle left direction input (entry point for external calls)
D_ED18:
    ldy  #$2B                   ; Cell offset
    lda  #$04                   ; Direction value (+4 for leftward)
    bpl  L_ECF7                 ; Always taken - jump to common handler

; D_ED1E: Movement handler for state bit flag 1 (called from D_EAFA)
; Controls animation frame based on position comparison
D_ED1E:
    lda  ZP_25                  ; Load player Y / level index
    cmp  D_8750,x               ; Compare with target
    bcc  L_ED2B                 ; If less, change frame
    
    ; Reset animation frame to zero
    lda  #$00
    sta  D_8520,x               ; Clear animation frame
    rts
    
L_ED2B:
    ; Check cell and set frame to 2
    ldy  #$2B                   ; Cell offset
    lda  INDEX2                 ; Check terrain index
    beq  L_ED33                 ; If zero, use default
    ldy  #$53                   ; Alternate cell offset
    
L_ED33:
    lda  #$02                   ; Animation frame 2
    bne  L_ECF7                 ; Always taken - use common direction handler

; Increment entity animation frame
L_ED37:
    inc  D_8818,x               ; Increment animation frame data
    rts

; D_ED3B: Normal entity handler - decrement animation frame
D_ED3B:
    dec  D_8818,x               ; Decrement animation frame data
    beq  L_ED41                 ; If zero, spawn projectile
    rts                         ; Otherwise return
    
; Spawn projectile/entity when animation frame reaches zero
L_ED41:
    ldy  D_87A0,x               ; Load collision state
    bmi  L_ED37                 ; If negative, just increment and return
    
    ; Setup to spawn projectile
    lda  #$FF
    sta  D_87A0,x               ; Set collision state
    
    ; Calculate spawn X position (entity X - $14) / 8
    lda  FA,x                   ; Load entity X position
    sec
    sbc  #$14                   ; Subtract left border offset
    lsr                         ; Divide by 8 (shift right 3 times)
    lsr
    lsr
    sta  ADRAY1                 ; Store grid X position in $03
    
    sty  $02                    ; Store Y register in temp
    
    ; Check entity animation frame vs target to determine projectile direction
    lda  D_8520,x               ; Load animation frame
    cmp  D_8750,x               ; Compare with target frame
    bcs  L_ED68                 ; If >=, projectile goes right
    
    ; Projectile goes left
    lda  #$02                   ; Direction code for left
    sta  D_0195,y               ; Store in projectile direction array
    ldy  #$2B                   ; Cell offset for left
    bne  L_ED71                 ; Skip right setup
    
L_ED68:
    ; Projectile goes right
    lda  #$80                   ; Direction code for right
    sta  D_0195,y               ; Store in projectile direction array
    ldy  #$27                   ; Cell offset for right
    lda  #$FE                   ; Direction offset
    
; Store direction and check if spawn position is valid
L_ED71:
    sta  $04                    ; Store direction offset
    lda  (INPFLG),y             ; Check spawn cell
    bmi  L_EDC7                 ; If solid, abort spawn
    iny                         ; Check adjacent cell
    lda  (INPFLG),y
    bmi  L_EDC7                 ; If solid, abort spawn
    
    ; Valid spawn position - create projectile entity
    ldy  $02                    ; Restore Y (entity slot)
    lda  ADRAY1                 ; Load grid X position
    clc
    adc  $04                    ; Add direction offset
    sta  a:ZP_DE,y              ; Store in entity array +$DE
    sta  D_AA0E,y               ; Store in data table
    
    ; Calculate spawn Y position (entity Y - $15) / 8
    lda  ZP_C2,x                ; Load entity Y position
    sec
    sbc  #$15                   ; Subtract top border offset
    lsr                         ; Divide by 8
    lsr
    lsr
    sta  a:ZP_F0,y              ; Store grid Y position in array +$F0
    
    ; Store source entity index
    txa                         ; Transfer entity index to A
    sta  D_AA20,y               ; Store in projectile source table
    
    ; Initialize projectile state
    lda  #$00
    sta  D_A9C6,y               ; Clear projectile state 1
    sta  D_A9D8,y               ; Clear projectile state 2
    
    ; Check entity type to determine projectile type
    lda  ENESSION,x             ; Load entity type/state
    cmp  #$08                   ; Entity type 8?
    bne  L_EDAA                 ; If not, check type 7
    
    ; Entity type 8 - spawn projectile type $2A
    lda  #$2A
    bne  L_EDC3                 ; Store and complete spawn
    
L_EDAA:
    cmp  #$07                   ; Entity type 7?
    bne  L_EDB9                 ; If not, use default projectile
    
    ; Entity type 7 - special handling
    tya                         ; Transfer slot to A
    sta  D_8890,x               ; Store in entity data array
    lda  #$2C                   ; Animation frame $2C
    sta  D_8818,x               ; Store in animation data
    bne  L_EDC3                 ; Complete spawn
    
L_EDB9:
    ; Default projectile type - based on direction
    lda  D_0195,y               ; Load projectile direction
    and  #$7F                   ; Clear high bit
    sta  D_A9C6,y               ; Store as projectile state
    lda  #$28                   ; Default projectile type
    
L_EDC3:
    sta  a:BLNON,y              ; Store projectile type in array +$CC
    
    ; L_EDC7
    rts

; End of entity movement handler section

; ===========================================================================
; Part 3: Entity AI & Attack Logic ($EDC7-$EFBB)
; ===========================================================================

; L_EDC7: Continuation from projectile spawn - jumped here when spawn aborted

L_EDC7:
    ldy  $02                    ; Restore Y register
    lda  #$FF                   ; Set value to $FF
    bmi  L_EDC3                 ; Always taken - jump back to projectile setup

; D_EDCD: Update entity position - main entity update routine
; Called from multiple places to update entity state
; X register holds entity index
D_EDCD:
    lda  D_8818,x               ; Load animation frame data
    bpl  L_EE49                 ; If positive, skip attack logic
    
    ; Check attack timer
    lda  D_8890,x               ; Load attack cooldown timer
    beq  L_EDDC                 ; If zero, check if can attack
    dec  D_8890,x               ; Decrement cooldown
    bne  L_EE49                 ; If not zero yet, skip attack logic
    
; Check if entity can attack player
L_EDDC:
    lda  D_87A0,x               ; Load collision state
    bpl  L_EE49                 ; If positive, can't attack
    lda  D_87F0,x               ; Load vertical collision flags
    bpl  L_EE49                 ; If positive, can't attack
    
    ; Use RNG to add randomness to attack (25% chance)
    jsr  D_E9EA                 ; Get random number
    and  #$03                   ; Keep only bits 0-1 (0-3 range)
    bne  L_EE49                 ; If not zero (75% chance), skip attack
    
    ; Compare entity X position with player X position
    ldy  OPPTR                  ; $4B - Player index pointer
    lda  FA,x                   ; Load entity X position
    sbc  a:FA,y                 ; Subtract player X position (carry already clear from AND)
    bcs  L_EE07                 ; If entity >= player, check right side
    
    ; Entity is to the left of player
    lda  D_8520,x               ; Load animation frame
    cmp  D_8750,x               ; Compare with frame limit
    bcs  L_EE49                 ; If frame >= limit, facing wrong way
    
    ; Check if entity at right edge
    lda  FA,x                   ; Load X position
    cmp  #$F4                   ; At right edge?
    bcs  L_EE49                 ; If yes, can't attack
    sec                         ; Set carry for next check
    bcs  L_EE15                 ; Always taken - check Y position
    
; Entity is to the right of player
L_EE07:
    lda  D_8520,x               ; Load animation frame
    cmp  D_8750,x               ; Compare with frame limit
    bcc  L_EE49                 ; If frame < limit, facing wrong way
    
    ; Check if entity at left edge
    lda  FA,x                   ; Load X position
    cmp  #$34                   ; At left boundary?
    bcc  L_EE49                 ; If yes, can't attack
    
; Check Y position - entity must be at or above player
L_EE15:
    lda  ZP_C2,x                ; Load entity Y position
    sbc  a:ZP_C2,y              ; Subtract player Y position
    bcc  L_EE49                 ; If entity below player, can't attack
    beq  L_EE25                 ; If equal Y, skip RNG check
    
    ; Add more randomness if Y positions differ (3.125% chance)
    jsr  D_E9EA                 ; Get random number
    and  #$1F                   ; Keep bits 0-4 (0-31 range)
    bne  L_EE49                 ; If not zero, skip attack
    
; Find free projectile slot
L_EE25:
    ldy  #$0F                   ; Start at slot 15 (check slots 15-0)
    
L_EE27:
    lda  a:BLNON,y              ; Check projectile slot
    bmi  L_EE31                 ; If negative (free), use this slot
    dey                         ; Try previous slot
    bpl  L_EE27                 ; Loop if more slots to check
    bmi  L_EE49                 ; No free slots, exit
    
; Create attack projectile
L_EE31:
    lda  #$42                   ; Projectile type $42
    sta  a:BLNON,y              ; Store in projectile slot
    tya                         ; Transfer slot index to A
    sta  D_87A0,x               ; Store in entity collision state
    lda  #$07                   ; Attack animation frame count
    sta  D_8818,x               ; Store in animation data
    lda  #$96                   ; Cooldown timer (150 frames)
    sta  D_8890,x               ; Store in attack timer
    lda  #$09                   ; Projectile state value
    sta  D_A9FC,y               ; Store in projectile state array
    
; L_EE49: Exit point for attack logic
L_EE49:
    rts

; D_EE4A: State handler - simple animation toggle
; Flips animation frame between 0 and 1 every 2 calls
D_EE4A:
    inc  D_8610,x               ; Increment animation counter
    lda  D_8610,x               ; Load counter
    cmp  #$02                   ; Reached 2?
    bcc  L_EE61                 ; If not, return
    
    ; Reset counter and toggle frame
    lda  #$00
    sta  D_8610,x               ; Reset counter to 0
    lda  D_8520,x               ; Load current frame
    eor  #$01                   ; Toggle bit 0 (0<->1)
    sta  D_8520,x               ; Store new frame
    
L_EE61:
    rts

; D_EE62: Jump handler - player Y-position comparison for AI
; Compares player Y with entity Y and sets entity state flags
D_EE62:
    ldy  OPPTR                  ; $4B - Player index pointer
    lda  a:ZP_C2,y              ; Load player Y position
    cmp  ZP_C2,x                ; Compare with entity Y
    beq  L_EE7E                 ; If equal, set state 1
    bcc  L_EE91                 ; If player below entity, set state 2
    
    ; Player above entity - clear state flags
    lda  #$00
    sta  D_86D8,x               ; Clear collision data
    sta  D_8700,x               ; Clear movement state
    lda  D_85E8,x               ; Load entity state flags
    and  #$0B                   ; Keep only bits 0, 1, 3 (clear bits 2, 4-7)
    sta  D_85E8,x               ; Store updated flags
    rts
    
; Player at same Y as entity
L_EE7E:
    lda  #$FF                   ; Set flag to $FF
    sta  D_86D8,x               ; Set collision data
    lda  #$00
    sta  D_8700,x               ; Clear movement state
    lda  D_85E8,x               ; Load entity state flags
    and  #$0B                   ; Keep only bits 0, 1, 3
    sta  D_85E8,x               ; Store updated flags
    
L_EE90:
    rts

; Player below entity - manage directional flags
L_EE91:
    dec  D_8660,x               ; Decrement direction timer
    bne  L_EE90                 ; If not zero, return
    
    ; Timer expired - toggle direction
    ldy  D_86B0,x               ; Load current direction index
    lda  #$FF
    sta  D_86D8,y               ; Set collision flag for current direction
    
    ; XOR with $28 to toggle between two direction states
    tya                         ; Transfer direction to A
    eor  #$28                   ; Toggle direction (0<->$28)
    tay                         ; Store back in Y
    
    lda  #$00
    sta  D_86D8,y               ; Clear collision flag for new direction
    
    ; Store new direction and reset timer
    tya
    sta  D_86B0,x               ; Store new direction index
    lda  D_8688,x               ; Load direction change interval
    sta  D_8660,x               ; Reset direction timer
    rts

; Unused entry point - sets $04 to $02 then continues
D_EEB2:
    lda  #$02                   ; Set value to 2
    
; Entity movement handler - D_EEB4
D_EEB4:
; Processes horizontal movement based on state flags
    sta  $04                    ; Store movement value in temp
    lda  D_85E8,x               ; Load entity state flags
    sta  $02                    ; Store in temp
    and  #$04                   ; Check bit 2 (trapped flag)
    beq  L_EEC5                 ; If clear, use normal movement
    
    ; Trapped between platforms - use inverted movement
    jsr  D_EF4C                 ; Handle inverted vertical movement
    jmp  D_EEC8                 ; Continue to position update
    
L_EEC5:
    jsr  D_EFA0                 ; Handle normal vertical movement
    
; D_EEC8: Position update after movement
D_EEC8:
    jsr  D_E9B8                 ; Convert entity position to screen coordinates
    
    ldy  #$BD                   ; Default value
    lda  $02                    ; Load state flags
    and  #$01                   ; Check bit 0 (direction flag)
    beq  L_EED9                 ; If clear, move right
    
    ; Move left
    jsr  D_EEDF                 ; Handle leftward movement
    jmp  L_EB0F                 ; Update animation
    
L_EED9:
    jsr  D_EF1E                 ; Handle rightward movement
    jmp  L_EB0F                 ; Update animation

; D_EEDF: Leftward movement handler
D_EEDF:
    lda  ZP_25                  ; Load player Y / level index
    cmp  #$04                   ; Compare with threshold
    bcs  D_EEEB                 ; If >= 4, check platforms
    
    ; Below threshold - force frame 4
    lda  #$04
    sta  D_8520,x               ; Set animation frame to 4
    rts
    
; Check platform cells for leftward movement - D_EEEB
D_EEEB:
    sty  D_EF15                 ; Store Y (self-modifying: changes RTS below to different opcode)
    lda  ZP_23                  ; Load level index
    bne  L_EF08                 ; If non-zero, move without checks
    
    ; Check cells to the left
    ldy  #$00                   ; Cell offset 0
    lda  (INPFLG),y             ; Check cell
    bmi  L_EF0D                 ; If solid, reverse direction
    
    ldy  #$28                   ; Cell offset $28
    lda  (INPFLG),y             ; Check cell
    bmi  L_EF0D                 ; If solid, reverse direction
    
    ldy  INDEX2                 ; Check terrain index
    beq  L_EF08                 ; If zero, move left
    
    ldy  #$50                   ; Cell offset $50
    lda  (INPFLG),y             ; Check cell
    bmi  L_EF0D                 ; If solid, reverse direction
    
; Move left 2 pixels
L_EF08:
    dec  FA,x                   ; Decrement X position
    dec  FA,x                   ; Decrement X position again
    rts
    
; Hit wall - reverse horizontal direction
L_EF0D:
    lda  D_85E8,x               ; Load entity state flags
    eor  #$03                   ; Toggle bits 0 and 1
    sta  D_85E8,x               ; Store updated flags
    
    ; D_EF15 - Self-modified by STY D_EF15 at entry to D_EEEB/L_EF2A:
    ;   Y=$60 (RTS): Just return after toggling D_85E8
    ;   Y=$BD (LDA abs,X): Fall through to also toggle D_8520
D_EF15:
    rts                         ; This byte gets modified

    ; Extended direction toggle - reached when D_EF15 is modified to LDA ($BD)
    ; When Y=$BD is stored at D_EF15, execution becomes:
    ;   LDA D_8520,X  (BD from D_EF15 + 20 85 from below)
    ;   EOR #$04
    ;   STA D_8520,X
    ;   RTS
    .byte $20, $85              ; Address low/high for LDA D_8520,X
    eor  #$04                   ; Toggle bit 2
    sta  D_8520,x               ; Store updated direction
    rts

; D_EF1E: Rightward movement handler
D_EF1E:
    lda  ZP_25                  ; Load player Y / level index
    cmp  #$04                   ; Compare with threshold
    bcc  L_EF2A                 ; If < 4, check platforms
    
    ; At or above threshold - force frame 0
    lda  #$00
    sta  D_8520,x               ; Set animation frame to 0
    rts
    
; Check platform cells for rightward movement
L_EF2A:
    sty  D_EF15                 ; Store Y (self-modifying: changes RTS)
    lda  ZP_23                  ; Load level index
    bne  L_EF47                 ; If non-zero, move without checks
    
    ; Check cells to the right
    ldy  #$03                   ; Cell offset 3
    lda  (INPFLG),y             ; Check cell
    bmi  L_EF0D                 ; If solid, reverse direction (reuse code)
    
    ldy  #$2B                   ; Cell offset $2B
    lda  (INPFLG),y             ; Check cell
    ; D_EF3B
    bmi  L_EF0D                 ; If solid, reverse direction
    
    ldy  INDEX2                 ; Check terrain index
    beq  L_EF47                 ; If zero, move right
    
    ldy  #$53                   ; Cell offset $53
    lda  (INPFLG),y             ; Check cell
    bmi  L_EF0D                 ; If solid, reverse direction
    
; Move right 2 pixels
L_EF47:
    inc  FA,x                   ; Increment X position
    inc  FA,x                   ; Increment X position again
    rts

; D_EF4C: Inverted vertical movement
; Used when entity trapped between platforms (bit 2 of state set)
D_EF4C:
    lda  $04                    ; Load movement value
    eor  #$FF                   ; Invert all bits
    sta  $04                    ; Store inverted value
    inc  $04                    ; Add 1 (two's complement negation)
    
    lda  INDEX2                 ; Check terrain index
    bne  L_EF98                 ; If non-zero, skip special checks
    
    ; Check for screen wrap at top
    lda  ZP_C2,x                ; Load Y position
    cmp  #$15                   ; At top boundary?
    bne  L_EF70                 ; If not, check platforms above
    
    ; At top - check if can wrap to bottom
    lda  FA,x                   ; Load X position
    sbc  #$13                   ; Subtract offset (carry clear from CMP)
    lsr                         ; Divide by 8
    lsr
    lsr
    tay                         ; Use as index
    lda  D_88C1,y               ; Check wrap permission table
    bmi  L_EF8F                 ; If negative, can't wrap - reverse
    
    ; Wrap to bottom
    lda  #$F5                   ; Bottom Y position
    sta  ZP_C2,x                ; Store new Y
    rts
    
; Check platforms above current position
L_EF70:
    lda  INPFLG                 ; Load cell pointer low
    sec
    sbc  #$28                   ; Subtract one row (40 bytes)
    sta  INPFLG                 ; Store back
    bcs  L_EF7B                 ; If no borrow, continue
    dec  TANSGN                 ; Decrement high byte
    
L_EF7B:
    ldy  #$01                   ; Cell offset 1
    
L_EF7D:
    lda  (INPFLG),y             ; Check cell above
    bmi  L_EF8F                 ; If solid, reverse direction
    iny                         ; Next cell
    lda  (INPFLG),y             ; Check next cell
    bmi  L_EF8F                 ; If solid, reverse direction
    lda  ZP_23                  ; Check level index
    beq  L_EF98                 ; If zero, continue movement
    iny                         ; Third cell
    lda  (INPFLG),y             ; Check third cell
    bpl  L_EF98                 ; If not solid, continue movement
    
; Hit ceiling or can't wrap - reverse vertical direction
L_EF8F:
    lda  D_85E8,x               ; Load entity state flags
    eor  #$0C                   ; Toggle bits 2 and 3
    sta  D_85E8,x               ; Store updated flags
    rts
    
; Apply vertical movement
L_EF98:
    lda  ZP_C2,x                ; Load Y position
    clc
    adc  $04                    ; Add movement offset
    sta  ZP_C2,x                ; Store new Y position
    rts

; Normal vertical movement handler - D_EFA0
; Used when entity not trapped
D_EFA0:
    lda  INDEX2                 ; Check terrain index
    bne  L_EF98                 ; If non-zero, apply movement directly
    
    ; Check for screen wrap at bottom
    lda  ZP_C2,x                ; Load Y position
    cmp  #$F5                   ; At bottom boundary?
    bcc  L_EFBC                 ; If not, check platforms below
    
    ; At bottom - check if can wrap to top
    lda  FA,x                   ; Load X position
    sbc  #$14                   ; Subtract offset (carry clear from CMP)
    lsr                         ; Divide by 8
    lsr
    lsr
    tay                         ; Use as index
    lda  D_8501,y               ; Check wrap permission table
    bmi  L_EF8F                 ; If negative, can't wrap - reverse
    
    ; Wrap to top
    lda  #$15                   ; Top Y position
    sta  ZP_C2,x                ; Store new Y
    rts

; End of entity AI section ($EFBC starts next section)

; ===========================================================================
; Part 4: Entity Physics Continuation & Title Screen Init ($EFBC-$F0ED)
; ===========================================================================

; L_EFBC - Platform collision check with Y offset $51
; Jumps to L_EF7D (earlier routine) for actual collision detection

L_EFBC:
    ldy  #$51                   ; Cell offset for platform check
    bne  L_EF7D                 ; Always branch to collision handler

; D_EFC0 - Main entity movement and animation update
; Called from entity update loop to handle physics and animation
D_EFC0:
    lda  #$01                   ; Set operation flag
    sta  $04                    ; Store in zero page
    lda  D_85E8,x               ; Load entity state flags
    sta  $02                    ; Save for later use
    and  #$04                   ; Check bit 2 (trapped flag)
    beq  L_EFD3                 ; If not trapped, use normal movement
    
    ; Trapped between platforms - use special handler
    jsr  D_EF4C                 ; Handle trapped movement
    jmp  D_EFD6                 ; Continue to horizontal movement

L_EFD3:
    ; Normal vertical movement
    jsr  D_EFA0                 ; Handle normal vertical movement

D_EFD6:
    ; Update entity position after vertical movement
    jsr  D_E9B8                 ; Update entity screen position
    
    ; Handle horizontal movement based on direction flag
    ldy  #$60                   ; Cell offset for horizontal check
    lda  $02                    ; Retrieve state flags
    and  #$01                   ; Check bit 0 (direction flag)
    beq  L_EFE7                 ; If 0 (right), move right
    
    ; Move left
    jsr  D_EEEB                 ; Left movement handler
    jmp  D_EFEA                 ; Continue to animation

L_EFE7:
    ; Move right
    jsr  L_EF2A                 ; Right movement handler

; D_EFEA: Freed state handler - update animation frame counter
D_EFEA:
    inc  D_8610,x               ; Increment animation counter
    lda  D_8610,x               ; Load counter
    cmp  #$02                   ; Check if 2 frames elapsed
    bcc  L_F004                 ; If less, skip frame update
    
    ; Reset counter and advance animation frame
    lda  #$00                   ; Reset counter
    sta  D_8610,x               ; Store counter
    inc  D_8520,x               ; Increment animation frame
    lda  D_8520,x               ; Load frame
    and  #$03                   ; Mask to 4 frames (0-3)
    sta  D_8520,x               ; Store masked frame

L_F004:
    rts                         ; Return


; ==============================================================================
; D_F005 - Title Screen Initialization
; ==============================================================================
; This routine sets up the title screen display:
; - Initializes sprites for title logo
; - Sets up VIC registers for display
; - Copies game state data
; - Displays credits text
; - Waits for player input (fire button)
; ==============================================================================

    ; D_F005 - Title Screen Initialization
D_F005:
.ifdef BBLAN
    jsr  bb_title               ; BB-LAN: a session ends here
.else
    jsr  D_A5A0                 ; Initialize title screen graphics
.endif
    
    ; Set up text display pointers
    ldx  #<title_screen_text    ; Text pointer low byte
    ldy  #>title_screen_text    ; Text pointer high byte
    jsr  display_text_string    ; Display text routine
    
    ; Initialize three sprites for title logo
    ldx  #$05                   ; Sprite 0 setup
    ldy  #$08
    jsr  D_A625                 ; Configure sprite
    
    ldx  #$03                   ; Sprite 1 setup
    ldy  #$0B
    jsr  D_A625                 ; Configure sprite
    
    ldx  #$01                   ; Sprite 2 setup
    ldy  #$0E
    jsr  D_A625                 ; Configure sprite
    
    ; Configure sprite positions and colors
    ldx  #$01                   ; Start with sprite 1
    ldy  #$02                   ; Y register for VIC offset
L_F028:
    lda  D_8570,x               ; Load sprite color
    sta  VIC_SPR0_COL,x         ; Set sprite color register
    lda  #$68                   ; X position = 104
    sta  VIC_SPR0_X,y           ; Set sprite X coordinate
    lda  D_A632,x               ; Load sprite Y position
    sta  VIC_SPR0_Y,y           ; Set sprite Y coordinate
    lda  #<__SPRITE_PTR_BASE__       ; Sprite data pointer (bank-relative)
    sta  D_53F8,x               ; Set screen pointer for sprite
    dey                         ; Previous VIC register
    dey                         ; (X/Y regs are 2 bytes apart)
    dex                         ; Previous sprite
    bpl  L_F028                 ; Loop for all sprites
    
    ; Enable sprites and set initial state
    stx  SUBFLG                 ; Store X (now $FF) in flag
    lda  #$03                   ; Enable sprites 0, 1
    sta  VIC_SPR_ENA            ; Write to sprite enable register
    
    ; Set up display pointers for text rendering
    lda  #$4F                   ; Text row pointer
    sta  DATLIN+1               ; Store in zero page
    lda  #$51                   ; Text column pointer
    sta  DATPTR                 ; Store in zero page
    sta  ROESSION               ; Also store in $BD
    
    inx                         ; X = 0 (was $FF)
    jsr  display_score_digits    ; Display text line
    
    ; Display second line of text
    lda  #$C7                   ; New row pointer
    sta  DATLIN+1               ; Update row
    jsr  display_score_digits   ; Display text line
    
    ; Display third line of text
    lda  #$3F                   ; New row pointer
    sta  DATLIN+1               ; Update row
    inc  DATPTR                 ; Increment column pointer
    jsr  display_score_digits   ; Display text line
    
    ; Update display and prepare game state
    jsr  clear_color_ram         ; Update screen display
    
    ; Copy game state data (10 bytes)
    ldx  #$09                   ; Counter for 10 bytes
L_F06D:
    lda  $6B,x                  ; Load from source
    sta  D_57D4,x               ; Store to destination
D_F073 = * + 1                   ; Self-modifying: operand byte modified externally
    lda  #$00                   ; Clear value
    sta  D_D8AF,x               ; Clear destination array
    dex                         ; Decrement counter
    bpl  L_F06D                 ; Loop until done
    
    ; Initialize game variables
    stx  D_5AFF                 ; Store $FF in flag
    inx                         ; X = 0
    stx  VARNAM                 ; Clear variable
    inx                         ; X = 1
    stx  D_8572                 ; Set game state flag
    inx                         ; X = 2

; Display player scores/stats loop
L_F085:
    lda  D_A637,x               ; Load pointer low byte
    sta  DATPTR                 ; Store in zero page
    ldy  D_A634,x               ; Load pointer high byte
    sty  DATLIN+1               ; Store in zero page
    
    lda  D_0409,x               ; Load score/stat value
    cmp  #$63                   ; Compare to 99
    bcc  L_F0AE                 ; If less, handle as number
    beq  L_F0A4                 ; If equal to 99, special case
    
    ; Value > 99: Copy 3-byte value
    ldy  #$02                   ; Copy 3 bytes
L_F09A:
    lda  a:ZP_75,y              ; Load from source
    sta  (DATLIN+1),y           ; Store via pointer
    dey                         ; Next byte
    bpl  L_F09A                 ; Loop for all 3 bytes
    bmi  L_F0BE                 ; Always branch to continue

L_F0A4:
    ; Value = 99: Display single "1"
    lda  #$01                   ; Value to display
    ldy  #$00                   ; Offset 0
    sta  (DATLIN+1),y           ; Store via pointer
    tya                         ; A = 0
    ldy  DATLIN+1               ; Load pointer high byte
    .byte $2C                   ; BIT absolute - skips next 2 bytes

L_F0AE:
    ; Value < 99: Convert and display number
    adc  #$01                   ; Add 1 to value
    iny                         ; Increment Y
    pha                         ; Save A
    stx  MEMSIZ+1               ; Save X register
    lda  D_8570,x               ; Load color value
    tax                         ; Move to X
    pla                         ; Restore A
    jsr  D_3266                 ; Display number routine
    ldx  MEMSIZ+1               ; Restore X register

L_F0BE:
    dex                         ; Next player/stat
    bpl  L_F085                 ; Loop for all players
    
    ; Initialize player state variables
    inx                         ; X = 0
    stx  ESSION+1               ; Clear player 1 state
    inx                         ; X = 1
    stx  ENESSION               ; Set player 2 state
    lda  #$0A                   ; Delay counter
    sta  D_8572                 ; Store counter

; Wait for input loop
L_F0CC:
    jsr  D_7EB3                 ; Read joystick/keyboard
    cmp  #$FE                   ; Check for fire button
    beq  L_F0E3                 ; Fire pressed - start game
    cmp  #$F7                   ; Check for special key
    beq  L_F0E1                 ; Special key - toggle mode
    
    jsr  D_E9EA                 ; Get random number (keep PRNG active)
    lda  #$FF                   ; Reset value
    sta  CIA1_PRB               ; Write to CIA port
    bne  L_F0CC                 ; Always branch - continue waiting

L_F0E1:
    ; Toggle number of players
    inc  ESSION+1               ; Increment player count

L_F0E3:
    ; Start game
.ifdef BBLAN
    jsr  bb_game_start          ; BB-LAN: same start state + both incs below
    BB_PATCH_END L_F0E3, 5
.else
    inc  SUBFLG                 ; Set game start flag
    inc  D_5AFF                 ; Set active flag
.endif
    jsr  D_08E4                 ; Initialize game
    jmp  D_F005                 ; Return to title (or continue)
