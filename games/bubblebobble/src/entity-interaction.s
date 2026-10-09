; ============================================================================
; ENTITY INTERACTION AND PLAYER STATE HANDLERS ($2162 - $26BE)
; ============================================================================
; This section handles bubble capture, bubble physics, player movement in
; bubbles, and entity state transitions.
;
; Key routines:
;   D_2162 - Main bubble/entity interaction check
;   D_220C - Player input dispatch (movement bits)
;   D_222B - Initialize bubble capture state
;   D_226B - Move left in bubble
;   D_22C3 - Move right in bubble
;   D_22E8 - Bubble release timer/animation
;   D_2301 - Continue bubble animation update
;   D_23EA - Bubble ascent (captured enemy rising)
;   D_2483 - Horizontal bubble movement
;   D_2519 - Bubble reached top - check for pop
;   D_257C - Bubble vertical movement (ascending)
;   D_25F1 - Animation frame update
;   L_25E2 - Animation counter increment
;
; Zero-page variables used:
;   $02 - Temp: entity flags
;   $04 - Movement delta
;   $10 - Current level number
;   $11 - Level data pointer (low)
;   $23 - Two-player mode flag
;   $24 - Player index (0 or 1)
;   $25 - Level type/variant
;   $B1 - Bubble count
;   $BA,x - Entity X position
;   $C2,x - Entity Y position
;   $CA,y - Entity type array
;   $DC,y - Entity screen column
;   $EE,y - Entity screen row
;
; Entity arrays:
;   $8520,x - Animation frame
;   $8610,x - Animation timer
;   $8818,x - Bubble timer
;   $8840,x - Horizontal movement direction (left)
;   $8868,x - Horizontal movement direction (right)
;   $87A0,x - Bubble capture state
;   $87C8,x - Bubble vertical state
;   $87F0,x - Bubble ascent state
;   $AA0C,y - Captured entity X position
;   $AA1E,y - Captured entity Y position
;   $ACCB,x - Saved animation frame
;   $ACCD,y - Vertical movement table
; ============================================================================

.segment "CODE_PHYSICS"

; --- Main bubble/entity interaction check ---
; Called to check if an entity should capture an enemy in a bubble
; Input: X = entity index
D_2162:
        ldy     D_8818,x                ; Get bubble timer
        bmi     L216A                   ; If negative, check for capture
        jsr     D_2301                  ; Continue bubble animation
L216A:
        lda     D_87A0,x                ; Get bubble capture state
        bmi     L2171                   ; If captured, check state
        bne     L21BD                   ; If non-zero, skip
L2171:
        lda     D_85E8,x                ; Get entity flags
        sta     ZP_02                   ; Save to temp
        and     #$01                    ; Check bit 0
        bne     L21BD                   ; If set, no interaction
        ldy     #$11                    ; Check all 18 entities
L217C:
        lda     PESSION,y               ; Get entity type
        beq     L21BA                   ; If empty, skip
        cmp     #$24                    ; Compare to type $24
        bcs     L21BA                   ; If >= $24, skip
        cmp     #$16                    ; Compare to bubble type
        beq     L21BA                   ; If bubble, skip
        lda     D_AA0C,y                ; Get entity X position
        sec
        sbc     FA,x                    ; Subtract our X
        bcs     L2195                   ; If positive, skip negate
        eor     #$FF                    ; Negate (absolute value)
        adc     #$01
L2195:
        cmp     #$0E                    ; Check X distance
        bcs     L21BA                   ; If too far, skip
        lda     D_AA1E,y                ; Get entity Y position
        sec
        sbc     ZP_C2,x                 ; Subtract our Y
        cmp     #$14                    ; Check Y distance
        bcs     L21BA                   ; If too far, skip
        jsr     D_7C21                  ; Call collision handler
        lda     #$FF                    ; Mark as captured
        sta     D_87A0,x                ; Set capture state
        sta     D_87C8,x                ; Set vertical state
        sta     D_87F0,x                ; Set ascent state
        lda     ZP_C2,x                 ; Get Y position
        ora     #$01                    ; Set low bit
        sta     ZP_C2,x                 ; Store back
        jmp     D_222B                  ; Initialize capture

L21BA:
        dey                             ; Next entity
        bpl     L217C                   ; Loop if more
L21BD:
        lda     D_87A0,x                ; Get capture state
        bmi     L21C5                   ; If captured, handle it
        jmp     D_23EA                  ; Otherwise, handle ascent

