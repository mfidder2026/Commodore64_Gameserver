;===============================================================================
; bb-platform-collision.s - Platform Collision Detection & Display Routines
;===============================================================================
; Address range: $3169-$32BE (342 bytes)
;
; Purpose: Platform collision detection between players and platforms,
;          platform destruction visual effects, and screen copying routines
;
; Key Features:
; 1. D_3169 - Screen area fill subroutine
;    - Copies 16 bytes from source screens to destination screens
;    - Uses double-buffering with offset calculations
;    - Called from level initialization (bb-level-start.s)
;
; 2. D_3193 - Platform collision detection loop
;    - Checks collision between players and all platforms on screen
;    - Distance check: Both X and Y deltas must be < $10 (16 pixels)
;    - When collision detected: destroys platform, updates tables, plays effect
;    - Uses platform position tables: D_4600 (Y), D_4700 (X), D_4E00/D_4F00 (screen addr)
;    - Decrements D_597F (platform counter) when platform destroyed
;
; 3. D_31A2 - Main collision detection coordinator
;    - Calls multiple game systems each frame
;    - Loops until all platforms destroyed (D_597F = 0)
;    - Then jumps to next game state (D_E3A7)
;
; 4. Unlabeled routine at $3234 - Timer/score display routine
;    - Displays timer value at screen position
;    - Handles player scores (STREND, STREND+1)
;    - Sets up VARNAM for character display
;    - Special case: exits early via stack pull if timer ($2A) reaches zero
;
; 5. D_3266 - Decimal to screen character converter
;    - Converts binary value to two decimal digits
;    - Uses repeated subtraction for divide-by-10
;    - ORs result with VARNAM for character encoding
;    - Displays at screen position specified by Y register
;
; 6. D_3293 - Screen memory copy routine
;    - Copies entire screen from one location to another
;    - 25 rows ($19) of 32 bytes ($1F) = 800 bytes
;    - Handles page boundary crossing with pointer increments
;    - Used for double-buffering and screen transitions
;
; Technical Details:
; - Platform collision uses Manhattan distance (sum of absolute X and Y differences)
; - Collision threshold: 16 pixels in both X and Y dimensions
; - Platform destruction: Zeroes out position tables, restores original screen tiles
; - Screen addressing: Multiple pointer pairs for source/destination management
; - Self-modifying code: Overwrites instruction operands at $31B2/$31B3, $3203
;
; External Calls:
; - D_045C: Check player state routine
; - D_05AD: Unknown routine (called with Y=$2E)
; - D_1853: Screen rendering routine
; - D_7BC3: Unknown routine
; - D_7C26: Unknown routine (animation/effect?)
; - D_7E80: Unknown routine
; - D_E374: Unknown routine
; - D_E3A7: Game state transition
; - wait_one_frame: Delay/frame wait routine
; - D_E9EA: Random number generator
; - D_F1AC: Unknown routine
; - entry_0400: Entry point at $0400
; - L_A474: READY label
;
; Called From:
; - $305F: jsr D_3169 (bb-level-start.s)
; - $3071: jsr D_3193 (bb-level-start.s)
; - $3080: jsr D_3169 (bb-level-start.s)
; - $3083: jsr D_3293 (bb-level-start.s)
; - $30AC: jsr D_3266 (bb-level-start.s)
; - $3112: jsr D_3293 (bb-level-start.s)
; - $322E: jmp D_31A2 (internal loop)
; - $3242: jsr D_3266 (internal)
; - $324F: jsr D_3266 (internal)
; - $3258: jsr D_3266 (internal)
; - $376E: jmp D_3193 (unknown location)
; - $A430: jsr D_3293 (unknown location)
; - $F0B9: jsr D_3266 (unknown location)
;
;===============================================================================

;-------------------------------------------------------------------------------
; Self-Modifying Code Target Addresses
; These addresses point to operand bytes within instructions that are modified at runtime.
; WARNING: If code changes, these addresses must be updated!
;-------------------------------------------------------------------------------
.segment "CODE_PLATFORM"

; D_31B2/D_31B3/D_3200: SMC targets defined below as label+offset

