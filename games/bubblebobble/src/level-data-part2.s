; ============================================================================
; level-data-part2.s - Level data part 2 with disassembled routines
; ============================================================================
;
; This file contains the disassembled code routines from the level-data-part2
; memory region. The sprite data portions are loaded from TGA files via
; binaries.s (see LEVELS2_SPR1 and LEVELS2_SPR2 segments).
;
; Memory range: $7440-$7FFF (3008 bytes)
; - $7440-$7ABF: Sprite data (from bubble-dragon-in-bubble.tga + grumple-gromit.tga)
; - $7AC0-$7C3F: Code (LEVELS2_CODE1 segment, this file)
; - $7C40-$7E7F: Sprite data (from grumple-gromit.tga right-facing)
; - $7E80-$7FFF: Code (LEVELS2_CODE2 segment, this file)
;
; Key routines converted to assembly:
; - L_7AC0: Sprite data transform helper
; - D_7AE3: Level 99 (Super Drunk) special handler  
; - D_7B53: Credits display routine
; - D_7BA6: Clear entity state
; - D_7BB3: Bank RAM under I/O
; - D_7BC3/D_7BC6/D_7BC8: Wait for frames
; - D_7BD4: Clear player enemy state
; - D_7BDB: Set player enemy state
; - D_7BE8: Game over sequence
; - D_7BFE: Get terrain type
; - D_7C14: Toggle entity flag
; - D_7C21: Add score
; - D_7C37: Special level handler
; - D_7C3C: Timer decrement
; - D_7E80: Check pause (SPACE key)
; - D_7EB3: Read keyboard
; - D_7EC1: Check quit (RUN/STOP)
; - D_7F53: Player death handler
; - D_7F85/D_7F88: Level skip handlers
;
; ============================================================================

.setcpu "6502"

; ============================================================================
; LOCAL SYMBOL ALIASES
; ============================================================================
; Map shorter names to the symbols defined in master.s for readability
; Only define symbols that DON'T already exist in master.s

ZP_37       = MEMSIZ                ; Pause flag ($37)
ZP_3C       = OLDLIN1               ; Temp storage - current player index ($3C)
ZP_40       = DATLIN1               ; Temp storage ($40)
ZP_41       = DATPTR                ; Temp storage ($41)

; Symbols needed but not defined elsewhere
D_1288      = L1288                 ; Score handler routine
D_587F      = $587F                 ; Target level storage
; D_A739..D_A789 are now labels in GAMETABLES segment (binaries.s)

; NOTE: Sprite data for $7440-$7ABF is loaded in binaries.s (LEVELS2_SPR1 segment)
; Label sprite_data_7440 is defined there.

.segment "LEVELS2_CODE1"

; ============================================================================
; SPRITE TRANSFORM HELPER ($7AC0)
; ============================================================================
; Transforms a byte value for sprite rendering on level 99
; Called by the level 99 handler to process sprite data
;
; Input: A = byte to transform, Y = source offset
; Output: A = transformed byte, ZP_40 updated
; Modifies: A, ZP_40

L_7AC0:
        tay                         ; a8
        and     #$C0                ; 29 c0
        asl                         ; 0a
        rol                         ; 2a
        rol                         ; 2a
        sta     ZP_40               ; 85 40
        tya                         ; 98
        and     #$30                ; 29 30
        lsr                         ; 4a
        lsr                         ; 4a
        ora     ZP_40               ; 05 40
        sta     ZP_40               ; 85 40
        tya                         ; 98
        and     #$0C                ; 29 0c
        asl                         ; 0a
        asl                         ; 0a
        ora     ZP_40               ; 05 40
        sta     ZP_40               ; 85 40
        tya                         ; 98
        and     #$03                ; 29 03
        lsr                         ; 4a
        ror                         ; 6a
        ror                         ; 6a
        ora     ZP_40               ; 05 40
        rts                         ; 60