L21C5:
        lda     D_87F0,x                ; Get ascent state
        bmi     L21CD                   ; If ascending, handle it
        jmp     D_257C                  ; Otherwise, vertical movement

L21CD:
        lda     INDEX2                  ; Get terrain index
        bne     L21EB                   ; If non-zero, skip platform check
        ldy     #$51                    ; Check platform at offset $51
        lda     (INPFLG),y              ; Read platform data
        bmi     L21EB                   ; If negative, blocked
        iny
        lda     (INPFLG),y              ; Check next byte
        bmi     L21EB                   ; If negative, blocked
        lda     ZP_23                   ; Get two-player flag
        beq     L21E5                   ; If single player, allow
        iny
        lda     (INPFLG),y              ; Check player 2 platform
        bmi     L21EB                   ; If negative, blocked
L21E5:
        inc     D_87F0,x                ; Increment ascent state
        jmp     D_257C                  ; Continue vertical movement

L21EB:
        lda     ZP_02                   ; Get saved flags
        and     #$1F                    ; Mask lower 5 bits
        cmp     #$1F                    ; Check if all set
        bne     D_220C                  ; If not, dispatch input
        lda     D_8818,x                ; Get bubble timer
        bpl     D_220C                  ; If positive, dispatch
        inc     D_8610,x                ; Increment animation timer
        lda     D_8610,x                ; Get timer value
        cmp     #$07                    ; Compare to 7
        bne     L222A                   ; If not 7, done
        jsr     D_2159                  ; Call animation handler
        lda     #$00                    ; Reset timer
        sta     D_8610,x
        beq     L222A                   ; Always branch (done)

; --- Player input dispatch ---
; Dispatches to movement handlers based on input bits
; Input: X = entity index, $02 = input flags
D_220C:
        lsr     ZP_02                   ; Shift bit 0 into carry
        bcs     L2213                   ; If set, skip capture init
        jmp     D_222B                  ; Initialize capture

L2213:
        lsr     ZP_02                   ; Shift next bit
        lsr     ZP_02                   ; And again
        bcs     L221C                   ; If set, skip left movement
        jsr     D_226B                  ; Move left in bubble
L221C:
        lsr     ZP_02                   ; Shift next bit
        bcs     L2223                   ; If set, skip right movement
        jsr     D_22C3                  ; Move right in bubble
L2223:
        lsr     ZP_02                   ; Shift next bit
        bcs     L222A                   ; If set, skip release
        jmp     D_22E8                  ; Handle bubble release

L222A:
        rts

; --- Initialize bubble capture state ---
; Sets up entity state when capturing an enemy in a bubble
; Input: X = entity index
D_222B:
        lda     #$0F                    ; Initial capture state
        sta     D_87A0,x                ; Set capture state
        ldy     #$00                    ; Default Y direction = 0
        lda     D_85E8,x                ; Get entity flags
        and     #$04                    ; Check direction bit
        bne     L2244                   ; If set, check right
        lda     ZP_25                   ; Get level variant
        cmp     #$04                    ; Check range
        bcc     L2244                   ; If < 4, check right
        cmp     #$08                    ; Check upper range
        bcs     L2244                   ; If >= 8, check right
        dey                             ; Y = $FF (move left)
L2244:
        tya                             ; Transfer Y to A
        sta     D_8840,x                ; Store left movement flag
        ldy     #$00                    ; Default right direction = 0
        lda     D_85E8,x                ; Get entity flags
        and     #$08                    ; Check direction bit
        bne     L2258                   ; If set, store
        lda     ZP_25                   ; Get level variant
        cmp     #$04                    ; Check range
        bcs     L2258                   ; If >= 4, store
        dey                             ; Y = $FF (move right)
L2258:
        tya                             ; Transfer Y to A
        sta     D_8868,x                ; Store right movement flag
        lda     D_8520,x                ; Get animation frame
        cmp     #$08                    ; Compare to 8
        bcs     L2268                   ; If >= 8, don't change
        ora     #$02                    ; Set bit 1
        sta     D_8520,x                ; Store new frame
L2268:
        inc     ZP_B1                   ; Increment bubble count
        rts

; --- Move left in bubble ---
; Handles leftward movement when player presses left in bubble
; Input: X = entity index
D_226B:
        lda     #$FE                    ; Movement delta = -2
        sta     ZP_04                   ; Store delta
        ldy     #$28                    ; Platform check offset (P1)
        lda     INDEX2                  ; Get terrain index
        beq     L2277                   ; If zero, check level
        ldy     #$50                    ; Platform check offset (P2)
