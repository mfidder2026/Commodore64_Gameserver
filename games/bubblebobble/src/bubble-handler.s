;===============================================================================
; bb-bubble-handler.s - Bubble State and Entity Type Processing
;===============================================================================
; Address range: $3DB0-$3E76 (199 bytes)
;
; This module handles entity processing when they're in bubble state ($34)
; or other special states. It includes:
; - Sound effect triggering for bubble pops
; - Power-up/item collection detection  
; - Entity state transitions based on type codes
; - Score/bonus processing
;===============================================================================

;-------------------------------------------------------------------------------
; Bubble State Handler ($3DB0-$3E76)
;-------------------------------------------------------------------------------
; Called from collision detection when entity state needs processing
;
; On entry:
;   X = entity index
;   A = entity type code from D_AA42,x
;
; Entity type codes:
;   $06 = Power-up/bonus item
;   $08 = Special item type
;   $0A = Another special type
;   $0C-$15 = Various enemy types in bubbles
;   $18-$23 = Captured enemy sprites

.segment "CODE_ENTITY_TBLS"

routine_3DB0:
        ldy     PESSION,x                           ; $3DB0 - Get entity state
        cpy     #$34                                ; $3DB2 - Is it bubble state?
        bne     L_3E02_check_item_type              ; $3DB4

        ; Entity is in bubble ($34 state) - play pop sound
        ldy     #$01                                ; $3DB6 - Default sound effect 1
        cmp     #$06                                ; $3DB8 - Check if type < 6
        bcc     L_3DC2_play_pop_sound               ; $3DBA
        cmp     #$0C                                ; $3DBC - Check if type >= $0C
        bcs     L_3DC2_play_pop_sound               ; $3DBE
        ldy     #$0A                                ; $3DC0 - Use sound effect $0A

L_3DC2_play_pop_sound:
        tya                                         ; $3DC2
        pha                                         ; $3DC3 - Save sound effect number
        lda     D_0193,x                            ; $3DC4 - Get player number
        and     #$01                                ; $3DC7 - Player 0 or 1
        tay                                         ; $3DC9
        lda     D_AB51,y                            ; $3DCA - Get sound channel for player
        tay                                         ; $3DCD
        pla                                         ; $3DCE - Restore sound effect
        jsr     D_7C26                              ; $3DCF - Play sound effect

        ; Check entity type for power-up processing
        lda     D_AA42,x                            ; $3DD2 - Get entity type
        cmp     #$16                                ; $3DD5 - Check if >= $16
        bcs     L_3E02_check_item_type              ; $3DD7
        cmp     #$0C                                ; $3DD9 - Check if < $0C
        bcc     L_3E02_check_item_type              ; $3DDB

        ; Entity type $0C-$15: Update player power-up flags
        sbc     #$0C                                ; $3DDD - Subtract base (carry set)
        lsr                                         ; $3DDF - Divide by 2
        tay                                         ; $3DE0 - Use as power-up index
        lda     D_0193,x                            ; $3DE1 - Get player number
        tax                                         ; $3DE4
        
        cpy     #$03                                ; $3DE5 - Adjust index if >= 3
        bcc     L_3DEA_check_zero                   ; $3DE7
        iny                                         ; $3DE9

L_3DEA_check_zero:
        cpy     #$00                                ; $3DEA - Is index 0?
        bne     L_3DF6_set_powerup_flag             ; $3DEC
        
        lda     $54,x                               ; $3DEE - Check player flags
        and     #$01                                ; $3DF0 - Test bit 0
        beq     L_3DF6_set_powerup_flag             ; $3DF2
        ldy     #$03                                ; $3DF4 - Use index 3 instead

L_3DF6_set_powerup_flag:
        lda     D_AB53,y                            ; $3DF6 - Get power-up bit mask
        ora     $54,x                               ; $3DF9 - OR with player flags
        sta     $54,x                               ; $3DFB - Store updated flags
        
        ldx     OLDTXT+1                            ; $3DFD - Restore entity index
        lda     D_AA42,x                            ; $3DFF - Reload entity type