; ============================================================================
; LEVEL 99 SPECIAL HANDLER ($7AE3)
; ============================================================================
; Called when player reaches level 99 (Super Drunk / final boss level)
; Sets up special screen rendering for the boss battle by copying and
; transforming sprite data to screen memory
;
; Input: None
; Output: Screen memory updated for boss display
; Modifies: A, X, Y, ZP_02-05, ZP_3C, DATPTR

level_99_handler:
D_7AE3:
        lda     #$08                ; a9 08 - 9 iterations (0-8)
        sta     ZP_3C               ; 85 3c
@loop_outer:
        ldx     ZP_3C               ; a6 3c
        lda     tbl_7B2F,x          ; bd 2f 7b - Load source pointer low
        sta     ZP_02               ; 85 02
        lda     tbl_7B38,x          ; bd 38 7b - Load source pointer high
        sta     ZP_03               ; 85 03
        lda     tbl_7B41,x          ; bd 41 7b - Load dest pointer low
        sta     ZP_04               ; 85 04
        lda     tbl_7B4A,x          ; bd 4a 7b - Load dest pointer high
        sta     ZP_05               ; 85 05
        ldy     #$3E                ; a0 3e - 62 bytes per block
        ldx     #$15                ; a2 15 - 21 iterations inner loop
@loop_inner:
        sty     DATPTR              ; 84 41
        lda     (ZP_02),y           ; b1 02 - Get source byte
        jsr     L_7AC0              ; 20 c0 7a - Transform it
        dec     DATPTR              ; c6 41
        ldy     DATPTR              ; a4 41
        dey                         ; 88
        sta     (ZP_04),y           ; 91 04 - Store transformed byte
        iny                         ; c8
        lda     (ZP_02),y           ; b1 02
        jsr     L_7AC0              ; 20 c0 7a
        ldy     DATPTR              ; a4 41
        sta     (ZP_04),y           ; 91 04
        dey                         ; 88
        lda     (ZP_02),y           ; b1 02
        jsr     L_7AC0              ; 20 c0 7a
        ldy     DATPTR              ; a4 41
        iny                         ; c8
        sta     (ZP_04),y           ; 91 04
        dey                         ; 88
        dey                         ; 88
        dey                         ; 88
        dex                         ; ca
        bne     @loop_inner         ; d0 d7
        dec     ZP_3C               ; c6 3c
        bpl     @loop_outer         ; 10 b9
        rts                         ; 60

; --- Data tables for level 99 handler ---
; Source pointers (low bytes) - point into LEVELS2_SPR1 sprite data
tbl_7B2F:
        .byte   <(sprite_data_7440+$200),<(sprite_data_7440+$240),<(sprite_data_7440+$280)
        .byte   <(sprite_data_7440+$2C0),<(sprite_data_7440+$300),<(sprite_data_7440+$340)
        .byte   <(sprite_data_7440+$380),<(sprite_data_7440+$3C0),<(sprite_data_7440+$400)
; Source pointers (high bytes)
tbl_7B38:
        .byte   >(sprite_data_7440+$200),>(sprite_data_7440+$240),>(sprite_data_7440+$280)
        .byte   >(sprite_data_7440+$2C0),>(sprite_data_7440+$300),>(sprite_data_7440+$340)
        .byte   >(sprite_data_7440+$380),>(sprite_data_7440+$3C0),>(sprite_data_7440+$400)
; Dest pointers (low bytes) - point into LEVELS2_SPR2 sprite data
tbl_7B41:
        .byte   <(sprite_data_7C40+$80),<(sprite_data_7C40+$40),<(sprite_data_7C40+$00)
        .byte   <(sprite_data_7C40+$140),<(sprite_data_7C40+$100),<(sprite_data_7C40+$C0)
        .byte   <(sprite_data_7C40+$200),<(sprite_data_7C40+$1C0),<(sprite_data_7C40+$180)
; Dest pointers (high bytes)
tbl_7B4A:
        .byte   >(sprite_data_7C40+$80),>(sprite_data_7C40+$40),>(sprite_data_7C40+$00)
        .byte   >(sprite_data_7C40+$140),>(sprite_data_7C40+$100),>(sprite_data_7C40+$C0)
        .byte   >(sprite_data_7C40+$200),>(sprite_data_7C40+$1C0),>(sprite_data_7C40+$180)

