; -----------------------------------------------------------------------------
; bb-spawn-handlers.s
; Enemy spawn handling, player collision with spawned items, score processing
; Address range: $284D - $29BA (366 bytes)
; -----------------------------------------------------------------------------

; External references
.segment "CODE_ITEMS"

L1E6C           := D_1E6C
L2162           := D_2162
L220C           := D_220C
L2301           := D_2301
L2C9F           := D_2C9F

; -----------------------------------------------------------------------------
; SPAWN_POSITION_INIT ($284D)
; Initialize spawn position from level data
; Calculates X,Y position from $A754/$A75F tables
; -----------------------------------------------------------------------------
spawn_position_init:                                    ; $284D
        lda     D_A754
        asl     a
        asl     a
        asl     a
        adc     #$14
        sta     $BA,x                   ; Set X position
        lda     D_A75F
        asl     a
        asl     a
        asl     a
        adc     #$05
        sta     $C2,x                   ; Set Y position
        cmp     #$ED
        bne     @L2877
        cpx     #$02
        bcc     @L287C
        lda     #$07
        sta     D_8890,x
        dec     $B2,x
        dec     $4A
        lda     #$0E
        sta     D_8548,x
@L2877:                                                 ; $2877
        cpx     #$02
        bcc     @L288D
        rts

@L287C:                                                 ; $287C
        lda     #$64
        ldy     $BA,x
        cpy     #$94
        bcc     @L2886
        lda     #$B4
@L2886:                                                 ; $2886
        sta     $BA,x
@L2888:                                                 ; $2888
        lda     #$01
        sta     $B2,x
        rts

; -----------------------------------------------------------------------------
; SPAWN_UPDATE ($288D)
; Update spawn state based on animation timer
; -----------------------------------------------------------------------------
@L288D:                                                 ; $288D
        ldy     D_8818,x
        bmi     @L2895
        jsr     L2301
@L2895:                                                 ; $2895
        lda     D_85E8,x
        sta     $02
        jsr     L220C
        ldx     $22
        lda     D_87A0,x
        bpl     @L2888
        rts

; -----------------------------------------------------------------------------
; SPAWN_ANIMATION ($28A5)
; Handle spawn animation state
; -----------------------------------------------------------------------------
spawn_animation:                                        ; $28A5
        lda     #$00
        sta     D_8728,x
        lda     D_86D8,x
        cmp     #$12
        beq     @L28BB
        lda     #$12
        sta     D_86D8,x
        lda     #$20
        sta     D_8610,x
@L28BB:                                                 ; $28BB
        dec     D_8610,x
        lda     D_8610,x
        bmi     L_28E9
        lsr     a
        and     #$03
        beq     @L28CE
        ldy     D_8840,x
        clc
        adc     #$0B
@L28CE:                                                 ; $28CE
        sta     D_8520,x
        lda     D_87A0,x
        bpl     @L28DB
        lda     D_87F0,x
        bmi     L_28E8
@L28DB:                                                 ; $28DB
        lda     $C2,x
        clc
        adc     #$03
        cmp     #$F5
        bcc     @L28E6
        lda     #$15
@L28E6:                                                 ; $28E6
        sta     $C2,x
L_28E8:                                                 ; $28E8
        rts

L_28E9:                                                 ; $28E9
        tay
        lsr     a
        and     #$03
        clc
        adc     #$0F
        sta     D_8520,x
        cpy     #$C8
        bne     L_28E8
        inc     $B2,x
        rts

; -----------------------------------------------------------------------------
; SPAWN_STATE_CHANGE ($28FB)
; Handle spawn state transitions
; -----------------------------------------------------------------------------
spawn_state_change:                                     ; $28FB
        jsr     L2916
        ldx     $22
        lda     #$01
        sta     $B2,x
        jsr     L1E6C
        ldx     $22
        lda     #$18
        sta     $B2,x
        rts

; -----------------------------------------------------------------------------
; SPAWN_TIMER ($290D)
; Decrement spawn timer and toggle state
; -----------------------------------------------------------------------------
spawn_timer:                                            ; $290D
        dec     D_8688,x
        bne     L2916
        lda     #$01
        sta     $B2,x
L2916:                                                  ; $2916
        lda     D_8548,x
        eor     #$05
        sta     D_8548,x
        jmp     L2162

