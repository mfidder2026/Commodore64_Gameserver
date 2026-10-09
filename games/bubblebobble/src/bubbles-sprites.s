; ============================================================================
; BUBBLE PHYSICS AND SPRITE POSITIONING ($1578 - $1843)
; ============================================================================
; This section handles:
;   - Bubble animation and movement
;   - Bubble firing mechanics
;   - VIC-II sprite register updates
;   - Player/entity sprite positioning
; ============================================================================

.segment "CODE_SPRITES"

; ============================================================================
; UPDATE_BUBBLES ($1578)
; ============================================================================
; Updates bubble animations and movement for both players.
; Handles bubble firing animation frames and screen updates.
;
; Zero-page usage:
;   $5D/$5E - Bubble animation timer (P1/P2)
;   $52/$53 - Bubble state flags (P1/P2)
;   $4E/$4F - Bubble screen position low (P1/P2)
;   $50/$51 - Bubble screen position high (P1/P2)
; ============================================================================

update_bubbles:
        ldx     #$01                    ; a2 01    - Process both players (1,0)
        
bubble_player_loop:
        lda     $5d,x                   ; b5 5d    - Get bubble animation timer
        bpl     bubble_animation_done   ; 10 48    - Skip if timer not expired
        
        ; Reset animation timer and toggle bubble state
        lda     #$0b                    ; a9 0b    - Reset animation timer to 11
        sta     $5d,x                   ; 95 5d
        lda     $52,x                   ; b5 52    - Get bubble state flag
        cmp     #$ff                    ; c9 ff    - Is it $FF (inactive)?
        beq     bubble_animation_done   ; f0 3e    - Yes, skip
        
        ; Toggle bubble state flag (bit 7)
        eor     #$80                    ; 49 80    - Toggle high bit
        sta     $52,x                   ; 95 52
        bpl     bubble_animation_done   ; 10 38    - Skip if now positive
        
        ; Bubble is firing - set to inactive
        lda     #$ff                    ; a9 ff
        sta     $52,x                   ; 95 52
        
        ; Clear bubble display areas on screen
        lda     $4e,x                   ; b5 4e    - Get bubble screen low
        sta     DATLIN+1                ; 85 40
        sta     DATPTR+1                ; 85 42
        sta     $44                     ; 85 44
        lda     $50,x                   ; b5 50    - Get bubble screen high
        ora     #>__VIC_SCREEN_B__          ; 09 54    - Set to screen memory page
        sta     DATPTR                  ; 85 41
        eor     #ARYTAB_SCREEN_TOGGLE   ; 49 04    - Flip between screens
        sta     VARNAM                  ; 85 45
        adc     #$3b                    ; 69 3b    - Add color RAM offset
        sta     INPPTR                  ; 85 43
        
        ; Clear 3 rows of bubble display (8 bytes each)
        ldy     #$00                    ; a0 00
clear_bubble_row1:
        lda     (DATPTR+1),y            ; b1 42    - Read from screen
        sta     (DATLIN+1),y            ; 91 40    - Write to clear area 1
        sta     ($44),y                 ; 91 44    - Write to clear area 2
        iny                             ; c8
        lda     (DATPTR+1),y            ; b1 42
        sta     (DATLIN+1),y            ; 91 40
        sta     ($44),y                 ; 91 44
        
        ldy     #$28                    ; a0 28    - Next row (+40 bytes)
        lda     (DATPTR+1),y            ; b1 42
        sta     (DATLIN+1),y            ; 91 40
        sta     ($44),y                 ; 91 44
        iny                             ; c8
        lda     (DATPTR+1),y            ; b1 42
        sta     (DATLIN+1),y            ; 91 40
        sta     ($44),y                 ; 91 44
        
bubble_animation_done:
        dex                             ; ca       - Next player
        bpl     bubble_player_loop      ; 10 b1    - Loop for both players
        
; ============================================================================
; ANIMATION_TIMER_HANDLER ($15C9)
; ============================================================================
; Handles animation timing and color cycling for background effects.
; Manages flash effects and periodic color toggling.
; 
; Flow:
;   - If SESSION == 0, skip directly to level_timer_check
;   - If SESSION != 0, decrement it
;   - If SESSION still != 0, loop back to bubble_player_loop
;   - If SESSION == 0 after decrement, do color toggle then fall through
; ============================================================================