L2277:
        lda     ZP_25                   ; Get level variant
        cmp     #$04                    ; Check type 4
        beq     L2294                   ; If type 4, handle timer
        cmp     #$05                    ; Check type 5
        beq     L2294                   ; If type 5, handle timer
        cmp     #$0A                    ; Check type 10
        beq     L22A6                   ; If type 10, check platform
        cmp     #$0B                    ; Check type 11
        beq     L22A6                   ; If type 11, check platform
        lda     D_8818,x                ; Get bubble timer
        bpl     L22C2                   ; If positive, done
        lda     #$04                    ; Set animation frame 4
        sta     D_8520,x
        rts

L2294:
        inc     D_8610,x                ; Increment animation timer
        lda     D_8610,x                ; Get timer
        cmp     #$04                    ; Compare to 4
        bcc     L22A6                   ; If < 4, check platform
        lda     #$00                    ; Reset timer
        sta     D_8610,x
        jsr     D_2159                  ; Call animation handler
L22A6:
        lda     ZP_C2,x                 ; Get Y position
        cmp     #$2D                    ; Compare to $2D
        bcc     L22B4                   ; If below, apply movement
        lda     ZP_23                   ; Get two-player flag
        bne     L22B4                   ; If two-player, apply
        lda     (INPFLG),y              ; Check platform
        bmi     L22C2                   ; If blocked, done
L22B4:
        lda     $63,x                   ; Get entity state
        beq     L22BB                   ; If zero, do move
        jsr     D_7C21                  ; Call collision handler
L22BB:
        lda     FA,x                    ; Get X position
        clc
        adc     ZP_04                   ; Add delta
        sta     FA,x                    ; Store new X
L22C2:
        rts

; --- Move right in bubble ---
; Handles rightward movement when player presses right in bubble
; Input: X = entity index
D_22C3:
        lda     #$02                    ; Movement delta = +2
        sta     ZP_04                   ; Store delta
        ldy     #$2B                    ; Platform check offset (P1)
        lda     INDEX2                  ; Get terrain index
        beq     L22CF                   ; If zero, check level
        ldy     #$53                    ; Platform check offset (P2)
L22CF:
        lda     ZP_25                   ; Get level variant
        cmp     #$02                    ; Check type 2
        bcc     L2294                   ; If < 2, handle timer (share code)
        cmp     #$08                    ; Check type 8
        beq     L22A6                   ; If type 8, check platform
        cmp     #$09                    ; Check type 9
        beq     L22A6                   ; If type 9, check platform
        lda     D_8818,x                ; Get bubble timer
        bpl     L22C2                   ; If positive, done
        lda     #$00                    ; Set animation frame 0
        sta     D_8520,x
        rts

; --- Bubble release timer/animation ---
; Handles the bubble release countdown and animation
; Input: X = entity index
D_22E8:
        lda     D_A824,x                ; Get release counter
        bne     L230D                   ; If non-zero, done
        lda     D_8818,x                ; Get bubble timer
        bpl     L230D                   ; If positive, done
        lda     #$06                    ; Set timer to 6
        sta     D_8818,x                ; Store timer
        lda     D_8520,x                ; Get animation frame
        and     #$04                    ; Mask direction bit
        lsr     a                       ; Shift right
        sta     D_ACCB,x                ; Save animation state
D_2300:
        rts

; --- Continue bubble animation update ---
; Updates bubble animation based on timer state
; Input: X = entity index, Y = timer value (from caller)
D_2301:
        bne     L230E                   ; If Y != 0, use table
        lda     D_ACCB,x                ; Get saved animation
        asl     a                       ; Shift left
        sta     D_8520,x                ; Store as frame
        dec     D_8818,x                ; Decrement timer
L230D:
        rts

L230E:
        lda     D_ACCB,x                ; Get saved animation
        clc
        adc     D_ACC4,y                ; Add table value
        sta     D_8520,x                ; Store as frame
        dec     D_8818,x                ; Decrement timer
        cpy     #$04                    ; Compare Y to 4
        bne     L230D                   ; If not 4, done
        ldy     #$11                    ; Check 18 entities
L2321:
        lda     PESSION,y               ; Get entity type
        bmi     L232A                   ; If negative (free), use it
        dey                             ; Next slot
        bpl     L2321                   ; Loop if more
