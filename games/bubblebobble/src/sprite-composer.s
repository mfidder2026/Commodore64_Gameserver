;===============================================================================
; bb-sprite-composer.s
; Bubble Bobble - Sprite Composition and Masking
;===============================================================================
; Address range: $E752-$E9FC (682 bytes)
;
; This module handles:
; - Multi-layer sprite composition with masking
; - Sprite rendering to screen buffers  
; - Character-based sprite drawing with bit masking
; - Score/bonus rendering with BCD arithmetic
; - Position-to-screen coordinate conversion
; - Random number generation
;
; Self-modifying code:
; - D_E966 - Low byte of indirect jump address in entity dispatch
;   CONSTRAINT: The SMC computes the address low byte as (entity_type + $0C),
;   which assumes game_variables starts at a page boundary ($xx00). The high
;   byte comes from the assembled instruction and is never modified at runtime.
;   CODE_VARIABLES must be page-aligned in the linker config.
; - D_E972 ($E973) - Contains ADC immediate operand for screen row advancement
;===============================================================================

;-------------------------------------------------------------------------------
; Sprite composition entry points (continuation from previous routines)
;-------------------------------------------------------------------------------

; Entry at $E752 - Start composing sprite with character offset $38
.segment "CODE_SPRITE_COMPOSER"

D_E752:
    ldy  #$00
    lda  #$38
    bne  L_E75D

; Entry at $E758 - Alternate entry using table lookup
D_E758:
    ldy  D_A9D6,x
    lda  #$34

L_E75D:
    sty  OLDTXT                ; Temp storage
    ora  D_A9C4,x
    clc
    bcc  L_E784

; Data table at $E765 (referenced as data by code at $E771)
D_E765:
    .byte $02, $00

D_E767:
    lda  #$00
    sta  OLDTXT
    lda  D_597F                ; Animation/frame counter
    lsr
    and  #$01
    ora  D_E765,x
    ora  #$30
    clc
    bcc  L_E784

D_E779:
    lda  D_A9D6,x
    sta  OLDTXT                ; OLDTXT
    lda  PESSION,x              ; PESSION - entity state
    asl
    adc  D_A9C4,x

;-------------------------------------------------------------------------------
; Setup sprite graphic pointers with offset calculations
; Sets up 6 pointers ($31-$36) for three 8x8 character columns
;-------------------------------------------------------------------------------
L_E784:
    tay
    stx  DATLIN                ; DATLIN - save X
    
    ; Get base character data pointer from table
    lda  D_AA54,y
    sta  D_E84C                ; Self-modifying LDA operand
    ldx  D_AA8E,y
    stx  D_E84D                ; Self-modifying LDA operand (high byte)
    
    ; Calculate pointer for second character row (+$10)
    adc  #$10
    sta  D_E856                ; Self-modifying LDA operand
    bcc  L_E79C
    inx
    clc

L_E79C:
    stx  D_E857                ; Self-modifying LDA operand (high byte)
    
    ; Calculate pointer for third character row (+$10 more)
    adc  #$10
    sta  D_E860                ; Self-modifying LDA operand
    bcc  L_E7A8
    inx
    clc

L_E7A8:
    stx  D_E861                ; Self-modifying LDA operand (high byte)
    
    ; Get base character data pointer from second table
    lda  D_AAC8,y
    sta  D_E849                ; Self-modifying LDA operand
    ldx  D_AB02,y
    stx  D_E84A                ; Self-modifying LDA operand (high byte)
    
    ; Calculate pointer for second character row (+$10)
    adc  #$10
    sta  D_E853                ; Self-modifying LDA operand
    bcc  L_E7C0
    inx
    clc

L_E7C0:
    stx  D_E854                ; Self-modifying LDA operand (high byte)
    
    ; Calculate pointer for third character row (+$10 more)
    adc  #$10
    sta  D_E85D                ; Self-modifying LDA operand
    bcc  L_E7CC
    inx
    clc