animation_timer_handler:
        lda     SESSION                 ; a5 67    - Get animation active flag
        beq     level_timer_check       ; f0 14    - Skip if no animation (branch to $15E1)
        dec     SESSION                 ; c6 67    - Decrement animation timer
        bne     L1577                   ; d0 a6    - Exit early if still counting (branch to rts)
        
        ; Animation timer hit zero - toggle background colors
        lda     ZP_1C                   ; a5 1c    - Get background color 1
        eor     #$07                    ; 49 07    - XOR with $07 (toggle color bits)
        sta     ZP_1C                   ; 85 1c    - Store back
        lda     ZP_1E                   ; a5 1e    - Get background color 2
        eor     #$07                    ; 49 07    - XOR with $07 (toggle color bits)
        sta     ZP_1E                   ; 85 1e    - Store back
        lda     #$32                    ; a9 32    - Reset sub-counter to 50
        sta     TXTTAB                  ; 85 2b

; ============================================================================
; LEVEL_TIMER_CHECK ($15E1)
; ============================================================================
; Checks level timer and handles baron hurry-up sequence.
; ============================================================================

level_timer_check:
        lda     ZP_2A                   ; a5 2a    - Get level timer
        beq     @start_hurryup          ; f0 03    - If zero, start hurry-up
        jmp     D_1694                  ; 4c 94 16 - Jump to baron handler

@start_hurryup:
        inc     MEMSIZ                  ; e6 37    - Increment pause flag
        lda     VARTAB                  ; a5 2d    - Get hurry-up state
        bne     @hurryup_active         ; d0 0a    - Branch if already active
        jsr     D_3AB8                  ; 20 b8 3a - Call hurry-up handler
        inc     VARTAB                  ; e6 2d    - Set hurry-up active
        lda     #$0a                    ; a9 0a    - New timer value
        jmp     D_168F                  ; 4c 8f 16 - Jump to continue

@hurryup_active:
        bpl     game_init_sequence      ; 10 27    - Branch if positive to $1621

; ============================================================================
; PLAYER_SPAWN_CHECK ($15FB)
; ============================================================================
; Checks if players need to spawn/respawn.
; ============================================================================

player_spawn_check:
        ldx     #$01                    ; a2 01    - Start with player 2
        
@spawn_loop:
        lda     ENESSION,x              ; b5 b2    - Get player state
        beq     @next_player            ; f0 19    - Skip if inactive
        cmp     #$01                    ; c9 01    - Is state 1 (normal)?
        beq     @next_player            ; f0 15    - Skip if normal
        cmp     D_5A7F                  ; cd 7f 5a - Compare with game mode flag
        bne     @exit_spawn             ; d0 15    - Exit early if not matching mode
        
        ; Player needs respawn setup
        lda     #$01                    ; a9 01    - Set to normal state
        sta     ENESSION,x              ; 95 b2    - Store player state
        lda     D_A813,x                ; bd 13 a8 - Get spawn data
        sta     D_8728,x                ; 9d 28 87 - Store to sprite data
        lda     D_8570,x                ; bd 70 85 - Get alternate color
        sta     D_8548,x                ; 9d 48 85 - Store to sprite color

@next_player:
        dex                             ; ca       - Next player
        bpl     @spawn_loop             ; 10 e0    - Loop both players
        inc     ZP_21                   ; e6 21    - Increment level complete flag
@exit_spawn:
        dec     MEMSIZ                  ; c6 37    - Decrement pause flag
        rts                             ; 60

; ============================================================================
; GAME_INIT_SEQUENCE ($1621)
; ============================================================================
; Initializes game state for new game or level.
; Sets up entity tables, sprite positions, and timers.
; ============================================================================

game_init_sequence:
        ldy     #(song_round_start - music_song_table) ; a0 43
        jsr     D_05AD                  ; 20 ad 05 - Start round music
        jsr     D_1AE8                  ; 20 e8 1a - Additional init routine
        
        ldx     #$ff                    ; a2 ff
        stx     ZP_58                   ; 86 58    - Initialize random seed
        inx                             ; e8       - X = 0
        stx     D_58FF                  ; 8e ff 58 - Clear special timer
        inx                             ; e8       - X = 1