L2329:
        rts                             ; No free slot

L232A:
        lda     FA,x                    ; Get our X position
        sta     D_AA0C,y                ; Store to captured X
        sec
        sbc     #$14                    ; Subtract $14
        pha                             ; Save
        and     #$06                    ; Mask to 0-6
        lsr     a                       ; Divide by 2
        sta     D_A9C4,y                ; Store sub-position
        pla                             ; Restore
        lsr     a                       ; Divide by 8
        lsr     a
        lsr     a
        sta     ZP_DC,y                 ; Store screen column
        lda     ZP_C2,x                 ; Get our Y position
        sta     D_AA1E,y                ; Store to captured Y
        sec
        sbc     #$15                    ; Subtract $15
        bcc     L2329                   ; If negative, abort
        pha                             ; Save
        and     #$06                    ; Mask to 0-6
        sta     D_A9D6,y                ; Store sub-position
        pla                             ; Restore
        lsr     a                       ; Divide by 8
        lsr     a
        lsr     a
        sta     ZP_EE,y                 ; Store screen row
        lda     #$16                    ; Bubble entity type
        sta     PESSION,y               ; Set entity type
        lda     #$7D                    ; Initial state
        sta     D_A9FA,y                ; Store state 1
        sta     D_A9E8,y                ; Store state 2
        lda     D_A77B,x                ; Get capture data
        sta     D_A824,x                ; Store release counter
        lda     D_A781,x                ; Get capture data
        sta     D_AA42,y                ; Store to captured entity
        lda     D_A77D,x                ; Get capture data
        sta     D_A9B2,y                ; Store to captured entity
        lda     D_A77F,x                ; Get capture data
        sta     D_AA30,y                ; Store to captured entity
        lda     D_8520,x                ; Get animation frame
        cmp     #$09                    ; Check if frame 9
        bne     L2397                   ; If not, skip adjustment
        lda     ZP_DC,y                 ; Get screen column
        clc
        adc     #$01                    ; Add 1
        sta     ZP_DC,y                 ; Store back
        lda     D_AA0C,y                ; Get captured X
        adc     #$08                    ; Add 8
        sta     D_AA0C,y                ; Store back
        lda     #$00                    ; Clear A
        .byte   $2C                     ; Skip next instruction (BIT abs)
L2397:
        lda     #$80                    ; Set high bit
        sta     D_0193,y                 ; Store player state
        lda     D_87A0,x                ; Get capture state
        bmi     L23B8                   ; If captured, check P2
        lda     INDEX2                  ; Get player index
        cmp     #$04                    ; Compare to 4
        bcc     L23B8                   ; If < 4, check P2
        lda     ZP_EE,y                 ; Get screen row
        clc
        adc     #$01                    ; Add 1
        sta     ZP_EE,y                 ; Store back
        lda     D_AA1E,y                ; Get captured Y
        adc     #$08                    ; Add 8
        sta     D_AA1E,y                ; Store back
L23B8:
        lda     D_A783,x                ; Get spawn counter
        bmi     L23D7                   ; If negative, check sound
        dec     D_A783,x                ; Decrement spawn counter
        lda     D_0193,y                 ; Get player state
        bmi     L23C8                   ; If negative, set zero
        lda     #$02                    ; Animation 2
        .byte   $2C                     ; Skip next instruction (BIT abs)
L23C8:
        lda     #$00                    ; Animation 0
        sta     D_A9C4,y                ; Store sub-position
        lda     #$00                    ; Clear
        sta     D_A9B2,y                ; Clear state
        lda     #$44                    ; Special bubble type
        sta     PESSION,y               ; Set entity type
L23D7:
        lda     $65,x                   ; Get sound flag
        beq     D_23DE                  ; If zero, skip sound
        jsr     D_7C21                  ; Call collision handler

; --- Set bubble sprite pointer based on player ---
D_23DE:
        lda     D_37C7,x                ; Get player sprite data
        bpl     L23E9                   ; If positive, done
        txa                             ; Transfer X to A
        ora     #$08                    ; Set bit 3
        sta     D_A9FA,y                ; Store to state
L23E9:
        rts

