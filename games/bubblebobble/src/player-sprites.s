; ============================================================================
; PLAYER SPRITE UPDATE ROUTINES ($1319 - $1577)
; ============================================================================
; This section handles updating player character sprites on screen, including:
;   - Drawing player sprite animations to screen memory
;   - Handling player-item collision detection  
;   - Managing enemy timers and state transitions
;   - Processing bubble spawn mechanics
;
; The player sprites are composed of multiple character cells that are drawn
; to screen memory each frame to create the animated player characters.
; ============================================================================

.segment "CODE_SPRITES"

; ============================================================================
; UPDATE_PLAYER_SPRITES ($1319)
; ============================================================================
; Main routine to update player character sprites on screen.
; Processes 5 player sprite slots (X = 4 down to 0).
;
; For each sprite slot:
;   - Checks if sprite is active (D_A770,X >= 0)
;   - Decrements animation timer every 4 frames
;   - Copies sprite character data to screen memory
;   - Handles both normal drawing and color RAM drawing
;
; Uses complex pointer arithmetic to calculate screen positions based on:
;   - D_A761,X: Column position
;   - D_A766,X: Row position  
;   - D_A76B,X: Sprite data index
;   - D_ACBD,Y: Character data pointer
; ============================================================================

update_player_sprites:
        ldx     #$04                    ; a2 04    - Process 5 sprites (4 down to 0)
sprite_update_loop:
        ldy     D_A770,x                ; bc 70 a7 - Get sprite active flag
        bmi     next_sprite             ; 30 4e    - Skip if negative (inactive)
        
        ; Decrement animation timer every 4 frames
        lda     D_597F                  ; ad 7f 59 - Get frame counter
        and     #$03                    ; 29 03    - Check low 2 bits
        bne     skip_timer_dec          ; d0 03    - Skip if not multiple of 4
        dec     D_A770,x                ; de 70 a7 - Decrement timer
        
skip_timer_dec:
        lda     D_A76B,x                ; bd 6b a7 - Get sprite data index
        sta     INPPTR                  ; 85 43    - Store in temp
        dec     INPPTR                  ; c6 43    - Decrement (height-1)
        lda     D_ACBD,y                ; b9 bd ac - Get character data
        sta     DATPTR+1                ; 85 42    - Store char data
        
        ; Calculate screen position
        ldy     D_A766,x                ; bc 66 a7 - Get row position
        lda     D_AD1E,y                ; b9 1e ad - Get screen row (low)
        clc                             ; 18
        adc     D_A761,x                ; 7d 61 a7 - Add column offset
        sta     DATLIN+1                ; 85 40    - Store screen address (low)
        lda     D_AD3D,y                ; b9 3d ad - Get screen row (high)
        adc     #$00                    ; 69 00    - Add carry
        sta     DATPTR                  ; 85 41    - Store screen address (high)
        
        ; Draw sprite characters
        ldy     INPPTR                  ; a4 43    - Get height counter
        lda     DATPTR+1                ; a5 42    - Get character data
        beq     use_color_ram           ; f0 0b    - If 0, use color RAM
        cmp     #$40                    ; c9 40    - Check if >= $40
        bcs     check_collision         ; b0 1f    - Yes, check for item collision
        
draw_chars:
        sta     (DATLIN+1),y            ; 91 40    - Write character to screen
        dey                             ; 88       - Next row
        bpl     draw_chars              ; 10 fb    - Loop while Y >= 0
        bmi     next_sprite             ; 30 14    - Done, next sprite

use_color_ram:
        lda     DATLIN+1                ; a5 40    - Get screen address (low)
        sta     DATPTR+1                ; 85 42    - Use as base for color
        lda     DATPTR                  ; a5 41    - Get screen address (high)
        and     #$03                    ; 29 03    - Mask to get page offset
        clc                             ; 18
        adc     #>__SCREEN_BACKUP__     ; 69 8b    - Convert to backup buffer page
        sta     INPPTR                  ; 85 43    - Store backup buffer high byte
        
copy_color:
        lda     (DATPTR+1),y            ; b1 42    - Read from screen
        sta     (DATLIN+1),y            ; 91 40    - Write to color RAM
        dey                             ; 88       - Next row
        bpl     copy_color              ; 10 f9    - Loop while Y >= 0

next_sprite:
        dex                             ; ca       - Next sprite slot
        bpl     sprite_update_loop      ; 10 aa    - Loop while X >= 0
        rts                             ; 60       - Done

; ============================================================================
; CHECK_COLLISION ($1372)
; ============================================================================
; Checks if player sprite collides with any active items (bubbles).
; Called when sprite character data is >= $40.
;
; Calculates sprite pixel position:
;   - X position: D_A761,X * 8 + $14
;   - Y position: D_A766,X * 8 + $15
;
; Then checks all 6 bubble slots ($b4-$b9) to see if any are within
; collision distance. If collision detected, awards points and decrements
; the item counter at D_8892,X.
; ============================================================================

