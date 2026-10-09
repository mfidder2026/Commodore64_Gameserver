; ============================================================================
; LEVEL COMPLETION AND GAME LOOP ($1AB6 - $1CA8)
; ============================================================================
; This section handles:
; - Level completion sequence with screen flash
; - Setting up next level
; - Death animation and respawn
; - Background restoration
; - Item collection collision detection
; ============================================================================

.segment "CODE_RENDER"

; ============================================================================
; Level completion - flash screen and setup next level
; ============================================================================
D_1AB6:
    inc  MEMSIZ                 ; Set pause flag
    jsr  D_1AE8                 ; Setup enemy states
    ldx  #$04
    stx  D_593F                 ; Enable special rendering mode
L_1AC0:
    lda  VIC_BORDER
    eor  #$07                   ; Flash border color
    sta  VIC_BORDER
    sta  VIC_BG0
    jsr  D_7BC3                 ; Wait for frame
    dex
    bne  L_1AC0
    lda  #$46                   ; Set special player state
    sta  PESSION
    sta  LSXP
    lda  #$02
    sta  $ee
    jsr  D_E9EA                 ; Random number
    and  #$07
    clc
    adc  #$16
    sta  $dc
    dec  MEMSIZ                 ; Clear pause flag
    rts

; ============================================================================
; Setup enemy states for level transition
; ============================================================================
D_1AE8:
    ldx  #$01
L_1AEA:
    lda  PESSION,x
    bmi  L_1AFF
    cmp  #$18
    bcc  L_1AF6
    cmp  #$24
    bcc  L_1AF8
L_1AF6:
    lda  #$00
L_1AF8:
    sta  D_AA42,x               ; Save enemy type
    lda  #$3a                   ; Set death state
    sta  PESSION,x
L_1AFF:
    dex
    bpl  L_1AEA

; ============================================================================
; Death/respawn loop
; ============================================================================
D_1B02:
    jsr  D_E90E                 ; Update game state
D_1B05:
    jsr  D_1844                 ; Update rendering (now in bb-render-screen.s)
    jsr  update_sprite_animations ; Update sprites
    lda  PESSION
    bpl  L_1B13
    lda  LSXP
    bmi  L_1B19
L_1B13:
    jsr  D_E90E
    jmp  D_1B05
L_1B19:
    lda  ARYTAB+1
    sta  DATPTR
    ldy  #$00
    sty  DATLIN+1
    sty  DATPTR+1
    lda  #>__SCREEN_BACKUP__
    sta  INPPTR
    ldx  #$04

; ============================================================================
; Restore background from backup buffer
; ============================================================================
L_1B29:
    lda  (DATLIN+1),y
    cmp  #$5e                   ; Check if needs restoration
    bcc  L_1B33
    lda  (DATPTR+1),y
    sta  (DATLIN+1),y
L_1B33:
    iny
    bne  L_1B29
    inc  DATPTR
    inc  INPPTR
    dex
    bne  L_1B29
    jmp  D_1805                 ; Update sprite positions

; ============================================================================
; Process item at position (player 1)
; Note: D_1B40 is defined as a forward reference in bb-master.s
; ============================================================================
D_1B40:
    ldy  D_A756
    cpy  #$04
    bcc  L_1B7B
    lda  D_AD1E,y
    clc
    adc  D_A74B
    sta  $02
D_1B50:
    sta  $04
    sta  $06
    lda  D_AD3D,y
    adc  #$00
    sta  ADRAY1
    eor  #ARYTAB_SCREEN_TOGGLE
    sta  ADRAY2
    and  #$03
    adc  #>__SCREEN_BACKUP__    ; Convert screen page to backup buffer page
    sta  CHARONE
    ldy  #$00
    lda  #$1f
    cmp  ($02),y                ; Check if item tile ($1F)
    bne  L_1B73
    lda  ($06),y
    sta  ($02),y                ; Restore background
    lda  #$1f
L_1B73:
    cmp  ($04),y
    bne  L_1B7B
    lda  ($06),y
    sta  ($04),y
L_1B7B:
    ldx  #$0a