; ============================================================================
; ENTITY_TABLE_CLEAR ($1633)
; ============================================================================
; Clears entity tables for fresh game state.
; ============================================================================

entity_table_clear:
        lda     #$00                    ; a9 00    - Zero value
        sta     D_A9D6,x                ; 9d d6 a9 - Clear direction flags
        sta     D_A9C4,x                ; 9d c4 a9 - Clear X sub-position
        sta     D_AA30,x                ; 9d 30 aa - Clear bubble type
        sta     D_AA42,x                ; 9d 42 aa - Clear saved enemy type
        jsr     D_E9EA                  ; 20 ea e9 - Random number generator
        and     #$01                    ; 29 01    - Mask to 0 or 1
        tay                             ; a8       - Transfer to Y
        lda     D_A777,y                ; b9 77 a7 - Get spawn position
        sta     ZP_DC,x                 ; 95 dc    - Store screen column
        sta     ZP_02,x                 ; 95 02    - Store temp
        jsr     D_E9EA                  ; 20 ea e9 - Random number generator
        and     #$01                    ; 29 01    - Mask to 0 or 1
        tay                             ; a8       - Transfer to Y
        lda     D_A779,y                ; b9 79 a7 - Get spawn Y position
        sta     ZP_EE,x                 ; 95 ee    - Store screen row
        sta     ZP_04,x                 ; 95 04    - Store temp
        lda     ENESSION,x              ; b5 b2    - Get entity state
        beq     @entity_inactive        ; f0 04    - Skip if inactive
        lda     #$3a                    ; a9 3a    - Active entity sprite
        sta     PESSION,x               ; 95 ca    - Store enemy type

@entity_inactive:
        dex                             ; ca       - Next entity
        bpl     entity_table_clear      ; 10 cd    - Loop all entities
        jsr     D_1B02                  ; 20 02 1b - Additional setup routine

; ============================================================================
; PLAYER_INIT_LOOP ($1669)
; ============================================================================
; Initializes player-specific data.
; ============================================================================

player_init_loop:
        ldx     #$01                    ; a2 01    - Start with player 2
        
player_init_loop_inner:
        lda     ENESSION,x              ; b5 b2    - Get player state
        beq     player_init_skip        ; f0 0e    - Skip if inactive
        lda     ZP_02,x                 ; b5 02    - Get temp X
        sta     ZP_DC,x                 ; 95 dc    - Store screen column
        lda     ZP_04,x                 ; b5 04    - Get temp Y
        sta     ZP_EE,x                 ; 95 ee    - Store screen row
D_1677:
        txa                             ; 8a       - Transfer X to A
        asl     a                       ; 0a       - Multiply by 2
        adc     #$2e                    ; 69 2e    - Add offset $2E
        sta     PESSION,x               ; 95 ca    - Store enemy type

player_init_skip:
        dex                             ; ca       - Next player
        bpl     player_init_loop_inner  ; 10 eb    - Loop both players
        stx     TXTTAB                  ; 86 2b    - Store -1 to sub-counter

; ============================================================================
; WAIT_FOR_FRAME_SYNC ($1681)
; ============================================================================
; Waits for frame sync and sets up level timer.
; ============================================================================

wait_for_frame_sync:
        inx                             ; e8       - X = 0
        stx     VARTAB                  ; 86 2d    - Clear hurry-up state
        
.if !SOUND_SONGS_LOOP
; Non-looping engine: wait for song to finish before starting next one.
@wait_loop:
        lda     SYESSION                ; a5 a4    - Wait for song to finish
        bne     @wait_loop              ; d0 fc
.endif
        
        ldy     #(song_level_complete - music_song_table) ; a0 27
        jsr     D_05AD                  ; 20 ad 05 - Level complete music
        lda     TXTTAB1                 ; a5 2c    - Get level timer setting
D_168F:                                 ; $168F - Entry point when A already set
        sta     ZP_2A                   ; 85 2a    - Store to level timer
        dec     MEMSIZ                  ; c6 37    - Decrement pause flag
        rts                             ; 60

