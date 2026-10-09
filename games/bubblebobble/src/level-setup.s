; ==============================================================================
; bb-level-setup.s
; ==============================================================================
; Memory range: $2B31-$2D64 (564 bytes)
;
; Level data initialization and special item scoring
; - Loads level-specific data for current round (1-100, or $63 for bonus)
; - Sets up platform layout pointers, scroll/wrap attributes
; - Initializes enemy types and special items
; - Handles collision detection and scoring for special power-up items
; - Manages bonus level configuration
;
; Level data tables:
;   $B569 - Item spawn positions A (100 bytes) - 5-bit packed coords
;   $B5CD - Item spawn positions B (100 bytes) - 5-bit packed coords
;   $B631 - Item spawn positions C (upper nibble) + bubble spawns (lower nibble, 100 bytes)
; ==============================================================================

.segment "CODE_ITEMS"

; Main level setup entry point
setup_level_data:
D_2B31:
        ldx     SUBFLG                  ; a6 10        $2b31 - X = current level number
        lda     item_positions + 100,x  ; bd cd b5     $2b33 - Get level attribute byte 1
        sta     ADRAY1                  ; 85 03        $2b36 - Store in work register
        lda     item_positions + 200,x  ; bd 31 b6     $2b38 - Get level attribute byte 2
        sta     $04                     ; 85 04        $2b3b - Store in work register
        lda     item_positions,x        ; bd 69 b5     $2b3d - Get scroll/wrap byte
        tax                             ; aa           $2b40 - Transfer to X
        and     #$f8                    ; 29 f8        $2b41
        sta     $59                     ; 85 59        $2b43
        lsr                             ; 4a           $2b45
        lsr                             ; 4a           $2b46
        lsr                             ; 4a           $2b47
        sta     DATLIN+1                ; 85 40        $2b48
        txa                             ; 8a           $2b4a
        and     #$07                    ; 29 07        $2b4b
        sta     DATPTR                  ; 85 41        $2b4d
        lda     ADRAY1                  ; a5 03        $2b4f
        asl                             ; 0a           $2b51
        rol     DATPTR                  ; 26 41        $2b52
        asl                             ; 0a           $2b54
        rol     DATPTR                  ; 26 41        $2b55
        lda     DATPTR                  ; a5 41        $2b57
        asl                             ; 0a           $2b59
        tay                             ; a8           $2b5a
        asl                             ; 0a           $2b5b
        asl                             ; 0a           $2b5c
        sta     $5b                     ; 85 5b        $2b5d
        lda     D_AC09,y                ; b9 09 ac     $2b5f
        clc                             ; 18           $2b62
        adc     DATLIN+1                ; 65 40        $2b63
        sta     DEFPNT                  ; 85 4e        $2b65
        lda     D_AC0A,y                ; b9 0a ac     $2b67
        adc     #$00                    ; 69 00        $2b6a
        sta     DSESSION                ; 85 50        $2b6c
        lda     ADRAY1                  ; a5 03        $2b6e
        and     #$3e                    ; 29 3e        $2b70
        lsr                             ; 4a           $2b72
        sta     DATLIN+1                ; 85 40        $2b73
        asl                             ; 0a           $2b75
        asl                             ; 0a           $2b76
        asl                             ; 0a           $2b77
        sta     TEMPF1                  ; 85 5a        $2b78
        lda     $04                     ; a5 04        $2b7a
        and     #$f0                    ; 29 f0        $2b7c
        tay                             ; a8           $2b7e
        lda     ADRAY1                  ; a5 03        $2b7f
        lsr                             ; 4a           $2b81
        tya                             ; 98           $2b82
        ror                             ; 6a           $2b83
        sta     $5c                     ; 85 5c        $2b84
        lsr                             ; 4a           $2b86
        lsr                             ; 4a           $2b87
        tay                             ; a8           $2b88
        lda     D_AC09,y                ; b9 09 ac     $2b89
        clc                             ; 18           $2b8c
        adc     DATLIN+1                ; 65 40        $2b8d
        sta     $4f                     ; 85 4f        $2b8f
        lda     D_AC0A,y                ; b9 0a ac     $2b91
        adc     #$00                    ; 69 00        $2b94
        sta     $51                     ; 85 51        $2b96

        ; Check if bonus level ($63)
        lda     SUBFLG                  ; a5 10        $2b98
        cmp     #$63                    ; c9 63        $2b9a
        bne     L_2BB0                  ; d0 12        $2b9c

        ; Bonus level setup
        lda     #$00                    ; a9 00        $2b9e
        sta     D_5B7F                  ; 8d 7f 5b     $2ba0
        lda     #$51                    ; a9 51        $2ba3
        jsr     D_2BBD                  ; 20 bd 2b     $2ba5
        lda     #$22                    ; a9 22        $2ba8
        jsr     D_2C32                  ; 20 32 2c     $2baa
        jmp     D_2C8C                  ; 4c 8c 2c     $2bad

        ; Normal level setup - random enemy type selection
