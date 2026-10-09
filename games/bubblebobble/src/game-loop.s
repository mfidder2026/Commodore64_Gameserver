; ============================================================================
; rebb64 - Game Loop and Level Management
; ============================================================================
; This file contains the game start sequence, level initialization, and
; the main game loop that runs every frame during gameplay.
;
; ADDRESS RANGE: $08E4 - $0AAA
;
; KEY ROUTINES:
;   D_08E4 - Game start sequence (new game initialization)
;   D_090E - Level start setup
;   D_09A5 - Level initialization/transition
;   L_0A07 - Main game loop (heart of the game, runs every frame)
;   D_0AAB - Player-enemy collision detection
; ============================================================================

.setcpu "6502"
.segment "CODE_GAMELOOP"

; ============================================================================
; GAME START SEQUENCE ($08E4)
; ============================================================================
; Called when starting a new game. Sets up initial state for both players.
; ============================================================================
D_08E4:
        jsr     D_0885                          ; $08E4 - Initialize game state
        ldy     #(song_level_theme - music_song_table) ; $08E7
        jsr     D_05AD                          ; $08E9 - Start level theme
        ldx     #<D_AC41                        ; $08EC
        ldy     #>D_AC41                        ; $08EE
        jsr     display_text_string              ; $08F0 - Load data
        lda     #$74                            ; $08F3
        sta     FA                              ; $08F5 - Player 1 X
        lda     #$e4                            ; $08F7
        sta     FA1                             ; $08F9 - Player 2 X
        lda     #$83                            ; $08FB
        sta     ZP_C2                           ; $08FD - Player 1 Y
        sta     ZP_C3                           ; $08FF - Player 2 Y
        lda     ENESSION1                       ; $0901 - Player 2 state
        pha                                     ; $0903 - Save for later
        inc     ENESSION1                       ; $0904 - Increment player 2 state
        jsr     setup_player_sprites                          ; $0906
D_0909:
        jsr     wait_one_frame                          ; $0909 - Wait one frame

; ============================================================================
; LEVEL START SETUP ($090E)
; ============================================================================
; Initializes all game state variables at the start of each level
; ============================================================================
D_090E:
        ldx     #$01                            ; $090C
        stx     ZP_20                           ; $090E - Set game mode flag
        stx     D_F073                          ; $0910 - Self-modifying code target
        lda     #$ff                            ; $0913
        sta     VIC_SPR_ENA                     ; $0915 - Enable all sprites
        jsr     D_7BC8                          ; $0918 - Wait routine
        jsr     clear_screen                     ; $091B - Screen setup
        
        ; Clear various game state variables
        ldx     #$00                            ; $091E
        stx     ZP_54                           ; $0920
        stx     ZP_55                           ; $0922
        stx     D_0409                          ; $0924
        stx     D_040A                          ; $0927
        stx     D_59BF                          ; $092A
        stx     D_8728                          ; $092D
        stx     D_8729                          ; $0930
        lda     #$12                            ; $0933
        sta     D_5B3F                          ; $0935
        jsr     D_7F53                          ; $0938 - Player death handler (player 0)
        inx                                     ; $093B
        jsr     D_7F53                          ; $093C - Player death handler (player 1)
        jsr     D_E9EA                          ; $093F - Random number
        and     #$1e                            ; $0942
        adc     #$0a                            ; $0944
        sta     ZP_58                           ; $0946
        
        ; Set player starting positions
        lda     #$84                            ; $0948
        sta     FA                              ; $094A - Player 1 X
        lda     #$94                            ; $094C
        sta     FA1                             ; $094E - Player 2 X
        lda     #$b5                            ; $0950
        sta     ZP_C2                           ; $0952 - Player 1 Y
        sta     ZP_C3                           ; $0954 - Player 2 Y
        
        ; Set starting lives (3)
        ldx     #$03                            ; $0956
        stx     D_045A                          ; $0958
        stx     lives_p2                        ; $095B
        stx     D_59FF                          ; $095E
        
        ; Initialize counters
        ldx     #$07                            ; $0961
        stx     RIDBE                           ; $0963
        lda     #$00                            ; $0965
        ldx     #$05                            ; $0967
L_0969:
        sta     entry_0400,x                    ; $0969 - Clear score area
        dex                                     ; $096C
        bpl     L_0969                          ; $096D
        sta     RIDBS                           ; $096F
        sta     RODBS                           ; $0971
        lda     #$01                            ; $0973
        sta     RODBE                           ; $0975
        lda     #$04                            ; $0977
        sta     IRQTMP                          ; $0979
        
        ; Handle 2-player mode
        ldy     #$03                            ; $097B
        pla                                     ; $097D - Restore player 2 state
        bne     L_098A                          ; $097E - Skip if 2-player
        ldy     #$01                            ; $0980 - 1-player mode
        inc     RIDBE                           ; $0982
        sta     ENESSION1                       ; $0984
        sta     FA1                             ; $0986
        sta     ZP_C3                           ; $0988