; ============================================================================
; BARON_HURRYUP_HANDLER ($1694)
; ============================================================================
; Handles the Baron Von Blubba hurry-up sequence.
; When level timer expires, copies Baron sprite to screen and spawns Baron.
; ============================================================================

D_1694:
baron_hurryup_handler:
        lda     D_A9B1                  ; ad b1 a9 - Get hurry-up timer
        bne     baron_not_level_99      ; d0 41    - Skip all baron setup if timer > 0
        ldx     #$08                    ; a2 08    - 9 bytes to copy

@copy_baron_sprite:
        lda     D_8C9C,x                ; bd 9c 8c - Get baron sprite data
        sta     D_519C,x                ; 9d 9c 51 - Store to screen 1
        sta     D_559C,x                ; 9d 9c 55 - Store to screen 2
        lda     D_8CEC,x                ; bd ec 8c - Get baron color data
        sta     D_51EC,x                ; 9d ec 51 - Store to screen 1
        sta     D_55EC,x                ; 9d ec 55 - Store to screen 2
        lda     #$0d                    ; a9 0d    - Baron color (light green)
        sta     D_D99C,x                ; 9d 9c d9 - Store to color RAM 1
        sta     D_D9EC,x                ; 9d ec d9 - Store to color RAM 2
        dex                             ; ca       - Next byte
        bpl     @copy_baron_sprite      ; 10 e3    - Loop all bytes
        dec     D_A9B1                  ; ce b1 a9 - Decrement hurry-up timer

        ; Timer was zero, now check for level 99 special case
        lda     SUBFLG                  ; a5 10    - Get current level
        cmp     #$63                    ; c9 63    - Is it level 99?
        bne     baron_not_level_99      ; d0 19    - Branch if not

        ; Level 99 special Baron setup
        lda     #$74                    ; a9 74    - Baron X position
        sta     ZP_BC                   ; 85 bc    - Store to viewport X
        lda     #$65                    ; a9 65    - Baron Y position
        sta     ROESSION                ; 85 bd    - Store to super bonus Y
        ldy     #$06                    ; a0 06    - Y = 6
        sty     $bf                     ; 84 bf    - Store to temp
        dey                             ; 88       - Y = 5
        sty     $c0                     ; 84 c0    - Store to temp
        ldx     #$00                    ; a2 00    - X = 0
        stx     FSESSION                ; 86 be    - Clear super bonus state
        dex                             ; ca       - X = $FF
        stx     D_5AFF                  ; 8e ff 5a - Set sprites active
        stx     TXTTAB                  ; 86 2b    - Set sub-counter

baron_not_level_99:                     ; $16D9 - global label for cross-reference
        lda     VARTAB                  ; a5 2d    - Get hurry-up state
        bpl     bubble_state_check      ; 10 19    - Branch if positive (skip invincibility clear)
        ldx     ZP_4A                   ; a6 4a    - Get enemies remaining
baron_enemy_check:                      ; $16E0 - target for bne at $16F9
        cpx     #$01                    ; e0 01    - Only 1 enemy left?
        bne     check_bubble_states     ; d0 12    - Exit early if not

        ; Clear enemy invincibility when last one
D_16E4:
        ldx     #$05                    ; a2 05    - Start at entity 5

baron_clear_invincibility:
        lda     ZP_B4,x                 ; b5 b4    - Get bubble state
        beq     baron_next_entity       ; f0 09    - Skip if inactive
        cmp     #$0b                    ; c9 0b    - State >= $0B?
        bcs     baron_next_entity       ; b0 05    - Skip if >= $0B
        lda     #$ff                    ; a9 ff    - Set invincibility
D_16EF := * - 1                         ; SMC: operand byte
        sta     D_872A,x                ; 9d 2a 87 - Store to flags

baron_next_entity:
        dex                             ; ca       - Next entity
        bpl     baron_clear_invincibility ; 10 f0  - Loop all

; ============================================================================
; CHECK_BUBBLE_STATES ($16F6)
; ============================================================================
; Early exit point when enemy count check fails.
; ============================================================================

check_bubble_states:                    ; $16F6 - target for bne at $16E2 (early exit)
baron_hurryup_done:                     ; D_16EF defined in master.s
        rts                             ; 60

