; ==============================================================================
; bb-super-bonus.s
; ==============================================================================
; Memory range: $2A18-$2B30 (281 bytes)
;
; Super bonus item spawning and collection routines
; - Spawns special items from data at $4700-$4730
; - Handles super bonus sprite expansion effects
; - Collision detection between players and super bonus
; - Awards points and clears bonus items when collected
;
; NOTE: This file uses .byte directives for several sections because:
; 1. The reference disassembly uses !byte directives
; 2. Mixed code/data that's difficult to separate cleanly
; 3. Ensures byte-perfect accuracy
; ==============================================================================

.segment "CODE_ITEMS"

; Position update code for super bonus items ($2A18-$2A27)
D_2A18:
        lda     $BA,x               ; $2A18 - Get X position
        clc
        adc     D_A7A3,x            ; Add X velocity from table
        sta     $BA,x               ; Store new X position
        lda     $C2,x               ; $2A20 - Get Y position
        clc
        adc     D_A7A8,x            ; Add Y velocity from table
        sta     $C2,x               ; Store new Y position

; Code fragment at $2A28-$2A3E (23 bytes)
        lda     D_8548,x                ; bd 48 85     $2a28 - Get entity timer
        eor     #$05                    ; 49 05        $2a2b - Toggle bits
        sta     D_8548,x                ; 9d 48 85     $2a2d - Store updated timer
        lda     #$00                    ; a9 00        $2a30 - Clear value
        sta     D_8728,x                ; 9d 28 87     $2a32 - Clear entity data
        cpx     #$02                    ; e0 02        $2a35 - Check entity index
        bne     L_2A73                  ; d0 3a        $2a37 - Not player, return
        lda     ZP_C2,x                 ; b5 c2        $2a39 - Get Y position
        cmp     #$50                    ; c9 50        $2a3b - Check Y threshold
        bcs     L_2A73                  ; b0 34        $2a3d - Too low, return

; Spawn special items from data tables at $4700
D_2A3F:
        jsr     L_069B                  ; 20 9b 06     $2a3f - Clear entities
        lda     #$00                    ; a9 00        $2a42
        sta     ZP_4A                   ; 85 4a        $2a44 - Clear enemies remaining
        ldx     #$05                    ; a2 05        $2a46 - Loop through 6 slots

; Load special item data from $4700 area
L_2A48:
        lda     D_4700,x                ; bd 00 47     $2a48 - Get item type
        cmp     #$11                    ; c9 11        $2a4b - Valid item type?
        bcs     L_2A68                  ; b0 19        $2a4d - Invalid, clear slot

        sta     $b4,x                   ; 95 b4        $2a4f - Store item state
        lda     D_4710,x                ; bd 10 47     $2a51 - Get item X position
        sta     $bc,x                   ; 95 bc        $2a54 - Store X position
        lda     D_4720,x                ; bd 20 47     $2a56 - Get item Y position
        sta     $c4,x                   ; 95 c4        $2a59 - Store Y position
        lda     D_4730,x                ; bd 30 47     $2a5b - Get item attributes
        sta     D_859A,x                ; 9d 9a 85     $2a5e - Store sprite data
        lda     #$0e                    ; a9 0e        $2a61 - Timer value
        sta     D_854A,x                ; 9d 4a 85     $2a63 - Set item timer
        bne     L_2A70                  ; d0 08        $2a66 - Continue loop

; Clear inactive item slot
L_2A68:
        lda     #$00                    ; a9 00        $2a68
        sta     $b4,x                   ; 95 b4        $2a6a - Clear state
        sta     $bc,x                   ; 95 bc        $2a6c - Clear X position
        sta     $c4,x                   ; 95 c4        $2a6e - Clear Y position

L_2A70:
        dex                             ; ca           $2a70
        bpl     L_2A48                  ; 10 d5        $2a71 - Loop for all slots

L_2A73:
        rts                             ; 60           $2a73