;-------------------------------------------------------------------------------
; D_3169 - Screen area fill subroutine
; Copies 16 bytes from two source screen locations to two destination locations
; Used for initializing screen areas during level start
;-------------------------------------------------------------------------------
D_3169:
    lda  #$10                   ; 16 bytes to copy
    sta  DATLIN+1               ; $40 = copy counter / destination ptr low
    asl                         ; A = $20
    sta  DATPTR+1               ; $42 = second destination ptr low
    lda  #>D_4210               ; Charset work buffer page (item work buf 1)
    sta  DATPTR                 ; $41 = first destination page (-> $4x10)
    sta  INPPTR                 ; $43 = second destination page (-> $4x20)
    ldx  #$0f                   ; Copy 16 bytes (countdown from 15 to 0)
L_3178:
    lda  #$04                   ; Delay value
    jsr  wait_one_frame                 ; Wait/delay routine
    txa                         ; Use X as index
    tay                         ; Transfer to Y
    lda  (MEMSIZ+1),y           ; Read from source 1 ($38/$39)
    sta  (DATLIN+1),y           ; Write to destination 1 ($40/$41)
    txa                         ; Get X again
    eor  #$0f                   ; Invert index (mirror copy)
    tay                         ; Transfer to Y
    lda  (CURLIN+1),y           ; Read from source 2 ($3A/$3B)
    sta  (DATPTR+1),y           ; Write to destination 2 ($42/$43)
    dex                         ; Next byte
    bpl  L_3178                 ; Continue until all 16 bytes copied
    rts

;-------------------------------------------------------------------------------
; Overlapping dispatch tables for D_3193 self-modifying JSR
; Forms two indexed tables sharing middle bytes:
;   X=0: lo=<routine_3234, hi=>routine_3234  → JSR routine_3234
;   X=2: lo=<D_3771,       hi=>D_3771        → JSR D_3771
;   X=1: unused (target $7132 in sound data)
;-------------------------------------------------------------------------------
D_318F:
    .byte <routine_3234         ; X=0 lo byte
D_3190:
    .byte >routine_3234         ; X=0 hi byte (also X=1 lo, unused)
    .byte <D_3771               ; X=2 lo byte (also X=1 hi, unused)
    .byte >D_3771               ; X=2 hi byte

;-------------------------------------------------------------------------------
; D_3193 - Platform collision detection setup
; Sets up self-modifying code addresses and enters main collision loop
; X register determines which screen/offset values to use
;-------------------------------------------------------------------------------
D_3193:
    lda  D_318F,x               ; Load screen page value
    sta  D_31B2                 ; Store to self-modifying instruction (high byte of jsr)
    lda  D_3190,x               ; Load screen offset
    sta  D_31B3                 ; Store to self-modifying instruction (low byte of jsr)
    sty  D_3200                 ; Store Y value to self-modifying location
    ; Fall through to D_31A2

;-------------------------------------------------------------------------------
; D_31A2 - Main game loop with platform collision detection
; Runs multiple game systems each frame, then checks for platform collisions
; Loops continuously until all platforms are destroyed (D_597F = 0)
;-------------------------------------------------------------------------------
D_31A2:
    jsr  wait_one_frame                 ; Wait/delay routine
    jsr  update_sprite_animations ; Game state update
    jsr  D_045C                 ; Check player state
    jsr  D_7E80                 ; Unknown routine
    jsr  D_F1AC                 ; Unknown routine
smc_plat_jsr:
    jsr  entry_0400             ; Self-modified call - address set by D_3193
                                ; (JSR operand at $31B2-$31B3 is overwritten at runtime)
D_31B2 = smc_plat_jsr + 1      ; SMC: low byte of JSR target
D_31B3 = smc_plat_jsr + 2      ; SMC: high byte of JSR target
    ldx  #$01                   ; Check both players (1 down to 0)

;-------------------------------------------------------------------------------
; Platform collision detection loop
; For each active player, checks collision against all platforms
; Uses Manhattan distance: if both |player_Y - platform_Y| < 16 AND
; |player_X - platform_X| < 16, then collision occurred
;-------------------------------------------------------------------------------
L_31B6:
    lda  ENESSION,x             ; Get player state ($B2 for player 1, $B3 for player 2)
    cmp  #$01                   ; Check if player is active
    bne  L_3226                 ; Skip if not active
    ldy  #$00                   ; Platform index (will check all platforms)

