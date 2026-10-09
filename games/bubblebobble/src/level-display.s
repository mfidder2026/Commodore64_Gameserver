;===============================================================================
; bb-level-display.s - Level Display and Screen Setup Routines
;===============================================================================
; Address range: $37C7-$39D2
;
; This module handles:
; - Screen scrolling and row copying
; - Level number display (BCD conversion for levels 1-100)
; - Screen buffer manipulation
; - Tile processing and platform marking
; - Enemy spawn data pointer calculation
;===============================================================================

;===============================================================================
; DATA STORAGE ($37C7-$37C8)
;===============================================================================
; Two-byte storage area used for level completion bonus tracking
.segment "CODE_LEVEL_DISP"

D_37C7:
        .byte   $00,$00                                         ; $37C7

;===============================================================================
; LEVEL SCROLL AND DISPLAY SETUP ($37C9-$39D2)
;===============================================================================

; --- D_37C9: Initialize screen pointers and prepare level display ---
D_37C9:
        lda     #$00                                            ; $37C9
        sta     ZP_02                                           ; $37CB
        lda     #>__VIC_SCREEN_B__                              ; $37CD
        sta     ADRAY1                                          ; $37CF
        dec     SUBFLG                                          ; $37D1 - Decrement level number
        ldx     #$03                                            ; $37D3
L_37D5:
        jsr     D_38E9                                          ; $37D5 - Copy screen row
        ldy     #$1F                                            ; $37D8
L_37DA:
        lda     D_5398,y                                        ; $37DA - Load from source table
        cmp     #$10                                            ; $37DD
        bcs     L_37EB                                          ; $37DF - Branch if >= $10
        cmp     #$0D                                            ; $37E1
        bne     L_37E9                                          ; $37E3
        lda     #$20                                            ; $37E5 - Space character
        bne     L_37EB                                          ; $37E7 - Always branch
L_37E9:
        lda     #$0E                                            ; $37E9
L_37EB:
        sta     D_53C0,y                                        ; $37EB - Store to screen buffer
        dey                                                     ; $37EE
        bpl     L_37DA                                          ; $37EF - Loop through row
        lda     D_501E                                          ; $37F1 - Load position data
        sta     D_53C0                                          ; $37F4
        sta     D_53DE                                          ; $37F7 - Duplicate to alternate buffer
        lda     D_501F                                          ; $37FA
        sta     D_53C1                                          ; $37FD
        sta     D_53DF                                          ; $3800
        dex                                                     ; $3803
        bne     L_37D5                                          ; $3804 - Loop 3 times

        lda     #$F2                                            ; $3806 - Initialize row pointer
        sta     ZP_20                                           ; $3808
        ldx     #$04                                            ; $380A
L_380C:
        jsr     D_38E9                                          ; $380C - Copy screen row
        ldy     #$1D                                            ; $380F
L_3811:
        lda     (ZP_02),y                                       ; $3811 - Copy via pointer
        sta     D_53C0,y                                        ; $3813
        dey                                                     ; $3816
        bne     L_3811                                          ; $3817 - Loop through row
        lda     D_5050                                          ; $3819 - Load level data
        clc                                                     ; $381C
        adc     #$05                                            ; $381D
        sta     D_53C0                                          ; $381F - Store to screen
        sta     D_53DE                                          ; $3822
        adc     #$01                                            ; $3825
        sta     D_53C1                                          ; $3827
        sta     D_53DF                                          ; $382A
        lda     ZP_20                                           ; $382D
        sec                                                     ; $382F
        sbc     #$08                                            ; $3830 - Move to next row
        sta     ZP_20                                           ; $3832
        dex                                                     ; $3834
        bne     L_380C                                          ; $3835 - Loop 4 times

        ldx     #$19                                            ; $3837
D_3839:
        jsr     D_38E9                                          ; $3839 - Copy screen row
        ldy     #$1F                                            ; $383C
