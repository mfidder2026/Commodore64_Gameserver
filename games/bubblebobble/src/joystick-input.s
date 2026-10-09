; ============================================================================
; JOYSTICK INPUT AND PLAYER STATE HANDLER ($1CBD - $1E6B)
; ============================================================================
; This section handles:
; - Reading joystick inputs from CIA ports
; - Player invincibility flash timing
; - Player state updates for all 8 sprite slots
; - Player-to-player collision detection
; - Special level 99 super bonus handling
; - Sprite animation and movement
; ============================================================================

.segment "CODE_RENDER"

; ============================================================================
; Read joystick ports and initialize player state loop
; ============================================================================
D_1CBD:
.ifdef BBLAN
    ldx  #$00
    stx  D_2922                 ; Clear joystick data
    lda  bb_in0                 ; BB-LAN: this tick's synced input
    sta  D_85E8
    lda  bb_in1
    sta  D_85E9
    BB_PATCH_END D_1CBD, 26
.else
    lda  #$7f
    sta  CIA1_PRA               ; Set up CIA port A
    ldx  #$ff
    stx  CIA1_PRB               ; Set up CIA port B
    inx
    stx  D_2922                 ; Clear joystick data
  .ifdef ORIGLAYOUT
    jsr  ol_joy                 ; test: bot input, same size as the reads
    .res 9, $EA
  .else
    lda  CIA1_PRA
    sta  D_85E8                 ; Store port A reading
    lda  CIA1_PRB
    sta  D_85E9                 ; Store port B reading
  .endif
.endif
    ldx  #$07
    stx  INDEX1                 ; Initialize player loop counter

; ============================================================================
; Main player state update loop (processes 8 player slots)
; ============================================================================
L_1CDB:
    lda  ENESSION,x
    beq  L_1D24                 ; Skip if slot empty
    lda  D_85C0,x
    bpl  L_1CA0                 ; Branch to falling handler
    txa
    and  #$01
    tay
    lda  a:ESSION,y             ; Get player state
    cmp  #$01
    beq  L_1CF3
    tya
    eor  #$01
    tay
L_1CF3:
    sty  OPPTR                  ; Store player index
    cpx  #$02
    bcc  L_1D03
    lda  SESSION
    beq  L_1D03
    lda  ENESSION,x
    cmp  #$0b
    bcc  L_1D24

; ============================================================================
; Player invincibility flash handler
; ============================================================================
L_1D03:
    lda  D_8728,x               ; Check invincibility timer
    beq  L_1D11                 ; Skip if not invincible
    ; Frame skip for 25fps flash
    lda  ENDCHR                 ; Get frame counter
D_1D0A:
    and  #$02                   ; Every 2nd frame
    bne  L_1D11
    jsr  D_1E6C                 ; Update player flash
L_1D11:
    lda  D_8638,x
    beq  L_1D21
    dec  D_8638,x
D_1D19:
    lda  ENESSION,x
    jsr  D_1E87                 ; Call player state handler
    jmp  L_1D24
L_1D21:
    jsr  D_1E6C
L_1D24:
    dec  INDEX1
    ldx  INDEX1
    bpl  L_1CDB
    lda  D_5AFF                 ; Check special flag
    beq  L_1D32
    jmp  D_1D84                 ; Jump to level 99 handler

; ============================================================================
; Player-to-player collision detection
; ============================================================================
L_1D32:
    ldy  #$01
L_1D34:
    lda  a:ESSION,y
    cmp  #$01
    bne  L_1D79
    lda  a:FA,y
    adc  #$01
    sta  $02
    lda  a:ZP_C2,y
    adc  #$02
    sta  ADRAY1
    ldx  #$05
L_1D4B:
    lda  $b4,x
    beq  L_1D76
    cmp  #$0b
    bcs  L_1D76
    lda  $bc,x
    sec
    sbc  $02
    bcs  L_1D5E
    eor  #$ff
    adc  #$01
L_1D5E:
    cmp  #$0c
    bcs  L_1D76
    lda  $c4,x
    sec
    sbc  ADRAY1
    bcs  L_1D6D
    eor  #$ff
    adc  #$01
L_1D6D:
    cmp  #$0c
    bcs  L_1D76
    lda  #$0e                   ; Set hit state
    sta  a:ESSION,y
L_1D76:
    dex
    bpl  L_1D4B
L_1D79:
    dey
    bpl  L_1D34
L_1D7C:
    rts

; ============================================================================
; Data table (appears to be unused code or padding)
; ============================================================================
    .byte   $20,$20,$20,$20,$20,$00,$00

; ============================================================================
; Level 99 super bonus handler
; ============================================================================
D_1D84:
    lda  SUBFLG                 ; Check current level
    cmp  #$63                   ; Level 99?
    bne  L_1D7C
    lda  D_872A
    beq  D_1D96
    jsr  D_1D96
    lda  #$0a
    sta  $c0
D_1D96:
    lda  FSESSION
    cmp  #$09
    beq  L_1DEA
    lda  $bf
    and  #$01
    bne  L_1DAE
    lda  $bc
    cmp  #$28
    bcc  L_1DBA
    dec  $bc
    dec  $bc
    bne  L_1DC6