L_2BB0:
        jsr     D_E9EA                  ; 20 ea e9     $2bb0 - Get random number
        and     #$03                    ; 29 03        $2bb3 - 0-3
        adc     $58                     ; 65 58        $2bb5
        cmp     #$2f                    ; c9 2f        $2bb7 - Max enemy type $2E
        bcc     D_2BBD                  ; 90 02        $2bb9
        lda     #$2e                    ; a9 2e        $2bbb - Cap at $2E

; Initialize enemy type
D_2BBD:
        tax                             ; aa           $2bbd
        ora     #$80                    ; 09 80        $2bbe - Set high bit
        sta     $52                     ; 85 52        $2bc0 - Store enemy type
        lda     D_A8E4,x                ; bd e4 a8     $2bc2 - Get enemy color
        sta     TEMPF2                  ; 85 5f        $2bc5 - Store color
        lda     #$00                    ; a9 00        $2bc7
        sta     ADRAY2                  ; 85 05        $2bc9
        sta     $58                     ; 85 58        $2bcb
        lda     D_A892,x                ; bd 92 a8     $2bcd - Get enemy data index
        jsr     D_2C9F                  ; 20 9f 2c     $2bd0 - Calculate address
        lda     $04                     ; a5 04        $2bd3
        sta     $02                     ; 85 02        $2bd5
        lda     ADRAY2                  ; a5 05        $2bd7
        sta     ADRAY1                  ; 85 03        $2bd9

        ; Check for special level progression
        lda     D_5B7F                  ; ad 7f 5b     $2bdb
        beq     L_2BFC                  ; f0 1c        $2bde
        lda     D_5B3F                  ; ad 3f 5b     $2be0
        cmp     SUBFLG                  ; c5 10        $2be3
        bcs     L_2BFC                  ; b0 15        $2be5
        adc     #$0a                    ; 69 0a        $2be7 - Add 10 levels
        sta     D_5B3F                  ; 8d 3f 5b     $2be9
        tay                             ; a8           $2bec
        lda     #$20                    ; a9 20        $2bed
        cpy     #$3a                    ; c0 3a        $2bef - Level 58?
        bne     D_2C32                  ; d0 3f        $2bf1
        lda     #$4e                    ; a9 4e        $2bf3
        sta     D_5B3F                  ; 8d 3f 5b     $2bf5
        lda     #$21                    ; a9 21        $2bf8
        bne     D_2C32                  ; d0 36        $2bfa

; Random special item selection
L_2BFC:
        ldx     RESHO                   ; a6 26        $2bfc - Save RNG state
        ldy     $27                     ; a4 27        $2bfe
        lda     SUBFLG                  ; a5 10        $2c00
        sta     RESHO                   ; 85 26        $2c02 - Seed with level number
        sta     $27                     ; 85 27        $2c04
        jsr     D_E9EA                  ; 20 ea e9     $2c06 - Get random number
        clc                             ; 18           $2c09
        adc     #$01                    ; 69 01        $2c0a - Add 1 (1-32 range)
        and     #$1f                    ; 29 1f        $2c0c - Mask to 0-31
        stx     RESHO                   ; 86 26        $2c0e - Restore RNG state
        sty     $27                     ; 84 27        $2c10
        sta     $04                     ; 85 04        $2c12 - Store item type
        jsr     D_E9EA                  ; 20 ea e9     $2c14 - Get random number
        and     #$0f                    ; 29 0f        $2c17 - 0-15
        bne     L_2C24                  ; d0 09        $2c19 - If not zero, branch
        jsr     D_E9EA                  ; 20 ea e9     $2c1b - Get another random
        and     #$01                    ; 29 01        $2c1e - 0 or 1
        ora     #$1e                    ; 09 1e        $2c20 - $1E or $1F
        bne     D_2C32                  ; d0 0e        $2c22 - Use this item type