L_383E:
        lda     (ZP_02),y                                       ; $383E
        sta     D_53C0,y                                        ; $3840
        dey                                                     ; $3843
        bpl     L_383E                                          ; $3844 - Loop through row
        lda     ZP_02                                           ; $3846
        clc                                                     ; $3848
        adc     #$28                                            ; $3849 - Move 40 chars (1 screen row)
        sta     ZP_02                                           ; $384B
        bcc     L_3851                                          ; $384D
        inc     ADRAY1                                          ; $384F - Increment high byte
L_3851:
        lda     ZP_20                                           ; $3851
        sec                                                     ; $3853
        sbc     #$08                                            ; $3854
        sta     ZP_20                                           ; $3856
        dex                                                     ; $3858
        beq     L_385E                                          ; $3859 - Exit if done
        jmp     D_3839                                          ; $385B - Continue loop
L_385E:
        inc     SUBFLG                                          ; $385E - Restore level number

; --- D_3860: Setup level display numbers (BCD conversion) ---
D_3860:
        lda     #>__VIC_BANK_BASE__                             ; $3860
        sta     VERCK                                           ; $3862 - Store to $0A
        lda     D_5050                                          ; $3864 - Load level data
        asl                                                     ; $3867 - Multiply by 8
        asl                                                     ; $3868
        asl                                                     ; $3869
        sta     TRMPOS                                          ; $386A - Store to $09
        ldy     #$05                                            ; $386C
        lda     #$00                                            ; $386E
L_3870:
        sta     D_40D0,y                                        ; $3870 - Clear 6 bytes
        dey                                                     ; $3873
        bpl     L_3870                                          ; $3874
        ldy     #$06                                            ; $3876
        lda     (TRMPOS),y                                      ; $3878 - Load from pointer
        sta     D_40D6                                          ; $387A
        ldy     #$07                                            ; $387D
        lda     (TRMPOS),y                                      ; $387F
        sta     D_40D7                                          ; $3881
        ldy     #$0E                                            ; $3884
        lda     (TRMPOS),y                                      ; $3886
        sta     D_40DE                                          ; $3888
        ldy     #$0F                                            ; $388B
        lda     (TRMPOS),y                                      ; $388D
        sta     D_40DF                                          ; $388F
        ldy     SUBFLG                                          ; $3892 - Get current level
        iny                                                     ; $3894 - Level + 1 for display
        tya                                                     ; $3895
        cmp     #$64                                            ; $3896 - Check if level 100
        beq     L_38E3                                          ; $3898 - Special case for 100

; --- BCD conversion: convert level number to decimal digits ---
        ldy     #$00                                            ; $389A
L_389C:
        cmp     #$0A                                            ; $389C - Less than 10?
        bcc     L_38A5                                          ; $389E
        sbc     #$0A                                            ; $38A0 - Subtract 10 (carry already set)
        iny                                                     ; $38A2 - Increment tens digit
        bne     L_389C                                          ; $38A3 - Continue
L_38A5:
        pha                                                     ; $38A5 - Save ones digit
        sta     D_A9AF                                          ; $38A6
        tya                                                     ; $38A9
        sty     D_A9AE                                          ; $38AA - Store tens digit
        beq     L_38C3                                          ; $38AD - Skip if zero
        lda     D_A83C,y                                        ; $38AF - Load digit graphics pointer (low)
        sta     TRMPOS                                          ; $38B2
        lda     D_A848,y                                        ; $38B4 - Load digit graphics pointer (high)
        sta     VERCK                                           ; $38B7
        ldy     #$04                                            ; $38B9
L_38BB:
        lda     (TRMPOS),y                                      ; $38BB - Copy 5 bytes
        sta     D_40D0,y                                        ; $38BD
        dey                                                     ; $38C0
        bpl     L_38BB                                          ; $38C1
L_38C3:
        pla                                                     ; $38C3 - Restore ones digit
        tay                                                     ; $38C4
        lda     D_A83C,y                                        ; $38C5 - Load digit graphics pointer (low)
        sta     TRMPOS                                          ; $38C8
        lda     D_A848,y                                        ; $38CA - Load digit graphics pointer (high)
        sta     VERCK                                           ; $38CD
        ldy     #$04                                            ; $38CF