; ============================================================================
; Draw all items on screen
; ============================================================================
L_1B7D:
    ldy  D_A756,x
    cpy  #$04
    bcc  L_1BB1
    cpy  #$1d
    bcs  L_1BB1
    lda  D_AD1E,y
    adc  D_A74B,x
    sta  $02
    sta  $04
    sta  $06
    lda  D_AD3D,y
    adc  #$00
    sta  ADRAY1
    eor  #ARYTAB_SCREEN_TOGGLE
    sta  ADRAY2
    and  #$03
    adc  #$d8                   ; Color RAM ($D800) base - hardware fixed
    sta  CHARONE
    ldy  #$00
    lda  #$1f                   ; Item character
    sta  ($02),y
    sta  ($04),y
    lda  #$0b                   ; Item color
    sta  ($06),y
L_1BB1:
    dex
    bne  L_1B7D
    lda  D_A75F
    cmp  #$04
    bcc  L_1C15
    cmp  #$1d
    bcs  L_1C15
    asl
    asl
    asl
    adc  #$05
    sta  ADRAY1
    lda  D_A754
    asl
    asl
    asl
    adc  #$14
    sta  $02
    ldx  #$07

; ============================================================================
; Check player collision with items
; ============================================================================
L_1BD2:
    lda  ENESSION,x
    beq  L_1C11
    cmp  #$0b
    bcs  L_1C11
    cpx  #$02
    bcs  L_1BE3
    lda  D_87A0,x
    bpl  L_1C11
L_1BE3:
    lda  FA,x
    sec
    sbc  $02
    bcs  L_1BEE
    eor  #$ff
    adc  #$01
L_1BEE:
    cmp  #$0c
    bcs  L_1C11
    lda  $c2,x
    sec
    sbc  ADRAY1
    bcs  L_1BFD
    eor  #$ff
    adc  #$01
L_1BFD:
    cmp  #$0c
    bcs  L_1C11
    lda  ENESSION,x
    cmp  #$0a
    bne  L_1C0A
    lda  D_87A0,x
L_1C0A:
    sta  D_8840,x               ; Save item type
    lda  #$0d                   ; Set collected state
    sta  ENESSION,x
L_1C11:
    dex
    bpl  L_1BD2
    inx

; ============================================================================
; Shift item array
; ============================================================================
L_1C15:
    lda  D_A74C,x
    sta  D_A74B,x
    lda  D_A757,x
    sta  D_A756,x
    inx
    cpx  #$0a
    bne  L_1C15
    lda  D_A756
    cmp  #$1d
    bne  L_1C32
    lda  #$00
    sta  OPMASK                 ; Clear items flag
    rts
L_1C32:
    lda  D_A760
    cmp  #$1d
    bcs  L_1C7A
    asl
    tay
    lda  D_AC01,y
    adc  D_A755
    sta  $02
    lda  D_AC02,y
    adc  #>D_8500
    sta  ADRAY1
    dec  $02
    lda  $02
    cmp  #$ff
    bne  L_1C54
    dec  ADRAY1
L_1C54:
    lda  OPMASK
    bpl  L_1C6D
    ldy  #$01
    lda  ($02),y
    bmi  L_1C77
    ldy  #$29
D_1C60:
    lda  ($02),y
    bpl  L_1C77
    jsr  D_E9EA
    and  #$01
    ora  #$04
    sta  OPMASK
L_1C6D:
    ldy  #$29
    lda  ($02),y
    bmi  L_1C7B
    lda  #$ff
    sta  OPMASK
L_1C77:
    inc  D_A760
L_1C7A:
    rts
L_1C7B:
    lda  OPMASK
    and  #$01
    bne  L_1C8D
    ldy  #$00
    lda  ($02),y
    bmi  L_1C8B
    dec  D_A755
    rts
L_1C8B:
    inc  OPMASK
L_1C8D:
    ldy  #$02
    lda  ($02),y
    bmi  L_1C97
    inc  D_A755
    rts
L_1C97:
    dec  OPMASK
    ldy  #$00
    lda  ($02),y
    bmi  L_1C77
    rts

; ============================================================================
; Player falling handler
; ============================================================================

.segment "CODE_RENDER"
L_1CA0:
    lda  $c2,x
    cmp  D_8890,x
    beq  L_1CAD
    inc  $c2,x                  ; Fall 2 pixels
D_1CA9:
    inc  $c2,x
    bne  L_1CBA
L_1CAD:
    dec  D_85C0,x
    lda  #$ff
    sta  D_8818,x
    lda  #$0a
    sta  D_8890,x
L_1CBA:
    jmp  D_1D19