L_31BE:
    ; Check Y coordinate collision
    lda  FA,x                   ; Get player Y position
    sec
    sbc  D_4600,y               ; Subtract platform Y position
    bcs  L_31CA                 ; Branch if no borrow (positive difference)
    eor  #$ff                   ; Two's complement part 1
    adc  #$01                   ; Two's complement part 2 (absolute value)
L_31CA:
    cmp  #$10                   ; Check if distance < 16 pixels
    bcs  L_3223                 ; No collision, try next platform
    
    ; Check X coordinate collision
    lda  $c2,x                  ; Get player X position
    sec
    sbc  D_4700,y               ; Subtract platform X position
    bcs  L_31DA                 ; Branch if no borrow (positive difference)
    eor  #$ff                   ; Two's complement part 1
    adc  #$01                   ; Two's complement part 2 (absolute value)
L_31DA:
    cmp  #$10                   ; Check if distance < 16 pixels
    bcs  L_3223                 ; No collision, try next platform

    ; Collision detected! Destroy the platform
    dec  D_597F                 ; Decrement platform counter
    sty  DATLIN+1               ; Save platform index
    lda  #$00                   ; Zero out this platform
    sta  D_4600,y               ; Clear Y position
    sta  D_4700,y               ; Clear X position
    
    ; Restore original screen tiles where platform was
    lda  D_4E00,y               ; Get platform screen address low byte
    sta  DATPTR+1               ; Store to pointer
    sta  $44                    ; Also store to temp location
    lda  D_4F00,y               ; Get platform screen address high byte
    sta  INPPTR                 ; Store to pointer
    clc
    adc  #$3b                   ; Add offset for color RAM?
    sta  VARNAM                 ; Store result
    
    ldy  D_AB51,x               ; Get value from table (animation frame?)
smc_plat_lda:
    lda  #$00                   ; Load value for comparison (operand at $3200 modified by D_3193)
D_3200 = smc_plat_lda + 1      ; SMC: operand of LDA #imm
    cmp  #$32                   ; Compare with 50
    bcs  L_3206                 ; Branch if >= 50
    dey                         ; Decrement Y
L_3206:
    jsr  D_7C26                 ; Call animation/effect routine
    
    ; Restore 4 character cells (2x2 platform area)
    ldy  #$00
    lda  ($44),y                ; Read original char top-left
    sta  (DATPTR+1),y           ; Restore to screen
    iny
    lda  ($44),y                ; Read original char top-right
    sta  (DATPTR+1),y           ; Restore to screen
    ldy  #$28                   ; Offset to next row (40 characters)
    lda  ($44),y                ; Read original char bottom-left
    sta  (DATPTR+1),y           ; Restore to screen
    iny
    lda  ($44),y                ; Read original char bottom-right
    sta  (DATPTR+1),y           ; Restore to screen
    
    ldy  DATLIN+1               ; Restore platform index
    inc  STREND,x               ; Increment player score/counter

L_3223:
    dey                         ; Next platform (counting down)
    bne  L_31BE                 ; Continue until all platforms checked

L_3226:
    dex                         ; Next player
    bpl  L_31B6                 ; Continue until both players checked
    
    ; Check if all platforms destroyed
    lda  D_597F                 ; Load platform counter
    beq  L_3231                 ; If zero, all destroyed - exit loop
    jmp  D_31A2                 ; Otherwise, continue collision loop

L_3231:
    jmp  update_sprite_animations ; All platforms destroyed - transition to next state

