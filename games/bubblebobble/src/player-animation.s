; ============================================================================
; PLAYER ANIMATION AND MOVEMENT ($1E6C - $2161)
; ============================================================================
; This module handles:
; - Player sprite animation frame selection
; - Player walking/jumping state machine
; - Horizontal movement (left/right) with wall collision
; - Bubble shooting mechanics
; - Animation frame cycling
;
; ENTRY POINTS:
;   D_1E6C - Main player animation/state handler
;   D_1E87 - Player state dispatcher
;   D_1FEF - Turn around handler
;   D_214A - Animation frame update
;
; NOTE: There are 2 bytes at $1E6A-$1E6B ($FA $28) that precede this section
;       in the original binary, but they appear to be unused padding or dead code.
; ============================================================================

.segment "CODE_RENDER"

; ============================================================================
; D_1E6C: Main Player Animation Handler
; ============================================================================
; Called each frame to handle player sprite animation and state processing
; Input: X = player index (0 or 1)
; Modifies: Lots of game state
D_1E6C:
        jsr     D_E9B8                  ; 20 b8 e9     $1e6c - Get sprite animation frame
        lda     D_8520,x                ; bd 20 85     $1e6f - Get player direction
        sta     $25                     ; 85 25        $1e72 - Store temporarily
        lda     ENESSION,x              ; b5 b2        $1e74 - Get player state
        asl                             ; 0a           $1e76 - Multiply by 2 for table lookup
        tay                             ; a8           $1e77
        lda     D_1E3A,y                ; b9 3a 1e     $1e78 - Get handler address low
        sta     D_1E85                  ; 8d 85 1e     $1e7b - Self-modify jump target
        lda     D_1E3B,y                ; b9 3b 1e     $1e7e - Get handler address high
        sta     D_1E86                  ; 8d 86 1e     $1e81 - Self-modify jump target
D_1E84:
        .byte   $4c                     ; 4c           $1e84 - JMP opcode
D_1E85:
        .byte   $ff                     ; ff           $1e85 - Low byte (self-modified)
D_1E86:
        .byte   $ff                     ; ff           $1e86 - High byte (self-modified)

; ============================================================================
; D_1E87: Player State Dispatcher
; ============================================================================
; Routes to different handlers based on player state
; States: 4=captured, 5=freed, 9=special
D_1E87:
        cmp     #$04                    ; c9 04        $1e87 - State 4 (captured)?
        beq     L_1E9C                  ; f0 11        $1e89
        cmp     #$05                    ; c9 05        $1e8b - State 5 (freed)?
        beq     L_1E99                  ; f0 0a        $1e8d
        cmp     #$09                    ; c9 09        $1e8f - State 9 (special)?
        beq     L_1E96                  ; f0 03        $1e91
        jmp     L_EB0F                  ; 4c 0f eb     $1e93 - Default handler

L_1E96:
        jmp     D_EE4A                  ; 4c 4a ee     $1e96 - Special state handler

L_1E99:
        jmp     D_EFEA                  ; 4c ea ef     $1e99 - Freed state handler

L_1E9C:
        jmp     D_214A                  ; 4c 4a 21     $1e9c - Captured state (animate only)

; ============================================================================
; Bubble Shooting Handler
; ============================================================================
; Checks if player can shoot a bubble and spawns it
D_1E9F:
        lda     D_8890,x                ; bd 90 88     $1e9f - Get shooting cooldown timer
        beq     L_1EA9                  ; f0 05        $1ea2 - Timer expired, can shoot
        dec     D_8890,x                ; de 90 88     $1ea4 - Decrement cooldown
        bne     L_1EF6                  ; d0 4d        $1ea7 - Still cooling down, skip