L_E7CC:
    stx  D_E85E                ; Self-modifying LDA operand (high byte)

;-------------------------------------------------------------------------------
; Calculate screen buffer destination pointers
; Sets up $3A/$3B, $18/$19, $1A/$1B for three rows of output
;-------------------------------------------------------------------------------
D_E7CF:
    lda  MEMSIZ1                ; MEMSIZ+1 - base screen address
    sta  CURLIN1                ; CURLIN+1
    ldx  CURLIN                ; CURLIN
    stx  OLDLIN                ; OLDLIN
    adc  #$08
    sta  $18
    bcc  L_E7DF
    inx
    clc

L_E7DF:
    stx  $19                ; TEMPST
    adc  #$08
    sta  $1A
    bcc  L_E7E8
    inx

L_E7E8:
    stx  $1B

;-------------------------------------------------------------------------------
; Composite first column of characters
; Uses indirect indexed addressing to compose sprite data
;-------------------------------------------------------------------------------
    ldy  #$00
    lda  (DATLIN1),y            ; DATLIN+1 - get character index
    tax
    
    ; Get character data pointer for first character
    lda  D_0200,x
    sta  STREND                ; STREND
    lda  D_0300,x             ; IERROR
    ora  ARYTAB                ; Screen pointer
    sta  STREND+1                ; STREND+1
    
    ; Store screen position byte
    lda  $3C                ; OLDLIN+1
    sta  (DATLIN1),y            ; DATLIN+1
    inc  $3C                ; OLDLIN+1
    
    ; Get character data pointer for second character
    iny
    lda  (DATLIN1),y            ; DATLIN+1
    tax
    lda  D_0200,x
    sta  FRETOP                ; FRETOP
    lda  D_0300,x             ; IERROR
    ora  ARYTAB                ; Screen pointer
    sta  FRETOP+1                ; FRETOP+1
    
    ; Store screen position byte
    lda  $3C                ; OLDLIN+1
    sta  (DATLIN1),y            ; DATLIN+1
    inc  $3C                ; OLDLIN+1
    
    ; Get character data pointer for third character
    iny
    lda  (DATLIN1),y            ; DATLIN+1
    tax
    lda  D_0200,x
    sta  $35                ; FRESPC
    lda  D_0300,x             ; IERROR
    ora  ARYTAB                ; Screen pointer
    sta  $36                ; FRESPC+1
    
    ; Store screen position byte
    lda  $3C                ; OLDLIN+1
    sta  (DATLIN1),y            ; DATLIN+1
    inc  $3C                ; OLDLIN+1

;-------------------------------------------------------------------------------
; Render sprite data with masking
; Y counts down from 7 to 0 (8 rows of character data)
; X counts down from $0F to 0 (determines masking level)
;-------------------------------------------------------------------------------
    ldy  #$07
    ldx  #$0F
    dec  OLDTXT                ; OLDTXT - decrement row counter
    bmi  L_E846                ; If negative, apply masking

; Copy full bytes without masking
L_E835:
    lda  (STREND),y            ; STREND - sprite data column 1
    sta  (CURLIN1),y            ; CURLIN+1 - screen dest 1
    lda  (FRETOP),y            ; FRETOP - sprite data column 2
    sta  ($18),y            ; screen dest 2
    lda  ($35),y            ; FRESPC - sprite data column 3

D_E83F:
    sta  ($1A),y            ; screen dest 3
    dey
    cpy  OLDTXT                ; OLDTXT
    bne  L_E835

; Apply masking to sprite edges
; SMC targets: D_E849/D_E84A through D_E860/D_E861 are operand bytes
; within the AND/ORA instructions below, patched at runtime to change
; which mask/background tables are used for sprite composition.
L_E846:
    lda  (STREND),y            ; STREND - sprite data column 1
smc_and1:
    and  D_8240,x              ; Mask table 1
smc_ora1:
    ora  D_8000,x              ; Background bits 1
    sta  (CURLIN1),y            ; CURLIN+1
    
    lda  (FRETOP),y            ; FRETOP - sprite data column 2
