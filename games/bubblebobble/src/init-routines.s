;===============================================================================
; bb-init-routines.s - System Initialization and Setup
;===============================================================================
; Address range: $4800-$48FF (256 bytes)
;
; This module contains the main system initialization routine that sets up
; memory banking, VIC chip configuration, and copies data to various memory
; locations. Also includes helper routines and data tables.
;
; Key routines:
; - D_4800: Main initialization routine (sets up VIC, memory banking)
; - D_4847: Memory block copy routine (copies X*256 bytes)
;
; The data tables at $4861-$48FF appear to be sprite or character data masks.
;===============================================================================

;-------------------------------------------------------------------------------
; Main Initialization Routine ($4800-$4846)
;-------------------------------------------------------------------------------
; Sets up the C64 for game operation:
; - Disables interrupts
; - Configures memory banking (switches BASIC/KERNAL ROM in/out)
; - Copies data blocks to various memory locations
; - Configures VIC chip (screen control, memory pointers)
; - Configures CIA chip
;-------------------------------------------------------------------------------

.segment "VIC_CHARSET_B"

D_4800:
        sei                                         ; $4800 - Disable interrupts
        lda     R6510                               ; $4801 - Get CPU port config
D_4803:
        and     #$FB                                ; $4803 - Bit 2 clear = BASIC ROM off
        sta     R6510                               ; $4805 - Update CPU port
        ldx     #$4B                                ; $4807 - Copy $4B00 bytes
        ldy     #$D0                                ; $4809 - Destination: $D000
        lda     #$30                                ; $480B - Source page: $30xx
        jsr     D_4847                              ; $480D - Copy memory block
        
        lda     R6510                               ; $4810 - Get CPU port config
        ora     #$04                                ; $4812 - Bit 2 set = BASIC ROM on
        sta     R6510                               ; $4814 - Update CPU port
        
        lda     #$34                                ; $4816 - Source page: $34xx
        ldx     #$00                                ; $4818 - Copy $00 pages (256 bytes)
        ldy     #>work_ram_init                     ; $481A - Destination: work_ram_init
        jsr     D_4900                              ; $481C - Copy memory block (different routine)
        
        lda     VIC_CTRL1                           ; $481F - Get VIC control register 1
        and     #$EF                                ; $4822 - Clear bit 4 (blank screen)
        sta     VIC_CTRL1                           ; $4824 - Update VIC control 1
        
        lda     #$35                                ; $4827 - Source page: $35xx
        ldx     #$00                                ; $4829 - Copy 256 bytes
        ldy     #>work_ram_init                     ; $482B - Destination: work_ram_init
        jsr     D_4900                              ; $482D - Copy memory block
        
; Entry point for release build (TSCrunch -x flag).
; Skips tape loader memory copy; jumps straight to VIC init + game entry.
.export game_entry
game_entry:
        lda     #$1B                                ; $4830 - VIC control: screen on, 25 rows
        sta     VIC_CTRL1                           ; $4832 - Enable screen
        
        lda     #$C8                                ; $4835 - VIC control 2: multicolor on
        sta     VIC_CTRL2                           ; $4837 - Set multicolor mode
        
        lda     #<__CIA2_PRA_INIT__                      ; $483A - CIA port config (Bank 0)
        sta     CIA2_PRA                            ; $483C - VIC bank selection
        
        lda     #$15                                ; $483F - Memory pointers (Bank 0 context)
        sta     VIC_MEMPTR                          ; $4841 - Set screen/charset location
        
        jmp     D_4460                              ; $4844 - Jump to main game code

;-------------------------------------------------------------------------------
; Memory Block Copy Routine ($4847-$4860)
;-------------------------------------------------------------------------------
; Copies a block of memory from source to destination.
;
; Parameters:
;   A = Source page (high byte of source address)
;   X = Number of 256-byte pages to copy
;   Y = Destination page (high byte of destination address)
;
; Uses zero page locations $FB-$FE as pointers.
;-------------------------------------------------------------------------------

