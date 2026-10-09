;===============================================================================
; bb-entity-state-tables.s - Entity State Data and Initialization
;===============================================================================
; Address range: $3CB2-$3D2C (123 bytes)
;
; This module contains data tables used by entity state machines and a
; routine that initializes entity sprite/display parameters.
;
; Key functions:
; - Data tables for entity state transitions
; - Sprite initialization routine with multiple entry points
;===============================================================================

;-------------------------------------------------------------------------------
; Data Tables ($3CB2-$3CD5)
;-------------------------------------------------------------------------------
; These appear to be fragments of entity state machine code or jump table data
; They are referenced by code in bb-screen-scroll.s

.segment "CODE_ENTITY_TBLS"

D_3CB2:                                             ; Screen scroll data buffer 1
        lda     PESSION,x                          ; $3CB2 - b5 ca
        sec                                         ; $3CB4 - 38
        sbc     #$18                                ; $3CB5 - e9 18
        lsr     a                                   ; $3CB7 - 4a
        tay                                         ; $3CB8 - a8
        lda     D_AA42,x                            ; $3CB9 - bd 42 aa

L_3CBA = D_3CB2 + 8                                ; Preserve equate for D_3CBB references
D_3CBB := D_3CB2 + 9                               ; Screen scroll color buffer
L_3CBB_continued:
        sta     D_8522,y                             ; $3CBC - 99 22 85
        lda     #$00                                ; $3CBF
        sta     D_872A,y                            ; $3CC1

D_3CC4:                                             ; Screen scroll saved data 1
        lda     D_AA0C,x                            ; $3CC4 - Entity X positions
        sta     a:ZP_BC,y                           ; $3CC7
        lda     D_AA1E,x                            ; $3CCA - Entity Y positions

D_3CCD:                                             ; Screen scroll saved data 2
        sta     a:ZP_C4,y                           ; $3CCD
        jmp     D_E968                              ; $3CD0 - Continue entity processing

routine_3CD3:                                       ; $3CD3 - inc PESSION,x; inc prefix
        .byte   $F6,$CA,$F6                         ; $3CD3 - Data fragment

D_3CD6:                                             ; Screen scroll output buffer 1
        .byte   $CA                                 ; $3CD6 - Entry point data

;-------------------------------------------------------------------------------
; Sprite/Entity Initialization Routine ($3CD7-$3D2C)
;-------------------------------------------------------------------------------
; This routine initializes sprite display parameters for entities.
; It has multiple entry points ($3CD7, $3CDB, $3CDF, $3CE5) that load
; different base values before setting up the sprite pointers.
;
; The routine writes sprite pointer addresses to $E849-$E861 (likely self-
; modifying code for sprite display routines).
;
; Entry points:
;   $3CD7: Load #$00 and branch to common setup at $3CE5
;   $3CDB: Load #$40 and set PESSION,x
;   $3CDF: Load #$38 and set PESSION,x  
;   $3CE5: Main initialization (accumulator contains offset)

routine_3CD7:
        lda     #$00                                ; $3CD7
        beq     L_3CE5_common_setup                 ; $3CD9 - Always branches

routine_3CDB:                                       ; $3CDB - Sprite init entry (load $40)
        lda     #$40                                ; $3CDB - Entry point 2
        bne     L_3CE1_set_pession                  ; $3CDD - Always branches

routine_3CDF:                                       ; $3CDF - Sprite init entry (load $38)
        lda     #$38                                ; $3CDF - Entry point 3
L_3CE1_set_pession:
        sta     PESSION,x                           ; $3CE1
        lda     #$04                                ; $3CE3

L_3CE5_common_setup:                                ; $3CE5 - Main entry point
        stx     DATLIN                              ; $3CE5 - Save entity index
        ora     D_A9C4,x                            ; $3CE7 - Combine with level data
        tay                                         ; $3CEA - Use as table index
        
        lda     D_A9D6,x                            ; $3CEB - Load entity type/flags
        sta     OLDTXT                              ; $3CEE - Store flags
        
        ; Set up first sprite pointer (at $E84C-$E84D)
        lda     D_AB41,y                            ; $3CF0 - Get sprite page low
        sta     D_E84C                              ; $3CF3 - Store at sprite ptr 1
        ldx     D_AB49,y                            ; $3CF6 - Get sprite page high
        stx     D_E84D                              ; $3CF9 - Store at sprite ptr 1 high
        
        ; Set up second sprite pointer (at $E856-$E857)
        adc     #$10                                ; $3CFC - Add offset
        sta     D_E856                              ; $3CFE - Store at sprite ptr 2
        bcc     @no_carry1                          ; $3D01
        inx                                         ; $3D03 - Increment high byte
        clc                                         ; $3D04

@no_carry1:
        stx     D_E857                              ; $3D05
        
        ; Set up third sprite pointer (at $E860-$E861)
        adc     #$10                                ; $3D08 - Add another offset
        sta     D_E860                              ; $3D0A
        bcc     @no_carry2                          ; $3D0D
        inx                                         ; $3D0F
        clc                                         ; $3D10

@no_carry2:
        stx     D_E861                              ; $3D11
        
        ; Set AND mask pointers for all 3 columns to D_8260 (bubble_masks + $260)
        lda     #<D_8260                            ; $3D14 - AND mask low byte
        sta     D_E849                              ; $3D16 - Set AND col1 operand low
        sta     D_E853                              ; $3D19 - Set AND col2 operand low
        sta     D_E85D                              ; $3D1C - Set AND col3 operand low
D_3D1E := * - 1                                     ; Screen scroll output buffer 2
        
        lda     #>D_8260                            ; $3D1F - AND mask high byte
        sta     D_E84A                              ; $3D21 - Set AND col1 operand high
        sta     D_E854                              ; $3D24 - Set AND col2 operand high
        sta     D_E85E                              ; $3D27 - Set AND col3 operand high
        
        jmp     D_E7CF                              ; $3D2A - Jump to sprite display

;===============================================================================
; End of bb-entity-state-tables.s
;===============================================================================