; --- Bubble ascent handler ---
; Handles vertical movement of captured enemy rising
; Input: X = entity index
D_23EA:
        beq     L2401                   ; If zero, ascent complete
        dec     D_87A0,x                ; Decrement capture state
        tay                             ; Transfer to Y
        lda     ZP_C2,x                 ; Get Y position
        sec
        sbc     D_ACCD,y                ; Subtract movement table value
        cmp     #$05                    ; Check if < 5
        bcs     L23FC                   ; If >= 5, store
        adc     #$F0                    ; Wrap around
L23FC:
        sta     ZP_C2,x                 ; Store new Y
        jmp     D_2483                  ; Continue horizontal movement

L2401:
        lda     D_87C8,x                ; Get vertical state
        bpl     L2423                   ; If positive, check pop
        lda     D_8520,x                ; Get animation frame
        cmp     #$02                    ; Check frame 2-3
        bcc     L241E                   ; If < 2, clear
        cmp     #$04                    ; Check frame 4-5
        bcc     L2419                   ; If < 4, fix animation
        cmp     #$06                    ; Check frame 6-7
        bcc     L241E                   ; If < 6, clear
        cmp     #$08                    ; Check frame >= 8
        bcs     L241E                   ; If >= 8, clear
L2419:
        and     #$05                    ; Keep bits 0 and 2
        sta     D_8520,x                ; Store fixed frame
L241E:
        lda     #$00                    ; Clear state
        sta     D_87C8,x                ; Store vertical state
L2423:
        cmp     #$10                    ; Check if state = $10
        bne     L242A                   ; If not, continue
        jmp     D_2519                  ; Handle bubble pop

L242A:
        inc     D_87C8,x                ; Increment vertical state
        tay                             ; Transfer to Y
        lda     ZP_C2,x                 ; Get Y position
        clc
        adc     D_ACCD,y                ; Add movement table value
        cmp     #$F5                    ; Check upper bound
        bcc     L243A                   ; If < $F5, store
        sbc     #$F0                    ; Wrap around
L243A:
        sta     ZP_C2,x                 ; Store new Y
        cmp     #$1F                    ; Check if >= $1F
        bcc     D_2483                  ; If < $1F, continue
        sec
        sbc     #$2D                    ; Subtract $2D
        and     #$07                    ; Mask to 0-7
        cmp     INDEX2                  ; Compare to terrain index
        bcs     D_2483                  ; If >=, continue
        jsr     D_E9B8                  ; Get sprite animation frame
        ldy     #$29                    ; Platform check offset
        lda     (INPFLG),y              ; Check platform
        bmi     L248D                   ; If blocked, check horizontal
        iny
        lda     (INPFLG),y              ; Check next byte
        bmi     L248D                   ; If blocked, check horizontal
        lda     ZP_23                   ; Get two-player flag
        beq     L2460                   ; If single player, check upper
        iny
        lda     (INPFLG),y              ; Check P2 platform
        bmi     L248D                   ; If blocked, check horizontal
L2460:
        ldy     #$51                    ; Upper platform offset
        lda     (INPFLG),y              ; Check upper platform
        bmi     L2474                   ; If blocked, snap to row
        iny
        lda     (INPFLG),y              ; Check next byte
        bmi     L2474                   ; If blocked, snap to row
        lda     ZP_23                   ; Get two-player flag
        beq     L248D                   ; If single player, continue
        iny
        lda     (INPFLG),y              ; Check P2 upper platform
        bpl     L248D                   ; If clear, continue
L2474:
        lda     ZP_C2,x                 ; Get Y position
        sec
        sbc     #$2D                    ; Subtract $2D
        and     #$F8                    ; Mask to row boundary
        clc
        adc     #$2D                    ; Add $2D back
        sta     ZP_C2,x                 ; Store snapped Y
        jmp     D_2519                  ; Handle bubble pop

; --- Horizontal bubble movement ---
; Handles left/right movement of bubble based on direction flags
; Input: X = entity index
D_2483:
        lda     FAC,x                   ; Get entity state ($61,x)
        beq     L248A                   ; If zero, skip
        jsr     D_7C21                  ; Call collision handler
L248A:
        jsr     D_E9B8                  ; Get sprite animation frame
L248D:
        lda     D_8840,x                ; Get left movement flag
        bpl     L24C5                   ; If positive, check right
        lda     FA,x                    ; Get X position
        cmp     #$25                    ; Check left boundary
        bcc     L24B5                   ; If < $25, stop
        ldy     #$28                    ; Platform check offset (P1)
        lda     INDEX2                  ; Get terrain index
        beq     L24A0                   ; If zero, check P1
        ldy     #$50                    ; Platform check offset (P2)