; ============================================================================
; CREDITS DISPLAY ROUTINE ($7B53)
; ============================================================================
; Shows credits display after game over, handles continue prompt
;
; Input: None
; Output: Credits screen displayed
; Modifies: A, X, Y, ZP_40, ZP_41, RIDBS

credits_display:
D_7B53:
        ldx     #<D_AB93            ; a2 93
        ldy     #>D_AB93            ; a0 ab
        jsr     display_text_string ; Display routine
        jsr     update_sprite_animations ; Update sprites
        ldx     #$00                ; a2 00
        lda     D_045A              ; ad 5a 04 - Player 1 lives
        pha                         ; 48
        bpl     @p1_alive           ; 10 03
        stx     D_045A              ; 8e 5a 04 - Clear if negative
@p1_alive:
        lda     lives_p2            ; ad 5b 04 - Player 2 lives
        pha                         ; 48
        bpl     @p2_alive           ; 10 03
        stx     lives_p2            ; 8e 5b 04 - Clear if negative
@p2_alive:
        jsr     D_046C              ; 20 6c 04 - Check player state
        ldx     #$01                ; a2 01
@restore_loop:
        pla                         ; 68
        sta     D_045A,x            ; 9d 5a 04 - Restore lives
        bpl     @skip_gameover      ; 10 03
        jsr     game_over_sequence  ; 20 e8 7b - Show game over
@skip_gameover:
        dex                         ; ca
        bpl     @restore_loop       ; 10 f4
        ldx     RIDBE               ; a6 ab
        inx                         ; e8
        bpl     @credit_ok          ; 10 02
        ldx     #$00                ; a2 00
@credit_ok:
        txa                         ; 8a
        ora     #$20                ; 09 20
        sta     credits_count       ; 8d a4 7b
        ldx     #<credits_text      ; a2 96
        ldy     #>credits_text      ; a0 7b
        jmp     display_text_string ; Display text

; --- Credits text data ---
credits_text:
        .byte   $1F,$21,$17,$03     ; Position: column $21, row $17, length 3
        .byte   $43,$52,$45,$44,$49,$54,$53  ; "CREDITS"
        .byte   $1F,$24,$18         ; Position: column $24, row $18
credits_count:
        .byte   $00                 ; Credit count (modified at runtime)
        .byte   $10                 ; Terminator ($10 = end of text marker)

; ============================================================================
; CLEAR ENTITY STATE ($7BA6)
; ============================================================================
; Clears entity state array, initializes for new level
;
; Input: None
; Output: X=0, OPMASK=0
; Modifies: A, X

clear_entity_state:
D_7BA6:
        ldx     #$05                ; a2 05
        lda     #$FF                ; a9 ff
@loop:
        sta     D_A76F,x            ; 9d 6f a7
        dex                         ; ca
        bne     @loop               ; d0 fa
        stx     OPMASK              ; 86 4d
        rts                         ; 60

; ============================================================================
; BANK RAM UNDER I/O ($7BB3)
; ============================================================================
; Saves registers and banks in RAM at $D000-$DFFF
; Called at start of IRQ handlers to access game data under I/O
;
; Input: A, X, Y (to be saved)
; Output: RAM banked in at $D000-$DFFF
; Modifies: ZP_15-17, ZP_2E, R6510

bank_ram_under_io:
D_7BB3:
        sta     ZP_15               ; 85 15 - Save A
        stx     ZP_16               ; 86 16 - Save X
        sty     ZP_17               ; 84 17 - Save Y
        cld                         ; d8    - Clear decimal mode
        lda     R6510               ; a5 01 - Get CPU port
        sta     ZP_2E               ; 85 2e - Save it
        lda     #$35                ; a9 35 - RAM under I/O, BASIC off
        sta     R6510               ; 85 01
        rts                         ; 60