L_3E02_check_item_type:
        cmp     #$06                                ; $3E02 - Is it power-up item?
        bne     L_3E2C_check_type_0A                ; $3E04
        
        ; Type $06: Bonus item collected
        lda     OPMASK                              ; $3E06 - Check if already collected
        bne     L_3E2C_check_type_0A                ; $3E08
        
        lda     $DC,x                               ; $3E0A - Get bonus value 1
        clc                                         ; $3E0C

D_3E0D:
        adc     #$01                                ; $3E0D - Increment bonus
        ldy     #$0A                                ; $3E0F - Update 11 display positions

L_3E11_store_bonus1:
        sta     D_A74B,y                            ; $3E11 - Store in bonus display array
        dey                                         ; $3E14
        bpl     L_3E11_store_bonus1                 ; $3E15
        
        lda     $EE,x                               ; $3E17 - Get bonus value 2
        adc     #$01                                ; $3E19 - Increment (carry from above)
        cmp     #$1D                                ; $3E1B - Check if >= $1D (overflow)
        bcs     L_3E2C_check_type_0A                ; $3E1D
        
        ldy     #$0A                                ; $3E1F - Update 11 display positions

L_3E21_store_bonus2:
        sta     D_A756,y                            ; $3E21 - Store in second bonus array
        dey                                         ; $3E24
        bpl     L_3E21_store_bonus2                 ; $3E25
        
        dec     OPMASK                              ; $3E27 - Mark bonus collected
        jmp     D_3DA9                              ; $3E29 - Continue to state $36

L_3E2C_check_type_0A:
        cmp     #$0A                                ; $3E2C - Is it type $0A?
        bne     L_3E5E_check_type_08                ; $3E2E
        
        ; Type $0A: Adjust entity position and player assignment
        lda     #$26                                ; $3E30 - Set new state $26
        sta     PESSION,x                           ; $3E32
        
        lda     D_AA0C,x                            ; $3E34 - Get X position
        sec                                         ; $3E37
        sbc     #$14                                ; $3E38 - Subtract $14
        and     #$F8                                ; $3E3A - Align to 8-pixel grid
        adc     #$13                                ; $3E3C - Add offset (carry clear from AND)
        sta     D_AA0C,x                            ; $3E3E - Store new X position
        
        ldy     D_0193,x                            ; $3E41 - Get current player number
        lda     D_8520,y                            ; $3E44 - Look up player mapping
        tay                                         ; $3E47
        
        lda     #$84                                ; $3E48 - Default player number
        cpy     #$04                                ; $3E4A - Check ranges
        bcc     L_3E58_set_player                   ; $3E4C
        cpy     #$08                                ; $3E4E
        bcc     L_3E56_use_player_04                ; $3E50
        cpy     #$0A                                ; $3E52
        bcc     L_3E58_set_player                   ; $3E54

L_3E56_use_player_04:
        lda     #$04                                ; $3E56

L_3E58_set_player:
        sta     D_0193,x                            ; $3E58 - Set new player number
        jmp     D_3E94                              ; $3E5B - Jump to sprite setup

L_3E5E_check_type_08:
        cmp     #$08                                ; $3E5E - Is it type $08?
        bne     L_3E6E_reset_state                  ; $3E60
        
        ; Type $08: Deactivate entity
        lda     #$00                                ; $3E62
        sta     D_A9D6,x                            ; $3E64 - Clear entity flags
        lda     #$24                                ; $3E67 - Set inactive state
        sta     PESSION,x                           ; $3E69
        jmp     D_E758                              ; $3E6B - Jump to cleanup

L_3E6E_reset_state:
        lda     #$3C                                ; $3E6E - State $3C
        sta     PESSION,x                           ; $3E70
        lda     #$00                                ; $3E72 - Reset parameter
        jmp     routine_3CD7+14                     ; $3E74 - Jump back to @common_setup ($3CE5)

; Note: Code continues into bb-remaining.s at $3E77

;===============================================================================
; End of bb-bubble-handler.s
;===============================================================================