smc_and2:
    and  D_8250,x              ; Mask table 2
smc_ora2:
    ora  D_8010,x              ; Background bits 2
    sta  ($18),y
    
    lda  ($35),y            ; FRESPC - sprite data column 3
smc_and3:
    and  D_8260,x              ; Mask table 3
smc_ora3:
    ora  D_8020,x              ; Background bits 3
    sta  ($1A),y

; Self-modifying code target aliases (operand bytes within instructions above)
D_E849 := smc_and1 + 1         ; AND col1 operand low byte
D_E84A := smc_and1 + 2         ; AND col1 operand high byte
D_E84C := smc_ora1 + 1         ; ORA col1 operand low byte
D_E84D := smc_ora1 + 2         ; ORA col1 operand high byte
D_E853 := smc_and2 + 1         ; AND col2 operand low byte
D_E854 := smc_and2 + 2         ; AND col2 operand high byte
D_E856 := smc_ora2 + 1         ; ORA col2 operand low byte
D_E857 := smc_ora2 + 2         ; ORA col2 operand high byte
D_E85D := smc_and3 + 1         ; AND col3 operand low byte
D_E85E := smc_and3 + 2         ; AND col3 operand high byte
D_E860 := smc_ora3 + 1         ; ORA col3 operand low byte
D_E861 := smc_ora3 + 2         ; ORA col3 operand high byte
    
    dey
    bmi  L_E87B                ; Done with this character row

D_E867:
    dex
    bpl  L_E846                ; Continue applying masks

; No more masking needed - copy remaining bytes directly
L_E86A:
    lda  (STREND),y            ; STREND
    sta  (CURLIN1),y            ; CURLIN+1
    lda  (FRETOP),y            ; FRETOP
    sta  ($18),y
    lda  ($35),y            ; FRESPC
    sta  ($1A),y
    dey
    bpl  L_E86A                ; Loop until Y < 0
    bmi  L_E885                ; Jump to cleanup

L_E87B:
    cpx  #$00
    bne  L_E88A                ; More columns to process
    
    ; Done with all columns - advance to next screen row
    lda  $3C                ; OLDLIN+1
    adc  #$02
    sta  $3C                ; OLDLIN+1

L_E885:
    ldx  DATLIN                ; DATLIN - restore X
    jmp  D_E96F                ; Continue with next sprite

;-------------------------------------------------------------------------------
; Process next column of sprite (second and third vertical slices)
;-------------------------------------------------------------------------------
L_E88A:
    ldy  $0D                ; VALTYP
    lda  D_AD1E,y
    clc
    adc  $0E                ; INTFLG
    sta  DATLIN1                ; DATLIN+1
    dec  $0D                ; VALTYP
    lda  #$00
    adc  D_AD3D,y
    sta  DATPTR                ; DATPTR
    
    ldy  #$00
    stx  OLDTXT                ; OLDTXT
    
    ; Get first character
    lda  (DATLIN1),y            ; DATLIN+1
    tay
    lda  D_0200,y
    sta  STREND                ; STREND
    lda  D_0300,y             ; IERROR
    adc  ARYTAB                ; Screen pointer
    sta  STREND+1                ; STREND+1
    
    ldy  #$00
    lda  $3C                ; OLDLIN+1
    sta  (DATLIN1),y            ; DATLIN+1
    tax
    inx
    
    ; Get second character
    iny
    lda  (DATLIN1),y            ; DATLIN+1
    tay
    lda  D_0200,y
    sta  FRETOP                ; FRETOP
    lda  D_0300,y             ; IERROR
    adc  ARYTAB                ; Screen pointer
    sta  FRETOP+1                ; FRETOP+1
    
    ldy  #$01
    txa
    sta  (DATLIN1),y            ; DATLIN+1
    inx
    
    ; Get third character
    iny
    lda  (DATLIN1),y            ; DATLIN+1
    tay
    lda  D_0200,y
    sta  $35                ; FRESPC
    lda  D_0300,y             ; IERROR