; ============================================================================
; BUBBLE_STATE_CHECK ($16F7)
; ============================================================================
; Actual bubble state processing. Reached via bpl from baron_not_level_99.
; ============================================================================

bubble_state_check:                     ; $16F7 - target for bpl at $16DC
        ldx     ZP_4A                   ; a6 4a    - Get enemies remaining
        bne     baron_enemy_check       ; d0 e5    - Branch back to enemy count check
        stx     D_58FF                  ; 8e ff 58 - Clear special timer
        dex                             ; ca       - X = $FF
        lda     FOUR6                   ; a5 53    - Get special item type
        bpl     @skip_p1_bubble         ; 10 04    - Skip if positive
        stx     FOUR6                   ; 86 53    - Store $FF
        bmi     @skip_p2_bubble         ; 30 02    - Branch always (negative)

@skip_p1_bubble:
        stx     ZP_5E                   ; 86 5e    - Store to P2 bubble timer

@skip_p2_bubble:
        lda     ZP_58                   ; a5 58    - Get random seed
        bpl     @use_timer              ; 10 08    - Branch if positive
        jsr     D_E9EA                  ; 20 ea e9 - Random number generator
        and     #$03                    ; 29 03    - Mask to 0-3
        jmp     store_timer             ; 4c 19 17

@use_timer:
        lda     ZP_2A                   ; a5 2a    - Get level timer
        adc     #$08                    ; 69 08    - Add 8

store_timer:                            ; $1719 - global label for jmp target
        sta     ZP_58                   ; 85 58    - Store to random seed

; ============================================================================
; ENTITY_STATE_UPDATE ($171B)
; ============================================================================
; Updates entity states for level completion.
; ============================================================================

entity_state_update:
        ldx     #$11                    ; a2 11    - Start at entity 17

@entity_loop:
        lda     PESSION,x               ; b5 ca    - Get enemy type
        bmi     @next_entity_state      ; 30 2c    - Skip if negative
        cmp     #$46                    ; c9 46    - Type $46?
        beq     @next_entity_state      ; f0 28    - Skip
        cmp     #$44                    ; c9 44    - Type $44?
        beq     @next_entity_state      ; f0 24    - Skip
        cmp     #$4a                    ; c9 4a    - Type $4A?
        beq     @next_entity_state      ; f0 20    - Skip
        sta     D_AA42,x                ; 9d 42 aa - Save enemy type
        tay                             ; a8       - Transfer to Y
        lda     #$3a                    ; a9 3a    - New sprite value
        cpy     #$04                    ; c0 04    - Type 4?
        beq     @check_timer            ; f0 08    - Type 4 -> check timer
        cpy     #$38                    ; c0 38    - Type < $38?
        bcc     @set_sprite             ; 90 10    - Type < $38 -> store default sprite
        cpy     #$42                    ; c0 42    - Type >= $42?
        bcs     @set_sprite             ; b0 0c    - Type >= $42 -> store default sprite

        ; Type is $38-$41 -> fall through to check timer
@check_timer:
        ldy     ZP_68                   ; a4 68    - Get timer
        beq     @set_sprite             ; f0 08    - If zero, store default sprite
        lda     D_A8E4,y                ; b9 e4 a8 - Get animation data
        sta     D_A9E8,x                ; 9d e8 a9 - Store AI index
        lda     #$4c                    ; a9 4c    - Special sprite value

@set_sprite:
        sta     PESSION,x               ; 95 ca    - Store enemy type

@next_entity_state:
        dex                             ; ca       - Next entity
        bpl     @entity_loop            ; 10 cd    - Loop all entities

; ============================================================================
; LEVEL_COMPLETE_CHECK ($1751)
; ============================================================================
; Checks if level is complete and triggers bonus sequence.
; ============================================================================

level_complete_check:
        lda     ARG                     ; a5 69    - Get score value
        beq     @no_bonus               ; f0 0b    - Skip if zero
        jsr     D_1E2E                  ; 20 2e 1e - Process bonus
        lda     #$15                    ; a9 15    - Reset value
        sta     ZP_B4                   ; 85 b4    - Store to bubble state
        sta     ZP_C6                   ; 85 c6    - Store to timer
        sta     ZP_C7                   ; 85 c7    - Store to timer

