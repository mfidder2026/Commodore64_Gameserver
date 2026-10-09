; ============================================================================
; SPECIAL ENEMY HANDLERS ($10D3 - $1318)
; ============================================================================
; This section handles special enemy types and behaviors:
;   - Baron Von Blubba (time-over boss, enemy type $44)
;   - Special items (enemy types $24-$33)
;   - Extended item routines
;
; Called from enemy_ai_update in bb-enemy-ai.s
; ============================================================================

.segment "CODE_ENEMY"

; ============================================================================
; BARON VON BLUBBA HANDLER ($10D3)
; ============================================================================
; Baron Von Blubba is the invincible ghost that appears when time runs out.
; Enemy type $44 triggers this handler.
;
; Movement:
;   - Moves horizontally toward the player who captured it
;   - $0193,X stores which player (0 or 1) captured this enemy
;   - Moves at 8 pixels per frame
;   - After 30 frames ($1E), transforms to type $38
;
; This boss cannot be defeated and will kill players on contact.
; ============================================================================

baron_von_blubba:
        jsr     toggle_enemy_direction  ; 20 2b 11 - Flip direction flag
baron_skip_toggle:                      ; $10D6 - Entry point for jump table (skips toggle)
        lda     D_0193,x                ; bd 93 01 - Which player captured?
        bmi     move_baron_left         ; 30 18    - Negative = move left
        
        ; Move Baron right (toward player)
        lda     D_AA0C,x                ; bd 0c aa - Get X position
        clc                             ; 18
        adc     #$08                    ; 69 08    - Move 8 pixels right
        sta     D_AA0C,x                ; 9d 0c aa
        inc     $dc,x                   ; f6 dc    - Increment move counter
        lda     $dc,x                   ; b5 dc
        cmp     #$1e                    ; c9 1e    - 30 frames elapsed?
        bne     baron_check_collision   ; d0 14    - Not yet

baron_transform:
        lda     #$38                    ; a9 38    - Transform to type $38
        sta     PESSION,x               ; 95 ca
baron_continue:
        jmp     L_0D4A                  ; 4c 4a 0d - Return to AI loop

move_baron_left:
        lda     D_AA0C,x                ; bd 0c aa - Get X position
        sec                             ; 38
        sbc     #$08                    ; e9 08    - Move 8 pixels left
        sta     D_AA0C,x                ; 9d 0c aa
        dec     $dc,x                   ; d6 dc    - Decrement move counter
        beq     baron_transform         ; f0 ec    - If zero, transform

baron_check_collision:
        lda     PESSION,x               ; b5 ca    - Get enemy type
        sta     DATLIN                  ; 85 3f    - Save current type
        stx     OLDTXT+1                ; 86 3e    - Save X register
        jsr     D_105B                  ; 20 5b 10 - Check bubble collision
        lda     PESSION,x               ; b5 ca    - Get enemy type again
        cmp     DATLIN                  ; c5 3f    - Did it change?
        beq     baron_continue          ; f0 e1    - No change, continue
        
        ; Enemy was captured in bubble
        sbc     #$17                    ; e9 17    - Calculate bubble slot
        lsr                             ; 4a       - Divide by 2
        sta     OLDTXT                  ; 85 3d    - Store bubble slot
        lda     D_AA30,x                ; bd 30 aa - Get bubble type
        ldx     OLDTXT                  ; a6 3d    - Get bubble slot
        sta     $b4,x                   ; 95 b4    - Store in bubble array
        jsr     D_1A6F                  ; 20 6f 1a - Award points
        ldx     OLDTXT+1                ; a6 3e    - Restore X
        lda     DATLIN                  ; a5 3f    - Restore enemy type
        sta     PESSION,x               ; 95 ca
        lda     #$02                    ; a9 02    - Set animation state
        sta     $b0                     ; 85 b0
        jmp     L_0D4A                  ; 4c 4a 0d

; ============================================================================
; TOGGLE_ENEMY_DIRECTION ($112B)
; ============================================================================
; Toggles the enemy's direction flag between 0 and 1.
; Used by Baron Von Blubba and other enemies.
;
; Input:  X = enemy slot (0-17)
; Output: D_A9C4,X toggled between 0 and 1
; ============================================================================

toggle_enemy_direction:
        lda     D_A9C4,x                ; bd c4 a9 - Get direction flag
        eor     #$01                    ; 49 01    - Toggle bit 0
        sta     D_A9C4,x                ; 9d c4 a9
        rts                             ; 60

