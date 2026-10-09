;===============================================================================
; bb-entity-collision.s - Entity Collision Detection
;===============================================================================
; Address range: $3D2D-$3DB0 (131 bytes)
;
; This module handles collision detection between entities. It checks if
; entities are within collision range ($18 pixels) of each other on both
; X and Y axes, and handles the collision response including:
; - Setting entity state to $34 (bubble captured state)
; - Enabling sprites for captured entities
; - Updating player score counters
;
; The routine loops through all active entities (Y=$11 down to $00) checking
; for collisions with the current entity (X register).
;===============================================================================

;-------------------------------------------------------------------------------
; Main Collision Detection Loop ($3D2D-$3DB0)
;-------------------------------------------------------------------------------
; Checks entity at index X against all other entities
; 
; On entry:
;   X = current entity index to check
;
; Uses:
;   Y = loop counter (entities to check against)
;   OLDTXT+1 ($3E) = saves entity X index

.segment "CODE_ENTITY_TBLS"

routine_3D2D:
        ldy     #$11                                ; $3D2D - Check 18 entities (0-17)
        stx     OLDTXT+1                            ; $3D2F - Save our entity index

L_3D31_check_entity_loop:
        cpy     OLDTXT+1                            ; $3D31 - Don't collide with self
        beq     L_3D74_next_entity                  ; $3D33

D_3D35:
        lda     a:PESSION,y                         ; $3D35 - Get other entity state
        cmp     #$24                                ; $3D38 - Check if >= $24 (inactive?)
        bcs     L_3D74_next_entity                  ; $3D3A - Skip if inactive

        lda     D_A9B2,x                            ; $3D3C - Check our entity flags
D_3D3F:
        bne     L_3D74_next_entity                  ; $3D3F - Skip if flag set

        ; Check X distance
        lda     D_AA0C,x                            ; $3D41 - Our X position
        sec                                         ; $3D44
        sbc     D_AA0C,y                            ; $3D45 - Subtract other's X position
        bcs     L_3D4E_x_dist_positive              ; $3D48 - Branch if positive
        
        ; Make negative distance positive (absolute value)
        eor     #$FF                                ; $3D4A - Invert bits
        adc     #$01                                ; $3D4C - Add 1 (two's complement)

L_3D4E_x_dist_positive:
        cmp     #$18                                ; $3D4E - Compare to collision range (24 pixels)
        bcs     L_3D74_next_entity                  ; $3D50 - Too far on X axis

        ; Check Y distance
        lda     D_AA1E,x                            ; $3D52 - Our Y position
        sec                                         ; $3D55
        sbc     D_AA1E,y                            ; $3D56 - Subtract other's Y position
        bcs     L_3D5F_y_dist_positive              ; $3D59 - Branch if positive
        
        ; Make negative distance positive
        eor     #$FF                                ; $3D5B
        adc     #$01                                ; $3D5D

L_3D5F_y_dist_positive:
        cmp     #$18                                ; $3D5F - Compare to collision range
        bcs     L_3D74_next_entity                  ; $3D61 - Too far on Y axis

        ; COLLISION DETECTED! Handle capture
        lda     a:PESSION,y                         ; $3D63 - Get other entity's state
        sta     D_AA42,y                            ; $3D66 - Save original state
        
        lda     #$34                                ; $3D69 - State $34 = captured in bubble
        sta     a:PESSION,y                         ; $3D6B - Set new state
        
        lda     D_0193,x                            ; $3D6E - Get our player number
        sta     D_0193,y                            ; $3D71 - Assign to captured entity

L_3D74_next_entity:
        dey                                         ; $3D74 - Next entity
        bpl     L_3D31_check_entity_loop            ; $3D75 - Loop for all entities

        ; Check if current entity was captured
routine_3D77:                                       ; $3D77 - Captured entity state check
        lda     D_AA42,x                            ; $3D77 - Check saved state
        cmp     #$24                                ; $3D7A - Is it >= $24?
        bcs     routine_3DB0                        ; $3D7C - Skip to bubble handler
        
        cmp     #$18                                ; $3D7E - Is it < $18?
        bcc     routine_3DB0                        ; $3D80 - Skip to bubble handler
        
        ; Entity was captured! Enable sprite display
        sbc     #$18                                ; $3D82 - Subtract base (carry already set)
        lsr                                         ; $3D84 - Divide by 2
        tax                                         ; $3D85 - Use as sprite index
        pha                                         ; $3D86 - Save sprite index
        
        ldy     OLDTXT+1                            ; $3D87 - Get original entity index
        lda     D_AA30,y                            ; $3D89 - Get sprite pointer value
        sta     $B4,x                               ; $3D8C - Set sprite pointer
        
        jsr     D_1A6F                              ; $3D8E - Call sprite setup routine
        
        ; Enable the sprite in VIC register
        lda     VIC_SPR_ENA                         ; $3D91 - Get current sprite enable bits
        ora     D_AB55,x                            ; $3D94 - OR with sprite bit mask
        sta     VIC_SPR_ENA                         ; $3D97 - Update sprite enable register
        
        ; Update score counter
        lda     D_0193,y                            ; $3D9A - Get player number
        tax                                         ; $3D9D
        inc     $46,x                               ; $3D9E - Increment score counter
        
        pla                                         ; $3DA0 - Restore sprite index
        tay                                         ; $3DA1
        lda     $46,x                               ; $3DA2 - Get score count
        sta     D_8892,y                            ; $3DA4 - Store in score display array
        
        ldx     OLDTXT+1                            ; $3DA7 - Restore entity index

D_3DA9:
        lda     #$36                                ; $3DA9 - State $36 = ???
        sta     PESSION,x                           ; $3DAB - Set new entity state
        jmp     D_E968                              ; $3DAD - Continue entity processing

; Note: routine continues into bb-bubble-handler.s at routine_3DB0

;===============================================================================
; End of bb-entity-collision.s
;===============================================================================