L_1EA9:
        jsr     D_E9EA                  ; 20 ea e9     $1ea9 - Get random number
        cmp     #$0c                    ; c9 0c        $1eac - Random check (for AI?)
        bcs     L_1EF6                  ; b0 46        $1eae - Random fail, skip
        lda     D_87F0,x                ; bd f0 87     $1eb0 - Check player flag
        bpl     L_1EF6                  ; 10 41        $1eb3 - If positive, skip
        lda     D_8818,x                ; bd 18 88     $1eb5 - Check another flag
        bpl     L_1EF6                  ; 10 3c        $1eb8 - If positive, skip
        lda     ZP_C2,x                 ; b5 c2        $1eba - Get player Y position
        cmp     #$a8                    ; c9 a8        $1ebc - Check if too low
        bcs     L_1EF6                  ; b0 36        $1ebe - Too low, skip

        ; Find empty bubble slot
        ldy     #$0f                    ; a0 0f        $1ec0 - Start at slot 15
L_1EC2:
        lda     BLNON,y                 ; b9 cc 00     $1ec2 - Check enemy type array
        bmi     L_1ECC                  ; 30 05        $1ec5 - Found empty slot (negative)
        dey                             ; 88           $1ec7
        bpl     L_1EC2                  ; 10 f8        $1ec8 - Keep looking
        bmi     L_1EF6                  ; 30 2a        $1eca - No slots available

L_1ECC:
        ; Initialize bubble in found slot
        lda     #$32                    ; a9 32        $1ecc - Bubble type $32
        sta     BLNON,y                 ; 99 cc 00     $1ece - Set enemy type
        sta     D_AA44,y                ; 99 44 aa     $1ed1 - Set bubble data
        txa                             ; 8a           $1ed4 - Get player index
        sta     D_AA0E,y                ; 99 0e aa     $1ed5 - Store which player shot it

        ; Calculate bubble X position (player X - 12) / 8
        lda     FA,x                    ; b5 ba        $1ed8 - Get player X
        sec                             ; 38           $1eda
        sbc     #$0c                    ; e9 0c        $1edb - Subtract 12
        lsr                             ; 4a           $1edd - Divide by 8
        lsr                             ; 4a           $1ede
        lsr                             ; 4a           $1edf
        sta     a:ZP_DE,y               ; 99 de 00     $1ee0 - Store bubble column

        ; Calculate bubble Y position (player Y - 5) / 8
        lda     ZP_C2,x                 ; b5 c2        $1ee3 - Get player Y
        sec                             ; 38           $1ee5
        sbc     #$05                    ; e9 05        $1ee6 - Subtract 5
        lsr                             ; 4a           $1ee8 - Divide by 8
        lsr                             ; 4a           $1ee9
        lsr                             ; 4a           $1eea
        sta     a:ZP_F0,y               ; 99 f0 00     $1eeb - Store bubble row

        ; Set shooting cooldown
        lda     #$64                    ; a9 64        $1eee - 100 frames cooldown
        sta     D_8890,x                ; 9d 90 88     $1ef0 - Set shoot cooldown
        sta     D_8818,x                ; 9d 18 88     $1ef3 - Set another cooldown

L_1EF6:
        ; Continue with player state processing
        lda     D_85E8,x                ; bd e8 85     $1ef6 - Get joystick data
        sta     ZP_02                   ; 85 02        $1ef9 - Store in zero page
        lda     D_87F0,x                ; bd f0 87     $1efb - Check player flag
        bmi     L_1F03                  ; 30 03        $1efe - If negative, continue
        jmp     D_EB34                  ; 4c 34 eb     $1f00 - Jump to alternate handler

L_1F03:
        ; Check if on solid ground (wall collision check at 3 positions)
        ldy     #$51                    ; a0 51        $1f03 - Offset $51
        lda     (INPFLG),y              ; b1 11        $1f05 - Check terrain
        bmi     L_1F1D                  ; 30 14        $1f07 - Solid, player on ground
        iny                             ; c8           $1f09 - Next position
        lda     (INPFLG),y              ; b1 11        $1f0a - Check terrain
        bmi     L_1F1D                  ; 30 0f        $1f0c - Solid, player on ground
        lda     $23                     ; a5 23        $1f0e - Check another flag
        beq     L_1F17                  ; f0 05        $1f10 - If zero, change state
        iny                             ; c8           $1f12 - Third position
        lda     (INPFLG),y              ; b1 11        $1f13 - Check terrain
        bmi     L_1F1D                  ; 30 06        $1f15 - Solid, player on ground

