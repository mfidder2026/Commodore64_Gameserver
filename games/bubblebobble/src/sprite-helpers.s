;===============================================================================
; bb-sprite-helpers.s - Sprite Helper Routines
;===============================================================================
; Address range: $3FB0-$3FFF (80 bytes)
;
; This module contains helper routines that appear to handle sprite data
; writing with conditional logic. The routines check various conditions
; and write space characters ($20) to memory via indirect addressing.
;
; These routines have similar structure, suggesting they're variants for
; different sprite processing contexts.
;===============================================================================

;-------------------------------------------------------------------------------
; Helper Routine 1 ($3FB0-$3FC2) - D_3FB0
;-------------------------------------------------------------------------------
; Conditional sprite data writer
; Checks flags and writes space character if conditions are met

.segment "CODE_ENTITY_TBLS"

D_3FB0:
        bne     L_3FBD                              ; $3FB0 - Exit if not zero
        bit     DATPTR+1                            ; $3FB2 - Test bit 7 of $42
        bmi     L_3FBD                              ; $3FB4 - Exit if negative
        cpy     #$05                                ; $3FB6 - Check Y against 5
        beq     L_3FBD                              ; $3FB8 - Exit if equal
        lda     #$20                                ; $3FBA - Load space character
        bit     D_42C6                              ; $3FBC - BIT $42C6 (overlaps next instr)
                                                    ; When falling through: BIT D_42C6
L_3FBD = * - 2                                      ; When jumping to L_3FBD: DEC $42
        sta     (DATLIN+1),y                        ; $3FBF - Store via ($40),Y
        iny                                         ; $3FC1 - Increment Y
        rts                                         ; $3FC2

;-------------------------------------------------------------------------------
; Sprite Setup 1 ($3FC3-$3FCE) - entered after sprite data load
;-------------------------------------------------------------------------------
        tay                                         ; $3FC3 - a8
        sta     D_E849                              ; $3FC4 - 8d 49 e8 - Set sprite routine 1

routine_3FC7:
        lda     #$B8                                ; $3FC7
        sta     D_E853                              ; $3FC9 - Set sprite routine 2
        jmp     D_3ED5                              ; $3FCC - Jump to sprite init 3

;-------------------------------------------------------------------------------
; Helper Routine 2 ($3FCF-$3FE1) - Conditional sprite data writer
;-------------------------------------------------------------------------------
D_3FCF:
        bne     L_3FDC                              ; $3FCF - Exit if not zero
        bit     DATPTR+1                            ; $3FD1 - Test bit 7 of $42
        bmi     L_3FDC                              ; $3FD3 - Exit if negative
        cpy     #$05                                ; $3FD5 - Check Y against 5
        beq     L_3FDC                              ; $3FD7 - Exit if equal
routine_3FD9:
        lda     #$20                                ; $3FD9 - Load space character
        bit     D_42C6                              ; $3FDB - BIT $42C6 (overlaps next instr)
L_3FDC = * - 2                                      ; When jumping to L_3FDC: DEC $42
        sta     (DATLIN+1),y                        ; $3FDE - Store via ($40),Y
        iny                                         ; $3FE0 - Increment Y
        rts                                         ; $3FE1

;-------------------------------------------------------------------------------
; Sprite Setup 2 ($3FE2-$3FEC) - entered after sprite data load
;-------------------------------------------------------------------------------
        sta     D_E849                              ; $3FE2 - 8d 49 e8 - Set sprite routine 1

routine_3FE5:
        lda     #$B8                                ; $3FE5
        sta     D_E853                              ; $3FE7 - Set sprite routine 2
        jmp     D_3EF3                              ; $3FEA - Jump to sprite init

;-------------------------------------------------------------------------------
; Helper Routine 3 ($3FED-$3FFF) - Conditional sprite data writer
;-------------------------------------------------------------------------------
D_3FED:
        bne     L_3FFA                              ; $3FED - Exit if not zero
        bit     DATPTR+1                            ; $3FEF - Test bit 7 of $42
        bmi     L_3FFA                              ; $3FF1 - Exit if negative
        cpy     #$05                                ; $3FF3 - Check Y against 5
        beq     L_3FFE                              ; $3FF5 - Skip to INY if equal
routine_3FF7:
        lda     #$20                                ; $3FF7 - Load space character
        bit     D_42C6                              ; $3FF9 - BIT $42C6 (overlaps next instr)
L_3FFA = * - 2                                      ; When jumping to L_3FFA: DEC $42
        sta     (DATLIN+1),y                        ; $3FFC - Store via ($40),Y
L_3FFE:
        iny                                         ; $3FFE - Increment Y

D_3FFF:
        rts                                         ; $3FFF - Return

;===============================================================================
; End of bb-sprite-helpers.s
;===============================================================================