L_098A:
        sty     D_5B7F                          ; $098A
        
        ; Self-modifying code setup
        lda     #$60                            ; $098D - RTS opcode
        sta     D_23DE                          ; $098F
        lda     #$4c                            ; $0992 - JMP opcode
        sta     D_0F73                          ; $0994
        sta     D_049D                          ; $0997
        lda     #<D_0BED                        ; $099A
        sta     D_0A39                          ; $099C - Modify instruction at D_0A39
        lda     #>D_0BED                        ; $099F
        sta     D_0A3A                          ; $09A1 - Modify instruction at D_0A3A
        sec                                     ; $09A4

; ============================================================================
; LEVEL INITIALIZATION ($09A5)
; ============================================================================
; Prepares the level for play. Can be called with carry set (new level)
; or carry clear (continue from death).
; ============================================================================
D_09A5:
        bcc     L_09D3                          ; $09A5 - Branch based on carry
        lda     #$00                            ; $09A7
        sta     VIC_SPR_ENA                     ; $09A9 - Disable sprites
        jsr     fill_color_ram                  ; $09AC
        jsr     setup_level_screen               ; $09AF
        jsr     D_37C9                          ; $09B2
        jsr     copy_charset_data                ; $09B5
        lda     #$0d                            ; $09B8
        jsr     fill_color_ram                  ; $09BA
        jsr     D_7B53                          ; $09BD
D_09C0:
        lda     #$09                            ; $09C0
        sta     D_D800                          ; $09C2 - Color RAM
        sta     D_D801                          ; $09C5 - Color RAM
        jsr     setup_player_sprites                          ; $09C8
        lda     #$ff                            ; $09CB
        sta     VIC_SPR_ENA                     ; $09CD - Enable sprites
        jmp     D_09DC                          ; $09D0

L_09D3:
        jsr     setup_level_screen               ; $09D3
        jsr     D_37C9                          ; $09D6
        jsr     copy_charset_data                ; $09D9

; ============================================================================
; FINAL LEVEL SETUP ($09DC)
; ============================================================================
; Final setup before entering main game loop
; ============================================================================
D_09DC:
        jsr     update_sprite_animations         ; $09DC - Update sprite animations
        jsr     decompress_level_data            ; $09DF
        jsr     D_392A                          ; $09E2
        jsr     D_05C5                          ; $09E5
        jsr     draw_animated_sprite            ; $09E8
        jsr     copy_and_mask_graphics          ; $09EB
        jsr     draw_player_digits              ; $09EE
        jsr     D_2B31                          ; $09F1
        jsr     copy_screen_buffers              ; $09F4
        jsr     D_17BE                          ; $09F7
        jsr     D_3C01                          ; $09FA
        lda     #$32                            ; $09FD - 50 frames = 1 second timer
        sta     TXTTAB                          ; $09FF - Frame sub-counter
        lda     #$00                            ; $0A01
        sta     ENDCHR                          ; $0A03 - Reset frame counter
        dec     MEMSIZ                          ; $0A05 - Unpause

; ============================================================================
; MAIN GAME LOOP ($0A07)
; ============================================================================
; This is the heart of the game - called every frame during gameplay.
; Processes all game logic: input, physics, enemies, collisions, etc.
;
; TIMING: The game runs at 25fps using a double-frame wait system.
; The loop executes once every 2 VIC frames (50Hz / 2 = 25Hz).
; ============================================================================
main_game_loop:
L_0A07:
.ifdef ORIGLAYOUT
        jsr     ol_pass                         ; test: count main loop passes
.else
        jsr     D_1844                          ; $0A07 - Update player input/movement
.endif
main_loop_entry:
D_0A0A:
        jsr     D_7E80                          ; $0A0A - Check for SPACE (pause)
        jsr     D_7EC1                          ; $0A0D - Check for RUN/STOP (quit)
        jsr     D_F1AC                          ; $0A10 - Update sound/music
        jsr     D_1578                          ; $0A13 - Update bubbles physics
        jsr     update_sprite_animations         ; $0A16 - Update sprite animations
        jsr     D_1319                          ; $0A19 - Update player sprites
        jsr     D_045C                          ; $0A1C - Check player state/join game
        
        ; Frame sync setup: Self-modifying code for double-buffer wait
        ; Stores current frame and next frame values for 2-frame wait (25fps)
        ldx     ENDCHR                          ; $0A1F - Frame counter
        stx     D_0A5D                          ; $0A21 - Modify CMP operand below
        inx                                     ; $0A24 - Frame + 1
        stx     D_0A61                          ; $0A25 - Modify second CMP operand
        
        ; Decrement invincibility timers
        lda     D_A824                          ; $0A28 - Player 1 invincibility
        beq     L_0A30                          ; $0A2B
        dec     D_A824                          ; $0A2D
