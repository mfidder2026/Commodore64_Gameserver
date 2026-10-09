; ============================================================================
; SCREEN RENDERING AND ENTITY DRAWING ($1844 - $1AB5)
; ============================================================================
; This section handles:
; - Frame synchronization and double-buffering
; - Drawing entities on screen and color RAM
; - Player bubble rendering
; - Enemy sprite rendering
; - Item collection and scoring
; ============================================================================

.segment "CODE_RENDER"

; ============================================================================
; Main rendering entry point - called each frame
; ============================================================================
update_player_input:
D_1844:
    jsr  wait_one_frame                 ; Wait for frame sync
D_1847:
    ; Toggle double-buffer screen pointers
    lda  ARYTAB                 ; Screen pointer low (charset page)
    eor  #ARYTAB_CHARSET_TOGGLE ; Toggle between charset A/B pages
    sta  ARYTAB
    lda  ARYTAB+1               ; Screen pointer high
    eor  #ARYTAB_SCREEN_TOGGLE  ; Toggle between screen A/B pages
    sta  ARYTAB+1
D_1853:
    ldx  #$00
    clc
L_1856:
    adc  D_AD5C,x
    sta  D_AD41,x
    inx
    cpx  #$19
    bne  L_1856
    lda  #$09
    sta  D_D800
    sta  D_D801
    ldx  #$01
L_186B:
    ldy  $52,x
    bmi  L_1889
    lda  DEFPNT,x
    sta  DATLIN+1
    lda  DSESSION,x
    ora  #$d8
    sta  DATPTR
    lda  TEMPF2,x
    ldy  #$00
    sta  (DATLIN+1),y
    iny
    sta  (DATLIN+1),y
    ldy  #$28
    sta  (DATLIN+1),y
    iny
    sta  (DATLIN+1),y
L_1889:
    dex
    bpl  L_186B
    ldx  #$11

; ============================================================================
; Clear enemy trails on screen
; ============================================================================
L_188E:
    lda  PESSION,x
    cmp  #$18
    bcc  L_1898
    cmp  #$4c
    bne  L_18E5
L_1898:
    ldy  #$02
    lda  D_A9C4,x
    bne  L_18A0
    dey
L_18A0:
    sty  D_18D6
    lda  D_A9E8,x
    sta  D_18D8
    lda  #$03
    sta  OLDLIN+1
    ldy  $ee,x
L_18AF:
    cpy  #$04
    bcc  L_18E0
    cpy  #$1d
    bcs  L_18E0
    lda  OLDLIN+1
    cmp  #$03
    bne  L_18C2
D_18BD:
    lda  D_A9D6,x
    beq  L_18E0
L_18C2:
    sty  D_18DF
    lda  D_AD1E,y
    adc  $dc,x
    sta  DATLIN+1
    lda  D_AD3D,y
    and  #$03
    adc  #$d8
    sta  DATPTR
    ldy  #$00
D_18D6 := * - 1                         ; SMC: operand byte
    lda  #$00
D_18D8 := * - 1                         ; SMC: operand byte
L_18D9:
    sta  (DATLIN+1),y
    dey
    bpl  L_18D9
    ldy  #$00
D_18DF := * - 1                         ; SMC: operand byte
L_18E0:
    iny
    dec  OLDLIN+1
    bne  L_18AF
L_18E5:
    dex
    bpl  L_188E
    ldx  #$11

; ============================================================================
; Draw enemy sprites on screen
; ============================================================================
L_18EA:
    lda  PESSION,x
    bmi  L_192F
    lda  #$03
    sta  OLDLIN+1
    ldy  D_0181,x
L_18F5:
    cpy  #$04
    bcc  L_192A
    cpy  #$1d
    bcs  L_192A
    sty  D_1929
    lda  D_AD1E,y
    clc
    adc  D_015D,x
    sta  DATLIN+1
    sta  DATPTR+1
    lda  #$00
    adc  D_AD3D,y
    sta  DATPTR
    and  #$03
    adc  #>__SCREEN_BACKUP__    ; Convert screen page to backup buffer page
    sta  INPPTR
    ldy  #$00
    lda  (DATPTR+1),y
    sta  (DATLIN+1),y
D_191E:
    iny
    lda  (DATPTR+1),y
    sta  (DATLIN+1),y
    iny
    lda  (DATPTR+1),y
    sta  (DATLIN+1),y
    ldy  #$00
D_1929 := * - 1                         ; SMC: operand byte
L_192A:
    iny
    dec  OLDLIN+1
    bne  L_18F5
L_192F:
    dex
    bpl  L_18EA
    ldx  #$01

; ============================================================================
; Draw player bubbles
; ============================================================================
L_1934:
    lda  $52,x
    bmi  L_195C
    lda  DEFPNT,x
    sta  DATLIN+1
    lda  DSESSION,x
    ora  ARYTAB+1
    sta  DATPTR
    lda  D_3F86,x
    clc
    ldy  #$00
    sta  (DATLIN+1),y
    ldy  #$28
    adc  #$01
    sta  (DATLIN+1),y
    ldy  #$01
    adc  #$01
    sta  (DATLIN+1),y
    ldy  #$29
    adc  #$01
    sta  (DATLIN+1),y