L_1F17:
        ; Not on ground, change state
        inc     D_87F0,x                ; fe f0 87     $1f17 - Increment state flag
        jmp     D_EB34                  ; 4c 34 eb     $1f1a - Jump to alternate handler

L_1F1D:
        ; Player on ground, handle left/right input
        lsr     ZP_02                   ; 46 02        $1f1d - Shift joystick data
        bcc     L_1F24                  ; 90 03        $1f1f - Bit 0 clear, skip
        jsr     D_ED12                  ; 20 12 ed     $1f21 - Handle right input

L_1F24:
        lsr     ZP_02                   ; 46 02        $1f24 - Shift joystick data
        bcc     L_1F2B                  ; 90 03        $1f26 - Bit 1 clear, skip
        jsr     D_ED18                  ; 20 18 ed     $1f28 - Handle left input

L_1F2B:
        jmp     D_EE4A                  ; 4c 4a ee     $1f2b - Continue with state handler

; ============================================================================
; Jumping/Falling State Handler
; ============================================================================
D_1F2E:
        jsr     D_EE62                  ; 20 62 ee     $1f2e
        lda     D_87F0,x                ; bd f0 87     $1f31 - Check player flag
        bmi     L_1F39                  ; 30 03        $1f34 - If negative, continue
        jmp     D_EBB8                  ; 4c b8 eb     $1f36 - Jump to alternate handler

L_1F39:
        lda     D_87A0,x                ; Load collision state
        bmi     L_1F41                  ; 30 03        $1f3c - Branch taken (Y=$87 is negative)
        jmp     D_1FEF                  ; 4c ef 1f     $1f3e - Never executed

L_1F41:
        ; Check if player at top of screen
        lda     ZP_C2,x                 ; b5 c2        $1f41 - Get player Y position
        cmp     #$1f                    ; c9 1f        $1f43 - Compare to $1F
        bcc     L_1F5B                  ; 90 14        $1f45 - Below $1F, skip

        ; Check terrain at 3 positions
        ldy     #$51                    ; a0 51        $1f47 - Offset $51
        lda     (INPFLG),y              ; b1 11        $1f49 - Check terrain
        bmi     L_1F61                  ; 30 14        $1f4b - Solid terrain
        iny                             ; c8           $1f4d
        lda     (INPFLG),y              ; b1 11        $1f4e - Check terrain
        bmi     L_1F61                  ; 30 0f        $1f50 - Solid terrain
        lda     $23                     ; a5 23        $1f52 - Check flag
        beq     L_1F5B                  ; f0 05        $1f54 - If zero, change state
        iny                             ; c8           $1f56
        lda     (INPFLG),y              ; b1 11        $1f57 - Check terrain
        bmi     L_1F61                  ; 30 06        $1f59 - Solid terrain

L_1F5B:
        ; Not on solid ground
        inc     D_87F0,x                ; fe f0 87     $1f5b - Increment state
        jmp     D_EBB8                  ; 4c b8 eb     $1f5e - Jump to handler