check_collision:
        lda     D_A761,x                ; bd 61 a7 - Get column
        asl                             ; 0a       - Multiply by 8
        asl                             ; 0a
        asl                             ; 0a
        adc     #$14                    ; 69 14    - Add offset (20 pixels)
        sta     $44                     ; 85 44    - Store sprite X position
        
        lda     D_A766,x                ; bd 66 a7 - Get row
        asl                             ; 0a       - Multiply by 8
        asl                             ; 0a
        asl                             ; 0a
        adc     #$15                    ; 69 15    - Add offset (21 pixels)
        sta     VARNAM                  ; 85 45    - Store sprite Y position
        
        ldy     D_A76B,x                ; bc 6b a7 - Get sprite data index
        lda     D_0200,y                ; b9 00 02 - Load collision threshold
        sta     OLDTXT                  ; 85 3d    - Store threshold
        stx     OLDTXT+1                ; 86 3e    - Save X register
        
        ; Check all 6 bubble slots
        ldx     #$05                    ; a2 05    - 6 bubbles (5 down to 0)
check_bubble_loop:
        lda     $b4,x                   ; b5 b4    - Get bubble state
        beq     next_bubble             ; f0 1c    - Skip if inactive
        cmp     #$0b                    ; c9 0b    - Check if >= $0B
        bcs     next_bubble             ; b0 18    - Skip if special bubble
        
        ; Check Y distance
        lda     VARNAM                  ; a5 45    - Get sprite Y
        sec                             ; 38
        sbc     $c4,x                   ; f5 c4    - Subtract bubble Y
        cmp     #$10                    ; c9 10    - Within 16 pixels?
        bne     next_bubble             ; d0 0f    - No, skip
        
        ; Check X distance
        lda     $bc,x                   ; b5 bc    - Get bubble X
        sec                             ; 38
        sbc     $44                     ; e5 44    - Subtract sprite X
        cmp     OLDTXT                  ; c5 3d    - Compare to threshold
        bcs     next_bubble             ; b0 06    - Skip if too far
        
        ; Collision detected!
        jsr     D_1A6F                  ; 20 6f 1a - Award points
        dec     D_8892,x                ; de 92 88 - Decrement item counter

next_bubble:
        dex                             ; ca       - Next bubble
        bpl     check_bubble_loop       ; 10 dd    - Loop while X >= 0
        
        ; Resume drawing sprite
        ldy     INPPTR                  ; a4 43    - Restore height counter
        lda     DATPTR+1                ; a5 42    - Restore character data
        ldx     OLDTXT+1                ; a6 3e    - Restore X register
        jmp     draw_chars              ; 4c 53 13 - Continue drawing

; ============================================================================
; ENEMY_TIMER_HANDLER ($13BE - $1577)
; ============================================================================
; Handles enemy timers, state transitions, bubble capture release, and
; player collision detection.
; ============================================================================

.segment "CODE_SPRITES"

; External reference: L0D4A ($0D4A) defined in enemy-ai.s

enemy_timer_handler:                                    ; $13BE
D_13BE = enemy_timer_handler                            ; Alias for external references
        ldx     #$11                    ; Process all 18 entities
L13C0:                                                  ; $13C0
        dec     D_A9FA,x                ; Decrement timer
        bne     L1413                   ; Skip if not expired
        lda     $CA,x                   ; Get entity type
        cmp     #$04
        bne     L13D2
        sta     D_AA42,x                ; Store original type
        lda     #$3A                    ; Set to released state
        bne     L1406

L13D2:                                                  ; $13D2
        cmp     #$24
        bcs     L140B                   ; Skip if special type
        cmp     #$18
        bcc     L1443                   ; Skip if < $18
        ; Release captured enemy from bubble
        sbc     #$18
        lsr     a
        tay                             ; Y = bubble slot
        lda     D_5ABF                  ; Get bubble state
        sta     $B4,y
        lda     $C4,y
        ora     #$01
        sta     $C4,y
        lda     $BC,y
        and     #$FE
        sta     $BC,y
        lda     #$FF
        sta     D_872A,y
        lda     D_AA30,x
        sta     D_87A2,y
        lda     #$00
        sta     D_8522,y
        lda     #$38
L1406:                                                  ; $1406
        sta     $CA,x
        jmp     L1443

L140B:                                                  ; $140B
        cmp     #$42
        bne     L1443
        lda     #$FF
        bmi     L1406

L1413:                                                  ; $1413
        lda     D_A9FA,x
        cmp     #$11
        bcs     L1443
        and     #$01
        bne     L1443
        lda     $CA,x
        cmp     #$04
        beq     L1428
        cmp     #$48
        bne     L142E
L1428:                                                  ; $1428
        eor     #$4C                    ; Toggle between states
        sta     $CA,x
        bne     L1443

L142E:                                                  ; $142E
        cmp     #$24
        bcs     L1443
        cmp     #$18
        bcc     L1443
        sbc     #$18
        lsr     a
        tay
        lda     D_AB55,y                ; Sprite enable mask
        eor     VIC_SPR_ENA             ; Toggle sprite
        sta     VIC_SPR_ENA

L1443:                                                  ; $1443
        dex
        bmi     L1449
        jmp     L13C0

L1449:                                                  ; $1449
        ldx     #$11
        ldy     #$00