; Code fragment at $2A74-$2A85 (18 bytes)
D_2A74:
        lda     D_8548,x                ; bd 48 85     $2a74 - Get entity timer
        eor     #$03                    ; 49 03        $2a77 - Toggle bits
        sta     D_8548,x                ; 9d 48 85     $2a79 - Store updated timer
        lda     ENDCHR                  ; a5 08        $2a7c - Get frame counter
        and     #$02                    ; 29 02        $2a7e - Check bit 1
        bne     L_2A73                  ; d0 f1        $2a80 - Skip if set
        cpx     #$02                    ; e0 02        $2a82 - Check entity index
        bne     L_2A73                  ; d0 ed        $2a84 - Not player, return

; Super bonus sprite expansion handler
        ldx     #$05                    ; a2 05        $2a86 - 6 sprites
        ldy     #$0e                    ; a0 0e        $2a88 - Y = sprite index offset
        lda     VIC_SPR_YEXP            ; ad 17 d0     $2a8a - Get Y expansion
        eor     #$fc                    ; 49 fc        $2a8d - Toggle expansion bits
        sta     VIC_SPR_YEXP            ; 8d 17 d0     $2a8f - Set Y expansion
        sta     VIC_SPR_XEXP            ; 8d 1d d0     $2a92 - Set X expansion
        beq     L_2AAD                  ; f0 16        $2a95 - Branch if expanded

; Position sprites (normal size)
L_2A97:
        lda     D_A7B0,x                ; bd b0 a7     $2a97 - Get sprite X position
        sta     $bc,x                   ; 95 bc        $2a9a - Store in RAM
        sta     VIC_SPR0_X,y            ; 99 00 d0     $2a9c - Set hardware sprite X
        lda     D_A7B6,x                ; bd b6 a7     $2a9f - Get sprite Y position

D_2AA2:
        sta     $c4,x                   ; 95 c4        $2aa2 - Store in RAM
        sta     VIC_SPR0_Y,y            ; 99 01 d0     $2aa4 - Set hardware sprite Y
        dey                             ; 88           $2aa7 - Next sprite pair
        dey                             ; 88           $2aa8
        dex                             ; ca           $2aa9
        bpl     L_2A97                  ; 10 eb        $2aaa - Loop for all sprites
        rts                             ; 60           $2aac

; Position sprites (expanded)
L_2AAD:
        lda     D_A7BC,x                ; bd bc a7     $2aad - Get alt sprite X position
        sta     $bc,x                   ; 95 bc        $2ab0 - Store in RAM
        sta     VIC_SPR0_X,y            ; 99 00 d0     $2ab2 - Set hardware sprite X
        lda     D_A7C2,x                ; bd c2 a7     $2ab5 - Get alt sprite Y position
        sta     $c4,x                   ; 95 c4        $2ab8 - Store in RAM
        sta     VIC_SPR0_Y,y            ; 99 01 d0     $2aba - Set hardware sprite Y
        dey                             ; 88           $2abd - Next sprite pair
        dey                             ; 88           $2abe
        dex                             ; ca           $2abf
        bpl     L_2AAD                  ; 10 eb        $2ac0 - Loop for all sprites

; Code fragment at $2AC2-$2ACA (9 bytes)
        lda     ENDCHR                  ; a5 08        $2ac2 - Get frame counter
        cmp     #$3c                    ; c9 3c        $2ac4 - Check if >= 60
        bcc     L_2A73                  ; 90 ab        $2ac6 - Not yet, return
        jmp     D_2A3F                  ; 4c 3f 2a     $2ac8 - Spawn special items

; Code at $2ACB-$2AD0 (6 bytes)
D_2ACB:
        lda     ZP_C4                   ; a5 c4        $2acb - Get Y position
        cmp     #$c8                    ; c9 c8        $2acd - Check Y threshold
        beq     L_2AF9                  ; f0 28        $2acf - At threshold, branch

