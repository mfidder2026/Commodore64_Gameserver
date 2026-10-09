; ============================================================================
; BUBBLE BOBBLE - COLLISION DETECTION AND ENEMY SPAWNING ($0AAB-$0CF1)
; ============================================================================
; Contains:
;   - Player-enemy collision detection ($0AAB-$0BEC)
;   - Enemy spawn handler ($0BED-$0CF1)
;
; Collision handles both pushing enemies (when player faces them) and death
; (when enemy touches player from behind).
;
; Called every frame by main game loop.
; ============================================================================

.segment "CODE_GAMELOOP"

; ============================================================================
; CHECK_PLAYER_ENEMY_COLLISION ($0AAB)
; ============================================================================
; Checks if either player is touching an enemy.
; Called every frame. Handles both pushing enemies (when facing)
; and getting killed (when touched from behind/above).
;
; ALGORITHM:
;   FOR each player (2, then 1):
;     IF player state == $01 (normal walking)
;     AND player animation < $08 (not invincible)
;       IF player animation >= $04 (facing forward):
;         Check all 18 enemies for pushing collision
;       ELSE:
;         Check all 18 enemies for death collision
;
; COLLISION DETECTION:
;   - X distance < 20 pixels ($14) or 18 pixels ($12)
;   - Y distance < 14 pixels ($0E)
;
; PUSHING (animation >= 4):
;   - Moves enemy 3 pixels left (subtracts from X)
;   - Checks if enemy hits wall - if so, snaps to grid
;
; DEATH (animation < 4):
;   - Moves enemy 4 pixels right (adds to X)
;   - Checks if enemy hits wall - if so, snaps to grid
;   - Kills player (not implemented in this section)
;
; USES:
;   $3C (OLDLIN+1) - Temp storage for current player index

check_player_enemy_collision:
D_0AAB:
        ldy     #$01                            ; $0AAB - Start with player 2
check_player_loop:
L_0AAD:
        lda     a:ESSION,y                      ; $0AAD - Get player state ($B2+Y)
        cmp     #$01                            ; $0AB0 - State $01 = normal walking
        bne     next_player                     ; $0AB2 - Skip if not walking
        lda     D_8520,y                        ; $0AB4 - Get player animation frame
        cmp     #$08                            ; $0AB7 - Check if invincible/special
        bcs     next_player                     ; $0AB9 - Skip if protected
        ldx     #$11                            ; $0ABB - Check 18 enemy slots (0-17)
        cmp     #$04                            ; $0ABD - Animation frame >= 4?
        bcs     check_push_collision            ; $0ABF - Yes - check for pushing
        jmp     check_death_collision           ; $0AC1 - No - check for death collision