; ============================================================================
; SPECIAL ITEM HANDLER ($1134)
; ============================================================================
; Handles special items (enemy types $24-$33) that fall from popped bubbles.
; These items include:
;   - Fruits (watermelon, apple, etc.) for points
;   - Power-ups (shoes for speed, etc.)
;   - Special bonuses
;
; This routine checks if items are within the visible play area and
; collects them when a player touches them.
; ============================================================================

special_item_handler:
        lda     ZP_BE                   ; a5 be    - Get game state
        cmp     #$09                    ; c9 09    - Is it state 9?
        beq     skip_item_check_far     ; f0 55    - Yes, skip (to $118F)
        
        ldx     #$11                    ; a2 11    - Check all 18 slots
check_item_loop:
        lda     PESSION,x               ; b5 ca    - Get enemy type
        cmp     #$26                    ; c9 26    - Is it type $26 (item)?
        bne     next_item               ; d0 36    - No, check next
        
        ; Calculate item screen position
        lda     $dc,x                   ; b5 dc    - Get item column
        asl                             ; 0a       - Multiply by 8
        asl                             ; 0a
        asl                             ; 0a
        adc     #$14                    ; 69 14    - Add offset (20 pixels)
        sta     DATLIN+1                ; 85 40    - Store X screen pos
        
        lda     $ee,x                   ; b5 ee    - Get item row
        asl                             ; 0a       - Multiply by 8
        asl                             ; 0a
        asl                             ; 0a
        adc     #$15                    ; 69 15    - Add offset (21 pixels)
        sec                             ; 38
        sbc     ZP_BD                   ; e5 bd    - Subtract viewport Y
        bcs     check_y_top             ; b0 04    - No underflow
        cmp     #$f8                    ; c9 f8    - Check if near top
        bcs     check_x_pos             ; b0 04    - Within range
check_y_top:
        cmp     #$38                    ; c9 38    - Check if below 56 pixels
        bcs     next_item               ; b0 19    - Too far down
        
check_x_pos:
        lda     DATLIN+1                ; a5 40    - Get X screen pos
        sec                             ; 38
        sbc     ZP_BC                   ; e5 bc    - Subtract viewport X
        bcs     check_x_left            ; b0 04    - No underflow
        cmp     #$f8                    ; c9 f8    - Check if near left
        bcs     collect_item            ; b0 04    - Within range
check_x_left:
        cmp     #$40                    ; c9 40    - Check if beyond 64 pixels
        bcs     next_item               ; b0 0a    - Too far right
        
collect_item:
        lda     #$3a                    ; a9 3a    - Set to collected type
        sta     PESSION,x               ; 95 ca
        sta     D_AA42,x                ; 9d 42 aa - Save original type
        dec     D_5BBF                  ; ce bf 5b - Decrement item counter

next_item:
        dex                             ; ca       - Next enemy slot
        bpl     check_item_loop         ; 10 c1    - Continue if >= 0
        
        ; Check if all items collected
        lda     D_5BBF                  ; ad bf 5b - Get item counter
        bpl     skip_item_check         ; 10 0e    - Still items left
        
        ; All items collected - trigger special event
        lda     ZP_BE                   ; a5 be    - Get current game state
        sta     D_119F                  ; 8d 9f 11 - Save it (self-mod target)
        lda     #$09                    ; a9 09    - Set state to 9
        sta     ZP_BE                   ; 85 be
        lda     #$82                    ; a9 82    - Reset counter to 130
        sta     D_5BBF                  ; 8d bf 5b
skip_item_check:
        rts                             ; 60       - Return ($118E)

; ============================================================================
; EXTENDED ITEM STATE HANDLER ($118F)
; ============================================================================
; Handles special item state 9 - controls sprite blinking and state reset.
; Called when all items have been collected.
; ============================================================================

skip_item_check_far:
        dec     D_5BBF                  ; Decrement counter
        bne     L11A3                   ; If not zero, continue blinking
        lda     #$28                    ; Reset counter to 40
        sta     D_5BBF
        lda     #$FF                    ; Set special flag
        sta     D_872A
        lda     #$00                    ; Clear game state
D_119F := * - 1                         ; SMC: operand byte
        sta     ZP_BE
        rts

L11A3:
        lda     D_5BBF                  ; Get counter
        cmp     #$11                    ; Compare to 17
        bcs     skip_item_check         ; If >= 17, return (branch to rts at $118E)
        and     #$01                    ; Check if odd
        bne     skip_item_check         ; If odd, return
        lda     VIC_SPR_ENA             ; Get sprite enable register
        eor     #$FC                    ; Toggle sprites 2-7
        sta     VIC_SPR_ENA             ; Store back (blink effect)
        rts

; ============================================================================
; FALLING ITEM HANDLER ($11B7)
; ============================================================================
; Handles items that fall after popping a bubble.
; Toggles vertical movement and checks for platform collision.
; ============================================================================