L_38D1:
        lda     (TRMPOS),y                                      ; $38D1 - Copy 5 bytes
        sta     D_40D8,y                                        ; $38D3
        dey                                                     ; $38D6
        bpl     L_38D1                                          ; $38D7
        ldy     #$1A                                            ; $38D9 - Store screen pointers
        sty     D_5000                                          ; $38DB
        iny                                                     ; $38DE
        sty     D_5001                                          ; $38DF
        rts                                                     ; $38E2

L_38E3:
        ; Special case: level 100 shown as "10" with special digits
        ldy     #$0A                                            ; $38E3
        lda     #$0B                                            ; $38E5
        bne     L_38A5                                          ; $38E7 - Jump to digit display code

; --- D_38E9: Copy screen row with delay ---
D_38E9:
        jsr     wait_one_frame                                          ; $38E9 - Wait for frame
        lda     #$00                                            ; $38EC
        sta     DATPTR+1                                        ; $38EE - Initialize pointers
        lda     #$28                                            ; $38F0
        sta     DATLIN+1                                        ; $38F2
        lda     #>__VIC_SCREEN_A__                              ; $38F4
        sta     DATPTR                                          ; $38F6
        sta     INPPTR                                          ; $38F8
        ldy     #$1F                                            ; $38FA
L_38FC:
        lda     (DATLIN+1),y                                    ; $38FC - Copy row data
        sta     (DATPTR+1),y                                    ; $38FE
        dey                                                     ; $3900
        bpl     L_38FC                                          ; $3901
        jsr     D_3860                                          ; $3903 - Setup display numbers
        stx     ZP_44                                           ; $3906 - Save X register
        ldx     #$17                                            ; $3908 - 24 rows to copy
L_390A:
        lda     DATLIN+1                                        ; $390A
        sta     DATPTR+1                                        ; $390C
        ldy     DATPTR                                          ; $390E
        sty     INPPTR                                          ; $3910
        clc                                                     ; $3912
        adc     #$28                                            ; $3913 - Next row (40 chars)
        sta     DATLIN+1                                        ; $3915
        bcc     L_391B                                          ; $3917
        inc     DATPTR                                          ; $3919 - Increment high byte
L_391B:
        ldy     #$1F                                            ; $391B
L_391D:
        lda     (DATLIN+1),y                                    ; $391D - Copy row
        sta     (DATPTR+1),y                                    ; $391F
        dey                                                     ; $3921
        bpl     L_391D                                          ; $3922
        dex                                                     ; $3924
        bne     L_390A                                          ; $3925 - Loop for all rows
        ldx     ZP_44                                           ; $3927 - Restore X register
        rts                                                     ; $3929

; --- D_392A: Level-specific timer setup ---
D_392A:
        lda     SUBFLG                                          ; $392A - Get current level
        ldx     #$1E                                            ; $392C - Default: 30 seconds
        cmp     #$37                                            ; $392E - Level 55?
        bne     L_3934                                          ; $3930
        ldx     #$0A                                            ; $3932 - Only 10 seconds
L_3934:
        cmp     #$38                                            ; $3934 - Level >= 56?
        bcc     L_393A                                          ; $3936
        ldx     #$14                                            ; $3938 - 20 seconds for higher levels
L_393A:
        stx     ZP_2A                                           ; $393A - Store timer
        stx     TXTTAB1                                         ; $393C
        ldx     #$27                                            ; $393E - 40 bytes to copy
L_3940:
        lda     D_40A8,x                                        ; $3940 - Copy layout data
        sta     D_4080,x                                        ; $3943
        sta     D_4880,x                                        ; $3946 - Duplicate to both buffers
        dex                                                     ; $3949
        bpl     L_3940                                          ; $394A

        ; --- Process screen tiles (fix tile indices) ---
        ldy     #$00                                            ; $394C
        sty     ZP_02                                           ; $394E
        lda     #>__VIC_SCREEN_A__                              ; $3950
        sta     ADRAY1                                          ; $3952
        ldx     #$04                                            ; $3954 - 4 pages to process