; ============================================================================
; WAIT FOR FRAME SYNC ($7BC3)
; ============================================================================
; Waits for a specified number of frames
;
; Entry points:
;   D_7BC3 - Wait 5 frames
;   D_7BC6 - Wait 10 frames
;   D_7BC8 - Wait N frames (counter in A)
;
; Input: A = frame count (or use specific entry point)
; Output: None
; Modifies: A

wait_5_frames:
D_7BC3:
        lda     #$05                ; a9 05
        .byte   $2C                 ; BIT abs - skip next 2 bytes
wait_10_frames:
D_7BC6:
        lda     #$0A                ; a9 0a
wait_frames:
D_7BC8:
        sta     D_0100              ; 8d 00 01 - Store counter on stack page
@loop:
        jsr     wait_one_frame              ; 20 94 e4 - Wait one frame
        dec     D_0100              ; ce 00 01
        bne     @loop               ; d0 f8
        rts                         ; 60

; ============================================================================
; PLAYER ENEMY STATE HANDLERS ($7BD4, $7BDB)
; ============================================================================

; Clear enemy state for a player entity
; Input: X = player index
; Output: Jump to enemy update routine
clear_player_enemy_state:
D_7BD4:
        lda     #$00                ; a9 00
        sta     PESSION,x           ; 95 ca
        jmp     D_E779              ; 4c 79 e7

; Set enemy state to $FF for player
; Input: X = player index
; Output: Jump to entity update
set_player_enemy_state:
D_7BDB:
        lda     #$FF                ; a9 ff
        sta     PESSION,x           ; 95 ca
        lda     #$00                ; a9 00
        sta     ZP_DC,x             ; 95 dc
        sta     ZP_EE,x             ; 95 ee
        jmp     D_E968              ; 4c 68 e9

; ============================================================================
; GAME OVER SEQUENCE ($7BE8)
; ============================================================================
; Called when a player loses all lives
; Updates display and handles game over state
;
; Input: X = player index
; Output: None
; Modifies: A, Y, ZP_40

game_over_sequence:
D_7BE8:
        stx     ZP_40               ; 86 40 - Save player index
        ldy     D_A739,x            ; bc 39 a7 - Get Y position offset
        sty     D_A73D              ; 8c 3d a7
        iny                         ; c8
        sty     D_A745              ; 8c 45 a7
        ldx     #<D_A73B            ; a2 3b
        ldy     #>D_A73B            ; a0 a7
        jsr     display_text_string ; Display "GAME OVER"
        ldx     ZP_40               ; a6 40
        rts                         ; 60

; ============================================================================
; GET TERRAIN TYPE ($7BFE)
; ============================================================================
; Gets terrain type for entity position
;
; Input: X = entity index
; Output: A = direction, Y = lookup index, ZP_40/41 = screen address
; Modifies: A, Y, ZP_40, ZP_41

get_terrain_type:
D_7BFE:
        lda     ZP_EE,x             ; b5 ee - Get entity row
        asl                         ; 0a   - *2 for table lookup
        tay                         ; a8
        lda     D_AC01,y            ; b9 01 ac - Screen address low
        adc     ZP_DC,x             ; 75 dc - Add column offset
        sta     ZP_40               ; 85 40
        lda     D_AC02,y            ; b9 02 ac - Screen address high
        adc     #>D_8500            ; 69 85 - Add page offset (D_8500 page)
        sta     ZP_41               ; 85 41
        lda     D_A9D6,x            ; bd d6 a9 - Get direction
        rts                         ; 60

; ============================================================================
; TOGGLE ENTITY FLAG ($7C14)
; ============================================================================
; Toggles bit 0 of entity flag, then jumps to score routine
;
; Input: X = entity index
; Output: A = $38
; Modifies: A, D_A9C4,x

toggle_entity_flag:
D_7C14:
        lda     D_A9C4,x            ; bd c4 a9
        eor     #$01                ; 49 01
        sta     D_A9C4,x            ; 9d c4 a9
        lda     #$38                ; a9 38
        jmp     D_1288              ; 4c 88 12