@no_bonus:
        lda     #$32                    ; a9 32    - Reset sub-counter
        sta     TXTTAB                  ; 85 2b
        lda     #$ff                    ; a9 ff    - Set hurry-up state
        sta     VARTAB                  ; 85 2d
        lda     #$09                    ; a9 09    - Reset timer
        sta     ZP_2A                   ; 85 2a    - Store level timer
        lda     ZP_68                   ; a5 68    - Get timer
        beq     @skip_special           ; f0 03    - Skip if zero
        jmp     D_3517                  ; 4c 17 35 - Jump to special handler

@skip_special:
        rts                             ; 60

; ============================================================================
; CONGRATULATIONS_TEXT ($1773)
; ============================================================================
; Text data for game completion messages.
; Format: $1F = control char, followed by X, Y, color, then text
; $40 = space in this encoding
; ============================================================================

congratulations_text:
        ; "CONGRATULATIONS" at row 5, column 12
        .byte   $1F,$0C,$05,$07         ; Control: X=12, Y=5, Color=7
        .byte   $43,$4F,$4E,$47,$52,$41,$54,$55  ; "CONGRATU"
        .byte   $4C,$41,$54,$49,$4F,$4E,$53      ; "LATIONS"

        ; "YOU HAVE COMPLETED BUBBLE BOBBLE" at row 8, column 4
        .byte   $1F,$04,$08,$05         ; Control: X=4, Y=8, Color=5
        .byte   $59,$4F,$55,$40,$48,$41,$56,$45  ; "YOU@HAVE"
        .byte   $40,$43,$4F,$4D,$50,$4C,$45,$54  ; "@COMPLET"
        .byte   $45,$44,$40,$42,$55,$42,$42,$4C  ; "ED@BUBBL"
        .byte   $45,$40,$42,$4F,$42,$42,$4C,$45  ; "E@BOBBLE"

        ; "\ WHAT HEROES \" at row 11, column 12
        .byte   $1F,$0C,$0B,$01         ; Control: X=12, Y=11, Color=1
        .byte   $5C,$40,$57,$48,$41,$54,$40,$48  ; "\@WHAT@H"
        .byte   $45,$52,$4F,$45,$53,$40,$5C      ; "EROES@\"

; ============================================================================
; GAME_COMPLETE_SEQUENCE ($17BE)
; ============================================================================
; Handles the game completion animation sequence.
; The first two bytes ($10 $A2) appear as "bpl $1762" which is mid-instruction
; but actually the code starts with these bytes which branch backward.
; ============================================================================

        .byte   $10                     ; $17BD - Dead byte (possibly padding)

game_complete_sequence:                 ; $17BE - Entry point for game completion
D_17BE = game_complete_sequence                         ; Alias for external references
save_entity_init:
        ldx     #$05                    ; a2 05    - Loop counter

save_entity_loop:
        lda     ZP_C4,x                 ; b5 c4    - Get entity Y+2
        sta     D_8892,x                ; 9d 92 88 - Save to buffer
        lda     #$15                    ; a9 15    - New state value
        sta     ZP_C4,x                 ; 95 c4    - Store entity state
        lda     #$00                    ; a9 00    - Clear value
        sta     D_85C2,x                ; 9d c2 85 - Clear collision flags
        dex                             ; ca       - Next entity
        bpl     save_entity_loop        ; 10 ef    - Loop all

; ============================================================================
; ANIMATION_DISPLAY_LOOP ($17D1)
; ============================================================================
; Displays the ending animation with scrolling credits.
; ============================================================================

animation_display_loop:
        lda     #$16                    ; a9 16    - Animation frame count
        sta     INPFLG                  ; 85 11    - Store to input flag

animation_frame_loop:                   ; $17D5 - Loop back point (after initial setup)
        jsr     wait_one_frame                  ; 20 94 e4 - Wait one frame
        jsr     wait_one_frame                  ; 20 94 e4 - Wait another frame
        jsr     update_sprite_positions ; 20 05 18 - Update sprites

        ldx     #$07                    ; a2 07    - 8 sprites

