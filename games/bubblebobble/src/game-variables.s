; ============================================================================
; rebb64 - Game Variables ($0400-$045B)
; ============================================================================
;
; This file contains the initial game variable data and lives counters.
; Score storage, lives, and game state data.
;
; ============================================================================

.segment "CODE_VARIABLES"

; ============================================================================
; [DATA] GAME VARIABLES ($0400-$045B)
; ============================================================================
; Score storage, lives, game state. Keep as bytes.

game_variables:
D_0409 = game_variables + 9                                             ; Score/stat value array
        .byte   $00,$00,$00,$00,$00,$00,$00,$20                         ; $0400 - Score area
        .byte   $00,$00,$00,$13                                         ; $0408 - Game state data
        .byte   <D_E779,>D_E779, <D_E779,>D_E779                       ; $040C - Entity render vectors
        .byte   <D_E779,>D_E779, <D_E779,>D_E779                       ; $0410
        .byte   <D_E779,>D_E779, <D_E779,>D_E779                       ; $0414
        .byte   <D_E779,>D_E779, <D_E779,>D_E779                       ; $0418
        .byte   <D_E779,>D_E779, <D_E779,>D_E779                       ; $041C
        .byte   <D_E779,>D_E779, <D_7BD4,>D_7BD4                       ; $0420
        .byte   <D_3CB2,>D_3CB2, <D_3CB2,>D_3CB2                        ; $0424
        .byte   <D_3CB2,>D_3CB2, <D_3CB2,>D_3CB2                       ; $0428
        .byte   <D_3CB2,>D_3CB2, <D_3CB2,>D_3CB2                       ; $042C
        .byte   <D_E758,>D_E758, <D_3E94,>D_3E94                       ; $0430
        .byte   <routine_3EFD,>routine_3EFD, <D_E752,>D_E752           ; $0434
        .byte   <routine_3ED4,>routine_3ED4, <D_E767,>D_E767           ; $0438
        .byte   <D_E767,>D_E767, <routine_3E77,>routine_3E77           ; $043C
        .byte   <routine_3D2D,>routine_3D2D, <D_7BDB,>D_7BDB          ; $0440
        .byte   <D_3DA9,>D_3DA9, <routine_3D77,>routine_3D77           ; $0444
        .byte   <routine_3CD3,>routine_3CD3, <routine_3CDB,>routine_3CDB ; $0448
        .byte   <routine_3CDF,>routine_3CDF, <D_E968,>D_E968           ; $044C
        .byte   <routine_3EFD,>routine_3EFD, <routine_3F28,>routine_3F28 ; $0450
        .byte   <D_E968,>D_E968, <D_E968,>D_E968                       ; $0454
        .byte   <routine_3F88,>routine_3F88                             ; $0458

; Lives counter - EASILY MODDABLE!
D_045A:
lives_p1:   .byte   $00                          ; $045A - Player 1 lives
lives_p2:   .byte   $00                          ; $045B - Player 2 lives