L144D:                                                  ; $144D
        lda     $CA,x
        cmp     #$34
        bcc     L1454
        iny                             ; Count captured enemies
L1454:                                                  ; $1454
        dex
        bpl     L144D
        tya
        cpy     #$02
        bcs     L146E                   ; Return if 2+ captured
        jsr     L145F                   ; Call twice if < 2

L145F:                                                  ; $145F
        ldx     #$11
L1461:                                                  ; $1461
        lda     $CA,x
        cmp     #$04
        bne     L146F
        sta     D_AA42,x
        lda     #$3A
        sta     $CA,x
L146E:                                                  ; $146E
        rts

L146F:                                                  ; $146F
        dex
        bpl     L1461
        rts

; -----------------------------------------------------------------------------
; Player death handler ($1473)
; -----------------------------------------------------------------------------
player_death_handler:                                   ; $1473
        lda     $B2,x
        cmp     #$0E                    ; Dying state?
        bne     L1496
L1479:                                                  ; $1479
        lda     #$3A
        sta     $CA,x
        sta     D_AA42,x
        txa
        eor     #$01
        tay                             ; Other player
        lda     $CA,y
        cmp     #$2E
        beq     L1493
        cmp     #$30
        beq     L1493
        lda     #$32
        sta     $2B
L1493:                                                  ; $1493
        jmp     L0D4A

; -----------------------------------------------------------------------------
; Enemy movement/collision ($1496)
; Contains self-modifying code at L1545/L1549
; -----------------------------------------------------------------------------
L1496:                                                  ; $1496
        dec     L1545
        inc     L1549
        jsr     L152B
        inc     L1545
        dec     L1549
        bcs     L1479
        lda     D_AA42,x
        and     #$7F
        bne     L14CB
        inc     D_AA30,x
        lda     D_AA30,x
        and     #$0F
        bne     L14BB
        dec     D_AA30,x
L14BB:                                                  ; $14BB
        lda     D_AA30,x
        eor     #$80
        sta     D_AA30,x
        sta     D_AA42,x
        lda     #$1E
        sta     D_A775,x
L14CB:                                                  ; $14CB
        lda     D_A775,x
        beq     L14D6
        dec     D_A775,x
        jmp     L0D4A

L14D6:                                                  ; $14D6
        lda     $BA,x
        sec
        sbc     #$14
        lsr     a
        lsr     a
        lsr     a
        sta     $40
        ldy     #$00
        cmp     $DC,x
        bcs     L14E8
        ldy     #$02
L14E8:                                                  ; $14E8
        tya
        sta     D_E765,x
        lda     $C2,x
        sec
        sbc     #$15
        lsr     a
        lsr     a
        lsr     a
        sta     $41
        dec     D_AA42,x
        bpl     L150F
        ; Move horizontally
        lda     #$01
        ldy     $DC,x
        cpy     $40
        bcc     L1508
        beq     L1523
        lda     #$FF
        clc
L1508:                                                  ; $1508
        adc     $DC,x
        sta     $DC,x
        jmp     L0D4A

L150F:                                                  ; $150F
        ; Move vertically
        lda     #$01
        ldy     $EE,x
        cpy     $41
        bcc     L151C
        beq     L1523
        lda     #$FF
        clc
L151C:                                                  ; $151C
        adc     $EE,x
        sta     $EE,x
        jmp     L0D4A

L1523:                                                  ; $1523
        lda     #$00
        sta     D_AA42,x
        jmp     L0D4A

; -----------------------------------------------------------------------------
; Collision check routine ($152B)
; Self-modifying: L1545/L1549 modified by caller
; -----------------------------------------------------------------------------
L152B:                                                  ; $152B
        lda     $DC,x
        asl     a
        asl     a
        asl     a
        adc     #$18
        sta     $40
        lda     $EE,x
        asl     a
        asl     a
        asl     a
        adc     #$15
        sta     $41
        ldy     #$01
L153F:                                                  ; $153F
        lda     $B2,y
        beq     L1573
L1544:                                                  ; $1544 - CMP instruction
        cmp     #$19                    ; Operand at $1545 is self-modified
        beq     L154C
L1548:                                                  ; $1548 - CMP instruction  
        cmp     #$0D                    ; Operand at $1549 is self-modified
        bcs     L1573
L154C:                                                  ; $154C

; Equates for self-modifying code (point to operand bytes)
L1545 = L1544 + 1                                       ; Operand of first CMP
L1549 = L1548 + 1                                       ; Operand of second CMP
        lda     $BA,y
        sec
        sbc     $40
        bcs     L1558
        eor     #$FF
        adc     #$01
L1558:                                                  ; $1558
        cmp     #$10
        bcs     L1573
        lda     $C2,y
        sec
        sbc     $41
        bcs     L1568
        eor     #$FF
        adc     #$01
L1568:                                                  ; $1568
        cmp     #$10
        bcs     L1573
        lda     #$0E                    ; Set dying state
        sta     $B2,y
        sec
        rts

L1573:                                                  ; $1573
        dey
        bpl     L153F
        clc
L1577:                                                  ; $1577 - Exit point for animation_timer_handler
        rts