L_1DAE:
    lda  $bc
    cmp  #$c0
    bcs  L_1DBA
    inc  $bc
    inc  $bc
    bne  L_1DC6
L_1DBA:
    lda  $bf
    eor  #$03
    sta  $bf
    lda  FSESSION
    eor  #$18
    sta  FSESSION
L_1DC6:
    lda  $bf
    and  #$08
    bne  L_1DD8
    lda  ROESSION
    cmp  #$3a
    bcc  L_1DE4
    dec  ROESSION
    dec  ROESSION
    bne  L_1DEA
L_1DD8:
    lda  ROESSION
    cmp  #$b8
    bcs  L_1DE4
    inc  ROESSION
    inc  ROESSION
    bne  L_1DEA
L_1DE4:
    lda  $bf
    eor  #$0c
    sta  $bf
L_1DEA:
    ldy  #$01

; ============================================================================
; Super bonus player collision check
; ============================================================================
L_1DEC:
    lda  a:ESSION,y
    cmp  #$01
    bne  L_1E2A
    lda  a:FA,y
    sec
    sbc  $bc
    bcs  L_1DFF
    cmp  #$f8
    bcs  L_1E03
L_1DFF:
    cmp  #$40
    bcs  L_1E2A
L_1E03:
    lda  a:ZP_C2,y
    sec
    sbc  ROESSION
    bcs  L_1E0F
    cmp  #$f8
    bcs  L_1E13
L_1E0F:
    cmp  #$38
    bcs  L_1E2A
L_1E13:
    lda  FSESSION
    cmp  #$09
    bne  L_1E25
    sty  D_A5B8
    dec  $21                    ; Level complete flag
    lda  #$00
    sta  D_5AFF
    beq  D_1E2E
L_1E25:
    lda  #$0e
    sta  a:ESSION,y
L_1E2A:
    dey
    bpl  L_1DEC
    rts

; ============================================================================
; Clear player sprite data
; ============================================================================
D_1E2E:
    ldx  #$05
D_1E30:
    lda  #$00
L_1E32:
    sta  $b4,x
    sta  $bc,x
    sta  $c4,x
    dex
; ============================================================================
; Animation/state handler jump table
; The table cleverly overlaps with the BPL instruction:
;   $1E39: BPL opcode ($10)
;   $1E3A: BPL offset ($F7) = D_1E3A (State 0 low byte = $F7)
;   $1E3B: RTS ($60) = D_1E3B (State 0 high byte = $60) -> State 0 = $60F7
; States 1-23 follow as normal 2-byte entries
; ============================================================================

.segment "CODE_RENDER"
D_1E3A = * + 1          ; D_1E3A points to the BPL operand byte (State 0 low)
    bpl  L_1E32
D_1E3B:                 ; D_1E3B is the RTS (State 0 high byte = $60)
    rts
    ; States 1-23 (23 entries = 46 bytes, State 0 is implicit from BPL+RTS = $60F7)
    .byte   <D_2162,>D_2162     ; $1E3C - State 1 handler
    .byte   <L_EA08,>L_EA08     ; $1E3E - State 2 handler
    .byte   <D_E9FD,>D_E9FD     ; $1E40 - State 3 handler
    .byte   <D_1F2E,>D_1F2E     ; $1E42 - State 4 handler
    .byte   <D_EFC0,>D_EFC0     ; $1E44 - State 5 handler
    .byte   <D_EEB2,>D_EEB2     ; $1E46 - State 6 handler
    .byte   <D_E9FD,>D_E9FD     ; $1E48 - State 7 handler
    .byte   <D_E9FD,>D_E9FD     ; $1E4A - State 8 handler
    .byte   <D_1E9F,>D_1E9F     ; $1E4C - State 9 handler
    .byte   <D_2808,>D_2808     ; $1E4E - State 10 handler
    .byte   <L267B,>L267B       ; $1E50 - State 11 handler
    .byte   <D_273D,>D_273D     ; $1E52 - State 12 handler
    .byte   <spawn_position_init,>spawn_position_init   ; $1E54 - State 13 handler
    .byte   <spawn_animation,>spawn_animation           ; $1E56 - State 14 handler
    .byte   <L_28E8,>L_28E8     ; $1E58 - State 15 handler
    .byte   <spawn_timer,>spawn_timer                   ; $1E5A - State 16 handler
    .byte   <score_display,>score_display               ; $1E5C - State 17 handler
    .byte   <D_29BB,>D_29BB     ; $1E5E - State 18 handler
    .byte   <D_2A18,>D_2A18     ; $1E60 - State 19 handler
    .byte   <D_2A74,>D_2A74     ; $1E62 - State 20 handler
    .byte   <D_2ACB,>D_2ACB     ; $1E64 - State 21 handler
    .byte   <D_2785,>D_2785     ; $1E66 - State 22 handler
    .byte   <L_27CB,>L_27CB     ; $1E68 - State 23 handler
; Two padding/dead code bytes after the jump table
    .byte   $FA,$28             ; $1E6A - Padding (illegal NOP + PLP)