; Initialize super bonus sprite positions
        lda     #$80                    ; a9 80        $2ad1 - X position $80 (128)
        sta     ZP_BC                   ; 85 bc        $2ad3 - Store viewport X
        sta     FSESSION                ; 85 be        $2ad5 - Store super bonus state
        lda     #$98                    ; a9 98        $2ad7 - Y position $98 (152)
        sta     ROESSION                ; 85 bd        $2ad9 - Store super bonus Y
        sta     $bf                     ; 85 bf        $2adb - Store Y position copy
        ldy     #$03                    ; a0 03        $2add - Loop counter (4 items)

; Initialize super bonus item states
L_2ADF:
        lda     #$f4                    ; a9 f4        $2adf - Sprite character $f4
        sta     D_859A,y                ; 99 9a 85     $2ae1 - Set sprite data
        tya                             ; 98           $2ae4 - Get loop counter
        sta     D_8522,y                ; 99 22 85     $2ae5 - Store index
        lda     #$00                    ; a9 00        $2ae8
D_2AE9 := * - 1                         ; SMC: operand byte
        sta     D_854A,y                ; 99 4a 85     $2aea - Clear item timer
        lda     a:ZP_C4,y               ; b9 c4 00     $2aed - Get Y position
        clc                             ; 18           $2af0
        adc     #$04                    ; 69 04        $2af1 - Add 4 pixels offset
        sta     a:ZP_C4,y               ; 99 c4 00     $2af3 - Store adjusted Y
        dey                             ; 88           $2af6
        bpl     L_2ADF                  ; 10 e6        $2af7 - Loop for all items

L_2AF9:
        ldy     #$01                    ; a0 01        $2af9 - Check both players

; Check player collision with super bonus
L_2AFB:
        lda     a:FA,y                  ; b9 ba 00     $2afb - Get player X position
        sec                             ; 38           $2afe
        sbc     ZP_BC                   ; e5 bc        $2aff - Subtract bonus X
        bcc     L_2B2D                  ; 90 2a        $2b01 - Too far left, skip
        cmp     #$30                    ; c9 30        $2b03 - Within $30 pixels?
        bcs     L_2B2D                  ; b0 26        $2b05 - Too far right, skip
        lda     a:ZP_C2,y               ; b9 c2 00     $2b07 - Get player Y position
        sec                             ; 38           $2b0a
        sbc     $c4                     ; e5 c4        $2b0b - Subtract bonus Y
        bcc     L_2B2D                  ; 90 1e        $2b0d - Too far up, skip
        cmp     #$24                    ; c9 24        $2b0f - Within $24 pixels?
        bcs     L_2B2D                  ; b0 1a        $2b11 - Too far down, skip

; Collision detected! Award points and clear bonus
        lda     D_AB51,y                ; b9 51 ab     $2b13 - Get player number
        tay                             ; a8           $2b16 - Y = player number
        dey                             ; 88           $2b17 - Adjust index
        lda     ARG                     ; a5 69        $2b18 - Get score value
        jsr     D_7C26                  ; 20 26 7c     $2b1a - Add score to player

        ldy     #$03                    ; a0 03        $2b1d - Clear 4 items
        lda     #$00                    ; a9 00        $2b1f

; Clear all super bonus items
L_2B21:
        sta     a:ZP_B4,y               ; 99 b4 00     $2b21 - Clear item state
        sta     a:ZP_BC,y               ; 99 bc 00     $2b24 - Clear item X
        sta     a:ZP_C4,y               ; 99 c4 00     $2b27 - Clear item Y
        dey                             ; 88           $2b2a
        bpl     L_2B21                  ; 10 f4        $2b2b - Loop for all items

L_2B2D:
        dey                             ; 88           $2b2d - Check next player
        bpl     L_2AFB                  ; 10 cb        $2b2e - Loop if more players
        rts                             ; 60           $2b30