; -----------------------------------------------------------------------------
; SCORE_DISPLAY ($2921)
; Display score from spawn pickup
; Self-modifying code: modifies addresses at $2970/$2971 and $298D/$298E
; -----------------------------------------------------------------------------
; Self-modifying operand address
smc_score_operand := score_display + 1                  ; $2922

score_display:                                          ; $2921
        .byte   $A9                     ; LDA immediate opcode
D_2922 := score_display + 1             ; $2922 - self-modified operand
        .byte   $00                     ; $2922 - self-modified operand
        bne     L_2995
        inc     smc_score_operand       ; Self-modify: inc $2922
        ldy     D_8890,x
        lda     D_A790,y
        tay
        inc     $B2,x
        lda     #$C8
        sta     D_87A0,x
        txa
        sta     D_8520,x
        ; VIC sprite pointer base for score/item display sprites.
        ; Entities 2-7 each get a 64-byte sprite slot in the screen buffer,
        ; starting at sprite_data_7C40+$40 (entity 0/1 are players).
        ; VIC pointer = D_8520[x] + D_8598[x], where D_8520[x] = x (entity index).
        ; So D_8598 = (sprite_data_7C40 + $40 - VIC_bank) / 64.
        ; ca65 can't divide relocatable expressions, so we use the identity:
        ;   X / 64 = hibyte(X * 4) = hibyte(X + X + X + X)
        lda     #>(sprite_data_7C40 + $40 - __VIC_BANK_BASE__ + sprite_data_7C40 + $40 - __VIC_BANK_BASE__ + sprite_data_7C40 + $40 - __VIC_BANK_BASE__ + sprite_data_7C40 + $40 - __VIC_BANK_BASE__)
        sta     D_8598,x
        lda     D_A8E4,y
        and     #$07
        sta     D_8548,x
        lda     #$00
        sta     D_8728,x
        sta     $05
        lda     D_A892,y
        jsr     L2C9F
        lda     D_A783,x
        sta     smc_L2970+1             ; Self-modify store address low
        sta     L_298D                  ; Store low byte to $298D
        lda     D_A789,x
        sta     smc_L2970+2             ; Self-modify store address high
        sta     L_298E                  ; Store high byte to $298E
        ldy     #$0F
        ldx     #$3D
smc_L296A:                                              ; $296A
        lda     ($04),y
        jsr     L_2996
smc_L2970:                                              ; $2970 - self-modified STA abs,x
        sta     D_0400,x                ; Address modified at runtime
D_2970 := smc_L2970                                     ; SMC: instruction byte
D_2971 := smc_L2970 + 1                                 ; SMC: low byte of address operand
        dex
        dex
        dex
        dey
        bpl     smc_L296A
        lda     $04
        clc
        adc     #$10
        sta     $04
        bcc     @L2983
        inc     $05
@L2983:                                                 ; $2983
        ldy     #$0F
D_2985:
        ldx     #$3E
L_2987:                                                 ; $2987
        lda     ($04),y
        jsr     L_2996
        .byte   $9D                     ; $298C - STA abs,x opcode
L_298D:                                                 ; $298D - low byte of address (self-modified)
        .byte   $00
L_298E:                                                 ; $298E - high byte of address (self-modified)
        .byte   $04
        dex
        dex
        dex
        dey
        bpl     L_2987
L_2995:                                                 ; $2995
        rts

; -----------------------------------------------------------------------------
; BIT_MIRROR ($2996)
; Mirror bits in accumulator for display purposes
; Input: A = byte to mirror
; Output: A = mirrored byte
; -----------------------------------------------------------------------------
L_2996:                                                 ; $2996
        sta     $02
        and     #$80
        beq     @L299D
        lsr     a
@L299D:                                                 ; $299D
        eor     $02
        sta     $02
        and     #$20
        beq     @L29A6
        lsr     a
@L29A6:                                                 ; $29A6
        eor     $02
        sta     $02
        and     #$08
        beq     @L29AF
        lsr     a
@L29AF:                                                 ; $29AF
        eor     $02
        sta     $02
        and     #$02
        beq     @L29B8
        lsr     a
@L29B8:                                                 ; $29B8
        eor     $02
        rts