L11B7:
        lda     D_A9D6,x                ; Get vertical direction
        eor     #$04                    ; Toggle bit 2
        sta     D_A9D6,x                ; Store back
        beq     L11D2                   ; If zero, check platform
        inc     ZP_EE,x                 ; Increment row (fall down)
        lda     ZP_EE,x                 ; Get row
        cmp     #$1D                    ; At bottom?
        bcc     L11CF                   ; If not, continue
        dec     ZP_EE,x                 ; Undo increment
        lda     #$38                    ; Transform to type $38 (collected)
        sta     PESSION,x
L11CF:
        jmp     L_0D4A                  ; Return to AI loop

; --- Check platform collision for falling item ---
L11D2:
        jsr     D_7BFE                  ; Get screen position
        ldy     #$00                    ; Check tile above
        lda     (DATLIN+1),y            ; Get tile
        bmi     L11CF                   ; If solid, continue falling
        ldy     #$28                    ; Check tile below (40 bytes down)
        lda     (DATLIN+1),y            ; Get tile
        bpl     L11CF                   ; If not solid, continue falling
        lda     #$38                    ; Landed on platform
        sta     PESSION,x               ; Transform to collected type
        ldy     #$04                    ; Check for free spawn slot
L11E7:
        lda     D_A770,y                ; Get spawn slot
        bmi     L11F2                   ; If negative (free), use it
        dey                             ; Try next slot
        bpl     L11E7                   ; Loop if more
        jmp     L_0D4A                  ; No free slot, return

; --- Setup bounce path for item ($11F2) ---
L11F2:
        sty     smc_bounce_y+1          ; Self-mod: store Y for later
        lda     ZP_DC,x                 ; Get column
        sta     DATPTR1                 ; Store in temp
        lda     #$00                    ; Clear path length
        sta     INPPTR                  ; Path counter
        jsr     D_E9EA                  ; Random number
D_1200:
        and     #$0F                    ; Mask to 0-15
        sta     OLDLIN1                 ; Left path length
        jsr     D_E9EA                  ; Random number
        and     #$0F                    ; Mask to 0-15
        sta     OLDTXT                  ; Right path length
        clc
        adc     ZP_DC,x                 ; Add to column
        cmp     #$1E                    ; Check bounds (30)
        bcc     L1216                   ; If in bounds, continue
        lda     #$FF                    ; Out of bounds
        sta     OLDTXT                  ; Mark invalid
L1216:
        lda     #$FF                    ; Decrement pointer
        dec     DATLIN+1                ; Low byte
        cmp     DATLIN+1                ; Check for underflow
        bne     L1220
        dec     DATPTR                  ; High byte underflow
L1220:
        ldy     #$00                    ; Check tile
        inc     INPPTR                  ; Increment path counter
        lda     (DATLIN+1),y            ; Get tile
        bmi     L1234                   ; If solid, stop
        ldy     #$28                    ; Check 40 bytes ahead
        lda     (DATLIN+1),y            ; Get tile
        bpl     L1234                   ; If not solid, stop
        dec     DATPTR1                 ; Decrement column
        dec     OLDLIN1                 ; Decrement left counter
        bpl     L1216                   ; Loop if more
L1234:
        lda     OLDTXT                  ; Get right path length
        bmi     L125B                   ; If invalid, done
        lda     INPPTR                  ; Get path counter
        clc
        adc     DATLIN+1                ; Add to pointer
        sta     DATLIN+1
        bcc     L1243
        inc     DATPTR                  ; Handle carry
L1243:
        inc     DATLIN+1                ; Move right
        bne     L1249
        inc     DATPTR                  ; Handle overflow
L1249:
        ldy     #$01                    ; Check tile to right
        lda     (DATLIN+1),y            ; Get tile
        bmi     L125B                   ; If solid, done
        ldy     #$29                    ; Check diagonal
        lda     (DATLIN+1),y            ; Get tile
        bpl     L125B                   ; If not solid, done
        inc     INPPTR                  ; Increment path
        dec     OLDTXT                  ; Decrement right counter
        bpl     L1243                   ; Loop if more

L125B:
smc_bounce_y:                           ; Self-modifying code target
        ldy     #$00                    ; Operand modified at $11F2
        lda     DATPTR1                 ; Get final column
        sta     D_A761,y                ; Store bounce X target
        lda     ZP_EE,x                 ; Get row
        sta     D_A766,y                ; Store bounce Y target
        lda     INPPTR                  ; Get path length
        sta     D_A76B,y                ; Store bounce distance
        lda     #$06                    ; Set bounce type
        sta     D_A770,y