@sprite_anim_loop:
        lda     ENESSION,x              ; b5 b2    - Get entity state
        beq     @skip_sprite            ; f0 17    - Skip if inactive
        stx     TANSGN                  ; 86 12    - Save X
        jsr     D_1E87                  ; 20 87 1e - Update sprite animation
        ldx     TANSGN                  ; a6 12    - Restore X
        lda     ZP_C2,x                 ; b5 c2    - Get Y position
        cmp     D_8890,x                ; dd 90 88 - Compare with target
        beq     @at_target              ; f0 06    - Branch if at target
        inc     ZP_C2,x                 ; f6 c2    - Increment Y
        inc     ZP_C2,x                 ; f6 c2    - Increment again
        bne     @skip_sprite            ; d0 03    - Branch always

@at_target:
        dec     D_85C0,x                ; de c0 85 - Decrement fall counter

@skip_sprite:
        dex                             ; ca       - Next sprite
        cpx     #$01                    ; e0 01    - Done with both players?
        bne     @sprite_anim_loop       ; d0 e0    - Continue loop

        dec     INPFLG                  ; c6 11    - Decrement frame count
        bne     animation_frame_loop    ; d0 d1    - Loop to $17D5 (skip setup)
        rts                             ; 60

; ============================================================================
; UPDATE_SPRITE_POSITIONS ($1805)
; ============================================================================
; Updates VIC-II sprite registers with current player/entity positions.
; Processes sprites 0-7, setting X, Y positions and colors.
;
; For each sprite (X = 7 down to 0):
;   - Reads position from $BA+X (X coord), $C2+X (Y coord)
;   - Writes to VIC-II sprite position registers ($D000+)
;   - Sets sprite color from D_8548,X
;   - Handles invincibility flash (alternates colors from D_8570,X)
;   - Sets sprite pointer from D_8520,X (animation frame)
; ============================================================================

.segment "CODE_SPRITES"

update_sprite_positions:
        ldx     #$07                    ; a2 07    - 8 sprites (7 down to 0)
        ldy     #$0e                    ; a0 0e    - VIC offset (sprite 7 Y = $D00E)
        
sprite_pos_loop:
        lda     FA,x                    ; b5 ba    - Get entity X position ($BA+X)
        sta     VIC_SPR0_X,y            ; 99 00 d0 - Store to VIC sprite X
        lda     ZP_C2,x                 ; b5 c2    - Get entity Y position ($C2+X)
        sta     VIC_SPR0_Y,y            ; 99 01 d0 - Store to VIC sprite Y
        lda     D_8548,x                ; bd 48 85 - Get sprite color
        sta     VIC_SPR0_COL,x          ; 9d 27 d0 - Set sprite color register
        
        ; Check if entity is active and should flash
        lda     ENESSION,x              ; b5 b2    - Get entity state ($B2+X)
        beq     set_sprite_pointer      ; f0 0f    - Skip if inactive
        cmp     #$11                    ; c9 11    - State >= $11?
        bcs     set_sprite_pointer      ; b0 0b    - Skip special states
        lda     D_8728,x                ; bd 28 87 - Get invincibility flash timer
        beq     set_sprite_pointer      ; f0 06    - Skip if not flashing
        lda     D_8570,x                ; bd 70 85 - Get alternate color (flash)
        sta     VIC_SPR0_COL,x          ; 9d 27 d0 - Override color for flash effect
        
set_sprite_pointer:
        ; Set sprite pointer (which sprite image to display)
        lda     D_8520,x                ; bd 20 85 - Get animation frame
        and     #$1f                    ; 29 1f    - Mask to 32 frames
        sta     D_8520,x                ; 9d 20 85 - Store back
        clc                             ; 18
        adc     D_8598,x                ; 7d 98 85 - Add sprite base pointer
        sta     D_53F8,x                ; 9d f8 53 - Store to screen 1 sprite pointers
        sta     D_57F8,x                ; 9d f8 57 - Store to screen 2 sprite pointers
        
        dey                             ; 88       - Next VIC Y register
        dey                             ; 88       - (Y decrements by 2 per sprite)
        dex                             ; ca       - Next sprite
        bpl     sprite_pos_loop         ; 10 c6    - Loop all 8 sprites
        rts                             ; 60
