;===============================================================================
; bb-screen-scroll.s - Level intro screen scrolling animation
;===============================================================================
; Address range: $3AB8-$3C00
;
; Creates a smooth vertical scrolling "curtain rise" effect when entering a
; new level. Uses self-modifying code and double buffering for smooth animation.
;===============================================================================

;-------------------------------------------------------------------------------
; Screen scroll/animation routine - vertical scrolling effect for level intro
;-------------------------------------------------------------------------------
; Address: $3AB8-$3C00
; Creates a smooth vertical scrolling animation when entering a new level.
; Uses self-modifying code and double buffering for the effect.
;-------------------------------------------------------------------------------
.segment "CODE_LEVEL_DISP"

D_3AB8:
        jsr     wait_one_frame              ; Wait for frame sync
        
        ; Setup self-modifying code addresses (store screen page)
        lda     $30                 ; ARYTAB+1 (screen page)
        sta     D_3BF1              ; Modify code at $3BF1
        sta     D_3BFA              ; Modify code at $3BFA
        sta     D_3AF0              ; Modify code at $3AF0 (self-mod target)
        
        ; Calculate alternate screen addresses
        eor     #ARYTAB_SCREEN_TOGGLE ; Toggle screen page
        clc
        adc     #$03
        sta     $41                 ; DATPTR - pointer high byte
        lda     $2F                 ; ARYTAB (screen page low)
        adc     #$01
        sta     $24                 ; INDEX2
        eor     #ARYTAB_CHARSET_TOGGLE
        sta     $19                 ; TEMPST
        
        ; Initialize screen pointers
        lda     #$CC
        sta     $40                 ; DATLIN+1 (screen pointer high)
        sta     $3E                 ; OLDTXT+1
        lda     #$B8
        sta     $18                 ; Screen output pointer low
        sta     $23                 ; Second screen pointer
        lda     #$DB
        sta     $3F                 ; DATLIN (screen pointer low)
        
        ; Copy initial data block
        jsr     D_16E4              ; Setup call
        inx

smc_copy_init_loop:
@copy_init_data:
        lda     D_3CB2,x            ; Source data
        sta     D_1200,x            ; Copy to destination
        inx
        bne     @copy_init_data     ; Loop until X wraps to 0
D_3AF0 := smc_copy_init_loop + 5   ; SMC: high byte of sta D_1200,x operand
        
        ; Setup scroll parameters
        lda     #$19                ; 25 rows to scroll
        sta     $42                 ; DATPTR+1 (row counter)
        ldy     #$30                ; Column offset
        ldx     #$08                ; 9 bytes per row

@save_row_data:
        lda     ($40),y             ; Read from screen buffer 1
        sta     D_3CC4,x            ; Save to temp buffer 1
        lda     ($3E),y             ; Read from screen buffer 2
        sta     D_3CCD,x            ; Save to temp buffer 2
        dey
        dex
        bpl     @save_row_data      ; Loop at $3B08
        
        ; Main scroll loop - process each row (D_3B0A in reference)
scroll_loop_init_3B0A:
        ldx     #$00
        stx     $3D                 ; OLDTXT (row index)
        stx     $3C                 ; OLDLIN+1

@process_row:
        ldy     $3D                 ; Get row index
        lda     ($3E),y             ; Read color data
        sta     D_3CBB,y            ; Store color
        lda     ($40),y             ; Read screen data
        sta     D_3CB2,y            ; Store screen char
        tay                         ; Use as index
        
        ; Get character definition pointer
        lda     D_0200,y            ; Character pointer low
        sta     $44
        lda     D_0300,y            ; Character pointer high
        ora     $2F                 ; ARYTAB
        eor     #ARYTAB_CHARSET_TOGGLE ; Select alternate charset page
        sta     $45                 ; VARNAM
        
        ; Process 8 bytes of character data
        ldy     #$00

@process_char_byte:
        lda     ($44),y             ; Get character byte
        ora     D_ADB1,x            ; OR with mask table
        sta     D_3CD6,x            ; Store to output buffer 1
        and     D_ADF9,x            ; AND with second mask
        ora     D_ADB1,x            ; OR with mask again
        sta     D_3D1E,x            ; Store to output buffer 2
        inx
        iny
        cpy     #$08                ; 8 bytes per character
        bne     @process_char_byte
        
        inc     $3D                 ; Next row
        cpx     #$48                ; 72 bytes total (9 chars * 8)
        bne     @process_row
        
        ; Frame sync and fill bottom row
        jsr     wait_one_frame              ; Wait for frame
        ldy     #$08
        clc