; ============================================================================
; ADD SCORE ($7C21)
; ============================================================================
; Adds score value to player's score using BCD arithmetic
;
; Input: X = player index
; Output: Score updated
; Modifies: A, Y

add_score:
D_7C21:
        ldy     D_AB51,x            ; bc 51 ab - Get player score offset
add_score_value:
D_7C24:
        lda     #$01                ; a9 01
        sed                         ; f8    - Set decimal mode
@add_loop:
        clc                         ; 18
        adc     D_0400,y            ; 79 00 04 - Add to score
        sta     D_0400,y            ; 99 00 04
        bcc     @done               ; 90 05 - No carry, done
        lda     #$01                ; a9 01
        dey                         ; 88
        bpl     @add_loop           ; 10 f2 - Continue adding carry
@done:
        cld                         ; d8    - Clear decimal mode
        rts                         ; 60

; ============================================================================
; SPECIAL LEVEL HANDLER ($7C37)
; ============================================================================
special_level_handler:
D_7C37:
        lda     #$45                ; a9 45
        jmp     D_7FB2              ; 4c b2 7f

; ============================================================================
; TIMER DECREMENT ($7C3C)
; ============================================================================
timer_decrement:
D_7C3C:
        dec     D_37C7,x            ; de c7 37 - X should be 0
        rts                         ; 60

; NOTE: Sprite data for $7C40-$7E7F is loaded in binaries.s (LEVELS2_SPR2 segment)
; Label sprite_data_7C40 is defined there.

.segment "LEVELS2_CODE2"

; ============================================================================
; CHECK PAUSE ($7E80)
; ============================================================================
; Check for SPACE key (pause game)
; When pressed, pauses game until SPACE is pressed again
;
; Input: None
; Output: Returns normally, or stays in pause loop
; Modifies: A, ZP_37, ZP_2A, ZP_5D, ZP_5E, D_A9B1

check_pause:
D_7E80:
        jsr     D_7EB6              ; 20 b6 7e - Read keyboard
        bne     check_pause_return  ; d0 2d - Key not pressed, return
        inc     ZP_37               ; e6 37 - Increment pause state
        lda     ZP_2A               ; a5 2a
        pha                         ; 48
        lda     D_A9B1              ; ad b1 a9
        pha                         ; 48
        lda     ZP_5D               ; a5 5d
        pha                         ; 48
        lda     ZP_5E               ; a5 5e
        pha                         ; 48
@wait_release1:
        jsr     read_keyboard_wait  ; 20 b3 7e - Wait for key release
        beq     @wait_release1      ; f0 fb
@wait_press:
        jsr     read_keyboard_wait  ; 20 b3 7e - Wait for key press
        bne     @wait_press         ; d0 fb
@wait_release2:
        jsr     read_keyboard_wait  ; 20 b3 7e - Wait for key release
        beq     @wait_release2      ; f0 fb
        pla                         ; 68
        sta     ZP_5E               ; 85 5e
        pla                         ; 68
        sta     ZP_5D               ; 85 5d
        pla                         ; 68
        sta     D_A9B1              ; 8d b1 a9
        pla                         ; 68
        sta     ZP_2A               ; 85 2a
        dec     ZP_37               ; c6 37
check_pause_return:                 ; Shared by check_quit
        rts                         ; 60

; ============================================================================
; READ KEYBOARD ($7EB3, $7EB6, $7EB8)
; ============================================================================
; Read keyboard for SPACE key
;
; Entry points:
;   D_7EB3 - Wait one frame then read
;   D_7EB6 - Read immediately  
;   D_7EB8 - Set row and read
;
; Output: Z flag set if SPACE pressed, A = keyboard value

read_keyboard_frame:
read_keyboard_wait:
D_7EB3:
        jsr     wait_one_frame              ; 20 94 e4 - Wait one frame
D_7EB6:
.if .defined(BBLAN) .or .defined(ORIGLAYOUT)
        lda     bb_key              ; BB-LAN: synced keyboard row 7
        BB_PATCH_END D_7EB6, 8