L_1F61:
        ; On solid ground, check for bubble riding
        lda     D_8700,x                ; bd 00 87     $1f61 - Check bubble flag
        beq     L_1FB3                  ; f0 4d        $1f64 - Not on bubble, skip

        ; Complex bubble riding collision check
        lda     INPFLG                  ; a5 11        $1f66 - Get pointer low
        sec                             ; 38           $1f68
        sbc     #$a0                    ; e9 a0        $1f69 - Subtract $A0
        sta     ZP_04                   ; 85 04        $1f6b - Store in ZP
        lda     INPFLG+1                ; a5 12        $1f6d - Get pointer high
        sbc     #$00                    ; e9 00        $1f6f - With borrow
        sta     ZP_05                   ; 85 05        $1f71 - Store in ZP

        ; Check 4 positions around player for bubbles
        ldy     #$02                    ; a0 02        $1f73 - Offset 2
        lda     (ZP_04),y               ; b1 04        $1f75 - Check position
        bmi     L_1F7F                  ; 30 06        $1f77 - Found bubble
        ldy     #$2a                    ; a0 2a        $1f79 - Offset $2A
        lda     (ZP_04),y               ; b1 04        $1f7b - Check position
        bmi     L_1FA3                  ; 30 24        $1f7d - Found bubble

L_1F7F:
        ldy     #$2a                    ; a0 2a        $1f7f - Offset $2A
        lda     (ZP_04),y               ; b1 04        $1f81 - Check position
        bmi     L_1F8B                  ; 30 06        $1f83 - Found bubble
        ldy     #$52                    ; a0 52        $1f85 - Offset $52
        lda     (ZP_04),y               ; b1 04        $1f87 - Check position
        bmi     L_1FA3                  ; 30 18        $1f89 - Found bubble

L_1F8B:
        ldy     #$52                    ; a0 52        $1f8b - Offset $52
        lda     (ZP_04),y               ; b1 04        $1f8d - Check position
        bmi     L_1F97                  ; 30 06        $1f8f - Found bubble
        ldy     #$7a                    ; a0 7a        $1f91 - Offset $7A
        lda     (ZP_04),y               ; b1 04        $1f93 - Check position
        bmi     L_1FA3                  ; 30 0c        $1f95 - Found bubble

L_1F97:
        ldy     #$7a                    ; a0 7a        $1f97 - Offset $7A
        lda     (ZP_04),y               ; b1 04        $1f99 - Check position
        bmi     L_1FB3                  ; 30 16        $1f9b - Found bubble, continue riding
        ldy     #$a2                    ; a0 a2        $1f9d - Offset $A2
        lda     (ZP_04),y               ; b1 04        $1f9f - Check position
        bpl     L_1FB3                  ; 10 10        $1fa1 - No bubble, stop riding

L_1FA3:
        ; Fell off bubble
        lda     #$00                    ; a9 00        $1fa3
        sta     D_8840,x                ; 9d 40 88     $1fa5 - Clear flag
        sta     D_8868,x                ; 9d 68 88     $1fa8 - Clear flag
        lda     #$1f                    ; a9 1f        $1fab
        sta     D_87A0,x                ; 9d a0 87     $1fad - Set animation state
        jmp     D_1FEF                  ; 4c ef 1f     $1fb0 - Turn around

L_1FB3:
        ; Check for turning around randomly
        lda     D_86D8,x                ; bd d8 86     $1fb3 - Check turn flag
        beq     L_1FD3                  ; f0 1b        $1fb6 - Zero, skip turn check

        jsr     D_E9EA                  ; 20 ea e9     $1fb8 - Get random number
        cmp     #$1e                    ; c9 1e        $1fbb - Random threshold
        bcs     L_1FD3                  ; b0 14        $1fbd - Too high, don't turn

        ; Turn toward other player
        ldy     OPPTR                   ; a4 4b        $1fbf - Get other player index
        lda     a:FA,y                  ; b9 ba 00     $1fc1 - Get other player X
        cmp     FA,x                    ; d5 ba        $1fc4 - Compare to this player X
        bcs     L_1FCC                  ; b0 04        $1fc6 - Other player is right, face right
        lda     #$07                    ; a9 07        $1fc8 - Face left direction
        bne     L_1FCE                  ; d0 02        $1fca - Skip

L_1FCC:
        lda     #$03                    ; a9 03        $1fcc - Face right direction