D_4847:
        stx     $FC                                 ; $4847 - Store dest page high
        sty     $FE                                 ; $4849 - Store dest+1 page high
        ldy     #$00                                ; $484B - Y = 0 (byte offset)
        sty     FREKZP                              ; $484D - Source pointer low = 0
        sty     $FD                                 ; $484F - Dest pointer low = 0
        tax                                         ; $4851 - X = page counter

L_4852:
        lda     (FREKZP),y                          ; $4852 - Read from source
        sta     ($FD),y                             ; $4854 - Write to destination
        iny                                         ; $4856 - Next byte
        bne     L_4852                              ; $4857 - Loop until page complete
        inc     $FC                                 ; $4859 - Next source page
        inc     $FE                                 ; $485B - Next dest page
        dex                                         ; $485D - Decrement page counter
        bne     L_4852                              ; $485E - Continue if more pages
        rts                                         ; $4860 - Return

;-------------------------------------------------------------------------------
; Data Tables ($4861-$48FF)
;-------------------------------------------------------------------------------
; These appear to be sprite or character data masks/patterns.
; Multiple data labels are defined as some routines may reference specific
; offsets within this data.
;-------------------------------------------------------------------------------

        .byte   $FF,$00,$00,$FF,$FF,$00,$00,$FD     ; $4861
        .byte   $FF,$00,$00,$FF,$FF,$00,$00,$FF     ; $4869
        .byte   $FF,$00,$00,$FF,$FF,$00,$00,$FF     ; $4871
        .byte   $FF,$00,$00,$FF,$BF,$D1,$00         ; $4879
        .byte   $FF,$EF,$00,$00                     ; $4880 - D_4880 (level layout buffer)

;-------------------------------------------------------------------------------
; Runtime Buffers ($4884-$48FF)
;-------------------------------------------------------------------------------
; These are WRITABLE BUFFERS that get populated at runtime during level loading.
; Initial values here are overwritten by level-renderer.s and sprites-display.s.
;-------------------------------------------------------------------------------

; Unreferenced buffer space (36 bytes)
D_4884:
        .byte   $FF,$FF,$00,$00, $FF,$FF,$00,$00         ; $4884
        .byte   $FF,$FF,$00,$00, $FF,$FF,$00,$00         ; $488C
        .byte   $FF,$FF,$00,$00, $FF,$FF,$00,$00         ; $4894
        .byte   $FF,$FF,$00,$00, $FF,$FF,$00,$00         ; $489C
        .byte   $FF,$FF,$00,$00                          ; $48A4

; Level header buffer (8 bytes) - written by level-renderer.s L_E021
D_48A8:
        .byte   $FF,$FF,$00,$00, $FF,$FF,$00,$00         ; $48A8

; Sidebar character buffers (8 bytes each)
; Written by level-renderer.s L_E051 and L_E060
D_48B0:
        .byte   $FF,$FF,$00,$00, $FF,$FF,$00,$00         ; $48B0
D_48B8:
        .byte   $FF,$FF,$00,$00, $FF,$EF,$00,$00         ; $48B8
D_48C0:
        .byte   $FF,$FF,$00,$00, $FF,$F7,$00,$00         ; $48C0
D_48C8:
        .byte   $FF,$FF,$00,$00, $FF,$FF,$00,$00         ; $48C8

; Character set data buffer (48 bytes) - written by copy_charset_data
D_48D0:
        .byte   $FF,$FF,$00,$00, $FF,$FF,$00,$00         ; $48D0
        .byte   $FF,$FF,$00,$00, $FF,$FF,$00,$00         ; $48D8
        .byte   $FF,$FF,$00,$00, $FF,$FF,$00,$00         ; $48E0
        .byte   $FD,$FF,$00,$00, $FF,$FF,$00,$00         ; $48E8
        .byte   $EF,$FF,$00,$00, $FF,$FF,$00,$00         ; $48F0
        .byte   $FF,$FF,$00,$00, $FF,$BF,$40,$00         ; $48F8

;===============================================================================
; End of bb-init-routines.s
;===============================================================================