; Label for BASIC ROM compatibility (PRTFIX at $E8DA)
PRTFIX:
    adc  ARYTAB                ; Screen pointer
    sta  $36                ; FRESPC+1
    
    ldy  #$02
    txa
    sta  (DATLIN1),y            ; DATLIN+1
    inx
    stx  $3C                ; OLDLIN+1
    
    ; Calculate next row screen addresses (+8 bytes each)
    ldx  $1B
    lda  $1A
    adc  #$08
    sta  CURLIN1                ; CURLIN+1
    bcc  L_E8F2
    inx
    clc

L_E8F2:
    stx  OLDLIN                ; OLDLIN
    adc  #$08
    sta  $18
    bcc  L_E8FC
    inx
    clc

L_E8FC:
    stx  $19                ; TEMPST
    adc  #$08
    sta  $1A
    bcc  L_E905
    inx

L_E905:
    stx  $1B
    ldx  OLDTXT                ; OLDTXT
    ldy  #$07
    jmp  D_E867                ; Continue rendering

;-------------------------------------------------------------------------------
; Render sprites for all active entities
; Iterates through entity table and renders each sprite
;-------------------------------------------------------------------------------
D_E90E:
    ldx  #$11
    inc  D_597F                ; Increment animation frame counter
    
    ; Save entity states for comparison
    lda  $46
    sta  $48
    lda  $47                ; VARPNT
    sta  $49                ; FORPNT
    lda  $54
    sta  $56
    lda  $55
    sta  $57                ; JMPER
    
    ; Initialize screen rendering parameters
    lda  #$f0
    sta  MEMSIZ1                ; MEMSIZ+1
    ldy  ARYTAB                ; Screen pointer
    iny
    iny
    sty  CURLIN                ; CURLIN
    lda  #$5e
    sta  $3C                ; OLDLIN+1

;-------------------------------------------------------------------------------
; Entity rendering loop
;-------------------------------------------------------------------------------
L_E931:
    lda  PESSION,x              ; PESSION - entity state
    bmi  D_E968                ; Skip if inactive (bit 7 set)
    
    clc
    adc  #$0c
    sta  D_E966                ; Self-modifying: store sprite frame offset
    
    ; Copy entity render state
    lda  D_014B,x
    sta  D_015D,x
    lda  D_016F,x
    sta  D_0181,x
    lda  $DC,x
    sta  D_014B,x
    sta  $0E                ; INTFLG
    lda  $EE,x
    sta  D_016F,x
    tay
    iny
    sty  $0D                ; VALTYP
    
    ; Calculate sprite data address
    lda  D_AD1F,y
    adc  $DC,x
    sta  DATLIN1                ; DATLIN+1
    lda  #$00
    adc  D_AD3E,y
    sta  DATPTR                ; DATPTR
    
    ; Jump to sprite rendering routine via vector
    ; D_E966: SMC target - low byte of indirect jump address
    ; Modified by entity rendering loop to select different dispatch vectors
smc_jmp_indirect:
    jmp  (game_variables + $22)
D_E966 := smc_jmp_indirect + 1 ; SMC target: indirect jump address low byte

; D_E968 is defined as forward reference in bb-master.s
    ; Entity inactive - advance screen position
D_E968:
    lda  $3C                ; D_E968 - OLDLIN+1
    clc
    adc  #$09
    sta  $3C                ; OLDLIN+1

;-------------------------------------------------------------------------------
; Continue to next entity
;-------------------------------------------------------------------------------
D_E96F:
    lda  MEMSIZ1                ; MEMSIZ+1
    clc

D_E972:
    .byte $69                  ; ADC immediate (operand modified by code)

D_E973:
    pha                        ; This byte serves as operand for ADC above
    sta  MEMSIZ1                ; MEMSIZ+1
    bcc  D_E97A
    inc  CURLIN                ; CURLIN