.else
        lda     #$7F                ; a9 7f - Select keyboard row
read_keyboard:
D_7EB8:
        sta     CIA1_PRA            ; 8d 00 dc
        lda     CIA1_PRB            ; ad 01 dc - Read keyboard column
.endif
        cmp     #$DF                ; c9 df - Check for SPACE ($DF when pressed)
        rts                         ; 60

; ============================================================================
; CHECK QUIT ($7EC1)
; ============================================================================
; Check for RUN/STOP key to quit game
;
; Input: None
; Output: If quit, jumps to title screen
; Modifies: A, X, ZP_37, D_5AFF

check_quit:
D_7EC1:
        jsr     D_7EB6              ; 20 b6 7e - Read keyboard
        cmp     #$BF                ; c9 bf - Check for RUN/STOP
        bne     check_pause_return  ; d0 ea - Not pressed, return (shares RTS with check_pause)
        ; RUN/STOP pressed - quit to title
        lda     #$00                ; a9 00
        sta     ZP_37               ; 85 37
        sta     D_5AFF              ; 8d ff 5a
        ldx     #$07                ; a2 07
        jsr     D_1E30              ; 20 30 1e
        jsr     D_1805              ; 20 05 18
.ifdef BBLAN
        jsr     bb_sound_init           ; BB-LAN: sound_init with IRQ held off
.else
        jsr     sound_init              ; 20 bd f4 - Init sound
.endif
        pla                         ; 68    - Clean up stack
        pla                         ; 68
        lda     #$19                ; a9 19
        jmp     D_7BC8              ; 4c c8 7b

; --- Text data for continue/game over messages ($7EA1-$7F52) ---
gameover_text_data:
        .byte   $00
        .byte   $1F,$0B,$08         ; Position code
        .byte   $8A,$8B,$97,$97,$97,$97,$97,$97,$40,$96
        .byte   $00
        .byte   $1F,$0B,$0C
        .byte   $8A,$8B,$97,$97,$97,$97,$97,$97,$40,$96
        .byte   $00
        .byte   $1F,$0B,$0D
        .byte   $8A,$8B,$97,$97,$97,$97,$97,$97,$40,$96
        .byte   $1F,$0D,$09
        .byte   $85,$86,$87,$87,$88,$89
        .byte   $1F,$0C,$0A
        .byte   $8A,$8B,$97,$97,$97,$97,$40,$96
        .byte   $1F,$0C,$0B
        .byte   $85,$86,$87,$87,$87,$87,$88,$89
        .byte   $1F,$0B,$0E
        .byte   $8A,$8B,$97,$97,$8C,$8E,$97,$97,$40,$96
        .byte   $1F,$0B,$0F
        .byte   $85,$86,$87,$87,$8D,$8F,$87,$87,$88,$89
        .byte   $1F,$0E,$16
        .byte   $90,$92,$94,$90
        .byte   $1F,$0E,$17
        .byte   $91,$93,$95,$91
        .byte   $10                 ; Terminator

; ============================================================================
; PLAYER DEATH RESPAWN HANDLER ($7F53)
; ============================================================================
; Called when a player dies to set up respawn state
; Handles level 99 special case with unique setup
;
; Input: X = player index
; Output: Player state updated for respawn
; Modifies: A, multiple ZP and memory locations

