;===============================================================================
; bb-entity-spawn.s - Entity spawning and initialization
;===============================================================================
; Address range: $39D2-$3AB7
;
; This module handles reading spawn data from level definitions and initializing
; entity arrays with position, movement, and sprite data.
;===============================================================================

;-------------------------------------------------------------------------------
; Entity spawn/setup loop - reads spawn data and initializes entity arrays
;-------------------------------------------------------------------------------
; Address: $39D2-$3A6B
; Called from level initialization
; Input: A = entity count, ($02) = pointer to spawn data
;-------------------------------------------------------------------------------
.segment "CODE_LEVEL_DISP"

D_39D2:
        tay                         ; Transfer count to Y
        sta     D_8638              ; Store in data tables
        sta     D_8639
        sty     $04                 ; Store entity index

; Main entity processing loop
D_39DB:
        lda     ($02),y             ; Load entity type/data
        bne     @process_entity     ; If non-zero, process this entity
        jmp     D_3A6C              ; Else done, jump to cleanup

@process_entity:
        ldx     $04                 ; Get current entity index
        sta     $09                 ; Store position data (TRMPOS)
        iny
        lda     ($02),y             ; Load Y coordinate
        sta     $0A                 ; Store (VERCK)
        iny
        lda     ($02),y             ; Load flags/type
        sta     $0B                 ; Store (COUNT)
        and     #$3F                ; Mask type bits
        asl                         ; Multiply by 2
        sta     D_863A,x            ; Store entity type

        ; Calculate X position
        lda     $09                 ; TRMPOS
        and     #$07                ; Lower 3 bits
        clc
        adc     #$02                ; Add offset
        sta     $B4,x               ; Store X position low

        ; Calculate X position high byte
        lda     $09
        and     #$F8                ; Upper 5 bits
        adc     #$14
        sta     $BC,x               ; Store X position high

        ; Calculate Y position
        lda     $0A                 ; VERCK
        and     #$F8
        adc     #$15
        sta     $C4,x               ; Store Y position high

        ; Calculate movement/direction flags
        lda     $0A
        and     #$07
        asl
        sta     $0A
        lda     $0B                 ; COUNT flags
        and     #$80                ; Get direction bit
        rol
        rol
        ora     $0A
        sta     D_85EA,x            ; Store direction/movement data

        ; Check for special flag bit
        lda     $0B
        and     #$40
        beq     @skip_special_load
        
        ; If special flag set, load value from table
        lda     $B4,x
        tax
        lda     D_AB79,x            ; Load from table
        ldx     $04

@skip_special_load:
        sta     D_8522,x            ; Store result (A unchanged if branch taken)
        
        ; Continue with normal entity setup
        lda     $B4,x
        tax
        lda     D_AB61,x            ; Load animation frame
        pha
        lda     D_AB69,x            ; Load sprite data
        pha
        jsr     D_E9EA              ; Call random number generator
        and     #$1F                ; Mask to 5 bits
        clc
        adc     D_AB71,x            ; Add offset from table
        pha
        lda     D_AB79,x
        ldx     $04
        sta     D_8752,x            ; Store sprite pointer
        sec
        sbc     #$01
        sta     D_877A,x            ; Store decremented value
        pla
        sta     D_868A,x            ; Restore and store animation
        sta     D_8662,x
        pla
        sta     D_859A,x            ; Store sprite data
        pla
        sta     D_854A,x            ; Store frame data
        
        ; Advance to next entity
        iny
        inc     $04                 ; Increment entity counter
        inc     $4A                 ; Increment spawn counter
        jmp     D_39DB              ; Loop back for next entity

;-------------------------------------------------------------------------------
; Clear/initialize entity data arrays
;-------------------------------------------------------------------------------
; Address: $3A6C-$3AB7
; Clears entity data arrays and performs level-specific initialization
;-------------------------------------------------------------------------------
D_3A6C:
        ldx     #$27                ; 40 entities

@clear_loop:
        lda     D_8500,x            ; Copy data between arrays
        sta     D_84D8,x
        sta     D_84B0,x
        sta     D_8488,x
        lda     D_88C0,x
        sta     D_88E8,x
        sta     D_8910,x
        sta     D_8938,x
        dex
        bpl     @clear_loop

        ; Level-specific initialization
        ldx     $10                 ; SUBFLG (level number)
        lda     item_positions + 200,x  ; Load item spawn positions C + bubble spawns
        sta     $02
        lda     #$2C
        lsr     $02                 ; Test flag bit
        bcc     @skip_random

        ; Random setup for certain levels
        ldy     #$4C
        jsr     D_E9EA              ; Random number
        and     #$01
        bne     @store_flag
        ldy     #$2C
        jsr     D_E9EA
        and     #$03
        sta     $4C

@store_flag:
        sty     D_0C9C
        lda     $02
        and     #$07
        sta     D_0CC2
        lda     #$20

@skip_random:
        sta     D_0A38              ; Store result
        rts
