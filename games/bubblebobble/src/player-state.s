; ============================================================================
; rebb64 - Player State Routines ($045C-$05C4)
; ============================================================================
;
; This file contains player state checking, death handling, and join game logic.
;
; Key routines:
;   check_player_state ($045C) - Handles player death and respawn
;   check_join_game ($052A) - Checks if inactive player presses fire to join
;   D_05AD ($05AD) - Sound initialization helper
;   D_05B9 ($05B9) - Level column offset table
;   D_05C5 ($05C5) - Level initialization
;
; MODIFICATION POINTS:
; - For infinite lives: change "dec D_045A,x" to NOPs at lives_decrement
; - For more starting lives: modify the "lda #$04" at starting_lives
;
; ============================================================================

.segment "CODE_PLAYER_STATE"

; ============================================================================
; [CODE] CHECK_PLAYER_STATE ($045C)
; ============================================================================
; Checks player states, handles death and respawn.

check_player_state:
        ldx     #$01                ; a2 01 - Start with player 2
        ldy     #$00                ; a0 00
L_0460:
        lda     ENESSION,x          ; b5 b2 - Get player state
        cmp     #$0F                ; c9 0f - Dying?
        beq     L_04A0              ; f0 3a - Yes, handle death
L_0466:
        dex                         ; ca
        bpl     L_0460              ; 10 f7
        tya                         ; 98
        bpl     L_049D              ; 10 31
L_046C:
D_046C = L_046C                     ; Alias for external references
        lda     #(>__VIC_SCREEN_A__)+1  ; a9 51 - screen A + $100 page
        ldy     #$39                ; a0 39
        ldx     #$00                ; a2 00
        jsr     D_047B              ; 20 7b 04
        lda     #(>__VIC_SCREEN_A__)+2  ; a9 52 - screen A + $200 page
        ldy     #$51                ; a0 51
        ldx     #$01                ; a2 01
D_047B:
        sty     DATLIN1             ; 84 40
        sty     DATPTR1             ; 84 42
        sta     DATPTR              ; 85 41
        ora     #ARYTAB_SCREEN_TOGGLE ; 09 04 - advance to screen B
        sta     INPPTR              ; 85 43
        lda     D_045A,x            ; bd 5a 04
        bmi     L_049D              ; 30 13
        tax                         ; aa
        ldy     #$06                ; a0 06
L_048D:
        lda     #$20                ; a9 20
        cpx     #$00                ; e0 00
        beq     L_0496              ; f0 03
        lda     #$1D                ; a9 1d
        dex                         ; ca
L_0496:
        sta     (DATLIN1),y         ; 91 40
        sta     (DATPTR1),y         ; 91 42
        dey                         ; 88
        bpl     L_048D              ; 10 f0
L_049D:
        jmp     check_join_game     ; 4c 2a 05

L_04A0:
        jsr     D_7F53              ; 20 53 7f
        lda     D_5C3F              ; ad 3f 5c  Current song Y-value
        cmp     #(song_game_over - music_song_table)  ; c9 20
        bcc     L_04BB              ; 90 11  Skip if below game_over
        cmp     #(song_super_bonus - music_song_table) ; c9 4a
        beq     L_04BB              ; f0 0d  Skip if super_bonus playing
        stx     DATLIN1             ; 86 40
        sty     DATPTR              ; 84 41
        ldy     #(song_level_resume - music_song_table) ; a0 0b
        jsr     D_05AD              ; 20 ad 05  Resume level music
        ldx     DATLIN1             ; a6 40
        ldy     DATPTR              ; a4 41
L_04BB:
        lda     D_AB53,x            ; bd 53 ab
        eor     #$FF                ; 49 ff
        and     D_5B7F              ; 2d 7f 5b
        sta     D_5B7F              ; 8d 7f 5b
        lda     D_A737,x            ; bd 37 a7
        sta     D_8520,x            ; 9d 20 85
        lda     #$FF                ; a9 ff
        sta     D_87A0,x            ; 9d a0 87
        sta     D_87C8,x            ; 9d c8 87
        sta     D_87F0,x            ; 9d f0 87
        dey                         ; 88
        