L_3956:
        lda     (ZP_02),y                                       ; $3956 - Load tile
        cmp     #$1A                                            ; $3958 - >= $1A?
        bcs     L_3964                                          ; $395A
        cmp     #$15                                            ; $395C - < $15?
        bcc     L_3964                                          ; $395E
        sbc     #$05                                            ; $3960 - Adjust tile index (carry set)
        sta     (ZP_02),y                                       ; $3962
L_3964:
        iny                                                     ; $3964
        bne     L_3956                                          ; $3965 - Loop through page
        inc     ADRAY1                                          ; $3967 - Next page
        dex                                                     ; $3969
        bne     L_3956                                          ; $396A - Loop for all pages

        jsr     wait_one_frame                                          ; $396C - Wait for frame
        lda     ZP_1D                                           ; $396F - Copy color values
        sta     ZP_1C                                           ; $3971
        lda     ZP_1F                                           ; $3973
        sta     ZP_1E                                           ; $3975
        jsr     wait_one_frame                                          ; $3977 - Wait for frame

        ; --- Mark platforms with high bit set ---
        ldy     #$00                                            ; $397A
        sty     ZP_02                                           ; $397C
        sty     ZP_04                                           ; $397E
        lda     #>__VIC_SCREEN_A__                              ; $3980
        sta     ADRAY1                                          ; $3982
        lda     #>D_8500                                        ; $3984
        sta     ADRAY2                                          ; $3986
        ldx     #$04                                            ; $3988 - 4 pages
L_398A:
        lda     (ZP_02),y                                       ; $398A - Load screen tile
        cmp     #$20                                            ; $398C
        bcs     L_399E                                          ; $398E - Skip if >= $20
        cmp     #$10                                            ; $3990
        bcc     L_399E                                          ; $3992 - Skip if < $10
        cmp     #$1E                                            ; $3994
        bcs     L_399E                                          ; $3996 - Skip if >= $1E
        lda     (ZP_04),y                                       ; $3998 - Load color attribute
        ora     #$80                                            ; $399A - Set high bit (platform marker)
        sta     (ZP_04),y                                       ; $399C
L_399E:
        iny                                                     ; $399E
        bne     L_398A                                          ; $399F - Loop through page
        inc     ADRAY1                                          ; $39A1 - Next page
        inc     ADRAY2                                          ; $39A3
        dex                                                     ; $39A5
        bne     L_398A                                          ; $39A6 - Loop for all pages

        ; --- Process enemy spawn data for current level ---
        lda     #<enemy_spawns                                  ; $39A8 - Spawn data pointer
        sta     ZP_02                                           ; $39AA
        lda     #>enemy_spawns                                  ; $39AC
        sta     ADRAY1                                          ; $39AE
        ldx     SUBFLG                                          ; $39B0 - Current level
        beq     L_39CD                                          ; $39B2 - Skip if level 0
L_39B4:
        ldy     #$00                                            ; $39B4
L_39B6:
        lda     (ZP_02),y                                       ; $39B6 - Find end of spawn data (zero byte)
        beq     L_39BF                                          ; $39B8
        iny                                                     ; $39BA - Skip 3 bytes per entry
        iny                                                     ; $39BB
        iny                                                     ; $39BC
        bne     L_39B6                                          ; $39BD
L_39BF:
        iny                                                     ; $39BF - Move past zero byte
        tya                                                     ; $39C0
        clc                                                     ; $39C1
        adc     ZP_02                                           ; $39C2 - Add offset to pointer
        sta     ZP_02                                           ; $39C4
        bcc     L_39CA                                          ; $39C6
        inc     ADRAY1                                          ; $39C8 - Increment high byte
L_39CA:
        dex                                                     ; $39CA
        bne     L_39B4                                          ; $39CB - Loop for each level
L_39CD:
        jsr     D_1E2E                                          ; $39CD - Get random spawn data
        sta     ZP_4A                                           ; $39D0 - Store enemy count
        ; Code continues in bb-remaining.s at $39D2