@fill_bottom:
        tya
        adc     #$37                ; Character code (space)
        sta     ($40),y             ; Write to screen
        lda     #$0F                ; White color
        sta     ($3E),y             ; Write color
        dey
        bpl     @fill_bottom
        
        ; Restore saved row data
        ldx     #$08
        ldy     #$30

@restore_row:
        lda     D_3CC4,x            ; Get saved screen data
        sta     ($40),y             ; Write to screen
        lda     D_3CCD,x            ; Get saved color
        sta     ($3E),y             ; Write color
        lda     D_3CBB,x            ; Rotate buffers
        sta     D_3CCD,x
        lda     D_3CB2,x
        sta     D_3CC4,x
        dey
        dex
        bpl     @restore_row
        
        ; Copy processed data to screen
        ldy     #$47                ; 72 bytes

@copy_to_screen:
        lda     D_3CD6,y            ; Get processed character data
        sta     ($18),y             ; Write to screen
        dey
        bpl     @copy_to_screen
        
        ; Check if scroll complete
        lda     $42                 ; DATPTR+1 (row counter)
        cmp     #$0C                ; 12 rows remaining?
        bne     advance_scroll_3BA7
        
        ; Final rows - copy second buffer
        ldy     #$47

@copy_final:
        lda     D_3D1E,y            ; Get second buffer data
        sta     ($18),y             ; Write to screen
        dey
        bpl     @copy_final
        
        ; Delay loop for final animation
        ldy     #(song_hurry_up - music_song_table)
        jsr     D_05AD              ; Start hurry-up music
        ldx     #$06

smc_delay_loop:
        lda     #$08
        jsr     D_7BC8              ; More delay
smc_3BA0:
        lda     #$0C
D_3BA1 := smc_3BA0 + 1             ; SMC: operand byte (self-modified)
        eor     #$03                ; Calculate value
        sta     D_3BA1              ; Self-modify instruction (!)
        ldy     #$08

@inner_delay:
        sta     ($3E),y             ; Write to screen
        dey
        bpl     @inner_delay
        dex
        bne     smc_delay_loop

.if !SOUND_SONGS_LOOP
; Non-looping engine: wait for song to finish before starting next one.
@wait_sync:
        lda     SYESSION            ; a5 a4    - Wait for song to finish
        bne     @wait_sync          ; d0 fc
.endif
        
        ldy     #(song_level_complete - music_song_table)
        jsr     D_05AD              ; Level complete music

advance_scroll_3BA7:
        ; Advance screen pointers up one row (40 bytes)
        lda     $40                 ; DATLIN+1
        sec
        sbc     #$28                ; Move up 40 bytes
        sta     $40                 ; DATLIN+1
        sta     $3E                 ; OLDTXT+1
        bcs     @no_page_wrap
        dec     $41                 ; DATPTR (handle page crossing)
        dec     $3F                 ; DATLIN

@no_page_wrap:
        dec     $42                 ; DATPTR+1 (decrement row counter)
        beq     @scroll_done        ; If zero, scroll complete
        jmp     scroll_loop_init_3B0A ; Continue scrolling (JMP $3B0A)

@scroll_done:
        ; Cleanup after scroll complete
        jsr     wait_one_frame              ; Wait for frame
        ldx     #$08
        ldy     #$30

@final_restore:
        lda     D_3CC4,x            ; Restore final row
        sta     ($40),y
        lda     D_3CCD,x
        sta     ($3E),y
        dey
        dex
        bpl     @final_restore
        
        ; Copy screen data
        ldy     #$47
        inx                         ; X = 1

@final_copy:
        lda     ($23),y             ; Read from source
        sta     ($18),y             ; Write to destination
        dey
        bpl     @final_copy
        
        ; Restore saved data
smc_restore_saved:
        lda     D_0100,x            ; Stack page data
D_3BF1 := smc_restore_saved + 2    ; SMC: high byte of address operand
        sta     D_3CB2,x            ; Restore to buffer
smc_restore_src2:
        lda     D_8B00,x            ; High memory data
        sta     level_decompress_data,x ; Restore to high memory
D_3BFA := smc_restore_src2 + 5     ; SMC: high byte of address operand
        dex
        bne     smc_restore_saved
        
        jmp     D_7B53              ; Jump to next routine
