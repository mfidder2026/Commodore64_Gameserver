; ==============================================================================
; bb-item-collision.s
; ==============================================================================
; Memory range: $29BB-$2A17 (93 bytes)
;
; Item and player collision detection routines
; - Checks collision between players and collectible items
; - Calculates Manhattan distance for collision detection (X and Y < $10)
; - Awards points based on item type from D_A79A score table
; - Clears entity state when collected
; ==============================================================================

.segment "CODE_ITEMS"

D_29BB:
        dec     D_87A0,x                ; Decrement collision state
        beq     L_2A0B                  ; f0 4b        $29be

; Entry point at $29C0 - check collision with players (Y=1 for player 2, Y=0 for player 1)
D_29C0:
        ldy     #$01                    ; a0 01        $29c0

; Main collision check loop
; Y = entity index to check against player X
L_29C2:
        lda     ENESSION,y              ; b9 b2 00     $29c2 - Check entity state
        beq     L_2A14                  ; f0 4d        $29c5 - Skip if entity inactive
        cmp     #$0e                    ; c9 0e        $29c7 - Check if entity type $0E
        beq     L_29CF                  ; f0 04        $29c9 - Continue if $0E
        cmp     #$0f                    ; c9 0f        $29cb - Check if entity type $0F
        beq     L_2A14                  ; f0 45        $29cd - Skip if $0F
        
; Calculate horizontal distance (Manhattan distance component 1)
L_29CF:
        lda     FA,x                    ; b5 ba        $29cf - Get player X position
        sec                             ; 38           $29d1
        sbc     a:FA,y                  ; f9 ba 00     $29d2 - Subtract entity X position
        bcs     L_29DB                  ; b0 04        $29d5 - If positive, skip abs conversion
        eor     #$ff                    ; 49 ff        $29d7 - Convert to absolute value
        adc     #$01                    ; 69 01        $29d9 - (two's complement)

L_29DB:
        cmp     #$10                    ; c9 10        $29db - Check if distance < 16 pixels
        bcs     L_2A14                  ; b0 35        $29dd - Too far, skip to next entity

; Calculate vertical distance (Manhattan distance component 2)
        lda     $c2,x                   ; b5 c2        $29df - Get player Y position
        sec                             ; 38           $29e1
        sbc     a:ZP_C2,y               ; f9 c2 00     $29e2 - Subtract entity Y position
        bcs     L_29EB                  ; b0 04        $29e5 - If positive, skip abs conversion
        eor     #$ff                    ; 49 ff        $29e7 - Convert to absolute value
        adc     #$01                    ; 69 01        $29e9 - (two's complement)

L_29EB:
        cmp     #$10                    ; c9 10        $29eb - Check if distance < 16 pixels
        bcs     L_2A14                  ; b0 25        $29ed - Too far, skip to next entity

; Collision detected! Award points based on item type
        sty     ZP_02                   ; 84 02        $29ef - Save entity index
        ldy     D_8890,x                ; bc 90 88     $29f1 - Get item type from spawn table
        lda     D_A79A,y                ; b9 9a a7     $29f4 - Load score value for this item
        pha                             ; 48           $29f7 - Save score on stack
        ldy     ZP_02                   ; a4 02        $29f8 - Restore entity index
        lda     D_AB51,y                ; b9 51 ab     $29fa - Get player number (0 or 1)
        tay                             ; a8           $29fd - Y = player number
        pla                             ; 68           $29fe - Restore score value
        cmp     #$50                    ; c9 50        $29ff - Check if score is $50 (special item?)
        beq     L_2A04                  ; f0 01        $2a01 - Skip decrement if $50
        dey                             ; 88           $2a03 - Decrement player number

; Add score to player
L_2A04:
        jsr     D_7C26                  ; 20 26 7c     $2a04 - Add score to player Y
        lda     #$01                    ; a9 01        $2a07
        sta     $b0                     ; 85 b0        $2a09 - Set flag (item collected?)

; Clear entity state (item has been collected)
L_2A0B:
        lda     #$00                    ; a9 00        $2a0b
        sta     FA,x                    ; 95 ba        $2a0d - Clear X position
        sta     $c2,x                   ; 95 c2        $2a0f - Clear Y position
        sta     ENESSION,x              ; 95 b2        $2a11 - Clear entity state
        rts                             ; 60           $2a13

; Loop to next entity
L_2A14:
        dey                             ; 88           $2a14 - Decrement entity index
        bpl     L_29C2                  ; 10 ab        $2a15 - Continue checking entities (Y >= 0)
        rts                             ; 60           $2a17