L_0A30:
        lda     D_A825                          ; $0A30 - Player 2 invincibility
        beq     L_0A38                          ; $0A33
        dec     D_A825                          ; $0A35
L_0A38:
        jsr     D_0BED                          ; $0A38 - Spawn enemies
D_0A39 := L_0A38 + 1                           ; SMC: low byte of JSR operand
D_0A3A := L_0A38 + 2                           ; SMC: high byte of JSR operand
        lda     D_58FF                          ; $0A3B - Boss active flag
        beq     L_0A48                          ; $0A3E
        lda     D_593F                          ; $0A40 - Boss state
D_0A43:
        bne     L_0A48                          ; $0A43
        jsr     D_1AB6                          ; $0A45 - Update boss
L_0A48:
        jsr     D_E90E                          ; $0A48 - Update screen/graphics
        jsr     D_0AAB                          ; $0A4B - Check player-enemy collisions
        jsr     D_0CF2                          ; $0A4E - Update enemy AI
        jsr     D_13BE                          ; $0A51 - Process bubble captures
        jsr     D_2CB7                          ; $0A54 - Update collectibles
        jsr     D_32C1                          ; $0A57 - Check for EXTEND bonus
        
        ; Frame skip: Wait for 2 frames (25fps double-buffer sync)
wait_frame:
L_0A5A:
.ifdef BBLAN
        ; BB-LAN: bb_wait2 advances logical frames until the frame counter
        ; has moved two past the snapshot, then continues at bb_wf_after.
        ; The snapshot bytes keep their original addresses.
        jsr     bb_wait2                        ; never returns here
D_0A5D: .byte   $00                             ; frame snapshot (SMC)
        .byte   $EA, $EA
D_0A60: .byte   $EA
D_0A61: .byte   $01                             ; frame snapshot + 1 (SMC)
        .byte   $EA, $EA
bb_wf_after:
.else
        lda     ENDCHR                          ; $0A5A - Frame counter
        cmp     #$00                            ; $0A5C - Self-modified value
D_0A5D = * - 1                                  ; Label for self-modifying code
        beq     L_0A5A                          ; $0A5E - Wait until frame changes
D_0A60:
        cmp     #$01                            ; $0A60 - Self-modified value
D_0A61 = * - 1                                  ; Label for self-modifying code
        beq     L_0A5A                          ; $0A62 - Wait another frame
.endif
        
        ; Check if game should continue
        lda     ENESSION                        ; $0A64 - Player 1 state
        ora     ENESSION1                       ; $0A66 - Player 2 state
        beq     L_0A99                          ; $0A68 - Both dead = GAME OVER
        lda     ZP_21                           ; $0A6A - Level complete flag
        beq     L_0A07                          ; $0A6C - Not complete, loop back
        
        ; Level complete sequence
        lda     #$00                            ; $0A6E
        sta     MEMSIZ                          ; $0A70 - Pause flag
        sta     D_5AFF                          ; $0A72
        jsr     wait_one_frame                          ; $0A75 - Wait one frame
        jsr     D_2E79                          ; $0A78
        inc     SUBFLG                          ; $0A7B - Increment level
        lda     SUBFLG                          ; $0A7D - Current level
        ldx     #$01                            ; $0A7F
L_0A81:
        ldy     ENESSION,x                      ; $0A81 - Check player state
        beq     L_0A88                          ; $0A83
        sta     D_0409,x                        ; $0A85 - Store level for player
L_0A88:
        dex                                     ; $0A88
        bpl     L_0A81                          ; $0A89
        cmp     #$64                            ; $0A8B - Check if level 100 (ending)
        beq     L_0AA8                          ; $0A8D
        jsr     setup_player_sprites                          ; $0A8F
        lda     ZP_21                           ; $0A92 - Level complete flag
        cmp     #$7f                            ; $0A94
        jmp     D_09A5                          ; $0A96 - Start next level
        
L_0A99:
        ; Game over sequence
        inc     MEMSIZ                          ; $0A99 - Pause flag
        jsr     update_sprite_animations         ; $0A9B
        ldy     #(song_game_over - music_song_table) ; $0A9E
D_0AA0:
        jsr     D_05AD                          ; $0AA0 - Start game over music
        lda     #$96                            ; $0AA3
        jmp     D_7BC8                          ; $0AA5 - Wait routine

L_0AA8:
        ; Ending sequence (level 100 complete)
        jmp     D_A5B7                          ; $0AA8 - Ending sequence handler