; D_E97A is defined as forward reference in bb-master.s
D_E97A:
    dex                        ; D_E97A
    bpl  L_E931                ; Loop for all entities

;-------------------------------------------------------------------------------
; Score/bonus update with BCD arithmetic
; Checks for point pickups and adds to score
;-------------------------------------------------------------------------------
    ldx  #$01

L_E97F:
    lda  $46,x
    beq  L_E9A5                ; No score change
    cmp  $48,x
    bne  L_E9A5                ; State changed, skip
    
    tay
    lda  #$00
    sta  $46,x              ; Clear score update flag
    
    ; Get score value from table
    lda  D_AB52,y
    pha
    ldy  D_AB51,x
    dey
    pla
    
    ; BCD arithmetic to add to score
    sed                        ; Set decimal mode
    clc

L_E997:
    adc  D_0400,y             ; entry_0400 - score digits
    sta  D_0400,y             ; entry_0400
    bcc  L_E9A4                ; No carry, done
    lda  #$00                  ; Propagate carry
    dey
    bpl  L_E997                ; Continue with next digit

L_E9A4:
    cld                        ; Clear decimal mode

L_E9A5:
    dex
    bpl  L_E97F                ; Check next player
    
    ; Check if entity states changed
    lda  $54
    cmp  $56
    bne  L_E9B4
    lda  $55
    cmp  $57                ; JMPER
    beq  L_E9B7                ; No change, return

L_E9B4:
    jmp  draw_player_digits    ; Handle state change

L_E9B7:
    rts

;-------------------------------------------------------------------------------
; convert_entity_pos_to_screen - Convert entity position to screen coordinates
; Input: X = entity index
; Output: $11 = screen row, $12 = screen column base, $23 = X offset, $24 = Y offset
;-------------------------------------------------------------------------------
D_E9B8:
convert_entity_pos_to_screen:
    ; Calculate Y position (vertical)
    lda  FA,x              ; FA - entity Y position
    sec
    sbc  #$14                  ; Subtract playfield top offset
    tay
    and  #$07                  ; Get fine Y offset (0-7 pixels)
    sta  $23                ; Store pixel offset
    
    tya
    lsr                        ; Divide by 8 to get character row
    lsr
    lsr
    sta  $11                ; INPFLG - screen row
    dec  $11                ; INPFLG - adjust

    ; Calculate X position (horizontal)
    lda  $C2,x              ; Entity X position
    sec
    sbc  #$15                  ; Subtract playfield left offset
    tay
    and  #$07                  ; Get fine X offset (0-7 pixels)
    sta  $24                ; INDEX2 - pixel offset
    
    tya
    lsr                        ; Divide by 4 to get character column
    lsr
    and  #$FE                  ; Align to even boundary
    tay
    
    ; Look up screen address from table
    lda  D_AC03,y
    clc
    adc  $11                ; INPFLG - add row offset
    sta  $11                ; INPFLG - final screen row
    lda  D_AC04,y
    adc  #>D_8500
    sta  $12                ; TANSGN - screen column base
    
    rts

;-------------------------------------------------------------------------------
; prng_update - Pseudo-random number generator
; Updates the random number state in $26/$27
; Output: A = new random value in $26 (RESHO)
;-------------------------------------------------------------------------------
D_E9EA:
prng_update:
    lda  RESHO                ; RESHO - random state byte 1
    asl                        ; Shift left
    rol  $27                ; Rotate into byte 2
    rol  RESHO                ; RESHO - rotate back
    
    lda  $27
    eor  RESHO                ; RESHO - XOR for mixing
    adc  $27                ; Add with carry
.ifdef BBLAN
    nop                        ; BB-LAN: no timer entropy (deterministic)
    nop
    nop
.else
    eor  CIA1_TBLO            ; CIA1_TBLO - XOR with timer for entropy
.endif
    sta  RESHO                ; RESHO - store new random value
    
    rts
