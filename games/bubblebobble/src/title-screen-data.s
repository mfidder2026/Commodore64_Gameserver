; ==============================================================================
; Bubble Bobble - Title Screen Text Data
; ==============================================================================
; Address range: $F0EE-$F1AB (190 bytes)
;
; ⚠️  This section contains ONLY DATA, no executable code
; ⚠️  Disassemblers may show "illegal opcodes" - these are false positives
;
; Text strings displayed on title screen with control codes for positioning
; and formatting. Text encoding:
;   $40 = space
;   $41-$5A = letters A-Z  
;   $5C = pound sign (£)
;   $1F = positioning control code
;   Other values = special characters/codes
;
; Data tables:
;   D_F192 - Index table used at $3673 for credit display
;   D_F19F - Timing values used at $3676 for animations
;   L_F1A8 - Additional data (not code despite disassembly showing ISC)
; ==============================================================================

; Title screen text data with embedded control codes
.segment "CODE_TITLE_DATA"

title_screen_text:
    .byte $1F, $0B              ; Position control

    ; D_F0F0 - Special codes + £
    .byte $00, $07, $5C

    ; D_F0F3 - "BUBBLE  B"
    .byte $40, $42, $55, $42, $42, $4C, $45, $40  ; " BUBBLE "
    .byte $40                                      ; " "

    ; D_F0FC - "BO"
    .byte $42, $4F

    ; D_F0FE - "B"
    .byte $42

    ; D_F0FF - "B"
    .byte $42

    ; D_F100 - "LE £" + control
    .byte $4C, $45, $40, $5C, $1F
    
    ; Control params + "COMMODORE"
    .byte $08, $11
    .byte $43, $4F, $4D, $4D, $4F, $44, $4F, $52, $45  ; "COMMODORE"
    
    ; " CONVERSION  BY"
    .byte $40, $43, $4F, $4E, $56, $45, $52, $53, $49, $4F, $4E  ; " CONVERSION"
    .byte $40, $40, $42, $59                                      ; "  BY"
    
    ; Position control codes
    .byte $1F, $0B, $12
    
    ; "SOFTWARE CREATIONS"
    .byte $53, $4F, $46, $54, $57, $41, $52, $45              ; "SOFTWARE"
    .byte $40, $43, $52, $45, $41, $54, $49, $4F, $4E, $53    ; " CREATIONS"
    
    ; Position control + "SCORE"
    .byte $1F, $10, $06, $04
    .byte $53, $43, $4F, $52, $45                             ; "SCORE"
    
    ; Position control + "ROUND"
    .byte $1F, $19, $06
    .byte $52, $4F, $55, $4E, $44                             ; "ROUND"
    
    ; Position control + "TOP"
    .byte $1F, $0A, $0E, $02
    .byte $54, $4F, $50                                       ; "TOP"
    
    ; Position control + "WRITTEN BY STEPHEN "
    .byte $1F, $08, $14, $03
    .byte $57, $52, $49, $54, $54, $45, $4E, $40, $42, $59, $40  ; "WRITTEN BY "
    .byte $53, $54, $45, $50, $48, $45, $4E, $40                 ; "STEPHEN "
    
    ; "RUDDY"
    .byte $52, $55, $44, $44, $59                             ; "RUDDY"
    
    ; Position control + "CREDITS !"
    .byte $1F, $1D, $18
    .byte $43, $52, $45, $44, $49, $54, $53, $40              ; "CREDITS "
    .byte $21                                                  ; "!"
    
    ; " " + position control + "£ PRESS ! OR " TO PLAY £"
    .byte $20, $1F, $08, $16, $01
    .byte $5C, $40, $50, $52, $45, $53, $53, $40, $21, $40    ; "£ PRESS ! "
    .byte $4F, $52, $40, $22, $40, $54, $4F, $40, $50, $4C    ; "OR \" TO PL"
    .byte $41, $59, $40, $5C                                   ; "AY £"
    
    ; Final control code
    .byte $10

; D_F192 - Index table (13 bytes)
; Used at $3673 for credit display indexing
credit_index_table:
    .byte $00, $02, $04, $06, $07, $0C, $0D, $12
    .byte $13, $18, $19, $1E, $1F

; D_F19F - Timing/delay values (9 bytes)
; Used at $3676 for credit scroll/display timing
credit_timing_table:
    .byte $C8, $C8, $C8, $FF, $C0, $07, $C0, $FF
    .byte $E0

; L_F1A8 - Additional data (4 bytes)
; NOTE: Disassemblers show this as "ISC $FFE0,X" (illegal opcode)
; but this is pure data, not executable code
    .byte $FF, $E0, $FF, $FF