;-------------------------------------------------------------------------------
; Timer and score display routine ($3234)
; Displays level timer and player scores on screen
; Special handling: exits via stack manipulation if timer reaches zero
;-------------------------------------------------------------------------------
routine_3234:
    lda  #$60                   ; Screen row offset
    sta  VARNAM                 ; Store for character encoding
    lda  #>__VIC_SCREEN_A__         ; Screen page base
    sta  DATPTR                 ; Store base screen position
    lda  $2a                    ; Load timer value (ZP_2A)
    ldx  #$09                   ; X position offset
    ldy  #$0f                   ; Y position offset
    jsr  D_3266                 ; Display timer value
    lda  #$53                   ; Different screen offset
    sta  DATPTR
    lda  STREND                 ; Load player 1 score low byte
    ldx  #$0d                   ; X position offset
    ldy  #$c0                   ; Y position offset
    jsr  D_3266                 ; Display score
    lda  STREND+1               ; Load player 2 score low byte (or high byte?)
    ldx  #$0b                   ; X position offset
    ldy  #$de                   ; Y position offset
    jsr  D_3266                 ; Display score
    lda  $2a                    ; Check timer again
    bne  L_3265                 ; If non-zero, normal return
    lda  #$ff                   ; Timer expired!
    sta  TXTTAB                 ; Store $FF
    pla                         ; Remove return address from stack
    pla                         ; (exits to caller's caller)
L_3265:
    rts

;-------------------------------------------------------------------------------
; D_3266 - Decimal to screen character converter
; Converts binary value (A) to two decimal digits and displays on screen
; Input: A = value to convert (0-99)
;        X = digit offset value
;        Y = screen position parameters
; Output: Two decimal digits displayed at screen location
; Uses: Repeated subtraction for division by 10
;-------------------------------------------------------------------------------
D_3266:
    sty  DATLIN+1               ; Store Y parameter
    sta  $44                    ; Save value to convert
    sty  DATPTR+1               ; Store Y to pointer high
    lda  DATPTR                 ; Load base screen position
    clc
    adc  #(>$D800 - >__VIC_SCREEN_A__) ; Add offset for color RAM ($D800) page
    sta  INPPTR                 ; Store result
    txa                         ; Get X parameter
    ldy  #$00                   ; Y = 0 for indexing
    sta  (DATPTR+1),y           ; Store X value at screen position
    iny                         ; Y = 1
    sta  (DATPTR+1),y           ; Store X value at screen position+1
    
    ; Convert to decimal using repeated subtraction
    ldx  #$00                   ; Tens digit = 0
    lda  $44                    ; Get value to convert
L_327F:
    cmp  #$0a                   ; Compare with 10
    bcc  L_3288                 ; If < 10, done with tens
    inx                         ; Increment tens digit
    sbc  #$0a                   ; Subtract 10 (carry is set from CMP)
    bcs  L_327F                 ; Continue loop (BCS always branches here)
    
L_3288:
    ; A now has ones digit, X has tens digit
    ora  VARNAM                 ; OR with character encoding base
    sta  (DATLIN+1),y           ; Store ones digit at Y=1
    txa                         ; Get tens digit
    dey                         ; Y = 0
    ora  VARNAM                 ; OR with character encoding base
    sta  (DATLIN+1),y           ; Store tens digit at Y=0
    rts

;-------------------------------------------------------------------------------
; D_3293 - Full screen copy routine
; Copies 25 rows of 32 bytes (800 bytes total) from one screen to another
; Source/destination determined by pointer setup before call
; Handles page boundary crossing with pointer increments
;-------------------------------------------------------------------------------
D_3293:
    lda  #$00                   ; Initialize pointers
    sta  DATLIN+1               ; Destination low = $00
    sta  DATPTR+1               ; Source low = $00
    lda  #>__VIC_SCREEN_A__         ; Screen page base
    sta  DATPTR                 ; Source high
    lda  #>__SCREEN_BACKUP__   ; Backup buffer page
    sta  INPPTR                 ; Destination high
    ldx  #$19                   ; 25 rows to copy

L_32A3:
    ldy  #$1f                   ; 32 bytes per row (0-31)
L_32A5:
    lda  (DATPTR+1),y           ; Read from source
    sta  (DATLIN+1),y           ; Write to destination
    dey                         ; Next byte
    bpl  L_32A5                 ; Continue until row complete
    
    ; Advance pointers to next row
    lda  DATPTR+1               ; Get source pointer low
    clc
    adc  #$28                   ; Add 40 (one screen row)
    sta  DATLIN+1               ; Update destination low
    sta  DATPTR+1               ; Update source low
    bcc  L_32BB                 ; If no carry, no page boundary crossed
    inc  DATPTR                 ; Increment source page
    inc  INPPTR                 ; Increment destination page
L_32BB:
    dex                         ; Next row
    bne  L_32A3                 ; Continue until all rows copied
    rts

;===============================================================================
; End of bb-platform-collision.s
;===============================================================================