L1271:
        jmp     L_0D4A                  ; Return to AI loop

; ============================================================================
; HORIZONTAL TRACKING ENEMY ($1274)
; ============================================================================
; Enemy that tracks and moves toward a player horizontally.
; Checks which player to track based on $0193,x.
; ============================================================================

L1274:
        jsr     toggle_enemy_direction  ; Toggle direction
        ldy     D_0193,x                ; Get player tracking flag
        bpl     L1282                   ; If positive, track P1
        cmp     #$01                    ; Check if moving right
        bne     L1271                   ; If not, return
        beq     L1286                   ; If yes, do movement
L1282:
        cmp     #$00                    ; Check if moving left
        bne     L1271                   ; If not, return

; --- Move toward player ($1286) ---
L1286:
        lda     #$3A                    ; Default: collected type
L1288:                                  ; $1288 - Entry point for score handler
        sta     smc_collect_type+1      ; Self-mod: store type
        jsr     D_7BFE                  ; Get screen position
        ldy     D_0193,x                ; Get player tracking
        bpl     L129D                   ; If positive, check right
        ldy     #$4F                    ; Check left boundary (79)
        lda     (DATLIN+1),y            ; Get tile
        bmi     L12AB                   ; If solid, collect item
        dec     ZP_DC,x                 ; Move left
        bpl     L12A5                   ; If still positive, check collision
L129D:
        ldy     #$52                    ; Check right boundary (82)
        lda     (DATLIN+1),y            ; Get tile
        bmi     L12AB                   ; If solid, collect item
        inc     ZP_DC,x                 ; Move right
L12A5:
        jsr     L152B                   ; Check player collision
L12A8:
        jmp     L_0D4A                  ; Return to AI loop

; --- Item collected ---
L12AB:
smc_collect_type:                       ; Self-modifying code target
        lda     #$3A                    ; Operand modified at $1288
        sta     PESSION,x               ; Set collected type
        sta     D_AA42,x                ; Save type
        bne     L12A8                   ; Return (always branches)

; ============================================================================
; OSCILLATING ENEMY ($12B4)
; ============================================================================
; Enemy that oscillates back and forth, tracking player.
; Uses self-modifying code to alternate between RTS and JMP.
; Entry point from enemy AI jump table.
; ============================================================================

oscillating_enemy:                      ; $12B4 - Jump table entry point
        lda     #$60                    ; RTS opcode
        sta     L12A8                   ; Self-mod: change JMP to RTS
        jsr     L1286                   ; Do one movement (returns)
        lda     #$4C                    ; JMP opcode
        sta     L12A8                   ; Self-mod: restore JMP
        inc     D_A9C4,x                ; Increment animation counter
        lda     D_A9C4,x                ; Get counter
        and     #$03                    ; Mask to 0-3
        sta     D_A9C4,x                ; Store back
        lda     PESSION,x               ; Get enemy type
        cmp     #$3A                    ; Is it collected?
        bne     L12DE                   ; If not, continue
        lda     #$2C                    ; Change to type $2C
        sta     PESSION,x
        lda     D_0193,x                ; Get player tracking
        eor     #$80                    ; Toggle direction
        sta     D_0193,x
L12DE:
        lda     ZP_DC,x                 ; Get column
        cmp     D_AA0C,x                ; Compare to target X
        bne     L12F6                   ; If not at target, continue
        ldy     D_AA1E,x                ; Get target entity
        lda     #$64                    ; Set timer to 100
        sta     D_8890,y                ; Store in entity timer
        lda     #$FF                    ; Set capture flag
        sta     D_8818,y                ; Store in bubble timer
        lda     #$38                    ; Transform to collected
        sta     PESSION,x
L12F6:
        jmp     L_0D4A                  ; Return to AI loop

; ============================================================================
; VERTICALLY FALLING ENEMY ($12F9)
; ============================================================================
; Enemy that falls vertically and checks for collision.
; ============================================================================

.segment "CODE_ENEMY"

L12F9:
        inc     ZP_EE,x                 ; Move down one row
        jsr     L152B                   ; Check player collision
        bcc     L1304                   ; If no collision, continue
        lda     #$3A                    ; Collected type
        bne     L130C                   ; Store and return
L1304:
        lda     ZP_EE,x                 ; Get row
        cmp     #$1D                    ; At bottom (29)?
        bne     L12F6                   ; If not, return
        lda     #$38                    ; At bottom, transform
L130C:
        sta     PESSION,x               ; Store type
        ldy     D_AA0C,x                ; Get target X
        lda     #$FF                    ; Set capture flag
        sta     D_8818,y                ; Store in bubble timer
        jmp     L_0D4A                  ; Return to AI loop