L24A0:
        lda     ZP_C2,x                 ; Get Y position
        cmp     #$2D                    ; Check Y threshold
        bcc     L24C0                   ; If below, do movement
        lda     ZP_23                   ; Get two-player flag
        bne     L24C0                   ; If two-player, do movement
        lda     (INPFLG),y              ; Check platform
        bpl     L24C0                   ; If clear, do movement
        iny
        lda     (INPFLG),y              ; Check next byte
        bmi     L24C0                   ; If blocked, do movement
        bpl     L24B9                   ; Always branch
L24B5:
        lda     #$24                    ; Set X to left boundary
        sta     FA,x
L24B9:
        lda     #$00                    ; Clear left flag
        sta     D_8840,x
        beq     L24FA                   ; Always branch
L24C0:
        dec     FA,x                    ; Decrement X position
        jmp     L24FA                   ; Continue

L24C5:
        lda     D_8868,x                ; Get right movement flag
        bpl     L24FA                   ; If positive, skip
        lda     FA,x                    ; Get X position
        cmp     #$F4                    ; Check right boundary
        bcs     L24ED                   ; If >= $F4, stop
        ldy     #$2B                    ; Platform check offset (P1)
        lda     INDEX2                  ; Get terrain index
        beq     L24D8                   ; If zero, check P1
        ldy     #$53                    ; Platform check offset (P2)
L24D8:
        lda     ZP_C2,x                 ; Get Y position
        cmp     #$2D                    ; Check Y threshold
        bcc     L24F8                   ; If below, do movement
        lda     ZP_23                   ; Get two-player flag
        bne     L24F8                   ; If two-player, do movement
        lda     (INPFLG),y              ; Check platform
        bpl     L24F8                   ; If clear, do movement
        dey
        lda     (INPFLG),y              ; Check previous byte
        bmi     L24F8                   ; If blocked, do movement
        bpl     L24F1                   ; Always branch
L24ED:
        lda     #$F4                    ; Set X to right boundary
        sta     FA,x
L24F1:
        lda     #$00                    ; Clear right flag
        sta     D_8868,x
        beq     L24FA                   ; Always branch
L24F8:
        inc     FA,x                    ; Increment X position

L24FA:
        inc     D_8610,x                ; Increment animation timer
        lda     D_8610,x                ; Get timer
        cmp     #$02                    ; Compare to 2
        bcc     L2518                   ; If < 2, done
        lda     #$00                    ; Reset timer
        sta     D_8610,x
        lda     D_8520,x                ; Get animation frame
        cmp     #$08                    ; Compare to 8
        bcs     L2518                   ; If >= 8, done
        eor     #$01                    ; Toggle bit 0
        sta     D_8520,x                ; Store new frame
        jmp     D_25F1                  ; Update animation

L2518:
        rts

; --- Bubble reached top - check for pop ---
; Handles bubble at top of screen, may pop or continue
; Input: X = entity index
D_2519:
        lda     #$FF                    ; Mark state
        sta     D_87A0,x                ; Set capture state
        sta     D_87C8,x                ; Set vertical state
        lda     D_8520,x                ; Get animation frame
        cmp     #$04                    ; Check frame range
        bcc     L2538                   ; If < 4, adjust X up
        cmp     #$08                    ; Check frame range
        bcc     L2530                   ; If < 8, adjust X down
        cmp     #$0A                    ; Check frame range
        bcs     L2538                   ; If >= 10, adjust X up
L2530:
        lda     FA,x                    ; Get X position
        and     #$FE                    ; Clear low bit
        sta     FA,x                    ; Store back
        bne     L2541                   ; Continue if non-zero
L2538:
        lda     FA,x                    ; Get X position
        clc
        adc     #$01                    ; Add 1
        and     #$FE                    ; Clear low bit
        sta     FA,x                    ; Store back
L2541:
        ldy     #$29                    ; Platform check offset
        lda     (INPFLG),y              ; Check platform
        bmi     L2569                   ; If blocked, check special
        iny
        lda     (INPFLG),y              ; Check next byte
        bmi     L2569                   ; If blocked, check special
        lda     ZP_23                   ; Get two-player flag
        beq     L2555                   ; If single player, check upper
        iny
        lda     (INPFLG),y              ; Check P2 platform
        bmi     L2569                   ; If blocked, check special