L_1FCE:
        sta     $25                     ; 85 25        $1fce - Store direction
        sta     D_8520,x                ; 9d 20 85     $1fd0 - Set player direction

L_1FD3:
        ; Setup walking animation
        lda     #$00                    ; a9 00        $1fd3
        sta     D_8840,x                ; 9d 40 88     $1fd5 - Clear flag
        sta     D_8868,x                ; 9d 68 88     $1fd8 - Clear flag
        lda     $25                     ; a5 25        $1fdb - Get direction
        cmp     D_8750,x                ; dd 50 87     $1fdd - Compare to stored direction
        bcc     L_1FE7                  ; 90 05        $1fe0 - Less than, decrement first flag
        dec     D_8840,x                ; de 40 88     $1fe2 - Decrement (sets to $FF)
        bne     L_1FEA                  ; d0 03        $1fe5 - Skip second decrement

L_1FE7:
        dec     D_8868,x                ; de 68 88     $1fe7 - Decrement (sets to $FF)

L_1FEA:
        lda     #$0f                    ; a9 0f        $1fea - Animation state $0F
        sta     D_87A0,x                ; 9d a0 87     $1fec - Set animation state

; ============================================================================
; D_1FEF: Turn Around / Animation Handler
; ============================================================================
D_1FEF:
        beq     L_2037                  ; f0 46        $1fef - If A=0, jump ahead
        cmp     #$10                    ; c9 10        $1ff1 - Check if >= $10
        bcs     L_201E                  ; b0 29        $1ff3 - Yes, different handler
        tay                             ; a8           $1ff5 - Use as index

        ; Handle sprite direction for walking
        lda     D_8520,x                ; bd 20 85     $1ff6 - Get direction
        and     #$03                    ; 29 03        $1ff9 - Mask to 0-3
        cmp     #$02                    ; c9 02        $1ffb - Check if facing left
        bcc     L_2003                  ; 90 04        $1ffd - No, increment
        dec     D_8520,x                ; de 20 85     $1fff - Yes, decrement (turn)
        rts                             ; 60           $2002

L_2003:
        dec     D_87A0,x                ; Decrement collision state

        ; Check movement flags and apply vertical movement
        lda     D_8840,x                ; bd 40 88     $2006 - Check left/right flag
        ora     D_8868,x                ; 1d 68 88     $2009 - OR with other flag
        beq     L_2013                  ; f0 05        $200c - Both zero, skip Y adjustment
        dec     ZP_C2,x                 ; d6 c2        $200e - Move up 1 pixel
        jmp     D_20D7                  ; 4c d7 20     $2010 - Continue

L_2013:
        lda     ZP_C2,x                 ; b5 c2        $2013 - Get player Y
D_2015:
        sec                             ; 38           $2015
        sbc     D_ACDD,y                ; f9 dd ac     $2016 - Subtract from table
        sta     ZP_C2,x                 ; 95 c2        $2019 - Store new Y
        jmp     D_214A                  ; 4c 4a 21     $201b - Update animation frame

L_201E:
        dec     D_87A0,x                ; Decrement collision state
D_2021:
        and     #$03                    ; 29 03        $2021 - Mask animation state
        bne     L_2036                  ; d0 11        $2023 - Not zero, done

        ; Reached animation boundary, check direction
        lda     D_8520,x                ; bd 20 85     $2025 - Get direction
        cmp     D_8750,x                ; dd 50 87     $2028 - Compare to target
        bcs     L_2031                  ; b0 04        $202b - Greater/equal, face left
        lda     #$07                    ; a9 07        $202d - Face right
D_202F:
        bne     L_2033                  ; d0 02        $202f - Skip

L_2031:
        lda     #$03                    ; a9 03        $2031 - Face left

L_2033:
        sta     D_8520,x                ; 9d 20 85     $2033 - Set direction

L_2036:
        rts                             ; 60           $2036