player_death_respawn:
D_7F53:
        lda     #$88                ; a9 88
        sta     D_A77D,x            ; 9d 7d a7
        and     #$08                ; 29 08
        sta     D_A77B,x            ; 9d 7b a7
        lsr                         ; 4a
        sta     D_A77F,x            ; 9d 7f a7
        sta     D_A781,x            ; 9d 81 a7
        lda     #$FF                ; a9 ff
        sta     D_A783,x            ; 9d 83 a7
        lda     #$00                ; a9 00
        sta     FAC,x               ; 95 61
        sta     FAC+2,x             ; 95 63
        sta     FAC+4,x             ; 95 65
        sta     D_37C7,x            ; 9d c7 37
        sta     D_8728,x            ; 9d 28 87
        sta     D_A813,x            ; 9d 13 a8
        sta     D_86D8,x            ; 9d d8 86
        lda     SUBFLG              ; a5 10 - Current level
        cmp     #$63                ; c9 63 - Level 99?
        bne     @done               ; d0 20 - No, skip special setup
        ; Level 99 special death handling
        lda     #$22                ; a9 22
        sta     FOUR6               ; 85 53
        sta     ZP_5E               ; 85 5e
        lda     #$51                ; a9 51
        sta     ZP_52               ; 85 52
        sta     ZP_5D               ; 85 5d
        lda     #$08                ; a9 08
        sta     D_A77B              ; 8d 7b a7
        sta     D_A77C              ; 8d 7c a7
        sta     ZP_4A               ; 85 4a
        lda     #$BD                ; a9 bd
        sta     D_23DE              ; 8d de 23
        lda     #$3C                ; a9 3c
        sta     D_0F73              ; 8d 73 0f
@done:
        rts                         ; 60

; ============================================================================
; LEVEL SKIP HANDLERS ($7FA4, $7FA7)
; ============================================================================
; Handles level skip cheat/powerup
;
; Entry points:
;   D_7FA4 - Skip 3 levels
;   D_7FA7 - Skip 7 levels
;   D_7FB2 - Entry with A already set (used by D_7C37)
;
; Input: None (or A = skip amount for D_7FB2)
; Output: Level advanced, screen updated
; Modifies: A, X, ZP_37, VIC registers

level_skip_3:
D_7FA4:
        lda     #$03                ; a9 03
        .byte   $2C                 ; BIT abs - skip next 2 bytes
level_skip_7:
D_7FA7:
        lda     #$07                ; a9 07
        clc                         ; 18
        adc     SUBFLG              ; 65 10 - Add to current level
        cmp     #$63                ; c9 63 - Cap at level 99
        bcc     @level_ok           ; 90 02
        lda     #$63                ; a9 63
@level_ok:
D_7FB2:                             ; Entry point from D_7C37
        sta     D_587F              ; 8d 7f 58
        pla                         ; 68    - Remove return addresses
        pla                         ; 68
        pla                         ; 68
        pla                         ; 68
        inc     ZP_37               ; e6 37
        ldx     #$06                ; a2 06
@flash_loop:
        lda     VIC_BORDER          ; ad 20 d0
        eor     #$02                ; 49 02 - Flash border
        sta     VIC_BORDER          ; 8d 20 d0
        sta     VIC_BG0             ; 8d 21 d0
        jsr     wait_10_frames      ; 20 c6 7b
        dex                         ; ca
        bne     @flash_loop         ; d0 ef
        jsr     D_2E79              ; 20 79 2e
        jsr     setup_player_sprites ; Setup player sprites
D_7FD4:                             ; Loop target for level advancement
        inc     SUBFLG              ; e6 10
        lda     SUBFLG              ; a5 10
        cmp     D_587F              ; cd 7f 58
        bne     @next_level         ; d0 04
        clc                         ; 18
        jmp     D_09A5              ; 4c a5 09
@next_level:
        jsr     setup_level_screen   ; 20 00 e0 - Level renderer
        jsr     D_37C9              ; 20 c9 37
        jsr     D_392A              ; 20 2a 39
        lda     #$00                ; a9 00
        sta     ZP_20               ; 85 20
        jmp     D_7FD4              ; 4c d4 7f - Loop back to check next level

; ============================================================================
; FINAL ROUTINE ($7FF1) - Not D_7FD4!
; ============================================================================
; This small routine is called from somewhere else
final_routine:
        lda     #$FE                ; a9 fe
        sta     D_8728,x            ; 9d 28 87
        rts                         ; 60

; --- Trailing data bytes ($7FF7-$7FFF) ---
trailing_data:
        .byte   $FF,$29,$FF,$FF,$00,$EF,$FF,$7D,$FF