L_2C24:
        cmp     #$07                    ; c9 07        $2c24
        bcc     L_2C2D                  ; 90 05        $2c26 - If < 7, get random
        lda     $04                     ; a5 04        $2c28 - Use stored item type
        jmp     D_2C32                  ; 4c 32 2c     $2c2a

L_2C2D:
        jsr     D_E9EA                  ; 20 ea e9     $2c2d - Get random number
        and     #$1f                    ; 29 1f        $2c30 - 0-31

; Initialize special item type
D_2C32:
        tax                             ; aa           $2c32
        ora     #$80                    ; 09 80        $2c33 - Set high bit
        sta     FOUR6                   ; 85 53        $2c35 - Store item type
        lda     D_A913,x                ; bd 13 a9     $2c37 - Get item color
        sta     $60                     ; 85 60        $2c3a
        lda     #$00                    ; a9 00        $2c3c
        sta     ADRAY2                  ; 85 05        $2c3e
        lda     D_A8C1,x                ; bd c1 a8     $2c40 - Get item data index
        jsr     D_2C9F                  ; 20 9f 2c     $2c43 - Calculate address

        ; Copy item data to work buffers
        ldy     #$1f                    ; a0 1f        $2c46 - 32 bytes
L_2C48:
        lda     ($02),y                 ; b1 02        $2c48
        sta     D_4210,y                ; 99 10 42     $2c4a
        sta     D_4A10,y                ; 99 10 4a     $2c4d
        lda     ($04),y                 ; b1 04        $2c50
        sta     D_4230,y                ; 99 30 42     $2c52
        sta     D_4A30,y                ; 99 30 4a     $2c55
        dey                             ; 88           $2c58
        bpl     L_2C48                  ; 10 ed        $2c59 - Loop for all bytes

        ; Initialize bubble timers
        jsr     D_E9EA                  ; 20 ea e9     $2c5b - Random number
        and     #$07                    ; 29 07        $2c5e - 0-7
        clc                             ; 18           $2c60
        adc     #$03                    ; 69 03        $2c61 - 3-10
        sta     $5d                     ; 85 5d        $2c63 - Player 1 bubble timer
        jsr     D_E9EA                  ; 20 ea e9     $2c65 - Random number
        and     #$0f                    ; 29 0f        $2c68 - 0-15
        clc                             ; 18           $2c6a
        adc     #$01                    ; 69 01        $2c6b - 1-16
        sta     $5e                     ; 85 5e        $2c6d - Player 2 bubble timer

        ; Check if bonus level
        lda     SUBFLG                  ; a5 10        $2c6f
        cmp     #$63                    ; c9 63        $2c71
        bne     D_2C8C                  ; d0 17        $2c73

        ; Bonus level specific setup
        lda     #$32                    ; a9 32        $2c75 - 50 frames
        sta     D_5BBF                  ; 8d bf 5b     $2c77 - Special item countdown
        lda     #<special_item_handler   ; a9 34        $2c7a
        sta     D_0A39                  ; 8d 39 0a     $2c7c
        lda     #>special_item_handler  ; a9 11        $2c7f
        sta     D_0A3A                  ; 8d 3a 0a     $2c81
        lda     #$20                    ; a9 20        $2c84
        sta     L_0A38                  ; 8d 38 0a     $2c86
        jmp     D_7F83                  ; 4c 83 7f     $2c89

; Adjust scroll offsets
D_2C8C:
        ldx     #$01                    ; a2 01        $2c8c - Loop counter
L_2C8E:
        lda     $59,x                   ; b5 59        $2c8e
        clc                             ; 18           $2c90
        adc     #$14                    ; 69 14        $2c91 - Add $14
        sta     $59,x                   ; 95 59        $2c93
        lda     $5b,x                   ; b5 5b        $2c95
        adc     #$2d                    ; 69 2d        $2c97 - Add $2D (with carry)
        sta     $5b,x                   ; 95 5b        $2c99
        dex                             ; ca           $2c9b
        bpl     L_2C8E                  ; 10 f0        $2c9c
        rts                             ; 60           $2c9e

