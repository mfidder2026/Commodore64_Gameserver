; ============================================================================
; rebb64 - IRQ Handlers ($06AB-$078B)
; ============================================================================
;
; This file contains the raster IRQ handlers for the game.
; These run every frame and handle:
;   - Frame timing and counters
;   - Background color split-screen effects
;   - Sound updates
;   - Sprite animation
;
; Key routines:
;   irq_frame_update ($06AB) - Main raster IRQ handler
;   L072E ($072E) - Split-screen IRQ handler
;
; ============================================================================

.segment "CODE_IRQ"

; ============================================================================
; [CODE] IRQ_FRAME_UPDATE ($06AB) - Raster IRQ handler
; ============================================================================

irq_frame_update:
        jsr     D_7BB3              ; 20 b3 7b - Bank in RAM
.ifdef BBLAN
        ; BB-LAN: timers, frame counter and the odd-frame logic run in
        ; vframe (bblan.s); bb_irq only counts real frames. The original
        ; code below stays in place but is no longer executed.
bb_irq_patch:
        jmp     bb_irq
        BB_PATCH_END bb_irq_patch, 4
.else
        lda     TXTTAB              ; a5 2b
        bmi     L_06CA              ; 30 18
.endif
        dec     TXTTAB              ; c6 2b
        bne     L_06CA              ; d0 14
        lda     #$32                ; a9 32 - 50 frames = 1 second
        sta     TXTTAB              ; 85 2b
        dec     ZP_2A               ; c6 2a
        lda     D_A9B1              ; ad b1 a9
        beq     L_06C6              ; f0 05
        bmi     L_06C6              ; 30 03
        dec     D_A9B1              ; ce b1 a9
L_06C6:
        dec     ZP_5D               ; c6 5d
        dec     ZP_5E               ; c6 5e
L_06CA:
        inc     ENDCHR              ; e6 08 - Frame counter++
        lda     #$4C                ; a9 4c - JMP opcode
        sta     D_077C              ; 8d 7c 07
        sta     D_0768              ; 8d 68 07
        sta     D_0786              ; 8d 86 07
        lda     MEMSIZ              ; a5 37 - Pause flag
        beq     L_06F0              ; f0 15 - Skip if paused

frame_skip_check:
        lda     ENDCHR              ; a5 08
        and     #$01                ; 29 01 - Check odd/even frame
        beq     L_06F0              ; f0 0f - Skip on even frames
        
        jsr     D_1805              ; 20 05 18
        lda     #$2C                ; a9 2c
        sta     D_077C              ; 8d 7c 07
        lda     OPMASK              ; a5 4d
        beq     L_06F0              ; f0 03
        jsr     D_1B40              ; 20 40 1b
L_06F0:
        jsr     sound_update              ; 20 3c f5 - Update music
        lda     D_5AFF              ; ad ff 5a
        beq     L_0703              ; f0 0b
        jsr     D_07E1              ; 20 e1 07
        lda     #$2C                ; a9 2c
        sta     D_0768              ; 8d 68 07
        sta     D_0786              ; 8d 86 07
L_0703:
        lda     ZP_1C               ; a5 1c
        sta     VIC_BG1             ; 8d 22 d0
        lda     ZP_1E               ; a5 1e
        sta     VIC_BG2             ; 8d 23 d0

; --- Setup raster split and return from IRQ ($070D) ---
        ldx     #<L072E                 ; IRQ vector low
        ldy     #>L072E                 ; IRQ vector high
        lda     ZP_20                   ; Get split-screen flag
        bne     L0717                   ; If split, use default
        lda     #$32                    ; Raster line 50
L0717:
        sta     VIC_RASTER              ; Set raster compare
        stx     IRQ_VEC                 ; Set IRQ vector low
        sty     IRQ_VEC_HI              ; Set IRQ vector high
L0720:
        dec     VIC_IRQ                 ; Acknowledge VIC interrupt
        lda     ZP_2E                   ; Get saved CPU port
        sta     R6510                   ; Restore CPU port
        ldy     ZP_17                   ; Restore Y
        ldx     ZP_16                   ; Restore X
        lda     ZP_15                   ; Restore A
nmi_handler:                            ; $072D - NMI handler (immediate RTI)
        rti                             ; Return from interrupt

; --- Split-screen IRQ handler ($072E) ---
L072E:
        jsr     D_7BB3                  ; Bank in game RAM
        lda     ZP_20                   ; Get split-screen flag
        beq     L075B                   ; If not split, skip
        lda     ZP_1D                   ; Get background color 1 temp
        sta     VIC_BG1                 ; Set background 1
        lda     ZP_1F                   ; Get background color 2 temp
        sta     VIC_BG2                 ; Set background 2
        lda     #$07                    ; Check frame counter
        tax                             ; X = 7
        and     ENDCHR                  ; AND with frame counter
        bne     L_078C                  ; If non-zero, skip animation
L0746:
        lda     D_53F8,x                ; Get sprite pointer
        ; Threshold for ending sprite animation (midpoint of bubble-dragon-in-bubble set).
        ; Value = (sprite_data_7440 + $100 - VIC_bank) / 64, computed as hibyte(X*4).
        cmp     #>(sprite_data_7440 + $100 - __VIC_BANK_BASE__ + sprite_data_7440 + $100 - __VIC_BANK_BASE__ + sprite_data_7440 + $100 - __VIC_BANK_BASE__ + sprite_data_7440 + $100 - __VIC_BANK_BASE__)
        bcs     L0751                   ; If >= $D5, subtract
        adc     #$04                    ; Add 4
        bne     L0753                   ; Store (always branches)
L0751:
        sbc     #$04                    ; Subtract 4
L0753:
        sta     D_53F8,x                ; Store sprite pointer
        dex                             ; Next sprite
        bpl     L0746                   ; Loop for all 8
        bmi     L_078C                  ; Always branch to exit

L075B:
        lda     #<__VIC_MEMPTR_B__           ; VIC memory: screen B + charset B
        ldx     ARYTAB                  ; Get screen pointer ($2F)
        cpx     #>__VIC_CHARSET_B__       ; Charset backup page?
        bne     L0765                   ; If not equal, use default
        lda     #<__VIC_MEMPTR_A__           ; VIC memory: screen A + charset A
L0765:
        sta     VIC_MEMPTR              ; Set VIC memory pointer

; --- Self-modifying jump 1 ($0768) ---
; Modified to JMP or BIT to skip/execute code
D_0768:
        jmp     D_077C                  ; Jump to next section (or skip)

        lda     #<irq_super_bonus       ; IRQ vector low
        sta     IRQ_VEC                 ; Set IRQ vector
        lda     #>irq_super_bonus       ; IRQ vector high
        sta     IRQ_VEC_HI              ; Set IRQ vector
        lda     ROESSION                ; Get super bonus Y ($BD)
        adc     #$1E                    ; Add 30
        sta     VIC_RASTER              ; Set raster line

; --- Self-modifying jump 2 ($077C) ---
; Modified to JMP or BIT to skip/execute code
D_077C:
        jmp     D_0786                  ; Jump to next section (or skip)

        dec     VIC_IRQ                 ; Acknowledge interrupt
        cli                             ; Enable interrupts
        jsr     D_1CBD                  ; Call game update

; --- Self-modifying jump 3 ($0786) ---
; Modified to JMP or BIT to skip/execute code
D_0786:
        jmp     L_078C                  ; Jump to sprites-init (or skip)

        jmp     L0720                   ; Unreachable - Return from IRQ (for reference)

; L_078C is defined in sprites-init.s, which is included after this file