; ============================================================================
; *** LIVES DECREMENT - PATCH POINT ***
; Change these 3 bytes to EA EA EA (NOP) for infinite lives
; ============================================================================
lives_decrement:
        dec     D_045A,x            ; de 5a 04 - DECREMENT LIVES
        
        bmi     L_04F0              ; 30 13 - Game over if negative
        lda     #$DD                ; a9 dd
        sta     ZP_C2,x             ; 95 c2
        lda     D_A735,x            ; bd 35 a7
        sta     FA,x                ; 95 ba
        lda     #$4A                ; a9 4a - 74 frames invincibility
        sta     D_8688,x            ; 9d 88 86
        lda     D_5A7F              ; ad 7f 5a
        bne     L_0502              ; d0 12
L_04F0:
        sty     DATPTR              ; 84 41
        lda     SUBFLG              ; a5 10
        sta     D_0409,x            ; 9d 09 04
        jsr     D_7BE8              ; 20 e8 7b
        ldy     DATPTR              ; a4 41
        lda     #$00                ; a9 00
        sta     FA,x                ; 95 ba
D_0500:
        sta     ZP_C2,x             ; 95 c2
L_0502:
        sta     ENESSION,x          ; 95 b2
        lda     TXTTAB              ; a5 2b
        bmi     L_0514              ; 30 0c
        lda     VARTAB              ; a5 2d
        bmi     L_0514              ; 30 08
        lda     #$00                ; a9 00
        sta     VARTAB              ; 85 2d
        lda     TXTTAB1             ; a5 2c
D_0512:
        sta     ZP_2A               ; 85 2a
L_0514:
        lda     ZP_4A               ; a5 4a
        cmp     #$02                ; c9 02
        bcc     L_0527              ; 90 0d
        stx     DATLIN1             ; 86 40
        inc     D_16EF              ; ee ef 16
D_051F:
        jsr     D_16E4              ; 20 e4 16
        dec     D_16EF              ; ce ef 16
        ldx     DATLIN1             ; a6 40
L_0527:
        jmp     L_0466              ; 4c 66 04

; ============================================================================
; [CODE] CHECK_JOIN_GAME ($052A)  
; ============================================================================
; Checks if inactive player presses fire to join.

check_join_game:
        ldx     #$01                ; a2 01
L_052C:
        lda     ENESSION,x          ; b5 b2
        bne     L_05A6              ; d0 76
.if .defined(BBLAN) .or .defined(ORIGLAYOUT)
        lda     bb_in0,x            ; BB-LAN: synced joystick
.else
        lda     CIA1_PRA,x          ; bd 00 dc - Read joystick
.endif
        and     #$10                ; 29 10    - Fire button
        bne     L_05A6              ; d0 6f    - Not pressed

; ============================================================================
; *** STARTING LIVES - PATCH POINT ***
; Change $04 to desired starting lives (e.g., $09 for 9 lives)
; ============================================================================
starting_lives:
        lda     #$04                ; a9 04 - 4 STARTING LIVES
        
        sta     D_045A,x            ; 9d 5a 04
        lda     #$0F                ; a9 0f
        sta     ENESSION,x          ; 95 b2
D_0540:
        lda     #$00                ; a9 00
        ldy     D_AB51,x            ; bc 51 ab
        sta     D_0400,y            ; 99 00 04
        dey                         ; 88
        sta     D_0400,y            ; 99 00 04
        dey                         ; 88
        sta     D_0400,y            ; 99 00 04
        sta     RIDBS,x             ; 95 ac
        iny                         ; c8
        tya                         ; 98
        sta     RODBE,x             ; 95 ae
        dec     D_53E4              ; ce e4 53
        dec     D_57E4              ; ce e4 57
        dec     RIDBE               ; c6 ab
        bpl     L_0565              ; 10 05
        lda     #$60                ; a9 60
        sta     L_049D              ; 8d 9d 04
L_0565:
        lda     #$E9                ; a9 e9
        ldy     #>__VIC_SCREEN_A__  ; a0 50
        cpx     #$01                ; e0 01
        bne     L_0571              ; d0 04
        lda     #$01                ; a9 01
        iny                         ; c8
        iny                         ; c8
