;===============================================================================
; bb-game-init.s - Game Initialization Routine
;===============================================================================
; Address range: $A428-$A631 (522 bytes including routines and data)
; Memory positions defined in linker config
;
; This module contains game initialization routines:
; - D_A428: Main initialization routine
; - D_A5A0: Clear screen areas
; - D_A5B7: Title screen setup with button wait
; - D_A625: Helper routine
;===============================================================================

; First part of game init code
        .segment "GAMEINIT1"

;-------------------------------------------------------------------------------
; Game Initialization Routine ($A428-$A47D)
;-------------------------------------------------------------------------------
; Called from:
;   - $2F91: Main game start
;   - $3621: Level transition/reset
;-------------------------------------------------------------------------------

D_A428:
        inc     MEMSIZ              ; e6 37 - Increment pause flag
        jsr     wait_one_frame              ; 20 94 e4 - Call screen setup routine
        jsr     D_2E79              ; 20 79 2e - Initialize game variables
        jsr     D_3293              ; 20 93 32 - Setup sprites
        jsr     D_1E2E              ; 20 2e 1e - Additional init
        
        stx     $5E                 ; 86 5e - Store X to temp location
        stx     $5D                 ; 86 5d
        stx     $2A                 ; 86 2a
        inx                         ; e8 - X = 1
        stx     $52                 ; 86 52

        ;-----------------------------------------------------------------------
        ; Clear memory regions $4600-$4700 (256 bytes each)
        ;-----------------------------------------------------------------------
@clear_mem_loop:
        sta     D_4600,x            ; 9d 00 46 - Clear $4600+X
        sta     D_4700,x            ; 9d 00 47 - Clear $4700+X
        dex                         ; ca
        bne     @clear_mem_loop     ; d0 f7 - Loop until X=0
        
        ;-----------------------------------------------------------------------
        ; Clear $4210-$422F (32 bytes)
        ;-----------------------------------------------------------------------
        ldx     #$1F                ; a2 1f - 31 bytes + 1 iteration
@clear_4210_loop:
        sta     D_4210,x            ; 9d 10 42 - Clear $4210+X
        dex                         ; ca
        bpl     @clear_4210_loop    ; 10 fa - Loop while X >= 0
        
        ;-----------------------------------------------------------------------
        ; Copy HUD font from $FE90 to $4300 (160 bytes)
        ;-----------------------------------------------------------------------
        ldx     #$A0                ; a2 a0 - 160 bytes
@copy_table_loop:
        lda     hud_font-1,x        ; bd 8f fe - Read from source table
        sta     D_4300,x            ; 9d 00 43 - Write to destination
        dex                         ; ca
        bne     @copy_table_loop    ; d0 f7 - Loop until X=0
        
        ;-----------------------------------------------------------------------
        ; Initialize zero page pointers
        ;-----------------------------------------------------------------------
        stx     OPMASK              ; 86 4d - Store 0 to OPMASK
        stx     D_4300              ; 8e 00 43 - Store 0 to $4300
        
        lda     #$2A                ; a9 2a
        sta     $02                 ; 85 02 - Setup pointer at $02
        sta     $04                 ; 85 04 - Setup pointer at $04
        sta     $06                 ; 85 06 - Setup pointer at $06
        
        lda     #>D_8500            ; a9 85
        sta     ADRAY1              ; 85 03 - High byte for $02 pointer
        
        lda     #>__VIC_SCREEN_A__      ; a9 50
        sta     ADRAY2              ; 85 05 - High byte for $04 pointer
        
        lda     #$D8                ; a9 d8
        sta     CHARONE             ; 85 07 - High byte for $06 pointer

        ;-----------------------------------------------------------------------
        ; Wait for screen setup completion
        ; Called directly via jsr from extend-bonus.s (READY screen setup)
        ;-----------------------------------------------------------------------
wait_screen:
        lda     ARYTAB+1            ; a5 30 - Check screen pointer high byte
        cmp     #>__VIC_SCREEN_B__    ; c9 54 - Is it screen B page?
        beq     @exit               ; f0 03 - Yes, exit
        jmp     D_1847              ; 4c 47 18 - No, jump to handler
        
@exit:
        rts                         ; 60 - Return

;-------------------------------------------------------------------------------
; Sprite Pattern Data - loaded via data/binaries.s
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; Clear Screen Areas ($A5A0-$A5B6)
;-------------------------------------------------------------------------------
; Clears specific screen memory regions
; Called from D_A5B7 (title screen setup)
; Memory position defined in linker config
;-------------------------------------------------------------------------------

        .segment "GAMEINIT2"

D_A5A0:
        jsr     D_0885              ; 20 85 08 - Clear/setup routine
        lda     #$1E                ; a9 1e - Character to fill with
        ldx     #$21                ; a2 21 - 33 bytes to clear
        
@clear_loop:
        sta     D_5053,x            ; 9d 53 50 - Clear screen area 1
        sta     D_D853,x            ; 9d 53 d8 - Clear color RAM area 1
        sta     D_525B,x            ; 9d 5b 52 - Clear screen area 2
        sta     D_DA5B,x            ; 9d 5b da - Clear color RAM area 2
        dex                         ; ca
        bpl     @clear_loop         ; 10 f1 - Loop while X >= 0
        rts                         ; 60