; ============================================================================
; Animation State $10 Handler (Jumping)
; ============================================================================
L_2037:
        ldy     D_87C8,x                ; bc c8 87     $2037 - Get jump counter
        bpl     L_2042                  ; 10 06        $203a - Positive, continue
D_203C:
        lda     #$00                    ; a9 00        $203c - Reset to 0
        sta     D_87C8,x                ; 9d c8 87     $203e - Store jump counter
        tay                             ; a8           $2041 - Y = 0

L_2042:
        cpy     #$10                    ; c0 10        $2042 - Check if counter = 16
        bne     L_2049                  ; d0 03        $2044 - Not 16, continue
L_2046:
        jmp     D_20B0                  ; 4c b0 20     $2046 - Jump reached apex

L_2049:
        lda     D_8520,x                ; bd 20 85     $2049 - Get animation frame
        and     #$03                    ; 29 03        $204c - Mask to 0-3
        cmp     #$02                    ; c9 02        $204e - Check threshold
L_2050:
        bcs     L_2046                  ; b0 f4        $2050 - Branch back to JMP D_20B0

        ; Increment jump animation
        inc     D_87C8,x                ; fe c8 87     $2052 - Increment jump counter
        lda     D_8840,x                ; bd 40 88     $2055 - Check movement flag
L_2058:
        ora     D_8868,x                ; 1d 68 88     $2058 - OR with other flag
        beq     L_2068                  ; f0 0b        $205b - Both zero, skip to L_2068
        lda     ZP_C2,x                 ; b5 c2        $205d - Get player Y
        clc                             ; 18           $205f
        adc     D_ACED,y                ; 79 ed ac     $2060 - Add jump table value
        sta     ZP_C2,x                 ; 95 c2        $2063 - Store new Y
        jmp     L_2070                  ; 4c 70 20     $2065 - Continue
; Note: The disassembler incorrectly decoded $20 (high byte of JMP $2070) as a JSR opcode
; The actual bytes at $2065-$2067 are: 4c 70 20 (JMP $2070)
; Code falls through here from elsewhere or is unreachable
L_2068:
        lda     ZP_C2,x                 ; b5 c2        $2068 - Get Y position
        clc                             ; 18           $206a
        adc     D_ACDD,y                ; 79 dd ac     $206b - Add from table
        sta     ZP_C2,x                 ; 95 c2        $206e - Store Y

L_2070:
        ; Check if player landed
        cmp     #$1f                    ; c9 1f        $2070 - Y < $1F?
        bcc     D_20D7                  ; 90 63        $2072 - Yes, still in air

        ; Landing collision check
        sbc     #$15                    ; e9 15        $2074 - Subtract $15
        and     #$07                    ; 29 07        $2076 - Mask to 0-7
        cmp     INDEX2                  ; c5 24        $2078 - Compare to terrain
        bcs     D_20D7                  ; b0 5b        $207a - Not landed, continue

        ; Check terrain at landing position (3 checks)
        ldy     #$51                    ; a0 51        $207c
        lda     (INPFLG),y              ; b1 11        $207e - Check terrain
        bmi     D_20D7                  ; 30 55        $2080 - Solid, continue falling
        iny                             ; c8           $2082
        lda     (INPFLG),y              ; b1 11        $2083 - Check terrain
        bmi     D_20D7                  ; 30 50        $2085 - Solid, continue falling
        lda     $23                     ; a5 23        $2087 - Check flag
        beq     L_2090                  ; f0 05        $2089 - Zero, check more
        iny                             ; c8           $208b
        lda     (INPFLG),y              ; b1 11        $208c - Check terrain
        bmi     D_20D7                  ; 30 47        $208e - Solid, continue falling

L_2090:
        ldy     #$79                    ; a0 79        $2090 - Offset $79
        lda     (INPFLG),y              ; b1 11        $2092 - Check terrain
        bmi     L_20A4                  ; 30 0e        $2094 - Solid, snap to grid
        iny                             ; c8           $2096
        lda     (INPFLG),y              ; b1 11        $2097 - Check terrain
        bmi     L_20A4                  ; 30 09        $2099 - Solid, snap to grid
        lda     $23                     ; a5 23        $209b - Check flag
        beq     D_20D7                  ; f0 38        $209d - Zero, continue falling
        iny                             ; c8           $209f