L_0571:
        sta     ZP_02               ; 85 02
        sty     ZP_03               ; 84 03
        sta     ZP_04               ; 85 04
        sta     ZP_06               ; 85 06
        tya                         ; 98
        ora     #ARYTAB_SCREEN_TOGGLE ; 09 04 - convert to screen B page
        sta     ZP_05               ; 85 05
        eor     #SCREEN_TO_COLORRAM_EOR ; 49 8c - convert to Color RAM page
D_0580:
        sta     ZP_07               ; 85 07
        ldy     #$06                ; a0 06
L_0584:
        tya                         ; 98
        clc                         ; 18
        adc     #>__VIC_SCREEN_A__  ; 69 50 - advance Y by screen page offset
        tay                         ; a8
        lda     #$20                ; a9 20
        sta     (ZP_02),y           ; 91 02
        sta     (ZP_04),y           ; 91 04
        lda     D_8570,x            ; bd 70 85
        sta     (ZP_06),y           ; 91 06
        tya                         ; 98
        clc                         ; 18
        adc     #$28                ; 69 28
        tay                         ; a8
        lda     #$20                ; a9 20
        sta     (ZP_02),y           ; 91 02
        sta     (ZP_04),y           ; 91 04
        tya                         ; 98
D_05A0:
        sec                         ; 38
        sbc     #$79                ; e9 79
        tay                         ; a8
        bpl     L_0584              ; 10 de
L_05A6:
        dex                         ; ca
        bmi     L_05AC              ; 30 03
        jmp     L_052C              ; 4c 2c 05
L_05AC:
        rts                         ; 60

; ============================================================================
; SOUND INITIALIZATION ($05AD)
; ============================================================================
; Called to initialize sound system
; Calls BASIC ROM routines and sound player initialization

D_05AD:
        jsr     wait_one_frame                  ; Sync to frame boundary
.ifdef BBLAN
bb_sound_patch:
        jmp     bb_sound_start          ; BB-LAN: same, with the IRQ held off
        BB_PATCH_END bb_sound_patch, 9
.else
        sty     D_5C3F                  ; Store Y to temp
        jsr     music_start             ; Queue new song (IRQ picks it up next frame)
        jmp     sound_update            ; Process first frame immediately
.endif

; ============================================================================
; LEVEL COLUMN OFFSET TABLE ($05B9) - DATA
; ============================================================================
; Table of screen column offsets used for level rendering
; 12 entries, indexed by level type/variant

D_05B9:
        .byte   $30, $01, $04, $10      ; Offsets 0-3
        .byte   $20, $30, $40, $50      ; Offsets 4-7
        .byte   $60, $70, $80, $90      ; Offsets 8-11

; ============================================================================
; LEVEL INITIALIZATION ($05C5)
; ============================================================================
; Called at the start of each level to initialize game state
; Sets up entity arrays, clears buffers, initializes timers

D_05C5:
        ldx     #$03                    ; Initialize with value 3
        stx     D_8548+1                ; Store to entity array
        inx                             ; X = 4
        stx     D_8520+1                ; Store to entity array
        inx                             ; X = 5
        stx     D_8548                  ; Store to entity array
        lda     D_8729                  ; Get saved state high
        pha                             ; Save on stack
        lda     D_8728                  ; Get saved state low
        pha                             ; Save on stack
        ldy     #(song_level_resume - music_song_table) ; Default: resume
        lda     SUBFLG                  ; Get current level
        cmp     #$63                    ; Is it level 99?
        bne     L05E5                   ; If not, continue
        ldy     #(song_level_final - music_song_table) ; Level 99 theme
        .byte   $2C                     ; Skip next instruction (BIT abs)
L05E5:
        lda     D_5C3F                  ; Current song Y-value
        cmp     #(song_level_final - music_song_table) ; Compare to level_final
        bcc     L05F3                   ; If below, skip
        cmp     #(song_super_bonus - music_song_table) ; Compare to super_bonus
        beq     L05F3                   ; If super_bonus playing, skip
        jsr     D_05AD                  ; Re-init sound
L05F3:
        ldx     #$07                    ; Initialize 8 entities