;-------------------------------------------------------------------------------
; Title Screen Setup with Button Wait ($A5B7-$A624)
;-------------------------------------------------------------------------------
; Sets up title screen and waits for fire button press
; Called from main menu/attract mode
;-------------------------------------------------------------------------------

; BB-LAN: the fire waits below read the synced input
.ifdef BBLAN
BB_JOY0 = bb_in0
BB_JOY1 = bb_in1
.else
BB_JOY0 = CIA1_PRA
BB_JOY1 = CIA1_PRB
.endif

D_A5B7:
        ldx     #$00                ; a2 00 (self-modified by joystick-input.s)
D_A5B8_smc = D_A5B7 + 1            ; SMC target: operand of ldx #imm above
        ldy     D_AB51,x            ; bc 51 ab - Load Y position from table
        dey                         ; 88 - Decrement
        sty     MEMSIZ+1            ; 84 38 - Store Y position
        lda     #$64                ; a9 64 - Set counter to 100
        sta     CURLIN              ; 85 39

        ;-----------------------------------------------------------------------
        ; Animation loop - runs 100 times
        ;-----------------------------------------------------------------------
@anim_loop:
        lda     #$10                ; a9 10 - Parameter for display routine
        ldy     MEMSIZ+1            ; a4 38 - Get Y position
        jsr     D_7C26              ; 20 26 7c - Display/update routine
        jsr     wait_one_frame              ; 20 94 e4 - Wait one frame
        jsr     update_sprite_animations ; Update sprites/display
        dec     CURLIN              ; c6 39 - Decrement counter
        bne     @anim_loop          ; d0 ef - Loop until counter = 0
        
        ;-----------------------------------------------------------------------
        ; Post-animation setup
        ;-----------------------------------------------------------------------
        lda     #$32                ; a9 32 - Delay value (50 frames)
        jsr     D_7BC8              ; 20 c8 7b - Wait with delay
        jsr     D_A5A0              ; 20 a0 a5 - Clear screen areas
        
        ldx     #$73                ; a2 73 - X parameter
        ldy     #$17                ; a0 17 - Y parameter
        jsr     display_text_string ; Sprite/entity update
        
        ldy     #(song_ending - music_song_table)
        jsr     D_05AD              ; Start ending music
        
        ;-----------------------------------------------------------------------
        ; Initialize title screen variables
        ;-----------------------------------------------------------------------
        lda     #$05                ; a9 05
        sta     $C0                 ; 85 c0 - Store to temp location
        
        lda     #$B3                ; a9 b3
        sta     ROESSION            ; 85 bd - Session variable
        
        lda     #$00                ; a9 00
        sta     FSESSION            ; 85 be - Clear session flag
        sta     $BF                 ; 85 bf - Clear temp
        
        lda     #$8D                ; a9 8d
        sta     $BC                 ; 85 bc - Setup parameter
        
        lda     #$FC                ; a9 fc
        sta     D_5AFF              ; 8d ff 5a - Store to memory
        sta     VIC_SPR_ENA         ; 8d 15 d0 - Enable all sprites

        ;-----------------------------------------------------------------------
        ; Wait for fire button press (either joystick port)
        ;-----------------------------------------------------------------------
@wait_press:
        jsr     wait_one_frame              ; 20 94 e4 - Wait one frame
        lda     BB_JOY0             ; ad 00 dc - Read joystick port 2
        and     #$10                ; 29 10 - Check fire button bit
        beq     @wait_release       ; f0 07 - Button pressed, wait for release
        lda     BB_JOY1             ; ad 01 dc - Read joystick port 1
        and     #$10                ; 29 10 - Check fire button bit
        bne     @wait_press         ; d0 ef - No button pressed, keep waiting

        ;-----------------------------------------------------------------------
        ; Wait for fire button release
        ;-----------------------------------------------------------------------
@wait_release:
        jsr     wait_one_frame              ; 20 94 e4 - Wait one frame
        lda     BB_JOY0             ; ad 00 dc - Read joystick port 2
        and     #$10                ; 29 10 - Check fire button bit
        beq     @wait_release       ; f0 f6 - Still pressed, keep waiting
        lda     BB_JOY1             ; ad 01 dc - Read joystick port 1
        and     #$10                ; 29 10 - Check fire button bit
        beq     @wait_release       ; f0 ef - Still pressed, keep waiting
        rts                         ; 60 - Return (button was pressed and released)

;-------------------------------------------------------------------------------
; Store X/Y and Jump to Sprite Update ($A625-$A631)
;-------------------------------------------------------------------------------
; Small helper routine that stores X and Y registers and jumps to sprite update
; Called from various game routines
;-------------------------------------------------------------------------------

D_A625:
        stx     D_A63D              ; 8e 3d a6 - Store X register
        sty     D_A63C              ; 8c 3c a6 - Store Y register
        ldx     #<D_A63A            ; a2 3a - Load X parameter
        ldy     #>D_A63A            ; a0 a6 - Load Y parameter
        jmp     display_text_string ; Jump to sprite/entity update

;===============================================================================
; End of bb-game-init.s
;===============================================================================