D_20A0:
        lda     (INPFLG),y              ; b1 11        $20a0 - Check terrain
        bpl     D_20D7                  ; 10 33        $20a2 - Not solid, continue falling

L_20A4:
        ; Landed, snap Y to grid
        lda     ZP_C2,x                 ; b5 c2        $20a4 - Get player Y
        sec                             ; 38           $20a6
        sbc     #$2d                    ; e9 2d        $20a7 - Subtract $2D
        and     #$f8                    ; 29 f8        $20a9 - Snap to 8-pixel grid
        clc                             ; 18           $20ab
        adc     #$2d                    ; 69 2d        $20ac - Add back $2D
        sta     ZP_C2,x                 ; 95 c2        $20ae - Store snapped Y

D_20B0:
        ; Jump apex or landing, finalize direction
        lda     D_8520,x                ; bd 20 85     $20b0 - Get direction
        and     #$03                    ; 29 03        $20b3 - Mask to 0-3
        cmp     #$03                    ; c9 03        $20b5 - Check if = 3
        beq     L_20CC                  ; f0 13        $20b7 - Yes, change to 2
        cmp     #$02                    ; c9 02        $20b9 - Check if = 2
        bcs     L_20C8                  ; b0 0b        $20bb - Yes, increment
        lda     D_8520,x                ; bd 20 85     $20bd - Get direction again
D_20C0:
        and     #$04                    ; 29 04        $20c0 - Keep bit 2
        ora     #$02                    ; 09 02        $20c2 - Set bit 1
        sta     D_8520,x                ; 9d 20 85     $20c4 - Store new direction
        rts                             ; 60           $20c7

L_20C8:
        inc     D_8520,x                ; fe 20 85     $20c8 - Increment direction
        rts                             ; 60           $20cb

L_20CC:
        ; End of jump
        lda     #$ff                    ; a9 ff        $20cc
        sta     D_87A0,x                ; 9d a0 87     $20ce - Reset animation state
        sta     D_87C8,x                ; 9d c8 87     $20d1 - Reset jump counter
        jmp     D_214A                  ; 4c 4a 21     $20d4 - Update animation

; ============================================================================
; D_20D7: Horizontal Movement Handler
; ============================================================================
D_20D7:
        lda     D_8840,x                ; bd 40 88     $20d7 - Check left flag
        bpl     L_210E                  ; 10 32        $20da - Positive, check right

        ; Moving left
        lda     ZP_C2,x                 ; b5 c2        $20dc - Get player Y
        cmp     #$2d                    ; c9 2d        $20de - Check if above $2D
        bcc     L_2107                  ; 90 25        $20e0 - Below, skip terrain check
        lda     $23                     ; a5 23        $20e2 - Check flag
        bne     L_2107                  ; d0 21        $20e4 - Non-zero, skip terrain

        ; Check left wall collision (3 positions)
        ldy     #$00                    ; a0 00        $20e6
        lda     (INPFLG),y              ; b1 11        $20e8 - Check terrain
        bmi     L_20FC                  ; 30 10        $20ea - Solid wall
        ldy     #$28                    ; a0 28        $20ec
        lda     (INPFLG),y              ; b1 11        $20ee - Check terrain
        bmi     L_20FC                  ; 30 0a        $20f0 - Solid wall
        ldy     INDEX2                  ; a4 24        $20f2 - Get terrain index
        beq     L_2107                  ; f0 11        $20f4 - Zero, can move
        ldy     #$50                    ; a0 50        $20f6
        lda     (INPFLG),y              ; b1 11        $20f8 - Check terrain
        bpl     L_2107                  ; 10 0b        $20fa - Not solid, can move

