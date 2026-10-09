; ==============================================================================
; SPECIAL ITEM EFFECTS ($2D65-$2DD6)
; ==============================================================================
; Memory range: $2D65-$2DD6 (114 bytes)
;
; Special item effect dispatch tables and power-up handlers.
; Contains jump tables for special item effects plus handler routines.
;
; Jump tables:
;   D_2D65: Low byte table for special effect routines (35 entries)
;   D_2D88: High byte table for special effect routines (35 entries)
;
; These tables are indexed by special item type (0-34) to dispatch to
; the appropriate effect handler routine.
;
; Code routines:
;   D_2DAB: Set item type to 3
;   D_2DB2: Set item effect to $8C
;   D_2DBE: Chain multiple effect calls
;   D_2DD2: Set effect flag and return
; ==============================================================================

.segment "CODE_EFFECTS"

; --- Special effect routine address table (low bytes) ---
; Indexed by special item type (0-34)
; Used at level-setup.s:365 - lda D_2D65,y
D_2D65:
        .byte   <final_routine          ; Entry 0:  final_routine
        .byte   <D_348A                 ; Entry 1:  D_348A
        .byte   <D_3495                 ; Entry 2:  D_3495
        .byte   <D_2DAB                 ; Entry 3:  D_2DAB
        .byte   <D_2DB2                 ; Entry 4:  D_2DB2
        .byte   <D_2DCD                 ; Entry 5:  D_2DCD
        .byte   <D_A64D                 ; Entry 6:  D_A64D
        .byte   <D_A653                 ; Entry 7:  D_A653
        .byte   <D_2DD7                 ; Entry 8:  D_2DD7
        .byte   <D_2DBE                 ; Entry 9:  D_2DBE
        .byte   <D_2DC7                 ; Entry 10: D_2DC7
        .byte   <D_2ECC                 ; Entry 11: D_2ECC
        .byte   <D_2F5F                 ; Entry 12: D_2F5F
        .byte   <D_2F62                 ; Entry 13: D_2F62
        .byte   <D_2F65                 ; Entry 14: D_2F65
        .byte   <D_2F68                 ; Entry 15: D_2F68
        .byte   <D_2F7D                 ; Entry 16: D_2F7D
        .byte   <D_2F83                 ; Entry 17: D_2F83
        .byte   <D_2F89                 ; Entry 18: D_2F89
        .byte   <D_3620                 ; Entry 19: D_3620
        .byte   <D_7FA4                 ; Entry 20: D_7FA4
        .byte   <D_348D                 ; Entry 21: D_348D
        .byte   <D_7FA7                 ; Entry 22: D_7FA7
        .byte   <D_3498                 ; Entry 23: D_3498
        .byte   <D_34A0                 ; Entry 24: D_34A0
        .byte   <D_34FA                 ; Entry 25: D_34FA
        .byte   <D_3502                 ; Entry 26: D_3502
        .byte   <D_350A                 ; Entry 27: D_350A
        .byte   <D_35A7                 ; Entry 28: D_35A7
        .byte   <D_35B0                 ; Entry 29: D_35B0
        .byte   <D_3620                 ; Entry 30: D_3620
        .byte   <D_3620                 ; Entry 31: D_3620
        .byte   <D_3621                 ; Entry 32: D_3621
        .byte   <D_7C37                 ; Entry 33: D_7C37
        .byte   <D_7C3C                 ; Entry 34: D_7C3C

; --- Special effect routine address table (high bytes) ---
; Indexed by special item type (0-34)
; Used at level-setup.s:367 - lda D_2D88,y
D_2D88:
        .byte   >final_routine          ; Entry 0:  final_routine
        .byte   >D_348A                 ; Entry 1:  D_348A
        .byte   >D_3495                 ; Entry 2:  D_3495
        .byte   >D_2DAB                 ; Entry 3:  D_2DAB
        .byte   >D_2DB2                 ; Entry 4:  D_2DB2
        .byte   >D_2DCD                 ; Entry 5:  D_2DCD
        .byte   >D_A64D                 ; Entry 6:  D_A64D
        .byte   >D_A653                 ; Entry 7:  D_A653
        .byte   >D_2DD7                 ; Entry 8:  D_2DD7
        .byte   >D_2DBE                 ; Entry 9:  D_2DBE
        .byte   >D_2DC7                 ; Entry 10: D_2DC7
        .byte   >D_2ECC                 ; Entry 11: D_2ECC
        .byte   >D_2F5F                 ; Entry 12: D_2F5F
        .byte   >D_2F62                 ; Entry 13: D_2F62
        .byte   >D_2F65                 ; Entry 14: D_2F65
        .byte   >D_2F68                 ; Entry 15: D_2F68
        .byte   >D_2F7D                 ; Entry 16: D_2F7D
        .byte   >D_2F83                 ; Entry 17: D_2F83
        .byte   >D_2F89                 ; Entry 18: D_2F89
        .byte   >D_3620                 ; Entry 19: D_3620
        .byte   >D_7FA4                 ; Entry 20: D_7FA4
        .byte   >D_348D                 ; Entry 21: D_348D
        .byte   >D_7FA7                 ; Entry 22: D_7FA7
        .byte   >D_3498                 ; Entry 23: D_3498
        .byte   >D_34A0                 ; Entry 24: D_34A0
        .byte   >D_34FA                 ; Entry 25: D_34FA
        .byte   >D_3502                 ; Entry 26: D_3502
        .byte   >D_350A                 ; Entry 27: D_350A
        .byte   >D_35A7                 ; Entry 28: D_35A7
        .byte   >D_35B0                 ; Entry 29: D_35B0
        .byte   >D_3620                 ; Entry 30: D_3620
        .byte   >D_3620                 ; Entry 31: D_3620
        .byte   >D_3621                 ; Entry 32: D_3621
        .byte   >D_7C37                 ; Entry 33: D_7C37
        .byte   >D_7C3C                 ; Entry 34: D_7C3C

; ==============================================================================
; SPECIAL ITEM EFFECT HANDLERS
; ==============================================================================

.segment "CODE_EFFECTS"

; --- Set item type to 3 ($2DAB) ---
; Sets basic item properties
; Input: X = entity index
D_2DAB:
        lda     #$03                    ; Item type 3
        sta     D_A77B,x                ; Store item type
        bne     L_2DD2                  ; Always branch to finish

; --- Set item effect to $8C ($2DB2) ---
; Sets item visual effect
; Input: X = entity index
D_2DB2:
        lda     #$8C                    ; Effect value
        sta     D_A77D,x                ; Store effect type
        lda     #$FF                    ; Flag value
        sta     D_A77F,x                ; Store flag
        bne     L_2DD2                  ; Always branch to finish

; --- Chain multiple effect calls ($2DBE) ---
; Calls multiple sub-effect routines in sequence
; Input: X = entity index
D_2DBE:
        jsr     D_2F5F                  ; Call effect 1
        jsr     D_2F62                  ; Call effect 2
        jsr     D_2F65                  ; Call effect 3
D_2DC7:
        jsr     D_2DAB                  ; Call set item type
        jsr     D_2DB2                  ; Call set effect
D_2DCD:
        lda     #$FF                    ; Flag value
        sta     D_A781,x                ; Store additional flag

; --- Set effect flag and return ($2DD2) ---
; Common exit point for effect handlers
L_2DD2:
        lda     #$05                    ; Effect flag value
        sta     ZP_B0                   ; Set effect active flag
        rts