; Helper: Calculate data address (multiply by 16, add sprites_rom base)
D_2C9F:
        asl                             ; 0a           $2c9f - x2
        asl                             ; 0a           $2ca0 - x4
        rol     ADRAY2                  ; 26 05        $2ca1
        asl                             ; 0a           $2ca3 - x8
        rol     ADRAY2                  ; 26 05        $2ca4
        asl                             ; 0a           $2ca6 - x16
        rol     ADRAY2                  ; 26 05        $2ca7
        asl                             ; 0a           $2ca9 - x32 (but only lower 5 bits used)
        rol     ADRAY2                  ; 26 05        $2caa
        adc     #<sprites_rom           ; 69 e0        $2cac - Add low byte of base
        sta     $04                     ; 85 04        $2cae
        lda     ADRAY2                  ; a5 05        $2cb0
        adc     #>sprites_rom           ; 69 9a        $2cb2 - Add high byte of base
        sta     ADRAY2                  ; 85 05        $2cb4
        rts                             ; 60           $2cb6

; Special item collision and scoring handler
D_2CB7:
        lda     FOUR6                   ; a5 53        $2cb7 - Get special item type
        cmp     #$18                    ; c9 18        $2cb9 - Type $18?
        bne     L_2CC3                  ; d0 06        $2cbb
        lda     $60                     ; a5 60        $2cbd - Get color
        eor     #$05                    ; 49 05        $2cbf - Toggle color bits
        sta     $60                     ; 85 60        $2cc1

L_2CC3:
        ldx     #$01                    ; a2 01        $2cc3 - Check both players

; Player loop - check if player can collect items
D_2CC5:
        lda     ENESSION,x              ; b5 b2        $2cc5 - Get player state
        beq     L_2CD5                  ; f0 0c        $2cc7 - Inactive, skip
        cmp     #$18                    ; c9 18        $2cc9 - State $18?
        beq     L_2CD8                  ; f0 0b        $2ccb - Yes, check collision
        cmp     #$0e                    ; c9 0e        $2ccd - State < $0E?
        bcc     L_2CD8                  ; 90 07        $2ccf - Yes, check collision
        cmp     #$10                    ; c9 10        $2cd1 - State $10?
        beq     L_2CD8                  ; f0 03        $2cd3 - Yes, check collision

L_2CD5:
        jmp     D_2D5E                  ; 4c 5e 2d     $2cd5 - Skip to next player

; Check collision with special items (2 item slots)
L_2CD8:
        ldy     #$01                    ; a0 01        $2cd8 - Check 2 item slots

D_2CDA:
        lda     a:ZP_52,y               ; b9 52 00     $2cda - Get item type
        bmi     L_2D58                  ; 30 79        $2cdd - Inactive (high bit set), skip

        ; Calculate X distance
        lda     FA,x                    ; b5 ba        $2cdf - Player X position
        sec                             ; 38           $2ce1
        sbc     a:ZP_59,y               ; f9 59 00     $2ce2 - Subtract item X
        bcs     L_2CEB                  ; b0 04        $2ce5 - Positive, skip abs
        eor     #$ff                    ; 49 ff        $2ce7 - Make absolute
        adc     #$01                    ; 69 01        $2ce9

L_2CEB:
        cmp     #$10                    ; c9 10        $2ceb - Distance < 16?
        bcs     L_2D58                  ; b0 69        $2ced - Too far, skip

        ; Calculate Y distance
        lda     $c2,x                   ; b5 c2        $2cef - Player Y position
        sec                             ; 38           $2cf1
        sbc     a:ZP_5B,y               ; f9 5b 00     $2cf2 - Subtract item Y
        bcs     L_2CFB                  ; b0 04        $2cf5 - Positive, skip abs
        eor     #$ff                    ; 49 ff        $2cf7 - Make absolute
        adc     #$01                    ; 69 01        $2cf9