; ----------------------------------------------------------------------------
; CHECK FOR PUSHING COLLISION (player facing forward, can push enemy)
; ----------------------------------------------------------------------------
check_push_collision:
L_0AC4:
        lda     D_A9B2,x                        ; $0AC4 - Enemy state flags
        bne     next_enemy_push                 ; $0AC7 - Skip if enemy busy
        lda     PESSION,x                       ; $0AC9 - Enemy type ($CA+X)
        cmp     #$24                            ; $0ACB - Enemy type >= $24?
        bcs     next_enemy_push                 ; $0ACD - Skip (special enemies can't be pushed)

        ; Calculate X distance between player and enemy
        lda     a:FA,y                          ; $0ACF - Player X position
        sec                                     ; $0AD2
        sbc     D_AA0C,x                        ; $0AD3 - Subtract enemy X
        cmp     #$14                            ; $0AD6 - Within 20 pixels?
D_0AD8:
        bcs     next_enemy_push                 ; $0AD8 - No - skip

        ; Calculate Y distance (absolute value)
        lda     a:ZP_C2,y                       ; $0ADA - Player Y position
        sec                                     ; $0ADD
        sbc     D_AA1E,x                        ; $0ADE - Subtract enemy Y
        bcs     positive_y_push                 ; $0AE1 - Positive? Skip abs
        eor     #$ff                            ; $0AE3 - Make positive (2's complement)
        adc     #$01                            ; $0AE5
positive_y_push:
L_0AE7:
        cmp     #$0e                            ; $0AE7 - Within 14 pixels?
        bcc     push_enemy                      ; $0AE9 - Yes - push enemy!

next_enemy_push:
L_0AEB:
        dex                                     ; $0AEB - Next enemy
        bpl     check_push_collision            ; $0AEC - Loop through all enemies

next_player:
L_0AEE:
        dey                                     ; $0AEE - Next player
        bpl     check_player_loop               ; $0AEF - Loop through both players
        rts                                     ; $0AF1 - Done

; ----------------------------------------------------------------------------
; PUSH ENEMY (move enemy left 3 pixels)
; ----------------------------------------------------------------------------
push_enemy:
L_0AF2:
        lda     D_AA0C,x                        ; $0AF2 - Enemy X position
        sbc     #$03                            ; $0AF5 - Move left 3 pixels (carry already clear)
        sta     D_AA0C,x                        ; $0AF7 - Store new X

        lda     D_A9C4,x                        ; $0AFA - Enemy X sub-position
        sbc     #$02                            ; $0AFD - Subtract sub-pixels
        bcs     store_sub_x_push                ; $0AFF - No underflow? Store it
        and     #$03                            ; $0B01 - Wrap sub-position
        dec     ZP_DC,x                         ; $0B03 - Decrement screen column

store_sub_x_push:
L_0B05:
        sta     D_A9C4,x                        ; $0B05 - Store enemy X sub-position (9D C4 A9)
        sty     OLDLIN1                         ; $0B08 - Save current player index (84 3C)
        ldy     ZP_EE,x                         ; $0B0A - Load enemy Y row (B4 EE)

        ; Check if enemy is within valid Y bounds
        cpy     #$04                            ; $0B0C - Y position >= 4?
        bcc     next_enemy_push                 ; $0B0E - No - skip wall check
        cpy     #$1d                            ; $0B10 - Y position < 29?
        bcs     next_enemy_push                 ; $0B12 - No - skip wall check

        ; Calculate screen memory pointer for collision check
        lda     D_AD1E,y                        ; $0B14 - Get screen row low byte
        adc     ZP_DC,x                         ; $0B17 - Add enemy column
        sta     DATLIN1                         ; $0B19 - Store in pointer ($40)

        lda     D_AD3D,y                        ; $0B1B - Get screen row high byte
        and     #$03                            ; $0B1E - Mask to valid range
        adc     #>D_8500                        ; $0B20 - Add base address (D_8500 page)
        sta     DATPTR                          ; $0B22 - Store pointer high byte ($41)

        ; Check for walls in 3 positions
        lda     D_A9D6,x                        ; $0B24 - Enemy direction flag
        beq     check_mid_wall_push             ; $0B27 - If 0, skip top check

        ldy     #$00                            ; $0B29 - Check top position
        lda     (DATLIN1),y                     ; $0B2B - Read screen char
        bmi     hit_wall_push                   ; $0B2D - High bit = wall

check_mid_wall_push:
L_0B2F:
        ldy     #$28                            ; $0B2F - Check middle position
        lda     (DATLIN1),y                     ; $0B31 - Read screen char
        bmi     hit_wall_push                   ; $0B33 - High bit = wall
        ldy     #$50                            ; $0B35 - Check bottom position
        lda     (DATLIN1),y                     ; $0B37 - Read screen char
        bpl     no_wall_push                    ; $0B39 - No wall? Continue

; Enemy hit wall - snap to grid
hit_wall_push:
L_0B3B:
        inc     ZP_DC,x                         ; $0B3B - Restore column position
        lda     #$00                            ; $0B3D - Clear sub-position
        sta     D_A9C4,x                        ; $0B3F

        ; Snap X position to grid (8-pixel alignment)
        lda     D_AA0C,x                        ; $0B42 - Enemy X position
        sec                                     ; $0B45
        sbc     #$14                            ; $0B46 - Subtract offset
        adc     #$07                            ; $0B48 - Add rounding
        and     #$f8                            ; $0B4A - Align to 8-pixel grid
        adc     #$14                            ; $0B4C - Add offset back
        sta     D_AA0C,x                        ; $0B4E - Store aligned X

no_wall_push:
L_0B51:
        ldy     OLDLIN1                         ; $0B51 - Restore player index
        jmp     next_enemy_push                 ; $0B53 - Continue checking enemies

; ============================================================================
; CHECK FOR DEATH COLLISION (enemy touching player from behind)
; ============================================================================
check_death_collision:
D_0B56:
        lda     D_A9B2,x                        ; $0B56 - Enemy state flags
        bne     next_enemy_death                ; $0B59 - Skip if enemy busy
        lda     PESSION,x                       ; $0B5B - Enemy type ($CA+X)
        cmp     #$24                            ; $0B5D - Enemy type >= $24?
        bcs     next_enemy_death                ; $0B5F - Skip (special enemies)

        ; Calculate X distance (enemy X - player X)
        lda     D_AA0C,x                        ; $0B61 - Enemy X position
        sec                                     ; $0B64
        sbc     a:FA,y                          ; $0B65 - Subtract player X
        cmp     #$12                            ; $0B68 - Within 18 pixels?
        bcs     next_enemy_death                ; $0B6A - No - skip

        ; Calculate Y distance (absolute value)
        lda     a:ZP_C2,y                       ; $0B6C - Player Y position
        sec                                     ; $0B6F
        sbc     D_AA1E,x                        ; $0B70 - Subtract enemy Y
        bcs     positive_y_death                ; $0B73 - Positive? Skip abs
        eor     #$ff                            ; $0B75 - Make positive (2's complement)
        adc     #$01                            ; $0B77

positive_y_death:
L_0B79:
        cmp     #$0e                            ; $0B79 - Within 14 pixels?
        bcc     kill_player                     ; $0B7B - Yes - kill player!

next_enemy_death:
D_0B7D:
        dex                                     ; $0B7D - Next enemy
        bpl     check_death_collision           ; $0B7E - Loop through all enemies
D_0B80:
        jmp     next_player                     ; $0B80 - Check other player

; ----------------------------------------------------------------------------
; KILL PLAYER (move enemy right 4 pixels, enemy wins)
; ----------------------------------------------------------------------------
kill_player:
L_0B83:
        lda     D_AA0C,x                        ; $0B83 - Enemy X position
        adc     #$04                            ; $0B86 - Move right 4 pixels
        sta     D_AA0C,x                        ; $0B88 - Store new X

        lda     D_A9C4,x                        ; $0B8B - Enemy X sub-position
        adc     #$02                            ; $0B8E - Add sub-pixels
        and     #$03                            ; $0B90 - Wrap sub-position
        cmp     D_A9C4,x                        ; $0B92 - Did we overflow?
        bcs     store_sub_x_death               ; $0B95 - No - store it
        inc     ZP_DC,x                         ; $0B97 - Yes - increment column

store_sub_x_death:
L_0B99:
        sta     D_A9C4,x                        ; $0B99 - Store enemy X sub-position (9D C4 A9)
        sty     OLDLIN1                         ; $0B9C - Save current player index (84 3C)
        ldy     ZP_EE,x                         ; $0B9E - Load enemy Y row (B4 EE)

        ; Clamp Y position to valid bounds
        cpy     #$04                            ; $0BA0 - Y position >= 4?
D_0BA2:
        bcs     check_y_max_death               ; $0BA2 - Yes - check max
        ldy     #$04                            ; $0BA4 - Clamp to minimum

check_y_max_death:
L_0BA6:
        cpy     #$1d                            ; $0BA6 - Y position < 29?
        bcc     y_in_bounds_death               ; $0BA8 - Yes - continue
        ldy     #$1c                            ; $0BAA - Clamp to maximum
        clc                                     ; $0BAC - Clear carry for addition

y_in_bounds_death:
L_0BAD:
        ; Calculate screen memory pointer for collision check
        lda     D_AD1E,y                        ; $0BAD - Get screen row low byte
D_0BB0:
        adc     ZP_DC,x                         ; $0BB0 - Add enemy column
        sta     DATLIN1                         ; $0BB2 - Store in pointer ($40)

        lda     D_AD3D,y                        ; $0BB4 - Get screen row high byte
        and     #$03                            ; $0BB7 - Mask to valid range
        adc     #>D_8500                        ; $0BB9 - Add base address (D_8500 page)
        sta     DATPTR                          ; $0BBB - Store pointer high byte ($41)

        ; Check for walls in 3 positions
        lda     D_A9D6,x                        ; $0BBD - Enemy direction flag
        beq     check_mid_wall_death            ; $0BC0 - If 0, skip top check

        ldy     #$01                            ; $0BC2 - Check top-right position
        lda     (DATLIN1),y                     ; $0BC4 - Read screen char
        bmi     hit_wall_death                  ; $0BC6 - High bit = wall

check_mid_wall_death:
L_0BC8:
        ldy     #$29                            ; $0BC8 - Check middle-right position
        lda     (DATLIN1),y                     ; $0BCA - Read screen char
        bmi     hit_wall_death                  ; $0BCC - High bit = wall
        ldy     #$51                            ; $0BCE - Check bottom-right position
        lda     (DATLIN1),y                     ; $0BD0 - Read screen char
        bpl     no_wall_death                   ; $0BD2 - No wall? Continue

; Enemy hit wall - snap to grid
hit_wall_death:
L_0BD4:
        dec     ZP_DC,x                         ; $0BD4 - Restore column position
        lda     #$00                            ; $0BD6 - Clear sub-position
        sta     D_A9C4,x                        ; $0BD8

        ; Snap X position to grid (8-pixel alignment)
        lda     D_AA0C,x                        ; $0BDB - Enemy X position
        sec                                     ; $0BDE
        sbc     #$1c                            ; $0BDF - Subtract offset
        and     #$f8                            ; $0BE1 - Align to 8-pixel grid
        adc     #$13                            ; $0BE3 - Add offset back (carry set from AND)
        sta     D_AA0C,x                        ; $0BE5 - Store aligned X

no_wall_death:
L_0BE8:
        ldy     OLDLIN1                         ; $0BE8 - Restore player index
        jmp     next_enemy_death                ; $0BEA - Continue checking enemies

; ============================================================================
; ENEMY_SPAWN_HANDLER ($0BED)
; ============================================================================

.segment "CODE_GAMELOOP"
; Handles spawning new enemies into the level.
; Uses self-modifying code for spawn timer countdown.
;
; ALGORITHM:
;   - Countdown timer (22 frames between spawns)
;   - When timer expires:
;     * 40% chance to skip spawning this frame
;     * Choose one of 4 corner spawn locations randomly
;     * Check if that spawn point is available (screen memory test)
;     * Check if < 10 active enemies on screen
;     * Find first empty enemy slot (type == $FF)
;     * Initialize enemy at spawn location
;     * Choose random enemy type
;
; SELF-MODIFYING CODE:
;   $0BED - LDA #$01 (timer value, modified at $0BF7)
;   $0C9C - JMP $0CC1 (can be changed to other spawn logic)
;
; SPAWN LOCATIONS (X, Y):
;   0: ($0B, $00) - Top left
;   1: ($14, $00) - Top right  
;   2: ($0B, $1C) - Bottom left
;   3: ($14, $1C) - Bottom right
;
; USES:
;   $40 (DATLIN+1) - Spawn X coordinate
;   $41 (DATPTR)   - Spawn Y coordinate

enemy_spawn_handler:
D_0BED:
        lda     #$01                            ; $0BED - Timer value (self-modifying)
D_0BEE  = D_0BED + 1                            ; Label for self-modifying timer
        beq     spawn_enemy                     ; $0BEF - Timer expired? Spawn enemy
        dec     D_0BEE                          ; $0BF1 - Decrement timer (self-modifying code)
exit_spawn:
L_0BF4:
        rts                                     ; $0BF4 - Exit

spawn_enemy:
L_0BF5:
        lda     #$16                            ; $0BF5 - Reset spawn timer to 22 frames
        sta     D_0BEE                          ; $0BF7 - Store (self-modifying at $0BEE)
        lda     ZP_4A                           ; $0BFA - Check enemies remaining counter
        beq     exit_spawn                      ; $0BFC - Exit if no more enemies

        ; 40% chance to skip spawning this frame
        jsr     D_E9EA                          ; $0BFE - Get random number (0-255)
        cmp     #$28                            ; $0C01 - Less than 40 (15.6%)?
        bcc     exit_spawn                      ; $0C03 - Don't spawn this frame

        ; Choose random spawn location (one of 4 corners)
        ldx     #$0b                            ; $0C05 - Default spawn X = 11
        ldy     #$00                            ; $0C07 - Default spawn Y = 0
        jsr     D_E9EA                          ; $0C09 - Get random number
D_0C0C:
        and     #$03                            ; $0C0C - Random 0-3 (4 corners)
        bne     check_spawn_1                   ; $0C0E - Branch if not corner 0

        ; Corner 0: Top left ($0B, $00)
        lda     D_850A                          ; $0C10 - Check spawn point 0 availability
        bmi     exit_spawn                      ; $0C13 - Negative = blocked
        and     #$03                            ; $0C15 - Check lower 2 bits
        cmp     #$02                            ; $0C17 - Must equal 2
        bne     exit_spawn                      ; $0C19 - Not available? Exit
        beq     spawn_at_location               ; $0C1B - Use default X=$0B, Y=$00

check_spawn_1:
L_0C1D:
        cmp     #$01                            ; $0C1D - Corner 1?
        bne     check_spawn_2                   ; $0C1F - No, check corner 2

        ; Corner 1: Top right ($14, $00)
        lda     D_8514                          ; $0C21 - Check spawn point 1 availability
        bmi     exit_spawn                      ; $0C24 - Negative = blocked
        and     #$03                            ; $0C26 - Check lower 2 bits
        cmp     #$02                            ; $0C28 - Must equal 2
D_0C2A:
        bne     exit_spawn                      ; $0C2A - Not available? Exit
        ldx     #$14                            ; $0C2C - Spawn X = 20
        bne     spawn_at_location               ; $0C2E - Use Y=$00 (from earlier)

check_spawn_2:
L_0C30:
        cmp     #$02                            ; $0C30 - Corner 2?
        bne     check_spawn_3                   ; $0C32 - No, check corner 3

        ; Corner 2: Bottom left ($0B, $1C)
D_0C34:
        lda     D_88CA                          ; $0C34 - Check spawn point 2 availability
        bmi     exit_spawn                      ; $0C37 - Negative = blocked
        and     #$03                            ; $0C39 - Check lower 2 bits
        bne     exit_spawn                      ; $0C3B - Must equal 0
        ldy     #$1c                            ; $0C3D - Spawn Y = 28
        bne     spawn_at_location               ; $0C3F - Use X=$0B (from earlier)

check_spawn_3:
L_0C41:
        ; Corner 3: Bottom right ($14, $1C)
        lda     D_88D4                          ; $0C41 - Check spawn point 3 availability
        bmi     exit_spawn                      ; $0C44 - Negative = blocked
        and     #$03                            ; $0C46 - Check lower 2 bits
        bne     exit_spawn                      ; $0C48 - Must equal 0
        ldx     #$14                            ; $0C4A - Spawn X = 20
        ldy     #$1c                            ; $0C4C - Spawn Y = 28

spawn_at_location:
L_0C4E:
        stx     DATLIN1                         ; $0C4E - Store spawn X coordinate
        sty     DATPTR                          ; $0C50 - Store spawn Y coordinate

        ; Count active enemies (types $06-$0B)
        ldy     #$11                            ; $0C52 - Check all 18 enemy slots
D_0C54:
        ldx     #$00                            ; $0C54 - Counter = 0
count_enemies_loop:
L_0C56:
        lda     a:PESSION,y                     ; $0C56 - Get enemy type
        cmp     #$06                            ; $0C59 - Type >= $06?
        bcc     not_active                      ; $0C5B - No, skip
        cmp     #$0c                            ; $0C5D - Type < $0C?
        bcs     not_active                      ; $0C5F - No, skip
        inx                                     ; $0C61 - Count active enemy
not_active:
L_0C62:
        dey                                     ; $0C62 - Next slot
        bpl     count_enemies_loop              ; $0C63 - Loop all 18
        cpx     #$0a                            ; $0C65 - 10 or more enemies?
        bcs     exit_spawn                      ; $0C67 - Yes, don't spawn

        ; Find first empty enemy slot (type = $FF negative)
        ldy     #$11                            ; $0C69 - Start at slot 17
find_empty_slot:
L_0C6B:
        lda     a:PESSION,y                     ; $0C6B - Get enemy type
        bmi     found_empty_slot                ; $0C6E - Negative = empty slot
        dey                                     ; $0C70 - Next slot
        bpl     find_empty_slot                 ; $0C71 - Loop all 18
        rts                                     ; $0C73 - No empty slots? Exit

; ----------------------------------------------------------------------------
; INITIALIZE NEW ENEMY
; ----------------------------------------------------------------------------
found_empty_slot:
L_0C74:
        lda     #$00                            ; $0C74 - Clear state
        sta     D_A9B2,y                        ; $0C76 - Enemy state = 0 (active, can move)
        sta     D_A9C4,y                        ; $0C79 - X sub-position = 0
        sta     D_A9D6,y                        ; $0C7C - Direction flag = 0

        ; Set spawn position
        lda     DATLIN1                         ; $0C7F - Get spawn X (grid column)
        sta     a:ZP_DC,y                       ; $0C81 - Store enemy column
        asl                                     ; $0C84 - Multiply by 8
        asl                                     ; $0C85
        asl                                     ; $0C86
        adc     #$14                            ; $0C87 - Add offset (20 pixels)
        sta     D_AA0C,y                        ; $0C89 - Store enemy X position

        lda     DATPTR                          ; $0C8C - Get spawn Y (grid row)
        sta     a:ZP_EE,y                       ; $0C8E - Store enemy row
        asl                                     ; $0C91 - Multiply by 8
        asl                                     ; $0C92
        asl                                     ; $0C93
        adc     #$15                            ; $0C94 - Add offset (21 pixels)
        sta     D_AA1E,y                        ; $0C96 - Store enemy Y position

        ; Choose random enemy type
        jsr     D_E9EA                          ; $0C99 - Get random number
D_0C9C:
        jmp     D_0CC1                          ; $0C9C - Choose enemy type (self-modifying)

        ; ALTERNATE SPAWN LOGIC (unreachable - dead code)
        ; This code is never executed but exists in the original binary
        dec     ZP_4C                           ; $0C9F - Decrement temp storage
        bpl     L_0CA8_random_spawn             ; $0CA1 - Branch if still positive

        ; Self-modifying spawn type selector
        lda     #$4c                            ; $0CA3 - JMP opcode
        sta     D_0C9C                          ; $0CA5 - Modify jump at $0C9C
L_0CA8_random_spawn:
        jsr     D_E9EA                          ; $0CA8 - Get random number
        clc                                     ; $0CAB
        adc     D_5BFF                          ; $0CAC - Add to level seed
        and     #$07                            ; $0CAF - Mask to 0-7
        cmp     #$05                            ; $0CB1 - Less than 5?
        bcc     store_enemy_seed                ; $0CB3 - Yes, use it
        and     #$03                            ; $0CB5 - No, mask to 0-3
store_enemy_seed:
L_0CB7:
        sta     D_5BFF                          ; $0CB7 - Store new seed
        asl                                     ; $0CBA - Multiply by 2
        adc     #$0c                            ; $0CBB - Add 12 (types $0C-$1A)
        ldx     #$0d                            ; $0CBD - Default AI routine = 13
        bne     set_enemy_type                  ; $0CBF - Set the type

; Standard enemy type chooser
D_0CC1:
        and     #$00                            ; $0CC1 - Clear accumulator (use seed)
D_0CC2 := * - 1                                 ; SMC: operand byte
        sta     DATLIN1                         ; $0CC3 - Store random bits
        lda     #$82                            ; $0CC5 - Set special flag
        sta     D_A9FA,y                        ; $0CC7 - Store in enemy flags

        ; Select enemy type based on random bits
        lda     #$04                            ; $0CCA - Default enemy type $04
D_0CCC:
        ldx     #$0d                            ; $0CCC - Default AI routine = 13
        lsr     DATLIN1                         ; $0CCE - Shift random bit 0
        bcc     check_bit_1                     ; $0CD0 - Bit clear? Check next

        ; Bit 0 set: Enemy type $06
        lda     #$06                            ; $0CD2 - Enemy type $06
        ldx     #$0b                            ; $0CD4 - AI routine = 11
        bne     set_enemy_type                  ; $0CD6 - Set it

check_bit_1:
L_0CD8:
        lsr     DATLIN1                         ; $0CD8 - Shift random bit 1
        bcc     check_bit_2                     ; $0CDA - Bit clear? Check next

        ; Bit 1 set: Enemy type $08
        lda     #$08                            ; $0CDC - Enemy type $08
        ldx     #$0a                            ; $0CDE - AI routine = 10
        bne     set_enemy_type                  ; $0CE0 - Set it

check_bit_2:
L_0CE2:
        lsr     DATLIN1                         ; $0CE2 - Shift random bit 2
        bcc     set_enemy_type                  ; $0CE4 - Bit clear? Use default

        ; Bit 2 set: Enemy type $0A
        lda     #$0a                            ; $0CE6 - Enemy type $0A
D_0CE8:
        ldx     #$0d                            ; $0CE8 - AI routine = 13

; Store enemy type and AI routine
set_enemy_type:
L_0CEA:
        sta     a:PESSION,y                     ; $0CEA - Store enemy type ($CA+Y)
        txa                                     ; $0CED - Get AI routine index
        sta     D_A9E8,y                        ; $0CEE - Store AI routine ($E8+Y)
        rts                                     ; $0CF1 - Done!