L2555:
        ldy     #$51                    ; Upper platform offset
        lda     (INPFLG),y              ; Check upper platform
        bmi     L257B                   ; If blocked, done
        iny
        lda     (INPFLG),y              ; Check next byte
        bmi     L257B                   ; If blocked, done
        lda     ZP_23                   ; Get two-player flag
        beq     L2569                   ; If single player, check special
        iny
        lda     (INPFLG),y              ; Check P2 upper platform
        bmi     L257B                   ; If blocked, done
L2569:
        lda     SUBFLG                  ; Get current level
        cmp     #$5B                    ; Check if level 91
        bne     L2575                   ; If not, pop bubble
        lda     ZP_C2,x                 ; Get Y position
        cmp     #$DD                    ; Check Y threshold
        beq     L257B                   ; If at threshold, done
L2575:
        inc     D_87F0,x                ; Increment ascent state
        jmp     D_EB3F                  ; Handle bubble pop

L257B:
        rts

; --- Bubble vertical movement (ascending) ---
; Handles upward movement of bubble
; Input: X = entity index
D_257C:
        lda     ZP_C2,x                 ; Get Y position
        clc
        adc     #$02                    ; Add 2 (move up)
        sta     ZP_C2,x                 ; Store new Y
        cmp     #$F5                    ; Check upper bound
        bne     L258C                   ; If not at top, check ceiling
        lda     #$15                    ; Wrap to bottom
        sta     ZP_C2,x
        rts

L258C:
        cmp     #$26                    ; Check ceiling threshold
        bcc     L_25E2                  ; If below, continue animation
        sec
        sbc     #$2D                    ; Subtract $2D
        and     #$07                    ; Mask to 0-7
        bne     L_25E2                  ; If not aligned, continue
        ldy     #$51                    ; Platform check offset
        lda     (INPFLG),y              ; Check platform
        bmi     L_25E2                  ; If blocked, continue
        iny
        lda     (INPFLG),y              ; Check next byte
        bmi     L_25E2                  ; If blocked, continue
        lda     ZP_23                   ; Get two-player flag
        beq     L25AB                   ; If single player, check upper
        iny
        lda     (INPFLG),y              ; Check P2 platform
        bmi     L_25E2                  ; If blocked, continue
L25AB:
        ldy     #$79                    ; Upper boundary offset
        lda     (INPFLG),y              ; Check boundary
        bmi     L25BF                   ; If blocked, hit ceiling
        iny
        lda     (INPFLG),y              ; Check next byte
        bmi     L25BF                   ; If blocked, hit ceiling
        lda     ZP_23                   ; Get two-player flag
        beq     L_25E2                  ; If single player, continue
        iny
        lda     (INPFLG),y              ; Check P2 boundary
        bpl     L_25E2                  ; If clear, continue
L25BF:
        dec     D_87F0,x                ; Decrement ascent state
        lda     D_8520,x                ; Get animation frame
        cmp     #$04                    ; Check frame range
        bcc     L25D8                   ; If < 4, adjust X up
        cmp     #$08                    ; Check frame range
        bcc     L25D1                   ; If < 8, adjust X down
        cmp     #$0A                    ; Check frame range
        bcc     L25D8                   ; If < 10, adjust X up
L25D1:
        lda     FA,x                    ; Get X position
        and     #$FE                    ; Clear low bit
        sta     FA,x                    ; Store back
        rts

L25D8:
        lda     FA,x                    ; Get X position
        clc
        adc     #$01                    ; Add 1
        and     #$FE                    ; Clear low bit
        sta     FA,x                    ; Store back
        rts

; --- Animation counter increment ---
; Increments animation counter and updates frame
; Input: X = entity index
L_25E2:
        inc     D_8610,x                ; Increment animation timer
        lda     D_8610,x                ; Get timer
        cmp     #$02                    ; Compare to 2
        bcc     L263C                   ; If < 2, done
        lda     #$00                    ; Reset timer
        sta     D_8610,x

; --- Animation frame update ---
; Updates sprite animation and handles movement
; Input: X = entity index
D_25F1:
        jsr     D_E9B8                  ; Get sprite animation frame
        lda     D_85E8,x                ; Get entity flags
        and     #$10                    ; Check bit 4
        bne     L25FE                   ; If set, skip bubble release
        jsr     D_22E8                  ; Handle bubble release