L05F5:
        lda     #$FF                    ; Value $FF
        sta     D_87A0,x                ; Clear bubble state
        sta     D_87C8,x                ; Clear vertical state
        sta     D_87F0,x                ; Clear ascent state
        sta     D_8818,x                ; Clear bubble timer
        lda     #$00                    ; Value $00
        sta     D_86D8,x                ; Clear entity array
        sta     D_8700,x                ; Clear entity array
        sta     D_8728,x                ; Clear entity array
        txa                             ; Transfer X to A
        sta     D_86B0,x                ; Store index
        dex                             ; Next entity
        bpl     L05F5                   ; Loop if more
        pla                             ; Restore saved state low
        sta     D_8728                  ; Store back
        pla                             ; Restore saved state high
        sta     D_8729                  ; Store back
        txa                             ; X = $FF after loop
        ldx     #$11                    ; Clear 18 entity types
L0620:
        sta     PESSION,x               ; Clear entity type
        dex                             ; Next slot
        bpl     L0620                   ; Loop if more
        jsr     D_7BA6                  ; Call setup routine
        txa                             ; Transfer X to A
        ldx     #$23                    ; Clear 36 bytes
L062B:
        sta     ZP_DC,x                 ; Clear screen column array
        dex                             ; Next byte
        bpl     L062B                   ; Loop if more
        sta     D_8520                  ; Clear animation frame
        sta     ZP_21                   ; Clear level complete flag
        sta     $46                     ; Clear temp
        sta     $47                     ; Clear temp
        sta     D_58FF                  ; Clear game buffer
        sta     D_593F                  ; Clear game buffer
        sta     D_58BF                  ; Clear game buffer
        sta     SESSION                 ; Clear animation flag ($67)
        sta     ZP_68                   ; Clear timer
        sta     ARG                     ; Clear score value ($69)
        sta     ZP_B1                   ; Clear bubble count
        sta     ZP_B0                   ; Clear temp
        ldx     #$48                    ; Clear 73 bytes
L064E:
        sta     D_015D,x                ; Clear buffer
        dex                             ; Next byte
        bpl     L064E                   ; Loop if more
        ldx     #$05                    ; Clear 6 bytes
L0656:
        sta     FAC,x                   ; Clear FAC area ($61-$66)
        dex                             ; Next byte
        bpl     L0656                   ; Loop if more
        stx     D_A783                  ; Store $FF
        stx     D_A784                  ; Store $FF
        stx     VIC_SPR_ENA             ; Disable all sprites
        stx     ZP_6A                   ; Clear temp
        lda     #$10                    ; Value 16
        sta     D_5A7F                  ; Set buffer
        lda     #$0A                    ; Value 10
        sta     D_5ABF                  ; Set buffer
        jsr     D_F217                  ; Call sound routine
        lda     D_59BF                  ; Get level state
        cmp     SUBFLG                  ; Compare to current level
        bne     L0692                   ; If different, skip
        adc     D_59FF                  ; Add offset
        sta     D_59BF                  ; Store back
        inc     D_59FF                  ; Increment offset
        lda     SUBFLG                  ; Get level number
        asl     a                       ; Multiply by 2
        adc     #$09                    ; Add 9
L0688:
        cmp     #$2F                    ; Compare to 47
        bcc     L0690                   ; If < 47, done
        sbc     #$2E                    ; Subtract 46
        bne     L0688                   ; Loop if not zero
L0690:
        sta     ZP_68                   ; Store result
L0692:
        lda     SUBFLG                  ; Get level number
        cmp     #$63                    ; Is it level 99?
        bne     L_069B                  ; If not, continue
        jmp     D_7AE3                  ; Jump to special handler

; L_069B / clear_screen_buffers - Clear screen buffers routine
L_069B:
clear_screen_buffers:
        ldx     #$00                    ; Clear index
        txa                             ; A = 0
L069E:
        sta     D_7D00,x                ; Clear screen buffer 1
        sta     D_7D80,x                ; Clear screen buffer 2
        sta     D_7E00,x                ; Clear screen buffer 3
        inx                             ; Next byte
        bpl     L069E                   ; Loop for 128 bytes
        rts