L_2CFB:
        cmp     #$10                    ; c9 10        $2cfb - Distance < 16?
        bcs     L_2D58                  ; b0 59        $2cfd - Too far, skip

        ; Collision detected! Collect item
        lda     #$ff                    ; a9 ff        $2cff
        sta     a:ZP_5D,y               ; 99 5d 00     $2d01 - Mark timer as expired
        lda     #$01                    ; a9 01        $2d04
        sta     $b0                     ; 85 b0        $2d06 - Set collected flag

        ; Calculate score based on item type
        lda     D_AB51,x                ; bd 51 ab     $2d08 - Get player number
        sta     DATLIN+1                ; 85 40        $2d0b
        sty     DATPTR                  ; 84 41        $2d0d - Save item index
        cpy     #$01                    ; c0 01        $2d0f - Item slot 1?
        beq     L_2D20                  ; f0 0d        $2d11 - Yes, use different table

        ; Item slot 0 - use enemy type score table
        ldy     $52                     ; a4 52        $2d13 - Enemy type
        lda     D_A936,y                ; b9 36 a9     $2d15 - Get score value
        cpy     #$0f                    ; c0 0f        $2d18 - Type < $0F?
        bcc     L_2D2B                  ; 90 0f        $2d1a - Yes, use score
        dec     DATLIN+1                ; c6 40        $2d1c - Decrement player offset
        bpl     L_2D2B                  ; 10 0b        $2d1e - Continue

; Item slot 1 - use special item score table
L_2D20:
        ldy     FOUR6                   ; a4 53        $2d20 - Special item type
        lda     D_A965,y                ; b9 65 a9     $2d22 - Get score value
        cpy     #$18                    ; c0 18        $2d25 - Type < $18?
        bcc     L_2D2B                  ; 90 02        $2d27 - Yes, use score
        dec     DATLIN+1                ; c6 40        $2d29 - Decrement player offset

L_2D2B:
        ldy     DATLIN+1                ; a4 40        $2d2b - Y = player number

; Add score to player
D_2D2D:
        jsr     D_7C26                  ; 20 26 7c     $2d2d - Add score routine
        ldy     DATPTR                  ; a4 41        $2d30 - Restore item index
        bne     L_2D40                  ; d0 0c        $2d32 - Item slot 1, do special

; Item slot 0 collected
D_2D34:
        lda     SUBFLG                  ; a5 10        $2d34 - Current level
        cmp     #$63                    ; c9 63        $2d36 - Bonus level?
        bne     L_2D58                  ; d0 1e        $2d38 - No, skip
        jsr     D_7C3C                  ; 20 3c 7c     $2d3a - Bonus level handler
        jmp     L_2D58                  ; 4c 58 2d     $2d3d

; Item slot 1 collected - trigger special effect
L_2D40:
        stx     D_2D57                  ; 8e 57 2d     $2d40 - Store player index (self-modifying code)
        ldy     FOUR6                   ; a4 53        $2d43 - Special item type
        lda     D_2D65,y                ; b9 65 2d     $2d45 - Get effect routine low byte
        sta     D_2D52                  ; 8d 52 2d     $2d48 - Store in JSR target (self-modifying)
        lda     D_2D88,y                ; b9 88 2d     $2d4b - Get effect routine high byte
        sta     D_2D53                  ; 8d 53 2d     $2d4e - Store in JSR target (self-modifying)

smc_effect_jsr:
        jsr     entry_0400              ; 20 00 04     $2d51 - Call effect routine (self-modified)
D_2D52      = smc_effect_jsr + 1        ; SMC: low byte of JSR target
D_2D53      = smc_effect_jsr + 2        ; SMC: high byte of JSR target
        ldy     #$01                    ; a0 01        $2d54
smc_player_ldx:
        ldx     #$00                    ; a2 00        $2d56 - Restore player index (self-modified)
D_2D57      = smc_player_ldx + 1        ; SMC: operand of LDX #imm

L_2D58:
        dey                             ; 88           $2d58 - Next item slot
        bmi     D_2D5E                  ; 30 03        $2d59 - Done with items
        jmp     D_2CDA                  ; 4c da 2c     $2d5b - Check next item

D_2D5E:
        dex                             ; ca           $2d5e - Next player
        bmi     L_2D64                  ; 30 03        $2d5f - Done with players
        jmp     D_2CC5                  ; 4c c5 2c     $2d61 - Check next player

L_2D64:
        rts                             ; 60           $2d64