L_20FC:
        ; Hit wall, reverse direction
        lda     #$00                    ; a9 00        $20fc
        sta     D_8840,x                ; 9d 40 88     $20fe - Clear left flag
        dec     D_8868,x                ; de 68 88     $2101 - Set right flag ($FF)
        jmp     D_213B                  ; 4c 3b 21     $2104 - Flip sprite direction

L_2107:
        ; Can move left
        dec     FA,x                    ; d6 ba        $2107 - Move left 2 pixels
        dec     FA,x                    ; d6 ba        $2109
        jmp     D_214A                  ; 4c 4a 21     $210b - Update animation

L_210E:
        ; Check right movement
        lda     D_8868,x                ; bd 68 88     $210e - Check right flag
        bpl     D_214A                  ; 10 37        $2111 - Positive, no movement

        ; Moving right
        lda     ZP_C2,x                 ; b5 c2        $2113 - Get player Y
        cmp     #$2d                    ; c9 2d        $2115 - Check if above $2D
        bcc     L_2146                  ; 90 2d        $2117 - Below, skip terrain check
        lda     $23                     ; a5 23        $2119 - Check flag
        bne     L_2146                  ; d0 29        $211b - Non-zero, skip terrain

        ; Check right wall collision (3 positions)
        ldy     #$03                    ; a0 03        $211d
        lda     (INPFLG),y              ; b1 11        $211f - Check terrain
        bmi     L_2133                  ; 30 10        $2121 - Solid wall
        ldy     #$2b                    ; a0 2b        $2123
        lda     (INPFLG),y              ; b1 11        $2125 - Check terrain
        bmi     L_2133                  ; 30 0a        $2127 - Solid wall
D_2129:
        ldy     INDEX2                  ; a4 24        $2129 - Get terrain index
        beq     L_2146                  ; f0 19        $212b - Zero, can move
        ldy     #$53                    ; a0 53        $212d
        lda     (INPFLG),y              ; b1 11        $212f - Check terrain
        bpl     L_2146                  ; 10 13        $2131 - Not solid, can move

L_2133:
        ; Hit wall, reverse direction
        lda     #$00                    ; a9 00        $2133
        sta     D_8868,x                ; 9d 68 88     $2135 - Clear right flag
        dec     D_8840,x                ; de 40 88     $2138 - Set left flag ($FF)

D_213B:
        ; Flip sprite direction
        lda     D_8520,x                ; bd 20 85     $213b - Get direction
        eor     #$04                    ; 49 04        $213e - Flip horizontal bit
        sta     D_8520,x                ; 9d 20 85     $2140 - Store new direction
        jmp     D_214A                  ; 4c 4a 21     $2143 - Update animation

L_2146:
        ; Can move right
        inc     FA,x                    ; f6 ba        $2146 - Move right 2 pixels
        inc     FA,x                    ; f6 ba        $2148

; ============================================================================
; D_214A: Animation Frame Update
; ============================================================================
; Cycles the animation frame for walking sprites
D_214A:
        inc     D_8610,x                ; fe 10 86     $214a - Increment animation counter
        lda     D_8610,x                ; bd 10 86     $214d - Get counter
        cmp     #$02                    ; c9 02        $2150 - Every 2 frames
        bcc     L_2161                  ; 90 0d        $2152 - Not yet, skip
        lda     #$00                    ; a9 00        $2154 - Reset counter
        sta     D_8610,x                ; 9d 10 86     $2156 - Store counter
D_2159:
        lda     D_8520,x                ; bd 20 85     $2159 - Get sprite frame
        eor     #$01                    ; 49 01        $215c - Toggle bit 0 (alternate frame)
        sta     D_8520,x                ; 9d 20 85     $215e - Store new frame

L_2161:
        rts                             ; 60           $2161

; ============================================================================
; Note: State Handler Jump Table D_1E3A is defined in bb-joystick-input.s
; ============================================================================

.segment "CODE_RENDER"