L_195C:
    dex
    bpl  L_1934
    lda  OPMASK
    beq  L_198A
    ldx  #$0a

; ============================================================================
; Draw special items with color
; ============================================================================
L_1965:
    ldy  D_A756,x
    cpy  #$04
    bcc  L_1987
    cpy  #$1d
    bcs  L_1987
    lda  D_AD1E,y
    adc  D_A74B,x
    sta  DATLIN+1
    lda  D_AD3D,y
    and  #$03
    adc  #$d8
    sta  DATPTR
    ldy  #$00
    lda  #$0b                   ; Color value
    sta  (DATLIN+1),y
L_1987:
    dex
    bne  L_1965

; ============================================================================
; Handle special rendering mode
; ============================================================================
L_198A:
    lda  D_593F
    beq  L_19C0
    lda  PESSION
    bmi  L_19C1
    ldy  D_0181
    lda  D_AD20,y
    adc  D_015D
    sta  DATLIN+1
    sta  DATPTR+1
    lda  #$00
    adc  D_AD3F,y
    sta  DATPTR
    and  #$03
    clc
    adc  #>__SCREEN_BACKUP__    ; Convert screen page to backup buffer page
    sta  INPPTR
    ldx  #$09
L_19B0:
    ldy  D_A82E,x
    lda  (DATPTR+1),y
    sta  (DATLIN+1),y
    dex
    bpl  L_19B0
    lda  PESSION
    cmp  #$46
    beq  L_19CF
L_19C0:
    rts
L_19C1:
    lda  #$00
    sta  D_593F
    lda  D_58FF
    beq  L_19C0
    dec  D_58FF
    rts

; ============================================================================
; Handle player at edge ($46 = special state)
; ============================================================================
L_19CF:
    dec  $dc
    inc  $ee
    lda  $dc
    asl
    asl
    asl
    adc  #$0c
    sta  DATLIN+1
    lda  $ee
    asl
    asl
    asl
    adc  #$0d
    sta  DATPTR
    ldx  #$0f

; ============================================================================
; Check item collection (enemy types $18-$23)
; ============================================================================
L_19E7:
    lda  BLNON,x
    cmp  #$18
    bcc  L_1A29
    cmp  #$24
    bcs  L_1A29
    lda  D_AA0E,x
    sec
    sbc  DATLIN+1
    bcc  L_1A29
    cmp  #$30
    bcs  L_1A29
    lda  D_AA20,x
    sec
    sbc  DATPTR
    bcc  L_1A29
    cmp  #$30
    bcs  L_1A29
    lda  BLNON,x
    sbc  #$17
    lsr
    stx  DATLIN+1
    ldy  D_AA30,x
    tax
    tya
    sta  $b4,x
    lda  VIC_SPR_ENA
    ora  D_AB55,x
    sta  VIC_SPR_ENA
    jsr  D_1A6F
    ldx  DATLIN+1
    lda  #$38
    sta  BLNON,x
L_1A29:
    dex
    bpl  L_19E7
    ldx  #$05

; ============================================================================
; Check player-item collision (sprite slots 0-5)
; ============================================================================
L_1A2E:
    lda  $b4,x
    beq  L_1A4F
    cmp  #$0b
    bcs  L_1A4F
    lda  $bc,x
    sec
    sbc  DATLIN+1
    bcc  L_1A4F
    cmp  #$30
    bcs  L_1A4F
    lda  $c4,x
    sec
    sbc  DATPTR
    bcc  L_1A4F
    cmp  #$30
    bcs  L_1A4F
    jsr  D_1A6F
L_1A4F:
    dex
    bpl  L_1A2E
    lda  $ee
    cmp  #$16
    bne  L_1A5F
    lda  #$38
    sta  PESSION
    sta  LSXP
    rts

; ============================================================================
; Random item spawn
; ============================================================================
L_1A5F:
    jsr  D_E9EA
    cmp  #$06
    bcs  L_1AB5
    tax
    lda  $b4,x
    beq  L_1AB5
    cmp  #$0b
    bcs  L_1AB5

; ============================================================================
; Award points and initialize collected item
; ============================================================================

.segment "CODE_RENDER"
D_1A6F:
    lda  $b4,x
    cmp  #$0a
    bne  L_1A78
    lda  D_87A2,x
L_1A78:
    cmp  #$0d
    beq  L_1A7F
    sta  D_8842,x
L_1A7F:
    lda  #$0b                   ; Entity state
    sta  $b4,x
    dec  $4a
    jsr  D_E9EA
    and  #$07
    clc
    adc  #$01
    sta  D_87A2,x
    jsr  D_E9EA
    and  #$07
    clc
    adc  #$01
    sta  D_87CA,x
    sta  D_886A,x
    jsr  D_E9EA
    and  #$01
    sta  D_87F2,x
    lda  #$07
    sta  D_881A,x
    lda  #$09
    sta  D_8892,x
    lda  #$0e
    sta  D_854A,x
L_1AB5:
    rts