L25FE:
        lda     D_85E8,x                ; Get entity flags
        and     #$04                    ; Check left direction
        bne     L263D                   ; If set, check right
        lda     ZP_25                   ; Get level variant
        cmp     #$04                    ; Check range
        bcc     L2613                   ; If < 4, move left
        cmp     #$08                    ; Check range
        bcc     L261E                   ; If < 8, skip
        cmp     #$0A                    ; Check range
        bcs     L261E                   ; If >= 10, skip
L2613:
        lda     D_8818,x                ; Get bubble timer
        bpl     L263C                   ; If positive, done
        lda     #$04                    ; Set animation frame 4
        sta     D_8520,x
        rts

L261E:
        lda     FA,x                    ; Get X position
        cmp     #$24                    ; Check left boundary
        beq     L263C                   ; If at boundary, done
        ldy     #$28                    ; Platform check offset (P1)
        lda     INDEX2                  ; Get terrain index
        beq     L2632                   ; If zero, check P1
        ldy     #$50                    ; Platform check offset (P2)
        lda     ZP_C2,x                 ; Get Y position
        cmp     #$2D                    ; Check Y threshold
        bcc     L263A                   ; If below, do movement
L2632:
        lda     ZP_23                   ; Get two-player flag
        bne     L263A                   ; If two-player, do movement
        lda     (INPFLG),y              ; Check platform
        bmi     L263C                   ; If blocked, done
L263A:
        dec     FA,x                    ; Decrement X position
L263C:
        rts

L263D:
        lda     D_85E8,x                ; Get entity flags
        and     #$08                    ; Check right direction
        bne     L263C                   ; If set, done
        lda     ZP_25                   ; Get level variant
        cmp     #$04                    ; Check range
        bcc     L265D                   ; If < 4, move right
        cmp     #$08                    ; Check type 8
        beq     L265D                   ; If type 8, move right
        cmp     #$09                    ; Check type 9
        beq     L265D                   ; If type 9, move right
        lda     D_8818,x                ; Get bubble timer
        bpl     L263C                   ; If positive, done
        lda     #$00                    ; Set animation frame 0
        sta     D_8520,x
        rts

L265D:
        lda     FA,x                    ; Get X position
        cmp     #$F4                    ; Check right boundary
        beq     L263C                   ; If at boundary, done
        ldy     #$2B                    ; Platform check offset (P1)
        lda     INDEX2                  ; Get terrain index
        beq     L2671                   ; If zero, check P1
        ldy     #$53                    ; Platform check offset (P2)
        lda     ZP_C2,x                 ; Get Y position
        cmp     #$2D                    ; Check Y threshold
        bcc     L2679                   ; If below, do movement
L2671:
        lda     ZP_23                   ; Get two-player flag
        bne     L2679                   ; If two-player, do movement
        lda     (INPFLG),y              ; Check platform
        bmi     L263C                   ; If blocked, done
L2679:
        inc     FA,x                    ; Increment X position
        rts

; --- Bubble wobble/animation timer ---
; Handles bubble wobble animation timing
; Input: X = entity index
L267B:
        dec     D_8818,x                ; Decrement bubble timer
        bpl     L26BF                   ; If positive, jump to end
        lda     #$03                    ; Reset timer to 3
        sta     D_8818,x
        lda     D_87C8,x                ; Get vertical state
        bmi     L269F                   ; If negative, increment
        dec     D_8868,x                ; Decrement right flag
        bne     L26BF                   ; If non-zero, jump to end
        jsr     D_E9EA                  ; Get random number
        and     #$07                    ; Mask to 0-7
        clc
        adc     #$01                    ; Add 1 (1-8)
        ora     #$80                    ; Set high bit
        sta     D_87C8,x                ; Store vertical state
        bne     L26BF                   ; Always branch
L269F:
        inc     D_8868,x                ; Increment right flag
        lda     D_8868,x                ; Get right flag
        ora     #$80                    ; Set high bit
        cmp     D_87C8,x                ; Compare to vertical state
        bcc     L26BF                   ; If less, jump to end
        beq     L26BF                   ; If equal, jump to end
        lda     FA,x                    ; Get X position
        and     #$FE                    ; Clear low bit
        sta     FA,x                    ; Store back
        lda     ZP_C2,x                 ; Get Y position
        ora     #$01                    ; Set low bit
        sta     ZP_C2,x                 ; Store back
        lda     #$0C                    ; Set entity state
        sta     ESSION,x                ; Store state
        rts

L26BF:  ; End of file - external continuation point
